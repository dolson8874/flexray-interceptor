library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;
use work.flexray;

entity flexray_interceptor is
  port (
    clk : in std_ulogic; -- Clock 8x higher than can bitrate
    rst : in std_ulogic;

    rx_0    : in std_ulogic;
    tx_0    : out std_ulogic;
    tx_en_0 : out std_ulogic;

    rx_1    : in std_ulogic;
    tx_1    : out std_ulogic;
    tx_en_1 : out std_ulogic;

    rx       : out std_ulogic;
    tx       : in std_ulogic;
    override : in std_ulogic;
    -- send fastserial
    rx_valid  : in std_ulogic; 
    send_log : out std_ulogic_vector(7 downto 0);
    ready    : out std_ulogic;
    log_stats : out std_ulogic_vector(383 downto 0);
    spi_byte_done : in std_ulogic := '0'
  );
end entity flexray_interceptor;


architecture syn of flexray_interceptor is

  component flexray_rx is
    port (
      clk   : in std_ulogic; -- Clock 8x higher than can bitrate
      rst   : in std_ulogic;
      rx    : in std_ulogic;
      msg   : out work.flexray.message;
      ready : out std_ulogic);
  end component flexray_rx;
  
  component flexray_log is
    port (
      i_clk      : in std_ulogic; -- Clock 80Mhz
      i_rst      : in std_ulogic;
      i_ready    : in std_ulogic; -- update msg
      i_busy     : in std_ulogic; -- fastserial_tx busy
      i_bus      : in std_ulogic; -- BCM-side = '0', DADC = '1'
      i_msg      : in work.flexray.message; -- flexray message
      o_tx_byte  : out std_ulogic_vector (7 downto 0); -- fastserial_tx data
      o_tx_ready : out std_ulogic; -- fastserial tx ready 
      o_busy     : out std_ulogic);
  end component flexray_log;
  
  signal s_tx_0 : std_ulogic;
  signal s_tx_1 : std_ulogic;

  signal tx_0_delayed : std_ulogic_vector(7 downto 0);
  signal tx_1_delayed : std_ulogic_vector(7 downto 0);

  -- for flexray_rx
  -- signal msg_psmc : work.flexray.message;
  signal msg_dadc : work.flexray.message;
  -- signal ready_psmc : std_ulogic;
  signal ready_dadc : std_ulogic;

  -- for flexray_log module
  signal log_busy  : std_ulogic;
  signal log_bus   : std_ulogic;
  -- signal log_msg :  work.flexray.message;

  -- for fastserial_tx
  signal tx_byte  : std_ulogic_vector(7 downto 0);
  signal tx_ready : std_ulogic;
  -- FIFO 
  signal fifo_din   : std_logic_vector(7 downto 0);
  signal fifo_wr_en : std_ulogic;
  signal fifo_full  : std_ulogic;
  signal fifo_dout  : std_logic_vector(7 downto 0);
  signal fifo_rd_en : std_ulogic;
  signal fifo_empty : std_ulogic;
  type fifo_read_state_t is (READ_IDLE, READ_PENDING, READ_VALID);
  signal fifo_read_state : fifo_read_state_t := READ_IDLE;
  signal log_data : std_ulogic_vector(7 downto 0) := (others => '0');
  
  signal log_req      : std_ulogic := '0';  
  signal msg_latched  : work.flexray.message;
  
  
  constant TEST_MODE : boolean := false;
  --constant TEST_MODE : boolean := true;
  
  signal ready_dadc_rx  : std_ulogic;
  signal msg_dadc_rx    : work.flexray.message;
  signal ready_bcm_rx   : std_ulogic;
  signal msg_bcm_rx     : work.flexray.message;
  -- Preserved debug probes; no new bytes/commands in the SPI stream.
  signal log_dadc_received, log_bcm_received : std_ulogic_vector(31 downto 0);
  signal log_dadc_dropped, log_bcm_dropped : std_ulogic_vector(31 downto 0);
  signal log_dadc_high_water, log_bcm_high_water : std_ulogic_vector(31 downto 0);
  signal log_dadc_bytes, log_bcm_bytes : std_ulogic_vector(31 downto 0);
  signal log_spi_bytes : unsigned(31 downto 0) := (others => '0');
  signal log_spi_clocked_bytes : unsigned(31 downto 0) := (others => '0');
  signal log_fifo_level, log_fifo_high_water : unsigned(17 downto 0) := (others => '0');
  signal log_fifo_full_events : unsigned(31 downto 0) := (others => '0');
  signal previous_fifo_full : std_ulogic := '0';
  attribute MARK_DEBUG : string;
  attribute MARK_DEBUG of log_dadc_received, log_bcm_received,
    log_dadc_dropped, log_bcm_dropped, log_dadc_high_water, log_bcm_high_water,
    log_dadc_bytes, log_bcm_bytes, log_spi_bytes, log_spi_clocked_bytes,
    log_fifo_level, log_fifo_high_water, log_fifo_full_events : signal is "TRUE";
  signal ready_dadc_test: std_ulogic := '0';
  signal msg_dadc_test  : work.flexray.message;  
  
