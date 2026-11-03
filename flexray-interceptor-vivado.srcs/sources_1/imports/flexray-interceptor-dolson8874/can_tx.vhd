library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.can;

-- Standard 11-bit classic CAN data frames, eight clocks per bus bit.
-- Requests while busy are ignored; the upstream queue owns pending messages.
-- Errors cause recessive abort and bounded retries. No active error flags or
-- ISO error confinement: this is a limited telemetry endpoint, not a full core.
entity can_tx is
  generic (
    MAX_RETRIES : natural range 0 to 15 := 1;
    MAX_WAIT_CYCLES : positive := 64000
  );
  port (
    clk, rst, ready : in std_ulogic;
    msg : in work.can.message;
    rx : in std_ulogic;
    busy, tx, done : out std_ulogic;
    dbg_state : out std_ulogic_vector(3 downto 0);
    dbg_arblost, dbg_ack_err : out std_ulogic;
    retry_count : out std_ulogic_vector(3 downto 0);
    active : out std_ulogic := '0';
    success : out std_ulogic := '0';
    dbg_bit_err : out std_ulogic := '0'
  );
end entity;

architecture rtl of can_tx is
  type state_t is (IDLE, WAIT_IDLE, SEND_BITS, ACK_SLOT, TAIL, RETRY_IDLE, FINISH);
  signal state : state_t := IDLE;
  signal latched : work.can.message;
  signal rx_meta, rx_sync : std_ulogic := '1';
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of rx_meta, rx_sync : signal is "TRUE";
  signal prev_ready : std_ulogic := '0';
  signal tx_i : std_ulogic := '1';
  signal phase : natural range 0 to 7 := 0;
  signal idle_ticks : natural range 0 to 88 := 0;
  signal bit_index : natural range 0 to 98 := 0;
  signal data_bits : natural range 0 to 64 := 0;
  signal run_length : natural range 1 to 5 := 1;
  signal last_bit, stuffed : std_ulogic := '0';
  signal crc : std_ulogic_vector(14 downto 0) := (others => '0');
  signal tail_index : natural range 0 to 10 := 0;
  signal attempts : natural range 0 to 15 := 0;
  signal failed, acknowledged : std_ulogic := '0';
  signal wait_count : natural range 0 to MAX_WAIT_CYCLES := 0;
  function crc_step(c : std_ulogic_vector(14 downto 0); b : std_ulogic)
    return std_ulogic_vector is
    variable n : std_ulogic_vector(14 downto 0);
  begin
    n := c(13 downto 0) & '0';
    if (b xor c(14)) = '1' then n := n xor "100010110011001"; end if;
    return n;
  end function;
