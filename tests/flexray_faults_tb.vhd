library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.flexray_reference.all;
entity flexray_faults_tb is end entity;
architecture test of flexray_faults_tb is
  signal clk : std_ulogic := '0';
  signal rst : std_ulogic := '1';
  signal rx : std_ulogic := '1';
  signal enable : std_ulogic := '1';
  signal overriding : std_ulogic;
  signal changed : natural := 0;
  signal tx_bit, rewritten, decoded_valid : std_ulogic;
  signal decoded : work.flexray.message;
  signal decoded_count : natural := 0;
  signal torque : std_ulogic_vector(13 downto 0) := std_ulogic_vector(to_unsigned(9000, 14));
  signal cut_permission : std_ulogic := '1';
  signal arm_cut : boolean := false;
begin
  clk <= not clk after 6.25 ns;
  dut : entity work.flexray_torque_intercept generic map (SYNC_TIMEOUT_CYCLES => 48000)
    port map (clk => clk, rst => rst, rx => rx,
      torque => torque, sign => "010000000",
      enable => enable and cut_permission, tx => tx_bit, override => overriding, sync_debug => open);
  process
  begin
    wait until arm_cut;
    wait for 10 us; cut_permission <= '0';
    wait until not arm_cut; cut_permission <= '1';
  end process;
  rewritten <= tx_bit when overriding = '1' else rx;
  output_receiver : entity work.flexray_rx port map (
    clk => clk, rst => rst, rx => rewritten, msg => decoded, ready => decoded_valid);
  process(clk)
    variable previous : std_ulogic := '0';
  begin
    if rising_edge(clk) then
      if rst = '1' then previous := '0';
      else
        if decoded_valid = '1' and previous = '0' then decoded_count <= decoded_count + 1; end if;
        previous := decoded_valid;
      end if;
    end if;
  end process;
  process(clk)
  begin
    if rising_edge(clk) and overriding = '1' then changed <= changed + 1; end if;
  end process;
  process begin wait for 10 ms; report "TEST_TIMEOUT faults" severity failure; end process;
  process
    variable before : natural;
    procedure packet(cycle : natural; bad : boolean := false; neutral : boolean := true;
                     counter : integer := -1) is
    begin
      send_frame(rx, 31, cycle, bad, neutral, counter); wait for 5 us;
    end procedure;
    procedure expect_quiet(cycle : natural) is
    begin
      before := changed; packet(cycle);
      assert changed = before report "Unexpected override in inhibited frame" severity failure;
    end procedure;
  begin
    for cycle in 0 to 63 loop
      for phase in 0 to 1 loop
        assert work.flexray.cycle_phase_12(std_ulogic_vector(to_unsigned(cycle, 6)), phase) = (cycle mod 12 = phase)
          report "Direct cycle decoder differs from modulo arithmetic" severity failure;
      end loop;
    end loop;
    report "TEST_PASS cycle_decode_exhaustive_64x2";
    wait for 1 us; rst <= '0'; wait for 5 us;
    packet(0); expect_quiet(1); packet(2); expect_quiet(3);
    before := changed; packet(4);
    assert changed > before report "Fault test did not exercise active override" severity failure;
    assert decoded_valid = '1' and decoded.data(15) = x"A3" and decoded.data(16) = x"28"
      report "Modified frame did not carry a valid CRC and expected torque" severity failure;
    enable <= '0'; wait for 1 us;
    expect_quiet(5); -- revoke before the next frame, without waiting for cycle 3
    expect_quiet(8); expect_quiet(9);
    report "TEST_PASS enable_revocation_missing_cycle3";
    enable <= '1'; packet(10); packet(11); packet(12);
    packet(13, true); expect_quiet(14); expect_quiet(15);
    report "TEST_PASS bad_crc_invalidates_sync";
    torque <= std_ulogic_vector(to_unsigned(9010, 14));
    packet(16); expect_quiet(17); packet(18); -- omit cycle 3 during reacquisition
    before := changed; packet(20);
    assert changed > before report "Sync did not recover" severity failure;
    assert decoded_valid = '1' and decoded.data(16) = x"32"
      report "Reacquisition reused stale pre-fault torque" severity failure;
    report "TEST_PASS reacquisition_uses_fresh_command";
    wait for 700 us;
    expect_quiet(21); -- a previously held valid flag must not refresh the TTL
    report "TEST_PASS sync_timeout";
    packet(24); packet(25); packet(26); packet(27);
    packet(28, false, false, 15); -- incorrect counter on a CRC-valid non-neutral reference
    expect_quiet(29);
    report "TEST_PASS counter_mismatch_invalidates_sync";
    packet(32); packet(33); packet(34); packet(35);
    before := changed; send_frame(rx, 49, 2); wait for 5 us;
    send_frame(rx, 59, 0); wait for 5 us; send_frame(rx, 13, 0); wait for 5 us;
    assert changed = before report "LCA test patch is still active" severity failure;
    report "TEST_PASS lca_test_disabled";
    -- Reset while sampling a partial frame, then reacquire from new frames.
    rx <= '0'; wait for 137 ns; rst <= '1'; wait for 53 ns; rx <= '1';
    assert overriding = '0' report "Reset did not clear override" severity failure;
    wait for 1 us; rst <= '0'; wait for 5 us;
    packet(0); expect_quiet(1); packet(2); packet(3);
    before := changed; packet(4);
    assert changed > before report "Warm-reset recovery failed" severity failure;
    for i in 2 to 19 loop packet((i * 4) mod 64); end loop;
    expect_quiet(13);
    report "TEST_PASS cycle1_cache_expires_independently";
    for i in 0 to 17 loop packet(17); end loop;
    expect_quiet(20);
    report "TEST_PASS only_reference_frames_refresh_sync";
    rst <= '1'; wait for 1 us; rst <= '0'; wait for 5 us;
    packet(4, false, true, 0); -- learn a nonzero modular counter offset
    for cycle in 5 to 63 loop packet(cycle, false, false, (cycle / 4 - 1) mod 16); end loop;
    packet(0, false, false, 15);
    before := changed; packet(1, false, false, 15);
    assert changed > before report "Counter rollover lost synchronization" severity failure;
    report "TEST_PASS counter_rollover_with_offset";
    arm_cut <= true; packet(4);
    assert decoded_valid = '1' report "Mid-frame revocation truncated the modified frame CRC" severity failure;
    expect_quiet(5); arm_cut <= false;
    report "TEST_PASS midframe_revoke_finishes_crc_then_inhibits_next_frame";
    report "TEST_SUMMARY flexray_faults failures=0"; finish;
  end process;
end architecture;