begin

  -- Twelve little-endian 32-bit diagnostic page values, sampled by the CAN
  -- diagnostics module in this same clock domain. Queue peaks share page 4.
  log_stats <= std_ulogic_vector(log_spi_clocked_bytes) &
    std_ulogic_vector(log_spi_bytes) & log_bcm_bytes & log_dadc_bytes &
    std_ulogic_vector(log_fifo_full_events) &
    std_ulogic_vector(resize(log_fifo_high_water, 32)) &
    std_ulogic_vector(resize(log_fifo_level, 32)) &
    log_bcm_high_water(15 downto 0) & log_dadc_high_water(15 downto 0) &
    log_bcm_dropped & log_dadc_dropped & log_bcm_received & log_dadc_received;

  fifo_inst : entity work.fifo_generator_0
    port map
    (
      clk   => clk,
      srst  => rst,
      din   => fifo_din,
      wr_en => fifo_wr_en,
      full  => fifo_full,
      dout  => fifo_dout,
      rd_en => fifo_rd_en,
      empty => fifo_empty
    );

  -- for log 
  rx_dadc : flexray_rx PORT map (
     clk => clk, 
     rst => rst, 
     rx => s_tx_0, 
     msg => msg_dadc_rx, 
     ready => ready_dadc_rx
     );

  rx_bcm : flexray_rx port map (
    clk => clk, rst => rst, rx => s_tx_1,
    msg => msg_bcm_rx, ready => ready_bcm_rx);
     
  tx_log : flexray_log PORT map(
    i_clk => clk, 
    i_rst => rst, 
    i_ready => log_req, 
    i_busy => fifo_full,
    i_bus => log_bus, 
    i_msg => msg_latched,
    o_tx_byte => tx_byte, 
    o_tx_ready => tx_ready, 
    o_busy => log_busy
    );  

  -- flexray_log, fifo push
  fifo_din   <= std_logic_vector(tx_byte);
  fifo_wr_en <= tx_ready when fifo_full = '0' else '0';

  -- fifo pop, SPI_SLAVE
  -- Standard_FIFO has a clocked read output, not a FWFT head. Read first,
  -- capture on the next clock, then hold the byte until SPI accepts it.
  send_log <= log_data;
  ready <= '1' when fifo_read_state = READ_VALID and rst = '0' else '0';
  fifo_rd_en <= '1' when fifo_read_state = READ_IDLE and fifo_empty = '0' and rst = '0' else '0';
  log_prefetch : process(clk, rst)
  begin
    if rst = '1' then
      fifo_read_state <= READ_IDLE; log_data <= (others => '0');
    elsif rising_edge(clk) then
      case fifo_read_state is
        when READ_IDLE =>
          if fifo_empty = '0' then fifo_read_state <= READ_PENDING; end if;
        when READ_PENDING =>
          log_data <= std_ulogic_vector(fifo_dout); fifo_read_state <= READ_VALID;
        when READ_VALID =>
          if rx_valid = '1' then fifo_read_state <= READ_IDLE; end if;
      end case;
    end if;
  end process;

  tx_0 <= s_tx_0;
  tx_1 <= s_tx_1;

  ready_dadc <= ready_dadc_test when TEST_MODE else ready_dadc_rx;
  msg_dadc   <= msg_dadc_test   when TEST_MODE else msg_dadc_rx;

  -- =========================
  -- TEST GENERATOR (ENABLE by TEST_MODE=TRUE)
  -- =========================
  test_flexray_rx : process (clk, rst)
    variable counter : integer range 0 to 63;
    variable tmp_msg : work.flexray.message;
    variable pulse_1shot : std_ulogic;
  begin
    if rst = '1' then
      ready_dadc_test <= '0';
      pulse_1shot     := '0';
      counter         := 53;

      tmp_msg.flags          := b"00000";
      tmp_msg.frame_id       := b"00000000011";     -- ID 3
      tmp_msg.payload_length := b"0001101";         -- length 13 
      tmp_msg.header_crc     := b"01111000110";     -- 0x3C6
      tmp_msg.cycle_count    := b"110101";          -- 53
      tmp_msg.data           := (others => (others => '0'));
      tmp_msg.data(0)  := x"FC";
      tmp_msg.data(1)  := x"04";
      tmp_msg.data(8)  := x"C4";
      tmp_msg.data(9)  := x"04";
      tmp_msg.data(10) := x"07";
      tmp_msg.data(11) := x"FF";
      tmp_msg.data(14) := x"FF";
      tmp_msg.data(15) := x"C0";
      tmp_msg.data(25) := x"60";
      tmp_msg.crc      := x"0EB5BC";

    elsif rising_edge(clk) then
      if TEST_MODE then
        if (pulse_1shot = '0') and (log_req = '0') and (log_busy = '0') then
          tmp_msg.cycle_count := std_ulogic_vector(to_unsigned(counter, 6));
          msg_dadc_test       <= tmp_msg;

          ready_dadc_test <= '1';
          pulse_1shot     := '1';

          if counter = 63 then
            counter := 0;
          else
            counter := counter + 1;
          end if;

        else
          ready_dadc_test <= '0';
          if pulse_1shot = '1' then
            pulse_1shot := '0';
          end if;
        end if;
      else
        ready_dadc_test <= '0';
      end if;
    end if;
  end process;

  
  
  log_dispatch : entity work.flexray_log_dispatch port map (
    clk => clk, rst => rst, dadc_valid => ready_dadc, dadc_frame => msg_dadc,
    bcm_valid => ready_bcm_rx, bcm_frame => msg_bcm_rx,
    log_busy => log_busy, log_req => log_req, log_bus => log_bus, log_frame => msg_latched,
    dadc_received => log_dadc_received, bcm_received => log_bcm_received,
    dadc_dropped => log_dadc_dropped, bcm_dropped => log_bcm_dropped,
    dadc_high_water => log_dadc_high_water, bcm_high_water => log_bcm_high_water,
    dadc_bytes => log_dadc_bytes, bcm_bytes => log_bcm_bytes);

  -- Saved FIFO depth = 131072 bytes; this excludes the prefetch byte.
  log_fifo_monitor : process(clk, rst)
    variable level : unsigned(17 downto 0);
  begin
    if rst = '1' then
      log_fifo_level <= (others => '0'); log_fifo_high_water <= (others => '0');
      log_fifo_full_events <= (others => '0'); previous_fifo_full <= '0';
      log_spi_bytes <= (others => '0');
      log_spi_clocked_bytes <= (others => '0');
    elsif rising_edge(clk) then
      level := log_fifo_level;
      if fifo_wr_en = '1' and fifo_rd_en = '0' then level := level+1;
      elsif fifo_wr_en = '0' and fifo_rd_en = '1' then level := level-1; end if;
      log_fifo_level <= level;
      if level > log_fifo_high_water then log_fifo_high_water <= level; end if;
      if fifo_full = '1' and previous_fifo_full = '0' and log_fifo_full_events /= x"FFFFFFFF" then
        log_fifo_full_events <= log_fifo_full_events+1;
      end if;
      previous_fifo_full <= fifo_full;
      -- Valid log bytes accepted by SPI prefetch, not idle zero filler. This
      -- is not USB delivery confirmation; SPI can hold a byte across CS abort.
      if fifo_read_state=READ_VALID and rx_valid='1' then
        log_spi_bytes<=log_spi_bytes+1;
      end if;
      if spi_byte_done='1' then
        log_spi_clocked_bytes<=log_spi_clocked_bytes+1;
      end if;
    end if;
  end process;
  

  manage_enables : process (clk, rst)
    variable bus_0_idle_counter : integer range 0 to 80;
    variable bus_1_idle_counter : integer range 0 to 80;
  begin
    if rst = '1' then
      tx_en_0 <= '1';
      tx_en_1 <= '1';

      bus_0_idle_counter := 80;
      bus_1_idle_counter := 80;
    elsif rising_edge(clk) then
      if s_tx_0 = '0' then
        bus_0_idle_counter := 0;
        tx_en_0 <= '0';
      else
        if bus_0_idle_counter < 80 then
          bus_0_idle_counter := bus_0_idle_counter + 1;
          tx_en_0 <= '0';
        else
          tx_en_0 <= '1';
        end if;
      end if;

      if s_tx_1 = '0' then
        bus_1_idle_counter := 0;
        tx_en_1 <= '0';
      else
        if bus_1_idle_counter < 80 then
          bus_1_idle_counter := bus_1_idle_counter + 1;
          tx_en_1 <= '0';
        else
          tx_en_1 <= '1';
        end if;
      end if;

    end if;

  end process;

  intercept : process (clk, rst)
  begin
    if rst = '1' then
      rx <= '1';
      s_tx_0 <= '1';
      s_tx_1 <= '1';

      tx_0_delayed <= (others => '1');
      tx_1_delayed <= (others => '1');
    elsif rising_edge(clk) then
      tx_0_delayed <= tx_0_delayed(6 downto 0) & s_tx_0;
      tx_1_delayed <= tx_1_delayed(6 downto 0) & s_tx_1;

      rx <= rx_1;

      if override = '1' then
        s_tx_0 <= tx;
      else
        if rx_1 = '0' and tx_1_delayed = b"11111111" then
          s_tx_0 <= '0';
        else
          s_tx_0 <= '1';
        end if;
      end if;

      if rx_0 = '0' and tx_0_delayed = b"11111111" then
        s_tx_1 <= '0';
      else
        s_tx_1 <= '1';
      end if;

    end if;
  end process;
end architecture syn;
