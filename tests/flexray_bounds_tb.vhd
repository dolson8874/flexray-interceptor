library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.flexray_reference.all;
entity flexray_bounds_tb is end entity;
architecture test of flexray_bounds_tb is
  signal clk:std_ulogic:='0';
  signal rst:std_ulogic:='1';
  signal rx, tx, changed, output_rx, raw_valid, output_valid:std_ulogic:='1';
  signal raw_frame, output_frame:work.flexray.message;
begin
  clk<=not clk after 6.25 ns;
  input_decoder:entity work.flexray_rx port map(clk=>clk,rst=>rst,rx=>rx,msg=>raw_frame,ready=>raw_valid);
  dut:entity work.flexray_torque_intercept port map(clk=>clk,rst=>rst,rx=>rx,
    torque=>std_ulogic_vector(to_unsigned(9000,14)),sign=>"010000000",enable=>'1',
    tx=>tx,override=>changed,sync_debug=>open);
  output_rx<=tx when changed='1' else rx;
  output_decoder:entity work.flexray_rx port map(clk=>clk,rst=>rst,rx=>output_rx,msg=>output_frame,ready=>output_valid);
  process
    procedure packet(words:natural; cycle:natural:=0; bad:boolean:=false) is
    begin send_frame(rx,31,cycle,bad_crc=>bad,payload_words=>words); wait for 5 us; end procedure;
  begin
    wait for 1 us; rst<='0'; wait for 5 us;
    -- Prime sync/cache, then exercise the former 2048 physical-bit boundary
    -- and the full seven-bit payload length, including active interception.
    packet(13,0); packet(13,1); packet(13,2); packet(13,3);
    for words in 98 to 127 loop
      packet(words,4);
      assert raw_valid='1' and output_valid='1' and unsigned(output_frame.payload_length)=words
        report "Long frame was lost or corrupted" severity failure;
      assert output_frame.data(words*2-1)=std_logic_vector(to_unsigned(words*2-1,8))
        and output_frame.data(15)=x"A3"
        report "Long frame tail or overridden torque was corrupted" severity failure;
    end loop;
    report "TEST_PASS long_frames_196_through_254_bytes";
    packet(127,4,true);
    assert raw_valid='0' and output_valid='0' report "Bad long-frame CRC accepted" severity failure;
    -- A long dominant level must neither overflow simulation ranges nor
    -- prevent reacquisition after the physical bus becomes idle again.
    rx<='0'; wait for 1 ms; rx<='1'; wait for 10 us;
    packet(13,0); packet(13,1); packet(13,2); packet(13,3); packet(13,4);
    assert raw_valid='1' and output_valid='1' report "Stuck-low recovery failed" severity failure;
    report "TEST_PASS stuck_low_then_valid_frame_recovery";
    -- A reset gives independent empty/short payload checks without LKAS sync.
    rst<='1'; wait for 1 us; rst<='0'; wait for 5 us;
    for words in 0 to 97 loop
      packet(words,2);
      assert raw_valid='1' and output_valid='1' and unsigned(raw_frame.payload_length)=words
        report "Empty/short payload was rejected" severity failure;
    end loop;
    report "TEST_SUMMARY flexray_bounds failures=0"; finish;
  end process;
end architecture;
