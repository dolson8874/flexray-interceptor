library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

-- Review harness: ideal digital I/O, phase sweep, no artificial interbyte gap.
-- Out-of-range clocks are observational. Supported 7.5 MHz and tight CS hold
-- cases are required regressions after the completion-edge correction.
entity spi_timing_review_tb is end entity;
architecture test of spi_timing_review_tb is
  signal clk:std_ulogic:='0';
  signal rst,cs:std_ulogic:='1';
  signal sclk,mosi:std_ulogic:='0';
  signal miso,ready,received:std_ulogic;
  signal din,dout:std_ulogic_vector(7 downto 0);
  signal consumed,rx_count,rx_errors:natural:=0;
  function pattern(n:natural) return std_ulogic_vector is
  begin return std_ulogic_vector(to_unsigned((n*73+165) mod 256,8));end function;
begin
  clk<=not clk after 6.25 ns;
  din<=pattern(consumed);
  dut:entity work.SPI_SLAVE port map(CLK=>clk,RST=>rst,SCLK=>sclk,CS_N=>cs,
    MOSI=>mosi,MISO=>miso,DIN=>din,DIN_VLD=>'1',DIN_RDY=>ready,DOUT=>dout,DOUT_VLD=>received);
  process(clk) begin
    if rising_edge(clk) then
      if rst='1' then consumed<=0;rx_count<=0;rx_errors<=0;
      else
        if ready='1' then consumed<=consumed+1;end if;
        if received='1' then
          if dout/=pattern(rx_count+17) then rx_errors<=rx_errors+1;end if;
          rx_count<=rx_count+1;
        end if;
      end if;
    end if;
  end process;
  process
    type times_t is array(natural range <>) of time;
    constant halves:times_t:=(66667 ps,50 ns,40 ns,31250 ps,25 ns);
    constant holds:times_t:=(0 ns,5 ns,12500 ps,25 ns,50 ns);
    variable observed,input_word:std_ulogic_vector(7 downto 0);
    variable tx_errors,failed_phases,supported_failures,cs_findings:natural:=0;
    procedure reset_dut is
    begin
      wait until falling_edge(clk); -- fixed reference for each 0..12 ns sweep
      rst<='1';cs<='1';sclk<='0';mosi<='0';wait for 200 ns;
      rst<='0';wait for 200 ns;
    end procedure;
    procedure shift_word(n:natural;half_period:time) is
    begin
      input_word:=pattern(n+17);
      for b in 7 downto 0 loop
        mosi<=input_word(b);wait for half_period;
        sclk<='1';observed(b):=miso;wait for half_period;sclk<='0';
      end loop;
    end procedure;
  begin
    for frequency in halves'range loop
      failed_phases:=0;
      for phase in 0 to 24 loop
        reset_dut;wait for phase*500 ps;
        cs<='0';wait for 200 ns;tx_errors:=0;
        for n in 0 to 255 loop
          shift_word(n,halves(frequency));
          if observed/=pattern(n) then tx_errors:=tx_errors+1;end if;
        end loop;
        wait for 200 ns;cs<='1';wait for 200 ns;
        if tx_errors/=0 or rx_errors/=0 or rx_count/=256 or consumed/=257 then
          failed_phases:=failed_phases+1;
        end if;
      end loop;
      if frequency=0 then supported_failures:=failed_phases;end if;
      report "REVIEW_CONTINUOUS half_ps=" & integer'image(halves(frequency)/1 ps) &
        " phases=25 failed_phases=" & integer'image(failed_phases);
    end loop;
    for hold_index in holds'range loop
      failed_phases:=0;
      for phase in 0 to 24 loop
        reset_dut;wait for phase*500 ps;
        cs<='0';wait for 200 ns;
        shift_word(0,66667 ps);wait for holds(hold_index);cs<='1';wait for 500 ns;
        if observed/=pattern(0) or rx_count/=1 or rx_errors/=0 or consumed/=2 then
          failed_phases:=failed_phases+1;
        end if;
        if hold_index=0 and phase=0 and rx_count=0 then
          assert observed=pattern(0) and consumed=1 severity failure;
          cs<='0';wait for 200 ns;shift_word(0,66667 ps);
          wait for 50 ns;cs<='1';wait for 500 ns;
          assert observed=pattern(0) and rx_count=1 and consumed=2 severity failure;
          report "REVIEW_CS_REPLAY master_received_first_byte_twice slave_completed_once";
        end if;
        if rx_count=1 then
          cs<='0';wait for 200 ns;shift_word(1,66667 ps);
          wait for 50 ns;cs<='1';wait for 500 ns;
          assert observed=pattern(1) and rx_count=2 and rx_errors=0 and consumed=3
            report "Completed word replayed or next prefetch lost across CS" severity failure;
        end if;
      end loop;
      cs_findings:=cs_findings+failed_phases;
      report "REVIEW_CS_HOLD hold_ps=" & integer'image(holds(hold_index)/1 ps) &
        " phases=25 failed_phases=" & integer'image(failed_phases);
    end loop;
    assert supported_failures=0 report "7.5 MHz ideal continuous stream failed" severity failure;
    assert cs_findings=0 report "Short CS hold lost/replayed a completed word" severity failure;
    report "TEST_SUMMARY spi_timing_review supported_failures=0 cs_findings=" & integer'image(cs_findings);
    finish;
  end process;
  process begin wait for 30 ms;report "TEST_TIMEOUT spi_timing_review" severity failure;end process;
end architecture;
