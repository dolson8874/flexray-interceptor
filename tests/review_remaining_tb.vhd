library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.flexray_reference.all;

-- Regressions for the four findings reproduced during the second review.
entity review_remaining_tb is end entity;
architecture test of review_remaining_tb is
  signal clk : std_ulogic := '0';
  signal rst : std_ulogic := '1';
  signal rx, tx, overriding, rewritten, valid : std_ulogic := '1';
  signal torque : std_ulogic_vector(13 downto 0) := std_ulogic_vector(to_unsigned(9000,14));
  signal enabled : std_ulogic := '1';
  signal hud_sign : std_ulogic_vector(8 downto 0) := "010000000";
  signal cut_hud : boolean := false;
  signal decoded : work.flexray.message;
  signal frames, override_clocks : natural := 0;
begin
  clk <= not clk after 6.25 ns;
  dut : entity work.flexray_torque_intercept generic map (SYNC_TIMEOUT_CYCLES => 48000)
    port map (clk=>clk, rst=>rst, rx=>rx, torque=>torque, sign=>hud_sign,
      enable=>enabled, tx=>tx, override=>overriding, sync_debug=>open);
  process
  begin
    wait until cut_hud; wait for 25 us; hud_sign <= (others=>'0');
    wait until not cut_hud; hud_sign <= "010000000";
  end process;
  rewritten <= tx when overriding='1' else rx;
  monitor : entity work.flexray_rx port map(clk=>clk,rst=>rst,rx=>rewritten,msg=>decoded,ready=>valid);
  process(clk)
    variable previous : std_ulogic := '0';
  begin
    if rising_edge(clk) then
      if rst='1' then previous:='0';
      else
        if valid='1' and previous='0' then frames<=frames+1; end if;
        previous:=valid;
        if overriding='1' then override_clocks<=override_clocks+1; end if;
      end if;
    end if;
  end process;
  process
    variable before, changed_before : natural := 0;
    variable expiry_start : time;
    procedure reset_dut is
    begin rst<='1'; rx<='1'; enabled<='1'; torque<=std_ulogic_vector(to_unsigned(9000,14));
      wait for 1 us; rst<='0'; wait for 5 us; end procedure;
    procedure packet(cycle:natural; bad:boolean:=false) is
    begin send_frame(rx,31,cycle,bad); wait for 5 us; end procedure;
  begin
    for error_bit in 0 to 23 loop
      reset_dut; packet(0); packet(1); packet(2);
      before:=frames;
      wait for error_bit * 1 ns; -- vary input phase relative to the 80 MHz clock
      send_frame(rx,31,4,bad_crc=>true,crc_error_bit=>error_bit); wait for 5 us;
      assert frames=before and valid='0'
        report "Corrupt input CRC was replaced with a valid output CRC" severity failure;
    end loop;
    report "TEST_PASS all_24_input_crc_errors_remain_invalid";
    -- Preserve errors even when the corrupted payload bit is overwritten.
    for byte_index in 16 to 24 loop
      reset_dut; packet(0); packet(1); packet(2); before:=frames;
      send_frame(rx,31,4,corrupt_payload_bit=>byte_index*8); wait for 5 us;
      assert frames=before and valid='0'
        report "Payload corruption was hidden by the interceptor" severity failure;
    end loop;
    report "TEST_PASS overwritten_and_unmodified_payload_errors_remain_invalid";

    reset_dut; packet(0); packet(1); packet(2); packet(4);
    torque<=std_ulogic_vector(to_unsigned(9010,14)); wait for 1 us; packet(8);
    assert valid='1' and decoded.data(16)=x"32"
      report "New torque was not captured without cycle 3" severity failure;
    report "TEST_PASS missing_cycle3_uses_latest_torque_9010";

    reset_dut; packet(0); packet(1); expiry_start:=now+585 us;
    packet(4); wait for expiry_start-now;
    before:=frames; changed_before:=override_clocks; packet(5);
    assert override_clocks>changed_before and frames=before+1 and valid='1'
      report "Mid-frame cache expiry interrupted the active frame" severity failure;
    report "TEST_PASS midframe_cache_expiry_finishes_crc";
    reset_dut; packet(0); packet(1); packet(2); packet(4);
    enabled<='0'; wait for 1 us; before:=frames; cut_hud<=true;
    send_frame(rx,13,1); wait for 5 us; cut_hud<=false;
    assert frames=before+1 and valid='1' and decoded.data(15)=x"63"
      report "Mid-frame HUD change interrupted the active frame" severity failure;
    report "TEST_PASS midframe_hud_update_finishes_current_snapshot";
    report "TEST_SUMMARY remaining_flexray failures=0"; finish;
  end process;
end architecture;
