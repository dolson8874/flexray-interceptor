library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.flexray.all;
use work.flexray_reference.all;
entity source5_frontend_tb is end entity;
architecture test of source5_frontend_tb is
  signal clk:std_ulogic:='0'; signal rst:std_ulogic:='1';
  signal rx0,rx1,tx0,tx1,en0,en1,source_rx,bit_tx,overriding,valid:std_ulogic:='1';
  signal physical0,physical1:std_ulogic;
  signal echo:boolean:=false;
  signal consume,enable:std_ulogic:='0';
  signal sign:std_ulogic_vector(8 downto 0):="100000000";
  signal byte_value:std_ulogic_vector(7 downto 0);
  signal input_frame,output_frame,bcm_frame:work.flexray.message;
  signal input_valid,output_valid,bcm_valid:std_ulogic;
  signal stats:std_ulogic_vector(383 downto 0);
begin
  clk<=not clk after 6.25 ns;
  physical0<=rx0 and tx0 after 50 ns when echo else rx0;
  physical1<=rx1 and tx1 after 50 ns when echo else rx1;
  frontend:entity work.flexray_interceptor port map(clk=>clk,rst=>rst,rx_0=>physical0,rx_1=>physical1,
    tx_0=>tx0,tx_1=>tx1,tx_en_0=>en0,tx_en_1=>en1,rx=>source_rx,tx=>bit_tx,override=>overriding,
    rx_valid=>consume,send_log=>byte_value,ready=>valid,log_stats=>stats);
  modifier:entity work.flexray_torque_intercept port map(clk=>clk,rst=>rst,rx=>source_rx,
    torque=>std_ulogic_vector(to_unsigned(9100,14)),sign=>sign,enable=>enable,
    tx=>bit_tx,override=>overriding,sync_debug=>open);
  original_monitor:entity work.flexray_rx port map(clk=>clk,rst=>rst,rx=>rx1,msg=>input_frame,ready=>input_valid);
  output_monitor:entity work.flexray_rx port map(clk=>clk,rst=>rst,rx=>tx0,msg=>output_frame,ready=>output_valid);
  bcm_monitor:entity work.flexray_rx port map(clk=>clk,rst=>rst,rx=>rx0,msg=>bcm_frame,ready=>bcm_valid);
  process
    procedure reset is
    begin
      consume<='0';enable<='0';sign<="100000000";rst<='1';rx0<='1';rx1<='1';
      wait for 2 us;rst<='0';wait for 3 us;
    end procedure;
    procedure check_log(m:work.flexray.message;marker:std_ulogic_vector(7 downto 0)) is
      type bytes_t is array(0 to 265) of std_ulogic_vector(7 downto 0);
      variable expected:bytes_t;variable n:natural;
    begin
      n:=to_integer(unsigned(m.payload_length))*2;
      expected(0 to 8):=(x"CA",marker,m.flags & m.frame_id(10 downto 8),m.frame_id(7 downto 0),
        m.payload_length & m.header_crc(10),m.header_crc(9 downto 2),m.header_crc(1 downto 0) & m.cycle_count,
        "000" & m.flags,"00" & m.cycle_count);
      for i in 0 to n-1 loop expected(9+i):=std_ulogic_vector(m.data(i));end loop;
      expected(9+n):=m.crc(23 downto 16);expected(10+n):=m.crc(15 downto 8);expected(11+n):=m.crc(7 downto 0);
      consume<='1';
      for i in 0 to 11+n loop
        for timeout in 0 to 2000 loop
          wait until rising_edge(clk);exit when valid='1';
          assert timeout<2000 report "Missing source5 test byte" severity failure;
        end loop;
        assert byte_value=expected(i) report "Wrong source/CRC/body index " & integer'image(i) &
          " expected " & to_hstring(expected(i)) & " observed " & to_hstring(byte_value) severity failure;
      end loop;
      consume<='0';wait for 2 us;
    end procedure;
    procedure dadc(id,cycle:natural;words:natural:=13;bad:boolean:=false;changed:boolean:=false) is
    begin
      send_frame(rx1,id,cycle,bad_crc=>bad,payload_words=>words);wait for 5 us;
      if bad then
        assert valid='0' report "Bad CRC original was logged" severity failure;
      else
        assert input_valid='1' and output_valid='1' report "Reference original/output CRC invalid" severity failure;
        if changed then assert input_frame.data/=output_frame.data report "Modification not exercised" severity failure;end if;
        check_log(output_frame,x"A0");check_log(input_frame,x"90");
        assert valid='0' report "Duplicate source5 record" severity failure;
      end if;
    end procedure;
  begin
    for echo_case in 0 to 1 loop
      echo<=echo_case=1;reset;
      -- Every cycle, including wrap, is captured even without engagement.
      for cycle in 0 to 63 loop
        dadc(31,cycle);dadc(49,cycle);dadc(13,cycle);
      end loop;
      dadc(31,0,127);dadc(49,63,0);dadc(13,1,13,true);
      send_frame(rx1,30,2);wait for 5 us;check_log(output_frame,x"A0");
      assert valid='0' report "Noncandidate original was logged" severity failure;
      -- A reverse candidate with PHY echo must only appear on source4.
      for id_case in 0 to 2 loop
        case id_case is
          when 0=>send_frame(rx0,31,0);
          when 1=>send_frame(rx0,49,1);
          when others=>send_frame(rx0,13,1);
        end case;
        wait for 5 us;check_log(bcm_frame,x"80");
        assert valid='0' report "BCM echo became a DADC original" severity failure;
      end loop;
      report "TEST_PASS source5_all_candidates_cycles_crc_lengths_and_echo";
      reset;dadc(31,0);enable<='1';wait for 1 us;
      dadc(31,4,13,false,true);
      dadc(31,8,13,true); -- Active CRC delta must not hide a corrupt input.
      -- HUD changes can occur with steering permission low.
      enable<='0';wait for 1 us;dadc(31,12); -- Reacquire sync after the corrupt reference.
      sign<="010000000";wait for 1 us;dadc(13,1,13,false,true);
      sign<="010000001";wait for 1 us;dadc(49,1,13,false,true);
      report "TEST_PASS source5_original_retained_during_lkas_and_independent_hud";
      -- Flush both queued records and the active serializer on reset.
      send_frame(rx1,31,8);wait for 5 us;assert valid='1' severity failure;
      reset;wait for 10 us;assert valid='0' report "Reset retained source5 data" severity failure;
    end loop;
    report "TEST_SUMMARY source5_frontend failures=0";finish;
  end process;
  process begin wait for 30 ms;report "TEST_TIMEOUT source5_frontend" severity failure;end process;
end architecture;
