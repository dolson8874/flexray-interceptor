library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
library xpm;
use xpm.vcomponents.all;

-- Read-only collection of CRC-validated FlexRay messages. Message boundary
-- snapshots cross the clock boundary atomically through an XPM async FIFO.
entity flexray_can_queue is
  generic (
    ENABLED : boolean := false;
    FRAME_ID : natural range 0 to 2047 := 0;
    CYCLE_MASK : natural range 0 to 63 := 0;
    CYCLE_VALUE : natural range 0 to 63 := 0;
    CAN_ID : natural range 0 to 2047 := 0;
    BYTE_COUNT : positive range 1 to 8 := 8;
    BYTE_0 : natural range 0 to 253 := 0;
    BYTE_1 : natural range 0 to 253 := 1;
    BYTE_2 : natural range 0 to 253 := 2;
    BYTE_3 : natural range 0 to 253 := 3;
    BYTE_4 : natural range 0 to 253 := 4;
    BYTE_5 : natural range 0 to 253 := 5;
    BYTE_6 : natural range 0 to 253 := 6;
    BYTE_7 : natural range 0 to 253 := 7;
    MIN_CAPTURE_CYCLES : natural := 8000000; -- 100 ms at 80 MHz
    MAX_AGE_CYCLES : positive := 8000000
  );
  port (
    src_clk, dst_clk, rst : in std_ulogic;
    frame_valid : in std_ulogic;
    frame : in work.flexray.message;
    m_valid : out std_ulogic;
    m_ready : in std_ulogic;
    m_data : out std_ulogic_vector(78 downto 0);
    dropped_full, dropped_stale : out std_ulogic_vector(31 downto 0)
  );
end entity;

architecture rtl of flexray_can_queue is
  type index_array is array(0 to 7) of natural;
  constant INDEXES : index_array := (BYTE_0, BYTE_1, BYTE_2, BYTE_3, BYTE_4, BYTE_5, BYTE_6, BYTE_7);
  signal source_reset, dest_reset : std_logic;
  signal fifo_full, fifo_empty, wr_reset_busy, rd_reset_busy : std_logic;
  signal write_en, read_en : std_logic := '0';
  signal fifo_in, fifo_out : std_logic_vector(110 downto 0);
  signal source_time : unsigned(31 downto 0) := (others => '0');
  signal synced_time : std_logic_vector(31 downto 0);
  signal full_count, stale_count : unsigned(31 downto 0) := (others => '0');
  signal stale, head_valid : std_ulogic;
  signal prev_valid : std_ulogic := '0';
  signal cooldown : natural range 0 to MIN_CAPTURE_CYCLES := 0;
