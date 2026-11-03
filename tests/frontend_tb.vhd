library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.flexray_reference.all;
entity frontend_tb is generic (CHECK_RESET:boolean:=true); end entity;
architecture test of frontend_tb is
  signal clk:std_ulogic:='0';
  signal rst:std_ulogic:='1';
  signal rx0,rx1:std_ulogic:='1';
  signal tx0,tx1,en0,en1,source_rx,valid:std_ulogic;
  signal override_enable:std_ulogic:='0';
  signal override_bit:std_ulogic:='1';
  signal consume:std_ulogic:='0';
  signal log_byte:std_ulogic_vector(7 downto 0);
  signal source_frame:work.flexray.message;
  signal source_valid:std_ulogic;
begin
  clk<=not clk after 6.25 ns;
  dut:entity work.flexray_interceptor port map(clk=>clk,rst=>rst,rx_0=>rx0,rx_1=>rx1,
    tx_0=>tx0,tx_1=>tx1,tx_en_0=>en0,tx_en_1=>en1,rx=>source_rx,
    tx=>override_bit,override=>override_enable,rx_valid=>consume,send_log=>log_byte,ready=>valid);
  source_monitor:entity work.flexray_rx port map(clk=>clk,rst=>rst,rx=>rx1,msg=>source_frame,ready=>source_valid);
  process
    type bytes_t is array(natural range <>) of std_ulogic_vector(7 downto 0);
    variable expected:bytes_t(0 to 37);
    variable observed:bytes_t(0 to 37);
    procedure idle_reset is
    begin
      rst<='1';rx0<='1';rx1<='1';override_enable<='0';consume<='0';
      wait for 2 us;rst<='0';wait for 2 us;
    end procedure;
    procedure check_reset_values is
    begin
      assert tx0='1' and tx1='1' and en0='1' and en1='1' and source_rx='1'
        report "Reset retained dominant/unknown FlexRay output or active enable" severity failure;
    end procedure;
  begin
    wait for 5 us;idle_reset;
    if CHECK_RESET then
      for direction in 0 to 2 loop
        if direction=0 then rx1<='0';
        elsif direction=1 then rx0<='0';
        else override_enable<='1';override_bit<='0';end if;
        wait for 200 ns;
        if direction=1 then assert tx1='0' severity failure;
        else assert tx0='0' severity failure;end if;
        rst<='1';wait for 1 ns;check_reset_values;
        wait for 100 ns;check_reset_values;
        idle_reset;
      end loop;
      -- Fresh traffic after reset must not be suppressed by artificial low history.
      rx1<='0';wait until rising_edge(clk);wait for 1 ns;
      assert tx0='0' report "Reset history blocked fresh dominant input" severity failure;
      rx1<='1';wait for 2 us;
      report "TEST_PASS frontend_reset_all_directions_override";
    end if;
    for words in 0 to 13 loop
    idle_reset;
    send_frame(rx1,30,0,payload_words=>words);wait for 5 us;
    assert source_valid='1' report "Input reference frame invalid" severity failure;
    expected(0 to 8):=(x"CA",x"A0",source_frame.flags & source_frame.frame_id(10 downto 8),
      source_frame.frame_id(7 downto 0),source_frame.payload_length & source_frame.header_crc(10),
      source_frame.header_crc(9 downto 2),source_frame.header_crc(1 downto 0) & source_frame.cycle_count,
      "000" & source_frame.flags,"00" & source_frame.cycle_count);
    for j in 0 to words*2-1 loop expected(9+j):=source_frame.data(j);end loop;
    expected(9+words*2):=source_frame.crc(23 downto 16);
    expected(10+words*2):=source_frame.crc(15 downto 8);
    expected(11+words*2):=source_frame.crc(7 downto 0);
    consume<='1';
    for i in 0 to 11+words*2 loop
      loop wait until rising_edge(clk);exit when valid='1';end loop;
      observed(i):=log_byte;
      assert observed(i)=expected(i)
        report "Standard FIFO delivered stale/shifted/missing log byte index " & integer'image(i) severity failure;
      if i=0 then
        consume<='0';wait for 2 us;
        assert valid='1' and log_byte=expected(1) report "Pending log byte unstable during stall" severity failure;
        consume<='1';
      end if;
    end loop;
    consume<='0';wait for 2 us;
    assert valid='0' report "Unexpected duplicate log byte after complete drain" severity failure;
    end loop;
    report "TEST_PASS frontend_standard_fifo_first_and_final_byte";
    send_frame(rx1,30,0,payload_words=>0);wait for 5 us;
    assert valid='1' report "Second log frame not buffered" severity failure;
    idle_reset;wait for 5 us;
    assert valid='0' report "Warm reset retained a buffered log byte" severity failure;
    report "TEST_PASS frontend_reset_flushes_prefetch";
    report "TEST_SUMMARY frontend failures=0";finish;
  end process;
  process begin wait for 1 ms;report "TEST_TIMEOUT frontend" severity failure;end process;
end architecture;

entity frontend_log_tb is end entity;
architecture test of frontend_log_tb is
begin
  dut:entity work.frontend_tb generic map(CHECK_RESET=>false);
end architecture;
