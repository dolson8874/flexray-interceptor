library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.flexray_reference.all;

entity cruise_hud_tb is end entity;

architecture test of cruise_hud_tb is
  signal fr_clk, can_clk : std_ulogic := '0';
  signal rst, fr_input, bcm_input : std_ulogic := '1';
  signal can_bus, can_tx, peer_ack, peer_valid : std_ulogic;
  signal hud_sample : std_ulogic_vector(17 downto 0);
  signal peer_message : work.can.message;
  signal hud_count : natural := 0;
  signal second_sample : boolean := false;

  function crc(data : std_ulogic_vector(31 downto 0)) return std_ulogic_vector is
    variable value : std_ulogic_vector(7 downto 0) := x"00";
  begin
    for bit_index in data'range loop
      if (value(7) xor data(bit_index)) = '1' then
        value := (value(6 downto 0) & '0') xor x"1D";
      else
        value := value(6 downto 0) & '0';
      end if;
    end loop;
    return value xor x"CC";
  end function;
begin
  fr_clk <= not fr_clk after 6.25 ns;
  can_clk <= not can_clk after 78125 ps;
  can_bus <= can_tx and peer_ack;

  frontend : entity work.flexray_interceptor
    port map (clk=>fr_clk, rst=>rst, rx_0=>bcm_input, rx_1=>fr_input,
      tx_0=>open, tx_1=>open, tx_en_0=>open, tx_en_1=>open, rx=>open, tx=>'1',
      override=>'0', rx_valid=>'1', send_log=>open, ready=>open, log_stats=>open,
      cruise_hud_sample=>hud_sample);

  dut : entity work.joystick_decoder
    generic map (ENABLE_CAN_TELEMETRY=>true, ENABLE_CRUISE_HUD=>true,
      HUD_PERIOD_CYCLES=>1920, HUD_TIMEOUT_CYCLES=>4800)
    port map (clk=>can_clk, rst=>rst, rx=>can_bus, tx=>can_tx, torque=>open, sign=>open,
      enable=>open, relay=>open, enCan=>open, debug=>open, hud_src_clk=>fr_clk,
      cruise_hud_sample=>hud_sample);

  peer : entity work.can_rx
    port map (clk=>can_clk, rst=>rst, rx=>can_bus, ready=>peer_valid,
      msg=>peer_message, tx=>peer_ack, debug=>open, ack_enable=>'1');

  process(can_clk)
    variable previous_valid : std_ulogic := '0';
    variable content : std_ulogic_vector(31 downto 0);
  begin
    if rising_edge(can_clk) then
      if rst='1' then
        hud_count<=0; previous_valid:='0';
      else
        if peer_valid='1' and previous_valid='0' then
          assert unsigned(peer_message.id)=16#1FB# and peer_message.len="1000"
            report "Unexpected CAN ID or DLC" severity failure;
          if not second_sample then
            content := "0011" & std_ulogic_vector(to_unsigned(hud_count mod 16,4)) & x"035000";
          else
            content := "1100" & std_ulogic_vector(to_unsigned(hud_count mod 16,4)) & x"165000";
          end if;
          assert peer_message.dat = (crc(content) & content & x"000000")
            report "HUD wire bytes differ at counter " & integer'image(hud_count) severity failure;
          hud_count<=hud_count+1;
        end if;
        previous_valid:=peer_valid;
      end if;
    end if;
  end process;

  process
    variable stopped_at : natural;
  begin
    wait for 5 us; rst<='0'; wait for 10 us;
    send_frame(fr_input, 49, 1, nfi=>'0', hud_bytes=>x"03042050"); wait for 10 us;
    send_frame(fr_input, 49, 2, nfi=>'1', hud_bytes=>x"03042050"); wait for 10 us;
    send_frame(fr_input, 49, 1, nfi=>'1', payload_words=>12, hud_bytes=>x"03042050"); wait for 10 us;
    send_frame(fr_input, 49, 1, nfi=>'1', bad_crc=>true, hud_bytes=>x"03042050"); wait for 10 us;
    send_frame(bcm_input, 49, 1, nfi=>'1', hud_bytes=>x"03042050"); wait for 250 us;
    assert hud_count=0 report "Non-HUD input started CAN reporting" severity failure;

    while hud_count < 16 loop
      send_frame(fr_input, 49, 1, nfi=>'1', hud_bytes=>x"03042050"); wait for 35 us;
    end loop;
    wait for 1600 us;
    stopped_at := hud_count;
    assert stopped_at>=18 and stopped_at<=19 report "Unexpected report count before input timeout" severity failure;
    wait for 900 us;
    assert hud_count=stopped_at report "Stale sample continued to send" severity failure;
    second_sample<=true;
    send_frame(fr_input, 49, 9, nfi=>'1', hud_bytes=>x"060A4050");
    wait until hud_count=stopped_at+1;
    rst<='1'; wait for 5 us; rst<='0';
    wait for 400 us;
    assert hud_count=0 report "Reset retained HUD state" severity failure;
    report "TEST_SUMMARY cruise_hud failures=0"; finish;
  end process;
  process begin wait for 10 ms; report "TEST_TIMEOUT cruise_hud" severity failure; end process;
end architecture;
