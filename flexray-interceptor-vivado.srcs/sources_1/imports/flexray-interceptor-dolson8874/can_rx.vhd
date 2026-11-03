library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Validates standard classic CAN data frames before ACK/delivery. Unsupported
-- formats and malformed frames are observed silently until the bus is idle.
entity can_rx is
  port (
    clk, rst, rx : in std_ulogic;
    debug, tx : out std_ulogic;
    msg : out work.can.message;
    ready : out std_ulogic;
    ack_enable : in std_ulogic := '1'
  );
end entity;

architecture rtl of can_rx is
  type state_t is (IDLE, FRAME_BITS, LAST_STUFF, CRC_DELIMITER, ACK_SLOT,
                   ACK_DELIMITER, EOF_BITS, INTERMISSION, DISCARD);
  signal state : state_t := IDLE;
  signal rx_meta, rx_sync, rx_prev : std_ulogic := '1';
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of rx_meta, rx_sync : signal is "TRUE";
  signal phase : natural range 0 to 7 := 0;
  signal idle_ticks : natural range 0 to 88 := 0;
begin
  process(clk, rst)
  begin
    if rst = '1' then rx_meta <= '1'; rx_sync <= '1'; rx_prev <= '1';
    elsif rising_edge(clk) then
      rx_meta <= rx; rx_sync <= rx_meta; rx_prev <= rx_sync;
    end if;
  end process;

  process(clk, rst)
    variable frame : work.can.message;
    variable bit_index : natural range 0 to 98 := 0;
    variable data_bits : natural range 0 to 64 := 0;
    variable run_length : natural range 0 to 5 := 0;
    variable previous_bit : std_ulogic := '1';
    variable computed_crc, received_crc : std_ulogic_vector(14 downto 0);
    variable crc_valid, own_frame : boolean := false;
    variable tail_count : natural range 0 to 7 := 0;
    variable invalid : boolean;
  begin
    if rst = '1' then
      state <= IDLE; phase <= 0; idle_ticks <= 0;
      tx <= '1'; ready <= '0'; debug <= '0';
      frame.id := (others => '0'); frame.len := (others => '0');
      frame.dat := (others => '0'); msg <= frame;
      bit_index := 0; data_bits := 0; run_length := 0; previous_bit := '1';
      computed_crc := (others => '0'); received_crc := (others => '0');
      crc_valid := false; own_frame := false; tail_count := 0;
    elsif rising_edge(clk) then
      ready <= '0'; debug <= '0';
      -- After arbitration loss the winning frame belongs to the other node.
      if state = FRAME_BITS and ack_enable = '1' then own_frame := false; end if;
      if phase = 7 then phase <= 0; else phase <= phase + 1; end if;
      if rx_sync = '0' then idle_ticks <= 0;
      elsif idle_ticks < 88 then idle_ticks <= idle_ticks + 1; end if;

      -- Hard-sync SOF and track subsequent dominant edges on the 8x clock.
      -- Account for the two-flop input synchronizer plus edge detection:
      -- sample at phase 3; drive ACK at phase 5, the physical bit boundary.
      if rx_sync = '0' and rx_prev = '1' and (state = IDLE or state = FRAME_BITS) then
        phase <= 0;
        if state = IDLE and idle_ticks = 88 then
          state <= FRAME_BITS; bit_index := 0; data_bits := 0; run_length := 0;
          previous_bit := '1'; computed_crc := (others => '0');
          received_crc := (others => '0'); crc_valid := false;
          own_frame := (ack_enable = '0');
          frame.id := (others => '0'); frame.len := (others => '0');
          frame.dat := (others => '0');
        end if;
      end if;

      if phase = 5 then
        if state = ACK_SLOT and crc_valid and not own_frame and ack_enable = '1' then
          tx <= '0';
        else tx <= '1'; end if;
      end if;
      if state = DISCARD then
        tx <= '1';
        if idle_ticks = 88 then state <= IDLE; end if;
      end if;

      if phase = 3 and not (rx_sync = '0' and rx_prev = '1' and state = FRAME_BITS) then
        debug <= '1'; invalid := false;
        case state is
          when FRAME_BITS =>
            if run_length = 5 then
              if rx_sync = previous_bit then invalid := true;
              else run_length := 1; previous_bit := rx_sync; end if;
            else
              if rx_sync = previous_bit then run_length := run_length + 1;
              else run_length := 1; end if;
              previous_bit := rx_sync;
              if bit_index <= 18 + data_bits then
                if (rx_sync xor computed_crc(14)) = '1' then
                  computed_crc := (computed_crc(13 downto 0) & '0') xor "100010110011001";
                else computed_crc := computed_crc(13 downto 0) & '0'; end if;
              end if;
              if bit_index = 0 then
                if rx_sync /= '0' then invalid := true; end if;
              elsif bit_index <= 11 then frame.id(11 - bit_index) := rx_sync;
              elsif bit_index <= 14 then
                if rx_sync /= '0' then invalid := true; end if; -- RTR/IDE/r0
              elsif bit_index <= 18 then
                frame.len(18 - bit_index) := rx_sync;
                if bit_index = 18 then
                  if unsigned(frame.len) > 8 then invalid := true;
                  else data_bits := to_integer(unsigned(frame.len)) * 8; end if;
                end if;
              elsif bit_index < 19 + data_bits then frame.dat(82 - bit_index) := rx_sync;
              else received_crc(33 + data_bits - bit_index) := rx_sync;
              end if;
              if bit_index = 33 + data_bits then
                crc_valid := (computed_crc = received_crc);
                if run_length = 5 then state <= LAST_STUFF;
                else state <= CRC_DELIMITER; end if;
              else bit_index := bit_index + 1; end if;
            end if;
          when LAST_STUFF =>
            if rx_sync = previous_bit then invalid := true;
            else state <= CRC_DELIMITER; end if;
          when CRC_DELIMITER =>
            if rx_sync /= '1' or not crc_valid then invalid := true;
            else state <= ACK_SLOT; end if;
          when ACK_SLOT => state <= ACK_DELIMITER;
          when ACK_DELIMITER =>
            if rx_sync /= '1' then invalid := true;
            else tail_count := 0; state <= EOF_BITS; end if;
          when EOF_BITS =>
            if rx_sync /= '1' then invalid := true;
            elsif tail_count = 6 then
              if not own_frame then msg <= frame; ready <= '1'; end if;
              tail_count := 0; state <= INTERMISSION;
            else tail_count := tail_count + 1; end if;
          when INTERMISSION =>
            if rx_sync /= '1' then invalid := true;
            elsif tail_count = 2 then state <= IDLE;
            else tail_count := tail_count + 1; end if;
          when others => null;
        end case;
        if invalid then state <= DISCARD; tx <= '1'; end if;
      end if;
    end if;
  end process;
end architecture;
