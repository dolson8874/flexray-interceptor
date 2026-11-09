library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.flexray.all;
entity log_dispatch_tb is generic (DEPTH:positive:=2); end entity;
architecture test of log_dispatch_tb is
  signal clk : std_ulogic := '0';
  signal rst : std_ulogic := '1';
  signal dadc_valid, bcm_valid, busy, request, bus_id : std_ulogic := '0';
  signal dadc_frame, bcm_frame, output_frame : work.flexray.message;
  signal dadc_drops, bcm_drops, dadc_count, bcm_count, dadc_peak, bcm_peak : std_ulogic_vector(31 downto 0);
  signal dadc_bytes, bcm_bytes:std_ulogic_vector(31 downto 0);
begin
  clk <= not clk after 6.25 ns;
  dut : entity work.flexray_log_dispatch generic map (QUEUE_DEPTH=>DEPTH) port map (clk => clk, rst => rst,
    dadc_valid => dadc_valid, dadc_frame => dadc_frame,
    bcm_valid => bcm_valid, bcm_frame => bcm_frame, log_busy => busy,
    log_req => request, log_bus => bus_id, log_frame => output_frame,
    dadc_received => dadc_count, bcm_received => bcm_count,
    dadc_dropped => dadc_drops, bcm_dropped => bcm_drops,
    dadc_high_water => dadc_peak, bcm_high_water => bcm_peak,
    dadc_bytes=>dadc_bytes,bcm_bytes=>bcm_bytes);
  process begin wait for 100 us; report "TEST_TIMEOUT log_dispatch" severity failure; end process;
  process
    procedure step is begin wait until falling_edge(clk); end procedure;
    function tagged(tag : natural) return work.flexray.message is
      variable m : work.flexray.message;
    begin
      m.flags := std_ulogic_vector(to_unsigned(tag mod 32, 5));
      m.frame_id := std_ulogic_vector(to_unsigned(tag, 11));
      m.payload_length := "1111111";
      m.header_crc := std_ulogic_vector(to_unsigned((tag*17) mod 2048, 11));
      m.cycle_count := std_ulogic_vector(to_unsigned(tag mod 64, 6));
      for i in 0 to 254 loop m.data(i) := std_logic_vector(to_unsigned((tag+i) mod 256, 8));end loop;
      m.crc := std_ulogic_vector(to_unsigned(tag, 24));
      return m;
    end function;
    procedure publish(d, b : natural) is
    begin
      step; dadc_frame <= tagged(d); bcm_frame <= tagged(b);
      dadc_valid <= '1'; bcm_valid <= '1';
      -- Decoder ready stays high until the next frame begins: count once only.
      for i in 1 to 5 loop step; end loop;
      dadc_valid <= '0'; bcm_valid <= '0'; step;
    end procedure;
    procedure accepted(tag : natural; source : std_ulogic) is
    begin
      if request /= '1' then wait until request = '1'; end if;
      wait for 1 ns;
      assert output_frame = tagged(tag) and bus_id = source
        report "Frame/direction lost, corrupted or reordered" severity failure;
      for i in 1 to 3 loop
        step;
        assert request = '1' and output_frame = tagged(tag) and bus_id = source
          report "Unaccepted request changed" severity failure;
      end loop;
      step; busy <= '1'; step; step;
      assert request = '0' report "Log request not acknowledged" severity failure;
      for i in 1 to 5 loop
        step;
        assert output_frame = tagged(tag) and bus_id = source
          report "Busy logger input overwritten" severity failure;
      end loop;
      busy <= '0'; step;
    end procedure;
  begin
    busy <= '1'; wait for 100 ns; rst <= '0';
    if DEPTH=2 then
    publish(1,11); publish(2,12); publish(3,13);
    assert unsigned(dadc_count)=3 and unsigned(bcm_count)=3 severity failure;
    assert unsigned(dadc_bytes)=798 and unsigned(bcm_bytes)=798
      report "Byte demand lost log overhead or dropped frames" severity failure;
    assert unsigned(dadc_drops)=1 and unsigned(bcm_drops)=1 report "Overflow not counted per direction" severity failure;
    assert unsigned(dadc_peak)=2 and unsigned(bcm_peak)=2 severity failure;
    step; busy <= '0';
    accepted(1,'1'); accepted(11,'0'); accepted(2,'1'); accepted(12,'0');
    step; step; assert request='0' report "Duplicate log request" severity failure;
    report "TEST_PASS bidirectional_simultaneous_fairness_stall_overflow";

    rst <= '1'; step; busy <= '1'; rst <= '0';
    publish(1,11); publish(2,12);
    step; busy <= '0'; dadc_frame <= tagged(3); bcm_frame <= tagged(13);
    dadc_valid <= '1'; bcm_valid <= '1';
    step; dadc_valid <= '0'; bcm_valid <= '0'; step;
    assert unsigned(dadc_drops)=0 and unsigned(bcm_drops)=1
      report "Full queue pop/push replacement mishandled" severity failure;
    accepted(1,'1'); accepted(11,'0'); accepted(2,'1'); accepted(12,'0'); accepted(3,'1');
    report "TEST_PASS bidirectional_full_pop_push_wraparound";
    else
      for pass in 0 to 1 loop
        busy<='1';
        for i in 1 to DEPTH+8 loop publish(i+pass*64,128+i+pass*64); end loop;
        assert unsigned(dadc_count)=(pass+1)*(DEPTH+8) and unsigned(bcm_count)=(pass+1)*(DEPTH+8) severity failure;
        assert unsigned(dadc_drops)=(pass+1)*8 and unsigned(bcm_drops)=(pass+1)*8 severity failure;
        assert unsigned(dadc_bytes)=(pass+1)*(DEPTH+8)*266 and unsigned(bcm_bytes)=(pass+1)*(DEPTH+8)*266 severity failure;
        assert unsigned(dadc_peak)=DEPTH and unsigned(bcm_peak)=DEPTH severity failure;
        busy<='0';step;
        for i in 1 to DEPTH loop accepted(i+pass*64,'1'); accepted(128+i+pass*64,'0'); end loop;
        step;step;assert request='0' report "Deep FIFO duplicated a frame" severity failure;
      end loop;
      report "TEST_PASS bidirectional_deep_fifo_full_order_and_wraparound";
    end if;

    rst <= '1'; step; rst <= '0'; step;
    for i in 1 to 20 loop
      publish(20+i,100+i); accepted(20+i,'1'); accepted(100+i,'0');
    end loop;
    publish(7,17); -- Reset an outstanding request and queued peer.
    rst <= '1'; step;
    assert request='0' and unsigned(dadc_drops)=0 and unsigned(bcm_drops)=0 and
      unsigned(dadc_count)=0 and unsigned(bcm_count)=0 and unsigned(dadc_peak)=0 and unsigned(bcm_peak)=0 severity failure;
    assert unsigned(dadc_bytes)=0 and unsigned(bcm_bytes)=0 severity failure;
    dadc_valid <= '0'; bcm_valid <= '0'; rst <= '0';
    step; step; step; assert request='0' report "Reset retained queued frames" severity failure;
    publish(8,18); accepted(8,'1'); accepted(18,'0');
    report "TEST_PASS bidirectional_reset_and_recovery";
    if DEPTH=2 then report "TEST_SUMMARY log_dispatch failures=0";
    else report "TEST_SUMMARY log_dispatch_deep failures=0";end if;finish;
  end process;
end architecture;

entity log_dispatch_deep_tb is end entity;
architecture test of log_dispatch_deep_tb is
begin
  dut:entity work.log_dispatch_tb generic map(DEPTH=>32);
end architecture;
