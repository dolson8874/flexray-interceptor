library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity spi_recovery_tb is end entity;
architecture test of spi_recovery_tb is
  signal clk:std_ulogic:='0';
  signal rst:std_ulogic:='1';
  signal sclk,mosi:std_ulogic:='0';
  signal cs:std_ulogic:='1';
  signal miso,ready,valid,received:std_ulogic;
  signal din,dout,last_received:std_ulogic_vector(7 downto 0);
  signal consumed,rx_count:natural:=0;
begin
  clk<=not clk after 6.25 ns;
  din<=x"A5" when consumed=0 else x"3C" when consumed=1 else x"69";
  valid<='1' when consumed<3 else '0';
  dut:entity work.SPI_SLAVE port map(CLK=>clk,RST=>rst,SCLK=>sclk,CS_N=>cs,
    MOSI=>mosi,MISO=>miso,DIN=>din,DIN_VLD=>valid,DIN_RDY=>ready,DOUT=>dout,DOUT_VLD=>received);
  process(clk)
  begin
    if rising_edge(clk) then
      if rst='1' then consumed<=0; rx_count<=0; last_received<=(others=>'0');
      else
        if ready='1' and valid='1' then consumed<=consumed+1; end if;
        if received='1' then rx_count<=rx_count+1; last_received<=dout; end if;
      end if;
    end if;
  end process;
  process
    variable data:std_ulogic_vector(7 downto 0);
    variable previous_count,previous_consumed:natural;
    procedure shift(constant value:std_ulogic_vector(7 downto 0); constant bits:natural:=8) is
    begin
      for i in 7 downto 8-bits loop
        mosi<=value(i); wait for 500 ns;
        sclk<='1'; data(i):=miso; wait for 500 ns; sclk<='0';
      end loop;
      wait for 200 ns;
    end procedure;
    procedure reset_dut is
    begin rst<='1';cs<='1';sclk<='0';wait for 200 ns;rst<='0';wait for 500 ns;end procedure;
  begin
    for partial in 1 to 7 loop
      reset_dut; assert consumed=1 report "Initial prefetch was not exactly one word" severity failure;
      cs<='0';wait for 200 ns;shift(x"FF",partial);cs<='1';wait for 500 ns;
      assert rx_count=0 and consumed=1 report "Partial transaction consumed another word" severity failure;
      cs<='0';wait for 200 ns;shift(x"12");
      assert data=x"A5" and rx_count=1 and last_received=x"12" and consumed=2
        report "CS abort did not restore TX word and RX byte boundary" severity failure;
      shift(x"34");
      assert data=x"3C" and rx_count=2 and last_received=x"34" and consumed=3
        report "Continuous-CS second word was corrupt or duplicated" severity failure;
      cs<='1';wait for 500 ns;cs<='0';wait for 200 ns;shift(x"56");
      assert data=x"69" and rx_count=3 and last_received=x"56" and consumed=3
        report "Prefetched word was lost across CS boundary" severity failure;
      cs<='1';wait for 500 ns;
    end loop;
    report "TEST_PASS spi_abort_recovery_all_partial_lengths";
    reset_dut;cs<='0';wait for 200 ns;shift(x"FF",7);cs<='1';wait for 500 ns;
    previous_count:=rx_count;previous_consumed:=consumed;
    shift(x"00",8); -- clocks while deselected must not complete a byte
    assert rx_count=previous_count and consumed=previous_consumed
      report "Deselected clock generated receive/ready activity" severity failure;
    cs<='0';wait for 200 ns;shift(x"78");
    assert data=x"A5" and last_received=x"78" and rx_count=1
      report "Deselected clocks damaged the pending word" severity failure;
    report "TEST_PASS spi_deselected_clocks_ignored";
    reset_dut;cs<='0';wait for 200 ns;
    shift(x"12");shift(x"34");shift(x"56");shift(x"AB");
    assert data=x"00" and consumed=3 and rx_count=4 and last_received=x"AB"
      report "Empty TX stream echoed MOSI or consumed nonexistent data" severity failure;
    report "TEST_PASS spi_empty_tx_zero_filler";
    shift(x"FF",3);rst<='1';wait for 200 ns;
    assert ready='0' and received='0' and miso='0'
      report "Reset left a handshake or stale MISO active" severity failure;
    cs<='1';rst<='0';wait for 500 ns;cs<='0';wait for 200 ns;shift(x"9A");
    assert data=x"A5" and last_received=x"9A" and rx_count=1 and consumed=2
      report "Warm reset did not recover SPI alignment and prefetch" severity failure;
    report "TEST_PASS spi_warm_reset_recovery";
    report "TEST_SUMMARY spi_recovery failures=0";finish;
  end process;
end architecture;
