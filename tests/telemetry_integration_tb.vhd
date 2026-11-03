library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.can_reference.all;
use work.flexray_reference.all;

entity telemetry_integration_tb is end entity;
architecture test of telemetry_integration_tb is
  constant CAN_TICK : time := 156666 ps; -- existing 600 MHz / 94 CAN clock
  constant CAN_BIT : time := CAN_TICK * 8;
  signal src_clk, dst_clk : std_ulogic := '0';
  signal rst : std_ulogic := '0';
  signal fr_rx, can_bus, can_tx, peer_ack, peer_data : std_ulogic := '1';
  signal valid, ready : std_ulogic;
  signal data : std_ulogic_vector(78 downto 0);
  signal peer_enabled : boolean := true;
  signal transmitted : natural := 0;
  signal disabled_valid : std_ulogic;
  signal monitor_self : boolean := true;
  signal command_torque, snapshot_torque : std_ulogic_vector(13 downto 0);
  signal command_sign, snapshot_sign : std_ulogic_vector(8 downto 0);
  signal command_enable, snapshot_enable : std_ulogic;
  function app_crc(d : std_ulogic_vector(31 downto 0)) return std_ulogic_vector is
    variable c : std_ulogic_vector(7 downto 0) := x"00";
  begin
    for i in d'range loop
      if (c(7) xor d(i)) = '1' then c := (c(6 downto 0) & '0') xor x"1D";
      else c := c(6 downto 0) & '0'; end if;
    end loop;
    return c xor x"CC";
  end function;