begin
  assert MAX_AGE_CYCLES < 1073741824 report "Age must fit the timestamp wrap window" severity failure;
  assert (to_unsigned(CYCLE_VALUE, 6) and to_unsigned(CYCLE_MASK, 6)) = to_unsigned(CYCLE_VALUE, 6)
    report "CYCLE_VALUE contains bits outside CYCLE_MASK" severity failure;
  src_reset_sync : xpm_cdc_async_rst
    generic map (DEST_SYNC_FF => 4, INIT_SYNC_FF => 0, RST_ACTIVE_HIGH => 1)
    port map (src_arst => rst, dest_clk => src_clk, dest_arst => source_reset);
  dst_reset_sync : xpm_cdc_async_rst
    generic map (DEST_SYNC_FF => 4, INIT_SYNC_FF => 0, RST_ACTIVE_HIGH => 1)
    port map (src_arst => rst, dest_clk => dst_clk, dest_arst => dest_reset);
  timestamp_cdc : xpm_cdc_gray
    generic map (DEST_SYNC_FF => 3, INIT_SYNC_FF => 1, REG_OUTPUT => 1, WIDTH => 32)
    port map (src_clk => src_clk, src_in_bin => std_logic_vector(source_time),
              dest_clk => dst_clk, dest_out_bin => synced_time);

  queue : xpm_fifo_async
    generic map (
      FIFO_MEMORY_TYPE => "distributed", FIFO_WRITE_DEPTH => 16,
      WRITE_DATA_WIDTH => 111, READ_DATA_WIDTH => 111,
      READ_MODE => "fwft", FIFO_READ_LATENCY => 0,
      CDC_SYNC_STAGES => 3, USE_ADV_FEATURES => "0000", SIM_ASSERT_CHK => 1)
    port map (
      sleep => '0', rst => source_reset, wr_clk => src_clk, wr_en => write_en,
      din => fifo_in, full => fifo_full, wr_rst_busy => wr_reset_busy,
      rd_clk => dst_clk, rd_en => read_en, dout => fifo_out,
      empty => fifo_empty, rd_rst_busy => rd_reset_busy,
      prog_full => open, wr_data_count => open, overflow => open,
      almost_full => open, wr_ack => open, prog_empty => open,
      rd_data_count => open, underflow => open, almost_empty => open,
      data_valid => open, injectsbiterr => '0', injectdbiterr => '0',
      sbiterr => open, dbiterr => open);

  -- Timestamp delivery can lag FIFO delivery by a few destination cycles.
  -- A negative modular difference means 'not yet aged', not 'very old'.
  process(all)
    variable age : unsigned(31 downto 0);
  begin
    age := unsigned(synced_time) - unsigned(fifo_out(110 downto 79));
    stale <= '0';
    if age(31) = '0' and age >= MAX_AGE_CYCLES then stale <= '1'; end if;
  end process;
  head_valid <= '1' when ENABLED and fifo_empty = '0' and rd_reset_busy = '0' and dest_reset = '0' else '0';
  m_valid <= head_valid and not stale;
  m_data <= std_ulogic_vector(fifo_out(78 downto 0));
  read_en <= head_valid and (stale or m_ready);
  dropped_full <= std_ulogic_vector(full_count);
  dropped_stale <= std_ulogic_vector(stale_count);

  process(src_clk)
    variable payload : std_logic_vector(63 downto 0);
    variable in_range : boolean;
  begin
    if rising_edge(src_clk) then
      if source_reset = '1' then
        source_time <= (others => '0'); full_count <= (others => '0');
        cooldown <= 0; prev_valid <= '0'; write_en <= '0'; fifo_in <= (others => '0');
      else
        source_time <= source_time + 1; prev_valid <= frame_valid; write_en <= '0';
        if cooldown > 0 then cooldown <= cooldown - 1; end if;
        if ENABLED and frame_valid = '1' and prev_valid = '0' and cooldown = 0 and
           unsigned(frame.frame_id) = FRAME_ID and
           (unsigned(frame.cycle_count) and to_unsigned(CYCLE_MASK, 6)) = to_unsigned(CYCLE_VALUE, 6) then
          payload := (others => '0'); in_range := true;
          for i in 0 to BYTE_COUNT - 1 loop
            if INDEXES(i) >= to_integer(unsigned(frame.payload_length)) * 2 then in_range := false; end if;
            payload(63 - i * 8 downto 56 - i * 8) := frame.data(INDEXES(i));
          end loop;
          if in_range then
            if fifo_full = '0' and wr_reset_busy = '0' and write_en = '0' then
              fifo_in <= std_logic_vector(source_time) & std_logic_vector(to_unsigned(CAN_ID, 11)) &
                std_logic_vector(to_unsigned(BYTE_COUNT, 4)) & payload;
              write_en <= '1'; cooldown <= MIN_CAPTURE_CYCLES;
            elsif full_count /= x"FFFFFFFF" then full_count <= full_count + 1; end if;
          end if;
        end if;
      end if;
    end if;
  end process;
  process(dst_clk)
  begin
    if rising_edge(dst_clk) then
      if dest_reset = '1' then stale_count <= (others => '0');
      elsif read_en = '1' and stale = '1' and stale_count /= x"FFFFFFFF" then stale_count <= stale_count + 1; end if;
    end if;
  end process;
end architecture;
