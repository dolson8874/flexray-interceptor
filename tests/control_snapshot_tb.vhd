library ieee;
use ieee.std_logic_1164.all;
use std.env.all;
entity control_snapshot_tb is end entity;
architecture test of control_snapshot_tb is
  signal src_clk, dst_clk : std_ulogic := '0';
  signal dst_running : boolean := true;
  signal rst : std_ulogic := '1';
  signal source_word, output_word : std_ulogic_vector(23 downto 0) := (others => '0');
  signal transitions : natural := 0;
begin
  src_clk <= not src_clk after 78 ns;
  process
  begin
    wait for 6.25 ns;
    if dst_running then dst_clk <= not dst_clk; else dst_clk <= '0'; end if;
  end process;
  dut : entity work.control_snapshot port map (
    src_clk => src_clk, dst_clk => dst_clk, rst => rst,
    torque_in => source_word(23 downto 10), sign_in => source_word(9 downto 1), enable_in => source_word(0),
    torque_out => output_word(23 downto 10), sign_out => output_word(9 downto 1), enable_out => output_word(0));
  process(dst_clk)
    variable previous : std_ulogic_vector(23 downto 0) := (others => '0');
  begin
    if falling_edge(dst_clk) then
      assert output_word = x"000000" or output_word = x"FFFFFF" or output_word = x"555555" or output_word = x"AAAAAA"
        report "Control snapshot contained mixed source values" severity failure;
      if output_word /= previous then transitions <= transitions + 1; end if;
      previous := output_word;
    end if;
  end process;
  process
  begin
    wait for 1 us; rst <= '0';
    for i in 0 to 99 loop
      wait until falling_edge(src_clk);
      case i mod 4 is
        when 0 => source_word <= x"FFFFFF";
        when 1 => source_word <= x"000000";
        when 2 => source_word <= x"555555";
        when others => source_word <= x"AAAAAA";
      end case;
    end loop;
    source_word <= x"FFFFFF"; wait for 3 us;
    assert output_word = x"FFFFFF" and transitions > 2 report "Mailbox did not deliver latest snapshot" severity failure;
    report "TEST_PASS control_atomic_latest";
    dst_running <= false; source_word <= x"555555"; wait for 1 us;
    source_word <= x"AAAAAA"; wait for 1 us;
    rst <= '1'; source_word <= x"000000"; wait for 1 us;
    assert output_word = x"000000" report "Common reset did not clear stopped-domain output" severity failure;
    rst <= '0'; dst_running <= true; wait for 3 us;
    assert output_word = x"000000" report "Stale pre-reset control reappeared" severity failure;
    source_word <= x"FFFFFF"; wait for 3 us;
    assert output_word = x"FFFFFF" report "Mailbox did not recover after reset" severity failure;
    report "TEST_SUMMARY control_snapshot failures=0"; finish;
  end process;
end architecture;
