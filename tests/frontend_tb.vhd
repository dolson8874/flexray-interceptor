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
  signal bcm_frame:work.flexray.message;
  signal bcm_valid:std_ulogic;
  signal stats:std_ulogic_vector(383 downto 0);
  signal spi_done,padding_tick:std_ulogic:='0';
  signal physical_rx0,physical_rx1:std_ulogic;
  signal emulate_echo:boolean:=false;
begin
  clk<=not clk after 6.25 ns;
  -- Representative PHY loopback delay, not a measured board specification.
  -- A zero-delay loop is outside the existing bridge's echo guard assumption.
  physical_rx0<=rx0 and tx0 after 50 ns when emulate_echo else rx0;
  physical_rx1<=rx1 and tx1 after 50 ns when emulate_echo else rx1;
  dut:entity work.flexray_interceptor port map(clk=>clk,rst=>rst,rx_0=>physical_rx0,rx_1=>physical_rx1,
    tx_0=>tx0,tx_1=>tx1,tx_en_0=>en0,tx_en_1=>en1,rx=>source_rx,
    tx=>override_bit,override=>override_enable,rx_valid=>consume,send_log=>log_byte,ready=>valid,log_stats=>stats,
    spi_byte_done=>spi_done);
  -- Model a byte-complete pulse per consumed byte, with optional idle filler.
  process(clk) begin
    if rising_edge(clk) then
      if rst='1' then spi_done<='0';else spi_done<=(consume and valid) or padding_tick;end if;
    end if;
  end process;
  source_monitor:entity work.flexray_rx port map(clk=>clk,rst=>rst,rx=>rx1,msg=>source_frame,ready=>source_valid);
  bcm_monitor:entity work.flexray_rx port map(clk=>clk,rst=>rst,rx=>rx0,msg=>bcm_frame,ready=>bcm_valid);
  process
    type bytes_t is array(natural range <>) of std_ulogic_vector(7 downto 0);
    variable expected:bytes_t(0 to 265);
    variable observed:bytes_t(0 to 265);
    variable reference_frame:work.flexray.message;
    variable words:natural;
    type frames_t is array(0 to 2) of work.flexray.message;
    variable mixed_frames:frames_t;
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
    procedure check_log(constant m:work.flexray.message; constant marker:std_ulogic_vector(7 downto 0)) is
      variable length_bytes:natural;
    begin
      length_bytes:=to_integer(unsigned(m.payload_length))*2;
      expected(0 to 8):=(x"CA",marker,m.flags & m.frame_id(10 downto 8),
        m.frame_id(7 downto 0),m.payload_length & m.header_crc(10),
        m.header_crc(9 downto 2),m.header_crc(1 downto 0) & m.cycle_count,
        "000" & m.flags,"00" & m.cycle_count);
      for j in 0 to length_bytes-1 loop expected(9+j):=m.data(j);end loop;
      expected(9+length_bytes):=m.crc(23 downto 16);
      expected(10+length_bytes):=m.crc(15 downto 8);
      expected(11+length_bytes):=m.crc(7 downto 0);
      consume<='1';
      for i in 0 to 11+length_bytes loop
        for timeout in 0 to 2000 loop
          wait until rising_edge(clk);
          exit when valid='1';
          assert timeout<2000 report "Missing log byte index " & integer'image(i) &
            " marker=" & to_hstring(marker) & " echo=" & boolean'image(emulate_echo) &
            " payload=" & integer'image(length_bytes) severity failure;
        end loop;
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
    for echo_case in 0 to 1 loop
    emulate_echo<=echo_case=1;
    for direction in 0 to 1 loop
    for length_case in 0 to 14 loop
    if length_case=14 then words:=127; else words:=length_case; end if;
    idle_reset;
    if direction=0 then
      send_frame(rx1,30,0,payload_words=>words); wait for 5 us;
      assert source_valid='1' report "DADC input reference frame invalid" severity failure;
      reference_frame:=source_frame;
    else
      send_frame(rx0,30,0,payload_words=>words); wait for 5 us;
      assert bcm_valid='1' report "BCM input reference frame invalid" severity failure;
      reference_frame:=bcm_frame;
    end if;
    if direction=0 then check_log(reference_frame,x"A0");
    else check_log(reference_frame,x"80");end if;
    assert valid='0' report "Unexpected duplicate log byte after complete drain" severity failure;
    if direction=0 then
      assert unsigned(stats(31 downto 0))=1 and unsigned(stats(63 downto 32))=0 severity failure;
      assert unsigned(stats(287 downto 256))=12+words*2 and unsigned(stats(319 downto 288))=0 severity failure;
    else
      assert unsigned(stats(31 downto 0))=0 and unsigned(stats(63 downto 32))=1 severity failure;
      assert unsigned(stats(287 downto 256))=0 and unsigned(stats(319 downto 288))=12+words*2 severity failure;
    end if;
    assert unsigned(stats(351 downto 320))=12+words*2 report "SPI valid-byte accounting wrong during stalls" severity failure;
    assert unsigned(stats(383 downto 352))=12+words*2 report "SPI clocked-byte accounting wrong" severity failure;
    assert unsigned(stats(127 downto 64))=0 report "Unexpected frame drops" severity failure;
    assert unsigned(stats(191 downto 160))=0 and unsigned(stats(223 downto 192))>0
      report "FIFO level/high-water accounting incorrect" severity failure;
    end loop;
    end loop;
    end loop;
    report "TEST_PASS frontend_standard_fifo_first_and_final_byte";
    report "TEST_PASS frontend_phy_echo_no_duplicate_and_fifo_statistics";
    idle_reset;
    send_frame(rx1,30,1,payload_words=>13);wait for 5 us;mixed_frames(0):=source_frame;
    send_frame(rx0,30,2,payload_words=>0);wait for 5 us;mixed_frames(1):=bcm_frame;
    send_frame(rx1,30,3,payload_words=>127);wait for 5 us;mixed_frames(2):=source_frame;
    check_log(mixed_frames(0),x"A0");check_log(mixed_frames(1),x"80");check_log(mixed_frames(2),x"A0");
    assert valid='0' and unsigned(stats(31 downto 0))=2 and unsigned(stats(63 downto 32))=1 and
      unsigned(stats(127 downto 64))=0 report "Mixed stream duplicated/lost direction" severity failure;
    assert unsigned(stats(287 downto 256))=304 and unsigned(stats(319 downto 288))=12 and
      unsigned(stats(351 downto 320))=316 report "Mixed stream demand/drain accounting wrong" severity failure;
    send_frame(rx0,30,4,bad_crc=>true);wait for 5 us;
    send_frame(rx1,30,5,bad_crc=>true);wait for 5 us;
    assert valid='0' report "Bad-CRC frames were logged" severity failure;
    assert unsigned(stats(287 downto 256))=304 and unsigned(stats(319 downto 288))=12
      report "Rejected CRC was included in byte demand" severity failure;
    for i in 1 to 4 loop
      wait until falling_edge(clk);padding_tick<='1';
      wait until falling_edge(clk);padding_tick<='0';
    end loop;
    wait for 100 ns;
    assert unsigned(stats(351 downto 320))=316 and unsigned(stats(383 downto 352))=320
      report "SPI idle filler was counted as valid log data" severity failure;
    report "TEST_PASS frontend_mixed_same_id_crc_rejection";
    send_frame(rx1,30,0,payload_words=>0);wait for 5 us;
    assert valid='1' report "Second log frame not buffered" severity failure;
    idle_reset;wait for 5 us;
    assert valid='0' report "Warm reset retained a buffered log byte" severity failure;
    report "TEST_PASS frontend_reset_flushes_prefetch";
    report "TEST_SUMMARY frontend failures=0";finish;
  end process;
  process begin wait for 5 ms;report "TEST_TIMEOUT frontend" severity failure;end process;
end architecture;

entity frontend_log_tb is end entity;
architecture test of frontend_log_tb is
begin
  dut:entity work.frontend_tb generic map(CHECK_RESET=>false);
end architecture;
