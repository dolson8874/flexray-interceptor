library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.can_reference.all;

entity log_diagnostics_tb is end entity;
architecture test of log_diagnostics_tb is
  constant CAN_TICK : time := 156666 ps;
  constant CAN_BIT : time := CAN_TICK*8;
  constant PERIOD : positive := 200000; -- 2.5 ms simulation period, production = 1 s
  signal src_clk, dst_clk : std_ulogic := '0';
  signal rst : std_ulogic := '1';
  signal stats : std_ulogic_vector(383 downto 0);
  signal diag_valid, diag_ready, disabled_valid : std_ulogic;
  signal diag_data, disabled_data : std_ulogic_vector(78 downto 0);
  signal drops, stale : std_ulogic_vector(31 downto 0);
  signal a_valid : std_ulogic := '0';
  signal a_ready, valid, ready : std_ulogic;
  signal a_data, data : std_ulogic_vector(78 downto 0);
  signal can_bus, can_tx, peer_ack : std_ulogic := '1';
  signal expected : work.can.message;
  signal diagnostic_frames, other_frames, wire_frames : natural := 0;
  function values(base : unsigned(31 downto 0)) return std_ulogic_vector is
    variable result : std_ulogic_vector(383 downto 0);
  begin
    for p in 0 to 11 loop result(p*32+31 downto p*32) := std_ulogic_vector(base+p); end loop;
    return result;
  end function;
begin
  src_clk <= not src_clk after 6.25 ns;
  dst_clk <= not dst_clk after CAN_TICK/2;
  can_bus <= can_tx and peer_ack;
  a_data <= std_ulogic_vector(to_unsigned(16#321#,11)) & "1000" & x"CAFEBABE11223344";
  diag : entity work.flexray_log_can_diagnostics generic map (
    ENABLED => true, PERIOD_CYCLES => PERIOD, MAX_AGE_CYCLES => 800000)
  port map (src_clk=>src_clk, dst_clk=>dst_clk, rst=>rst, stats=>stats,
    m_valid=>diag_valid, m_ready=>diag_ready, m_data=>diag_data, dropped_full=>drops, dropped_stale=>stale);
  disabled : entity work.flexray_log_can_diagnostics generic map (PERIOD_CYCLES=>PERIOD)
  port map (src_clk=>src_clk, dst_clk=>dst_clk, rst=>rst, stats=>stats,
    m_valid=>disabled_valid, m_ready=>'1', m_data=>disabled_data, dropped_full=>open, dropped_stale=>open);
  mux : entity work.can_telemetry_mux port map (clk=>dst_clk, rst=>rst,
    a_valid=>a_valid, a_ready=>a_ready, a_data=>a_data,
    b_valid=>diag_valid, b_ready=>diag_ready, b_data=>diag_data,
    m_valid=>valid, m_ready=>ready, m_data=>data);
  controller : entity work.joystick_decoder generic map (ENABLE_CAN_TELEMETRY=>true)
  port map (clk=>dst_clk, rst=>rst, rx=>can_bus, tx=>can_tx,
    torque=>open, sign=>open, enable=>open, relay=>open, enCan=>open, debug=>open,
    telemetry_valid=>valid, telemetry_ready=>ready, telemetry_data=>data);

  -- Check full coherent snapshots, page/sequence encoding and held requests.
  process(dst_clk)
    variable previous_stall : boolean := false;
    variable held : std_ulogic_vector(78 downto 0);
    variable p, seq, byte_offset, word_index, byte_index : natural;
    variable reference_value : unsigned(31 downto 0);
  begin
    if rising_edge(dst_clk) then
      if rst='1' then
        diagnostic_frames<=0; other_frames<=0; previous_stall:=false;
      else
        assert disabled_valid='0' report "Default-disabled diagnostics generated traffic" severity failure;
        if previous_stall then assert valid='1' and data=held report "Mux changed a stalled request" severity failure; end if;
        previous_stall:=valid='1' and ready='0'; held:=data;
        if valid='1' and ready='1' then
          expected.id<=data(78 downto 68); expected.len<=data(67 downto 64); expected.dat<=data(63 downto 0);
          if unsigned(data(78 downto 68))=16#1FA# then
            p:=diagnostic_frames mod 8; seq:=diagnostic_frames/8;
            assert data(67 downto 64)="1000" and unsigned(data(63 downto 56))=16#20#+p and
              unsigned(data(55 downto 48))=seq report "Diagnostic ID/DLC/page/sequence mismatch" severity failure;
            for b in 0 to 5 loop
              byte_offset:=p*6+b;word_index:=byte_offset/4;byte_index:=byte_offset mod 4;
              if seq=0 then reference_value:=x"A1B20000"; else reference_value:=x"55660000"; end if;
              reference_value:=reference_value+word_index;
              assert unsigned(data(47-b*8 downto 40-b*8))=reference_value(byte_index*8+7 downto byte_index*8)
                report "Diagnostic snapshot mixed capture times or byte order" severity failure;
            end loop;
            diagnostic_frames<=diagnostic_frames+1;
          else
            assert data=a_data report "Other CAN source corrupted" severity failure;
            other_frames<=other_frames+1;
          end if;
        end if;
      end if;
    end if;
  end process;
  -- Independent wire CRC/stuffing and external ACK for every accepted request.
  process
    variable f : wire_frame;
  begin
    loop
      wait until falling_edge(can_tx);
      if rst='0' then
        f:=encode(expected); wait for CAN_BIT/2;
        for bit_index in 0 to f.count-1 loop
          assert can_tx=f.bits(bit_index) report "Diagnostic CAN wire/CRC/stuffing mismatch" severity failure;
          if bit_index=f.count-1 then wait for CAN_BIT/2; else wait for CAN_BIT; end if;
        end loop;
        peer_ack<='0'; wait for CAN_BIT; peer_ack<='1';
        wire_frames<=wire_frames+1; wait for CAN_BIT*11;
      end if;
    end loop;
  end process;
  process
  begin
    stats<=values(x"A1B20000"); wait for 2 us; rst<='0';
    wait for 1 ms; assert diag_valid='0' report "Diagnostics sent before configured period" severity failure;
    -- Mutate the source during page emission, after capture.
    wait for 1500020 ns; stats<=values(x"55660000"); a_valid<='1';
    for i in 1 to 2 loop
      loop wait until rising_edge(dst_clk); exit when a_ready='1'; end loop;
    end loop;
    a_valid<='0';
    wait until wire_frames=18; wait for 20 us;
    assert diagnostic_frames=16 and other_frames=2 and unsigned(drops)=0 and unsigned(stale)=0 severity failure;
    report "TEST_PASS diagnostic_coherent_pages_mux_and_can_wire";
    rst<='1'; wait for 2 us;
    assert valid='0' and diag_valid='0' severity failure;
    report "TEST_SUMMARY log_diagnostics failures=0"; finish;
  end process;
  process begin wait for 12 ms; report "TEST_TIMEOUT log_diagnostics" severity failure; end process;
end architecture;