begin
  src_clk <= not src_clk after 6.25 ns;
  dst_clk <= not dst_clk after CAN_TICK / 2;
  can_bus <= can_tx and peer_ack and peer_data;
  observer : entity work.flexray_can_telemetry generic map (
    ENABLED => true, FRAME_ID => 31, CYCLE_MASK => 3, CYCLE_VALUE => 1,
    CAN_ID => 16#600#, BYTE_COUNT => 2, BYTE_0 => 15, BYTE_1 => 16,
    MIN_CAPTURE_CYCLES => 0)
    port map (src_clk => src_clk, dst_clk => dst_clk, rst => rst, rx => fr_rx,
      m_valid => valid, m_ready => ready, m_data => data,
      dropped_full => open, dropped_stale => open);
  disabled_observer : entity work.flexray_can_telemetry port map (
    src_clk => src_clk, dst_clk => dst_clk, rst => rst, rx => fr_rx,
    m_valid => disabled_valid, m_ready => '1', m_data => open,
    dropped_full => open, dropped_stale => open);
  controller : entity work.joystick_decoder generic map (ENABLE_CAN_TELEMETRY => true)
    port map (clk => dst_clk, rst => rst, rx => can_bus, tx => can_tx,
      torque => command_torque, sign => command_sign, enable => command_enable, relay => open,
      enCan => open, debug => open, telemetry_valid => valid,
      telemetry_data => data, telemetry_ready => ready);
  mailbox : entity work.control_snapshot port map (
    src_clk => dst_clk, dst_clk => src_clk, rst => rst,
    torque_in => command_torque, sign_in => command_sign, enable_in => command_enable,
    torque_out => snapshot_torque, sign_out => snapshot_sign, enable_out => snapshot_enable);
  process
    variable expected : work.can.message;
    variable f : wire_frame;
  begin
    expected.id := std_ulogic_vector(to_unsigned(16#600#, 11));
    expected.len := "0010"; expected.dat := x"2328000000000000";
    f := encode(expected);
    loop
      wait until falling_edge(can_tx);
      if rst = '0' and monitor_self then
        wait for CAN_BIT / 2;
        for i in 0 to f.count - 1 loop
          assert can_tx = f.bits(i) report "End-to-end CAN payload/CRC/stuff mismatch" severity failure;
          if i = f.count - 1 then wait for CAN_BIT / 2; else wait for CAN_BIT; end if;
        end loop;
        if peer_enabled then peer_ack <= '0'; end if;
        wait for CAN_BIT / 2;
        if not peer_enabled then
          assert can_bus = '1' report "Integrated receiver ACKed its own frame" severity failure;
        end if;
        wait for CAN_BIT / 2; peer_ack <= '1';
        transmitted <= transmitted + 1;
        wait for 11 * CAN_BIT;
      end if;
    end loop;
  end process;
  process begin wait for 500 ms; report "TEST_TIMEOUT integration" severity failure; end process;
  process
    variable external_message : work.can.message;
    procedure send_external(constant m : work.can.message) is
      variable f : wire_frame;
    begin
      f := encode(m);
      for i in 0 to f.count - 1 loop peer_data <= f.bits(i); wait for CAN_BIT; end loop;
      peer_data <= '1'; wait for CAN_BIT / 2;
      assert can_bus = '0' report "Integrated receiver did not ACK external frame" severity failure;
      wait for 12 * CAN_BIT;
    end procedure;
  begin
    wait for 5 us; rst <= '1'; wait for 2 us; rst <= '0'; wait for 20 us;
    send_frame(fr_rx, 30, 1); wait for 50 us;
    send_frame(fr_rx, 31, 2); wait for 50 us;
    send_frame(fr_rx, 31, 1, true); wait for 50 us;
    assert transmitted = 0 report "Invalid/unselected FlexRay frame was forwarded" severity failure;
    send_frame(fr_rx, 31, 1); wait for 200 us;
    assert transmitted = 1 report "Validated FlexRay data did not reach CAN" severity failure;
    send_frame(fr_rx, 31, 5); wait for 200 us;
    assert transmitted = 2 report "Second frame handshaking duplicated or lost data" severity failure;
    assert disabled_valid = '0' report "Default configuration produced traffic" severity failure;
    report "TEST_PASS end_to_end_filter_mapping_can_ack";
    peer_enabled <= false;
    send_frame(fr_rx, 31, 9); wait for 500 us;
    assert transmitted = 4 report "No-ACK integrated retry count incorrect" severity failure;
    wait for 100 us;
    assert transmitted = 4 report "Integrated transmitter retried indefinitely" severity failure;
    report "TEST_PASS integrated_no_self_ack_bounded_retry";
    monitor_self <= false;
    external_message.id := std_ulogic_vector(to_unsigned(16#1F9#, 11));
    external_message.len := "1000"; external_message.dat := x"0001000000008000";
    external_message.dat(63 downto 56) := app_crc(external_message.dat(55 downto 24));
    send_external(external_message);
    external_message.id := std_ulogic_vector(to_unsigned(16#1F0#, 11));
    external_message.dat := x"000100A328000000";
    external_message.dat(63 downto 56) := app_crc(external_message.dat(55 downto 24));
    send_external(external_message); wait for 3 us;
    assert command_enable = '1' and unsigned(command_torque) = 9000
      report "Existing CAN command decoding regressed" severity failure;
    assert snapshot_enable = '1' and snapshot_torque = command_torque and snapshot_sign = command_sign
      report "CAN command did not cross the control mailbox intact" severity failure;
    report "TEST_PASS existing_can_receive_control_mailbox";
    -- A corrupt application HUD must not refresh the relay-health timeout.
    wait for 190 ms;
    external_message.id := std_ulogic_vector(to_unsigned(16#1F9#, 11));
    external_message.dat := x"0002000000008000";
    external_message.dat(63 downto 56) := app_crc(external_message.dat(55 downto 24)) xor x"01";
    send_external(external_message); wait for 20 ms;
    external_message.id := std_ulogic_vector(to_unsigned(16#1F0#, 11));
    external_message.dat := x"000200A328000000";
    external_message.dat(63 downto 56) := app_crc(external_message.dat(55 downto 24));
    send_external(external_message); wait for 3 us;
    assert command_enable = '0' report "Corrupt HUD refreshed CAN health" severity failure;
    -- The same HUD counter must still be accepted after a bad-CRC packet.
    external_message.id := std_ulogic_vector(to_unsigned(16#1F9#, 11));
    external_message.dat := x"0002000000008000";
    external_message.dat(63 downto 56) := app_crc(external_message.dat(55 downto 24));
    send_external(external_message);
    external_message.id := std_ulogic_vector(to_unsigned(16#1F0#, 11));
    external_message.dat := x"000200A328000000";
    external_message.dat(63 downto 56) := app_crc(external_message.dat(55 downto 24));
    send_external(external_message); wait for 3 us;
    assert command_enable = '1' report "Valid HUD counter recovery failed" severity failure;
    report "TEST_PASS invalid_hud_health_and_counter_recovery";
    -- Expire watchdog, reset, and receive a command before the first 10ms tick.
    wait for 110 ms; rst <= '1'; wait for 2 us; rst <= '0'; wait for 20 us;
    external_message.id := std_ulogic_vector(to_unsigned(16#1F9#, 11));
    external_message.dat := x"0001000000008000";
    external_message.dat(63 downto 56) := app_crc(external_message.dat(55 downto 24));
    send_external(external_message);
    external_message.id := std_ulogic_vector(to_unsigned(16#1F0#, 11));
    external_message.dat := x"000100A328000000";
    external_message.dat(63 downto 56) := app_crc(external_message.dat(55 downto 24));
    send_external(external_message); wait for 11 ms;
    assert command_enable = '1' report "Warm reset retained expired watchdog" severity failure;
    report "TEST_PASS can_watchdog_warm_reset";
    report "TEST_SUMMARY integration failures=0"; finish;
  end process;
end architecture;
