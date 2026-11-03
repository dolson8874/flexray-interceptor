library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity flexray_can_queue_tb is end entity;
architecture test of flexray_can_queue_tb is
  signal src_clk : std_ulogic := '0';
  signal dst_clk : std_ulogic := '0';
  signal rst : std_ulogic := '0';
  signal frame_valid : std_ulogic := '0';
  signal frame : work.flexray.message;
  signal valid, ready : std_ulogic := '0';
  signal data : std_ulogic_vector(78 downto 0);
  signal full_drops, stale_drops : std_ulogic_vector(31 downto 0);
  signal disabled_valid : std_ulogic;
  signal rate_valid : std_ulogic;
  signal rate_count : natural := 0;
begin
  src_clk <= not src_clk after 6.25 ns;
  dst_clk <= not dst_clk after 78 ns;
  dut : entity work.flexray_can_queue generic map (
    ENABLED => true, FRAME_ID => 31, CYCLE_MASK => 3, CYCLE_VALUE => 1,
    CAN_ID => 16#600#, BYTE_COUNT => 2, BYTE_0 => 5, BYTE_1 => 1,
    MIN_CAPTURE_CYCLES => 0, MAX_AGE_CYCLES => 2000)
    port map (src_clk => src_clk, dst_clk => dst_clk, rst => rst,
      frame_valid => frame_valid, frame => frame, m_valid => valid, m_ready => ready,
      m_data => data, dropped_full => full_drops, dropped_stale => stale_drops);
  disabled_dut : entity work.flexray_can_queue generic map (ENABLED => false)
    port map (src_clk => src_clk, dst_clk => dst_clk, rst => rst,
      frame_valid => frame_valid, frame => frame, m_valid => disabled_valid, m_ready => '1',
      m_data => open, dropped_full => open, dropped_stale => open);
  rate_dut : entity work.flexray_can_queue generic map (
    ENABLED => true, FRAME_ID => 31, CYCLE_MASK => 3, CYCLE_VALUE => 1,
    BYTE_COUNT => 1, MIN_CAPTURE_CYCLES => 1000)
    port map (src_clk => src_clk, dst_clk => dst_clk, rst => rst,
      frame_valid => frame_valid, frame => frame, m_valid => rate_valid, m_ready => '1',
      m_data => open, dropped_full => open, dropped_stale => open);
  process(dst_clk)
  begin
    if rising_edge(dst_clk) then
      if rst = '1' then rate_count <= 0;
      elsif rate_valid = '1' then rate_count <= rate_count + 1; end if;
    end if;
  end process;
  process begin wait for 1 ms; report "TEST_TIMEOUT queue" severity failure; end process;
  process
    variable sample : work.flexray.message;
    variable accepted : natural;
    procedure publish is
    begin
      wait until falling_edge(src_clk); frame <= sample; frame_valid <= '1';
      wait until falling_edge(src_clk); frame_valid <= '0';
      wait until falling_edge(src_clk);
    end procedure;
    procedure reset_queue is
    begin
      rst <= '1'; ready <= '0'; frame_valid <= '0'; wait for 2 us;
      rst <= '0'; wait for 20 us;
    end procedure;
  begin
    wait for 5 us; -- allow GSR and the FIFO's power-up reset sequence to finish
    sample.flags := (others => '0'); sample.frame_id := std_ulogic_vector(to_unsigned(31, 11));
    sample.payload_length := "0000100"; sample.cycle_count := "000001";
    sample.header_crc := (others => '0'); sample.crc := (others => '0');
    sample.data := (others => (others => '0'));
    sample.data(5) := x"A5"; sample.data(1) := x"12";
    reset_queue;
    sample.frame_id := std_ulogic_vector(to_unsigned(30, 11)); publish;
    sample.frame_id := std_ulogic_vector(to_unsigned(31, 11)); sample.cycle_count := "000010"; publish;
    sample.cycle_count := "000001"; sample.payload_length := "0000010"; publish;
    wait for 3 us;
    assert valid = '0' report "Filter admitted wrong ID/cycle/short payload" severity failure;
    sample.payload_length := "0000100"; publish;
    wait until valid = '1'; wait for 2 us;
    assert unsigned(data(78 downto 68)) = 16#600# and data(67 downto 64) = "0010" and
      data(63 downto 0) = x"A512000000000000" report "Mapping or CDC snapshot corrupt" severity failure;
    -- The source record can change while the consumer is stalled.
    sample.data(5) := x"00"; frame <= sample; wait for 2 us;
    assert data(63 downto 56) = x"A5" report "Unstable FIFO head during backpressure" severity failure;
    assert disabled_valid = '0' report "Disabled collector produced traffic" severity failure;
    ready <= '1'; wait until rising_edge(dst_clk); wait for 2 us; ready <= '0';
    assert valid = '0' report "Handshake did not consume one message" severity failure;
    report "TEST_PASS queue_filter_mapping_atomic_handshake_disabled";

    reset_queue;
    for i in 0 to 17 loop sample.data(5) := std_logic_vector(to_unsigned(i, 8)); publish; end loop;
    wait for 3 us;
    accepted := 18 - to_integer(unsigned(full_drops));
    assert rate_count = 1 report "Capture rate limit admitted a burst" severity failure;
    assert accepted >= 14 and accepted < 18 report "Full FIFO did not drop a bounded burst" severity failure;
    for i in 0 to accepted - 1 loop
      wait until falling_edge(dst_clk);
      assert valid = '1' and unsigned(data(63 downto 56)) = i report "FIFO order/data lost" severity failure;
      ready <= '1'; wait until rising_edge(dst_clk); wait for 1 ns; ready <= '0';
    end loop;
    wait for 2 us;
    assert valid = '0' report "FIFO duplicate after full drain" severity failure;
    report "TEST_PASS queue_overflow_order";
    wait for 8 us; publish; wait for 3 us;
    assert rate_count = 2 report "Capture rate limit did not rearm" severity failure;
    report "TEST_PASS queue_capture_rate_limit";

    reset_queue; publish; wait for 50 us;
    assert valid = '0' and unsigned(stale_drops) = 1 report "Stale data not discarded" severity failure;
    report "TEST_PASS queue_expiry";
    reset_queue;
    assert valid = '0' and unsigned(full_drops) = 0 and unsigned(stale_drops) = 0
      report "Reset did not flush queue and counters" severity failure;
    report "TEST_SUMMARY queue failures=0"; finish;
  end process;
end architecture;
