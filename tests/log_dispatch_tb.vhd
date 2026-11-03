library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
entity log_dispatch_tb is end entity;
architecture test of log_dispatch_tb is
  signal clk : std_ulogic := '0';
  signal rst : std_ulogic := '1';
  signal valid, busy, request : std_ulogic := '0';
  signal frame, output_frame : work.flexray.message;
  signal drops : std_ulogic_vector(31 downto 0);
begin
  clk <= not clk after 6.25 ns;
  dut : entity work.flexray_log_dispatch port map (clk => clk, rst => rst,
    frame_valid => valid, frame => frame, log_busy => busy,
    log_req => request, log_frame => output_frame, dropped => drops);
  process begin wait for 50 us; report "TEST_TIMEOUT log_dispatch" severity failure; end process;
  process
    procedure step is begin wait until falling_edge(clk); end procedure;
    procedure publish(tag : natural) is
    begin
      step; frame.frame_id <= std_ulogic_vector(to_unsigned(tag, 11)); valid <= '1';
      step; valid <= '0'; step;
    end procedure;
    procedure accepted(tag : natural) is
    begin
      if request /= '1' then wait until request = '1'; end if;
      wait for 1 ns;
      assert unsigned(output_frame.frame_id) = tag report "Log request lost/reordered" severity failure;
      step; busy <= '1'; step; step;
      assert request = '0' report "Log request not acknowledged" severity failure;
    end procedure;
  begin
    wait for 100 ns; rst <= '0'; publish(1); accepted(1);
    publish(2); publish(3);
    assert unsigned(output_frame.frame_id) = 1 report "Busy logger input overwritten" severity failure;
    assert unsigned(drops) = 1 report "Overflow not counted" severity failure;
    step; busy <= '0'; accepted(2); -- no additional arrival to drain pending
    report "TEST_PASS log_pending_drains_without_new_frame";
    publish(4);
    step; busy <= '0';
    frame.frame_id <= std_ulogic_vector(to_unsigned(5, 11)); valid <= '1';
    step; valid <= '0'; accepted(4);
    step; busy <= '0'; accepted(5);
    step; busy <= '0'; step; step;
    assert request = '0' report "Duplicate log request" severity failure;
    rst <= '1'; step; assert request = '0' and unsigned(drops) = 0 severity failure;
    report "TEST_SUMMARY log_dispatch failures=0"; finish;
  end process;
end architecture;
