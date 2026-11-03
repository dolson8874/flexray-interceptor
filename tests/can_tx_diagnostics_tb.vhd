library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

-- Standalone diagnostics: no board, CAN transceiver, or vehicle required.
entity can_tx_diagnostics_tb is
end entity;

architecture test of can_tx_diagnostics_tb is
  constant TICK : time := 156250 ps;
  constant BIT_TIME : time := 8 * TICK;
  signal clk : std_ulogic := '0';
  signal rst : std_ulogic := '1';
  signal ready : std_ulogic := '0';
  signal msg : work.can.message := (
    id => "10101010101", len => "1000", dat => x"A55AA55AA55AA55A");
  signal peer : std_ulogic := '1';
  signal rx, tx, busy, done, arblost, ackerr : std_ulogic;
  signal state, retries : std_ulogic_vector(3 downto 0);
  signal reference_ready : std_ulogic := '0';
  signal reference_msg : work.can.message := (
    id => "10101010101", len => "1000", dat => x"A55AA55AA55AA55A");
  signal reference_tx : std_ulogic;
begin
  clk <= not clk after TICK / 2;
  rx <= tx and peer;
  dut : entity work.can_tx port map (
    clk => clk, rst => rst, ready => ready, msg => msg, rx => rx,
    busy => busy, tx => tx, done => done, dbg_state => state,
    dbg_arblost => arblost, dbg_ack_err => ackerr, retry_count => retries);

  -- Identical undisturbed transmitter for the in-flight request comparison.
  reference_dut : entity work.can_tx port map (
    clk => clk, rst => rst, ready => reference_ready, msg => reference_msg,
    rx => reference_tx, busy => open, tx => reference_tx, done => open,
    dbg_state => open, dbg_arblost => open, dbg_ack_err => open, retry_count => open);

  watchdog : process
  begin
    wait for 2 ms;
    report "TEST_TIMEOUT" severity failure;
  end process;

  stimulus : process
    variable failures : natural := 0;
    variable mismatches : natural;
    variable expected : std_ulogic;
    variable intruded : boolean;
    variable crc : unsigned(14 downto 0);
    variable body_bits : std_ulogic_vector(82 downto 0);
    variable frame_bits : std_ulogic_vector(97 downto 0);
    variable previous_bit : std_ulogic;
    variable run_length : natural;

    procedure reset_dut is
    begin
      rst <= '1'; ready <= '0'; reference_ready <= '0'; peer <= '1';
      wait for 4 * BIT_TIME;
      wait until falling_edge(clk);
      rst <= '0';
      wait for 2 * BIT_TIME;
    end procedure;

    procedure request is
    begin
      wait until falling_edge(clk);
      ready <= '1';
      wait until falling_edge(clk);
      ready <= '0';
    end procedure;

    procedure send_peer_bit(constant value : std_ulogic) is
    begin
      peer <= value;
      wait for BIT_TIME;
      if tx = '0' then intruded := true; end if;
    end procedure;
  begin
    -- Alternating prefix needs no stuffing: check SOF and the eleven ID bits.
    reset_dut;
    request;
    wait until falling_edge(tx);
    wait for BIT_TIME / 2;
    mismatches := 0;
    for i in 0 to 11 loop
      if i = 0 then expected := '0'; else expected := msg.id(11 - i); end if;
      if tx /= expected then
        mismatches := mismatches + 1;
        report "PREFIX bit " & integer'image(i) & " expected " &
          std_ulogic'image(expected) & " observed " & std_ulogic'image(tx);
      end if;
      wait for BIT_TIME;
    end loop;
    if mismatches = 0 then
      report "TEST_PASS prefix";
    else
      report "TEST_FAIL prefix mismatches=" & integer'image(mismatches);
      failures := failures + 1;
    end if;

    -- Start a request inside an incoming data frame. A short recessive run
    -- inside its identifier must not be mistaken for an idle bus.
    reset_dut;
    body_bits := '0' & "00001111000" & "000" & "1000" & x"A55AA55AA55AA55A";
    crc := (others => '0');
    for i in body_bits'range loop
      if (body_bits(i) xor crc(14)) = '1' then
        crc := shift_left(crc, 1) xor to_unsigned(16#4599#, 15);
      else
        crc := shift_left(crc, 1);
      end if;
    end loop;
    frame_bits := body_bits & std_ulogic_vector(crc);
    intruded := false;
    previous_bit := '1'; run_length := 0;
    for i in frame_bits'range loop
      if i = frame_bits'high - 1 then ready <= '1';
      elsif i = frame_bits'high - 2 then ready <= '0'; end if;
      send_peer_bit(frame_bits(i));
      if frame_bits(i) = previous_bit then run_length := run_length + 1;
      else run_length := 1; end if;
      previous_bit := frame_bits(i);
      if run_length = 5 then
        previous_bit := not previous_bit;
        send_peer_bit(previous_bit);
        run_length := 1;
      end if;
    end loop;
    peer <= '1';
    if intruded then
      report "TEST_FAIL bus_idle transmitted_inside_peer_frame";
      failures := failures + 1;
    else
      report "TEST_PASS bus_idle";
    end if;

    -- No remote ACK: observe whether the retry starts with a dominant SOF.
    reset_dut;
    request;
    wait until state = "0110";
    wait until state = "0010";
    wait for BIT_TIME / 2;
    if tx = '0' then
      report "TEST_PASS retry_sof";
    else
      report "TEST_FAIL retry_sof recessive_at_retry_start";
      failures := failures + 1;
    end if;

    -- A second request must not alter a frame already on the wire. Compare
    -- against the same implementation with only the original request.
    reset_dut;
    wait until falling_edge(clk);
    ready <= '1'; reference_ready <= '1';
    wait until falling_edge(clk);
    ready <= '0'; reference_ready <= '0';
    wait until falling_edge(tx);
    wait for 25 * BIT_TIME;
    wait until falling_edge(clk);
    msg.dat <= x"0000000000000000";
    ready <= '1';
    wait until falling_edge(clk);
    ready <= '0';
    mismatches := 0;
    for i in 1 to 32 * 8 loop
      wait until falling_edge(clk);
      if tx /= reference_tx then mismatches := mismatches + 1; end if;
    end loop;
    if mismatches = 0 then
      report "TEST_PASS in_flight_request";
    else
      report "TEST_FAIL in_flight_request changed_active_frame ticks=" & integer'image(mismatches);
      failures := failures + 1;
    end if;
    report "TEST_SUMMARY failures=" & integer'image(failures);
    finish;
  end process;
end architecture;
