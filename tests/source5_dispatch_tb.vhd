library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.flexray.all;
entity source5_dispatch_tb is end entity;
architecture test of source5_dispatch_tb is
  signal clk : std_ulogic := '0';
  signal rst : std_ulogic := '1';
  signal dv, bv, ov, busy, req, bus_id, original : std_ulogic := '0';
  signal dm, bm, om, result_frame : work.flexray.message := work.flexray.EMPTY_MESSAGE;
  signal received, dropped, peak, bytes : std_ulogic_vector(31 downto 0);
begin
  clk <= not clk after 6.25 ns;
  dut : entity work.flexray_log_dispatch generic map(QUEUE_DEPTH=>2) port map(
    clk=>clk,rst=>rst,dadc_valid=>dv,bcm_valid=>bv,dadc_frame=>dm,bcm_frame=>bm,
    log_busy=>busy,log_req=>req,log_bus=>bus_id,log_frame=>result_frame,
    dadc_received=>open,bcm_received=>open,dadc_dropped=>open,bcm_dropped=>open,
    dadc_high_water=>open,bcm_high_water=>open,dadc_bytes=>open,bcm_bytes=>open,
    original_valid=>ov,original_frame=>om,log_original=>original,
    original_received=>received,original_dropped=>dropped,original_high_water=>peak,original_bytes=>bytes);
  process
    function tagged(tag:natural) return work.flexray.message is
      variable m:work.flexray.message:=work.flexray.EMPTY_MESSAGE;
    begin
      m.frame_id:=std_ulogic_vector(to_unsigned(tag,11)); m.payload_length:="1111111";
      m.cycle_count:=std_ulogic_vector(to_unsigned(tag mod 64,6));
      for i in 0 to 254 loop m.data(i):=std_logic_vector(to_unsigned((tag+i) mod 256,8));end loop;
      m.crc:=std_ulogic_vector(to_unsigned(tag*65537,24));return m;
    end function;
    procedure step is begin wait until falling_edge(clk);end procedure;
    procedure publish(tag:natural) is
    begin
      dm<=tagged(tag);bm<=tagged(tag+10);om<=tagged(tag+20);dv<='1';bv<='1';ov<='1';
      for i in 1 to 5 loop step;end loop;
      dv<='0';bv<='0';ov<='0';step;
    end procedure;
    procedure accept(tag,source:natural) is
    begin
      if req/='1' then wait until req='1';end if;wait for 1 ns;
      assert result_frame=tagged(tag) report "Three-source payload/order corruption" severity failure;
      assert (source=5 and original='1') or
        (source=6 and original='0' and bus_id='1') or
        (source=4 and original='0' and bus_id='0') report "Source tag lost" severity failure;
      for i in 1 to 4 loop
        step;assert req='1' and result_frame=tagged(tag) report "Stalled head changed" severity failure;
        if source=5 then assert original='1' severity failure;end if;
      end loop;
      busy<='1';step;step;assert req='0' severity failure;busy<='0';step;
    end procedure;
  begin
    busy<='1';wait for 100 ns;rst<='0';step;
    publish(1);publish(2);publish(3);
    assert unsigned(received)=3 and unsigned(dropped)=1 and unsigned(peak)=2 and unsigned(bytes)=798
      report "Original queue edge/overflow/byte accounting" severity failure;
    busy<='0';step;
    accept(1,6);accept(21,5);accept(11,4);accept(2,6);accept(22,5);accept(12,4);
    step;step;assert req='0' report "Duplicate original" severity failure;
    report "TEST_PASS source5_fairness_stall_and_overflow";
    for i in 4 to 15 loop
      busy<='1';step;publish(i);busy<='0';step;
      accept(i,6);accept(i+20,5);accept(i+10,4);
    end loop;
    busy<='1';step;publish(16);rst<='1';step;rst<='0';step;
    assert req='0' and original='0' and unsigned(received)=0 and unsigned(dropped)=0 and unsigned(bytes)=0
      report "Original queue retained state across reset" severity failure;
    report "TEST_PASS source5_wraparound_and_reset";
    report "TEST_SUMMARY source5_dispatch failures=0";finish;
  end process;
  process begin wait for 100 us;report "TEST_TIMEOUT source5_dispatch" severity failure;end process;
end architecture;
