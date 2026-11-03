library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity flexray_timing_equivalence_tb is end entity;
architecture test of flexray_timing_equivalence_tb is
  signal clk : std_ulogic := '0';
  signal rst : std_ulogic := '1';
  signal rx : std_ulogic := '1';
  signal torque : std_ulogic_vector(13 downto 0) := std_ulogic_vector(to_unsigned(9000, 14));
  signal sign : std_ulogic_vector(8 downto 0) := "010000000";
  signal enable : std_ulogic := '1';
  signal tx_new, tx_old, override_new, override_old, sync_new, sync_old : std_ulogic;
  signal override_clocks : natural := 0;
  signal compare_enabled : boolean := false;
begin
  clk <= not clk after 6.25 ns;
  current_dut : entity work.flexray_torque_intercept port map (
    clk => clk, rst => rst, rx => rx, torque => torque, sign => sign, enable => enable,
    tx => tx_new, override => override_new, sync_debug => sync_new);
  baseline_dut : entity work.baseline_torque_intercept port map (
    clk => clk, rst => rst, rx => rx, torque => torque, sign => sign, enable => enable,
    tx => tx_old, override => override_old, sync_debug => sync_old);
  process(clk)
  begin
    if falling_edge(clk) and rst = '0' then
      if compare_enabled then
        assert tx_new = tx_old and override_new = override_old and sync_new = sync_old
          report "Steady-state FlexRay serial behavior changed" severity failure;
      end if;
      if override_new = '1' then override_clocks <= override_clocks + 1; end if;
    end if;
  end process;
  process
    variable frame : work.flexray.message;
    variable header : std_ulogic_vector(39 downto 0);
    variable header_crc : std_ulogic_vector(10 downto 0);
    variable frame_crc : std_ulogic_vector(23 downto 0);
    procedure wire_bit(b : std_ulogic) is
    begin rx <= b; wait for 100 ns; end procedure;
    procedure crc_step(b : std_ulogic) is
    begin
      if (b xor frame_crc(23)) = '1' then
        frame_crc := (frame_crc(22 downto 0) & '0') xor x"5D6DCB";
      else frame_crc := frame_crc(22 downto 0) & '0'; end if;
    end procedure;
    procedure wire_byte(b : std_ulogic_vector(7 downto 0)) is
    begin
      wire_bit('1'); wire_bit('0');
      for j in 7 downto 0 loop wire_bit(b(j)); end loop;
    end procedure;
  begin
    wait for 1 us; rst <= '0'; wait for 5 us;
    frame.flags := (others => '0'); frame.payload_length := "0001101";
    frame.data := (others => (others => '0'));
    frame.data(15) := x"23"; frame.data(16) := x"28"; frame.data(25) := x"60";
    for packet in 0 to 15 loop
      -- Initial cycle-1 data is now inhibited until its CRC-valid cache exists.
      if packet = 4 then compare_enabled <= true; end if;
      frame.cycle_count := std_ulogic_vector(to_unsigned(packet, 6));
      if packet < 8 then frame.frame_id := std_ulogic_vector(to_unsigned(31, 11));
      elsif packet < 12 then frame.frame_id := std_ulogic_vector(to_unsigned(49, 11));
      else frame.frame_id := std_ulogic_vector(to_unsigned(13, 11)); end if;
      -- Compare unchanged-command steady state. Per-header torque updates
      -- intentionally differ from the baseline and have a separate regression.
      header := frame.flags & frame.frame_id & frame.payload_length & "00000000000" & frame.cycle_count;
      header_crc := std_ulogic_vector(to_unsigned(26, 11));
      for j in 36 downto 17 loop
        if (header(j) xor header_crc(10)) = '1' then
          header_crc := (header_crc(9 downto 0) & '0') xor "01110000101";
        else header_crc := header_crc(9 downto 0) & '0'; end if;
      end loop;
      header(16 downto 6) := header_crc;
      frame_crc := x"FEDCBA";
      for j in 39 downto 0 loop crc_step(header(j)); end loop;
      for j in 0 to 25 loop
        for k in 7 downto 0 loop crc_step(frame.data(j)(k)); end loop;
      end loop;
      for j in 1 to 9 loop wire_bit('0'); end loop;
      wire_bit('1');
      for j in 0 to 4 loop wire_byte(header(39 - j * 8 downto 32 - j * 8)); end loop;
      for j in 0 to 25 loop wire_byte(std_ulogic_vector(frame.data(j))); end loop;
      for j in 0 to 2 loop wire_byte(frame_crc(23 - j * 8 downto 16 - j * 8)); end loop;
      wire_bit('0'); wire_bit('1'); wait for 5 us;
    end loop;
    assert override_clocks > 100 report "Equivalence test did not exercise overrides" severity failure;
    report "TEST_SUMMARY equivalence failures=0 override_clocks=" & integer'image(override_clocks);
    finish;
  end process;
end architecture;