begin
  tx <= tx_i;
  busy <= '0' when state = IDLE else '1';
  active <= '1' when state = SEND_BITS or state = ACK_SLOT or state = TAIL else '0';
  retry_count <= std_ulogic_vector(to_unsigned(attempts, 4));
  with state select dbg_state <=
    "0000" when IDLE, "0001" when WAIT_IDLE, "0010" when SEND_BITS,
    "0011" when ACK_SLOT, "0100" when TAIL, "0110" when RETRY_IDLE,
    "0101" when FINISH;
  process(clk, rst)
  begin
    if rst = '1' then rx_meta <= '1'; rx_sync <= '1';
    elsif rising_edge(clk) then rx_meta <= rx; rx_sync <= rx_meta; end if;
  end process;
  process(clk, rst)
    variable b : std_ulogic;
  begin
    if rst = '1' then
      state <= IDLE; tx_i <= '1'; done <= '0'; success <= '0';
      dbg_arblost <= '0'; dbg_ack_err <= '0'; dbg_bit_err <= '0';
      phase <= 0; idle_ticks <= 0; prev_ready <= '0';
      bit_index <= 0; data_bits <= 0; run_length <= 1;
      last_bit <= '0'; stuffed <= '0'; crc <= (others => '0');
      tail_index <= 0; attempts <= 0; failed <= '0'; acknowledged <= '0';
      wait_count <= 0;
      latched.id <= (others => '0'); latched.len <= (others => '0');
      latched.dat <= (others => '0');
    elsif rising_edge(clk) then
      done <= '0'; success <= '0'; prev_ready <= ready;
      if phase = 7 then phase <= 0; else phase <= phase + 1; end if;
      if rx_sync = '0' then idle_ticks <= 0;
      elsif idle_ticks < 88 then idle_ticks <= idle_ticks + 1; end if;
      case state is
        when IDLE =>
          tx_i <= '1';
          if ready = '1' and prev_ready = '0' then
            latched <= msg; attempts <= 0; failed <= '0'; wait_count <= 0;
            dbg_arblost <= '0'; dbg_ack_err <= '0'; dbg_bit_err <= '0';
            if unsigned(msg.len) > 8 then
              failed <= '1'; dbg_bit_err <= '1'; state <= FINISH;
            else
              data_bits <= to_integer(unsigned(msg.len)) * 8; state <= WAIT_IDLE;
            end if;
          end if;
        when WAIT_IDLE | RETRY_IDLE =>
          tx_i <= '1';
          if wait_count < MAX_WAIT_CYCLES then wait_count <= wait_count + 1; end if;
          -- Eleven whole recessive bit times cannot occur inside a valid
          -- stuffed frame. Check both synchronizer stages at launch as well.
          if idle_ticks = 88 and rx_sync = '1' and rx_meta = '1' then
            tx_i <= '0'; phase <= 1; bit_index <= 0; stuffed <= '0';
            last_bit <= '0'; run_length <= 1; crc <= (others => '0');
            acknowledged <= '0'; failed <= '0'; state <= SEND_BITS;
            wait_count <= 0;
          elsif wait_count = MAX_WAIT_CYCLES then
            failed <= '1'; state <= FINISH;
          end if;
        when SEND_BITS =>
          if phase = 0 then
            stuffed <= '0';
            -- Include a possible stuff bit after the final CRC bit.
            if run_length = 5 and bit_index <= 34 + data_bits then
              b := not last_bit; stuffed <= '1'; run_length <= 1;
            else
              if bit_index = 0 then b := '0';
              elsif bit_index <= 11 then b := latched.id(11 - bit_index);
              elsif bit_index <= 14 then b := '0';
              elsif bit_index <= 18 then b := latched.len(18 - bit_index);
              elsif bit_index < 19 + data_bits then b := latched.dat(82 - bit_index);
              elsif bit_index <= 33 + data_bits then b := crc(33 + data_bits - bit_index);
              else b := '1'; end if;
              if bit_index <= 18 + data_bits then crc <= crc_step(crc, b); end if;
              if bit_index <= 33 + data_bits then
                if b = last_bit then run_length <= run_length + 1;
                else run_length <= 1; end if;
              else run_length <= 1; end if;
            end if;
            tx_i <= b; last_bit <= b;
          end if;
          if phase = 7 then
            if stuffed = '0' then
              if bit_index = 34 + data_bits then state <= ACK_SLOT;
              else bit_index <= bit_index + 1; end if;
            end if;
          end if;
          if phase = 6 and tx_i /= rx_sync then
            tx_i <= '1'; idle_ticks <= 0;
            if tx_i = '1' and rx_sync = '0' and bit_index >= 1 and bit_index <= 12 and stuffed = '0' then
              dbg_arblost <= '1';
            else dbg_bit_err <= '1'; end if;
            if attempts < MAX_RETRIES then attempts <= attempts + 1; state <= RETRY_IDLE;
            else failed <= '1'; state <= FINISH; end if;
          end if;
        when ACK_SLOT =>
          tx_i <= '1';
          if phase = 6 then
            if rx_sync = '0' then acknowledged <= '1';
            else dbg_ack_err <= '1'; acknowledged <= '0'; end if;
          end if;
          if phase = 7 then
            if acknowledged = '1' then tail_index <= 0; state <= TAIL;
            else
              idle_ticks <= 0;
              if attempts < MAX_RETRIES then attempts <= attempts + 1; state <= RETRY_IDLE;
              else failed <= '1'; state <= FINISH; end if;
            end if;
          end if;
        when TAIL =>
          tx_i <= '1';
          if phase = 6 and tail_index <= 7 and rx_sync /= '1' then
            dbg_bit_err <= '1'; idle_ticks <= 0;
            if attempts < MAX_RETRIES then attempts <= attempts + 1; state <= RETRY_IDLE;
            else failed <= '1'; state <= FINISH; end if;
          elsif phase = 7 then
            if tail_index = 10 then state <= FINISH; else tail_index <= tail_index + 1; end if;
          end if;
        when FINISH =>
          tx_i <= '1'; done <= '1'; success <= not failed; state <= IDLE;
      end case;
    end if;
  end process;
end architecture;
