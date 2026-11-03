library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.can_reference.all;

entity can_protocol_tb is end entity;
architecture test of can_protocol_tb is
  constant TICK : time := 156250 ps;
  constant BT : time := 8 * TICK;
  signal clk : std_ulogic := '0';
  signal rst : std_ulogic := '1';
  signal request, peer : std_ulogic := '0';
  signal rx, tx, ack_tx, busy, done, active, success, bit_err, arb_err, ack_err : std_ulogic;
  signal ack_enable : std_ulogic := '0';
  signal tx_msg, rx_msg : work.can.message;
  signal received : std_ulogic;
  signal received_count : natural := 0;
  signal captured : work.can.message;
  signal retries : std_ulogic_vector(3 downto 0);
begin
  clk <= not clk after TICK / 2;
  rx <= tx and peer and ack_tx;
  sender : entity work.can_tx port map (
    clk => clk, rst => rst, ready => request, msg => tx_msg, rx => rx,
    busy => busy, tx => tx, done => done, active => active, success => success,
    dbg_state => open, dbg_arblost => arb_err, dbg_ack_err => ack_err,
    dbg_bit_err => bit_err, retry_count => retries);
  receiver : entity work.can_rx port map (
    clk => clk, rst => rst, rx => rx, debug => open, tx => ack_tx,
    msg => rx_msg, ready => received, ack_enable => ack_enable);
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then received_count <= 0;
      elsif received = '1' then received_count <= received_count + 1; captured <= rx_msg; end if;
    end if;
  end process;
  process begin wait for 30 ms; report "TEST_TIMEOUT protocol" severity failure; end process;
  process
    variable m : work.can.message;
    variable frame : wire_frame;
    variable covered_final_stuff : boolean := false;
    procedure reset_dut is
    begin
      rst <= '1'; request <= '0'; peer <= '1'; ack_enable <= '0';
      wait for 4 * BT; rst <= '0'; wait for 14 * BT;
    end procedure;
    procedure send_request is
    begin
      wait until falling_edge(clk); request <= '1';
      wait until falling_edge(clk); request <= '0';
    end procedure;
    procedure send_reference(constant f : wire_frame; constant valid_ack : boolean;
                             constant bad_eof : boolean := false;
                             constant peer_bt : time := BT) is
    begin
      for i in 0 to f.count - 1 loop peer <= f.bits(i); wait for peer_bt; end loop;
      peer <= '1'; wait for peer_bt / 2;
      if valid_ack then assert ack_tx = '0' report "RX missing ACK" severity failure;
      else assert ack_tx = '1' report "RX ACKed rejected frame" severity failure; end if;
      wait for peer_bt / 2;
      wait for peer_bt / 2;
      assert ack_tx = '1' report "RX ACK extended into delimiter" severity failure;
      wait for peer_bt / 2;
      for i in 0 to 6 loop
        if bad_eof and i = 2 then peer <= '0'; else peer <= '1'; end if;
        wait for peer_bt;
      end loop;
      peer <= '1'; wait for 14 * BT;
    end procedure;
  begin
    m.id := "10101010101"; m.len := "1000"; m.dat := x"A55AA55AA55AA55A";
    -- Full wire comparison, including zero/eight-byte payloads and long runs.
    for test_case in 0 to 13 loop
      reset_dut;
      case test_case is
        when 0 => m.id := "00000000000"; m.len := "0000"; m.dat := (others => '0');
        when 1 => m.id := "11111111111"; m.len := "1000"; m.dat := (others => '1');
        when 2 => m.id := "10101010101"; m.len := "1000"; m.dat := x"A55AA55AA55AA55A";
        when 3 => m.id := "00000000000"; m.len := "1000"; m.dat := (others => '0');
        when 4 =>
          -- Search independently for a final-CRC stuffing boundary case.
          m.len := "0001"; m.dat := (others => '0');
          for identifier in 0 to 2047 loop
            m.id := std_ulogic_vector(to_unsigned(identifier, 11));
            frame := encode(m);
            exit when frame.final_crc_stuff;
          end loop;
          assert frame.final_crc_stuff report "No final CRC stuff vector found" severity failure;
          covered_final_stuff := true;
        when others =>
          m.id := std_ulogic_vector(to_unsigned(16#123# + test_case, 11));
          m.len := std_ulogic_vector(to_unsigned(test_case - 5, 4));
          m.dat := x"0102030405060708";
      end case;
      tx_msg <= m; frame := encode(m); send_request;
      wait until falling_edge(tx); wait for BT / 2;
      for i in 0 to frame.count - 1 loop
        assert tx = frame.bits(i) report "TX wire mismatch at " & integer'image(i) severity failure;
        if i = frame.count - 1 then wait for BT / 2; else wait for BT; end if;
      end loop;
      peer <= '0'; wait for BT; peer <= '1';
      wait until done = '1';
      assert success = '1' and ack_err = '0' and bit_err = '0' report "TX rejected valid ACK" severity failure;
      assert received_count = 0 report "Receiver delivered its own inhibited frame" severity failure;
    end loop;
    assert covered_final_stuff severity failure;
    report "TEST_PASS full_wire_crc_stuff_ack (14 vectors, DLC 0..8)";

    reset_dut; ack_enable <= '1'; frame := encode(m);
    send_reference(frame, true);
    assert received_count = 1 and captured.id = m.id and captured.len = m.len and
      captured.dat = m.dat report "RX valid-frame delivery failed" severity failure;
    report "TEST_PASS receive_ack_delivery";

    reset_dut; ack_enable <= '1'; frame := encode(m, true);
    send_reference(frame, false);
    assert received_count = 0 report "RX delivered corrupt CRC" severity failure;
    report "TEST_PASS receive_bad_crc";

    reset_dut; ack_enable <= '1'; frame := encode(m);
    send_reference(frame, true, true);
    assert received_count = 0 report "RX delivered malformed EOF" severity failure;
    report "TEST_PASS receive_bad_eof";

    reset_dut; ack_enable <= '1';
    m.id := "00000000000"; m.len := "1000"; m.dat := (others => '0');
    frame := encode(m); frame.bits(5) := '0'; -- violate the first stuff bit
    send_reference(frame, false);
    assert received_count = 0 report "RX delivered invalid stuffing" severity failure;
    report "TEST_PASS receive_bad_stuff";

    reset_dut; ack_enable <= '1'; frame := encode(m);
    frame.bits(frame.count - 1) := '0'; -- CRC delimiter must be recessive
    send_reference(frame, false);
    assert received_count = 0 report "RX delivered invalid CRC delimiter" severity failure;
    report "TEST_PASS receive_bad_crc_delimiter";

    for offset in 0 to 7 loop
      reset_dut; ack_enable <= '1';
      m.id := "10101010101"; m.len := "1000"; m.dat := x"00000000FFFFFFFF";
      frame := encode(m); wait for offset * TICK / 8;
      if offset mod 2 = 0 then send_reference(frame, true, false, BT * 1003 / 1000);
      else send_reference(frame, true, false, BT * 997 / 1000); end if;
      assert received_count = 1 and captured.dat = m.dat report "RX phase/rate tolerance failed" severity failure;
    end loop;
    report "TEST_PASS receive_phase_and_rate_offsets (8 vectors)";

    reset_dut; m.id := "10101010101"; tx_msg <= m;
    m.id := "00101010101"; frame := encode(m); send_request;
    wait until falling_edge(tx);
    for i in 0 to frame.count - 1 loop
      peer <= frame.bits(i); wait for BT;
      if arb_err = '1' then assert tx = '1' report "TX drove bus after arbitration loss" severity failure; end if;
    end loop;
    peer <= '1';
    assert arb_err = '1' and unsigned(retries) = 1 report "TX did not detect arbitration loss" severity failure;
    wait until done = '1';
    assert success = '0' report "Unacknowledged arbitration retry reported success" severity failure;
    report "TEST_PASS arbitration_loss_release_retry";

    reset_dut; m.id := "10101010101"; tx_msg <= m; send_request;
    wait until falling_edge(tx); wait for 25 * BT;
    if tx /= '1' then wait until rising_edge(tx); end if;
    peer <= '0'; wait for 2 * BT; peer <= '1';
    wait until done = '1';
    assert success = '0' and bit_err = '1' report "Data bit error not diagnosed" severity failure;
    report "TEST_PASS data_bit_error";

    reset_dut; tx_msg <= m; send_request;
    wait until done = '1';
    assert success = '0' and ack_err = '1' and unsigned(retries) = 1
      report "Missing ACK did not terminate after bounded retry" severity failure;
    report "TEST_PASS missing_ack_retry_limit";

    reset_dut; m.len := "1001"; tx_msg <= m; send_request;
    wait until done = '1';
    assert success = '0' and tx = '1' report "Invalid DLC was transmitted" severity failure;
    report "TEST_PASS invalid_dlc";
    reset_dut; m.len := "1000"; tx_msg <= m; peer <= '0'; send_request;
    wait until done = '1';
    assert success = '0' and tx = '1' report "Busy bus timeout did not release the request" severity failure;
    report "TEST_PASS busy_bus_wait_timeout";
    report "TEST_SUMMARY protocol failures=0"; finish;
  end process;
end architecture;
