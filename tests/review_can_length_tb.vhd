library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.can_reference.all;
entity review_can_length_tb is end entity;
architecture test of review_can_length_tb is
  constant BIT_TIME : time := 1250 ns;
  signal clk : std_ulogic := '0';
  signal rst : std_ulogic := '1';
  signal peer, tx, bus_rx : std_ulogic := '1';
  signal torque : std_ulogic_vector(13 downto 0);
  signal sign : std_ulogic_vector(8 downto 0);
  signal enabled : std_ulogic;
  function app_crc(d:std_ulogic_vector(31 downto 0)) return std_ulogic_vector is
    variable c:std_ulogic_vector(7 downto 0):=x"00";
  begin
    for i in d'range loop
      if (c(7) xor d(i))='1' then c:=(c(6 downto 0)&'0') xor x"1D";
      else c:=c(6 downto 0)&'0'; end if;
    end loop;
    return c xor x"CC";
  end function;
begin
  clk<=not clk after 78125 ps;
  bus_rx<=peer and tx;
  dut:entity work.joystick_decoder port map(clk=>clk,rst=>rst,rx=>bus_rx,tx=>tx,
    torque=>torque,enable=>enabled,sign=>sign,relay=>open,enCan=>open,debug=>open);
  process
    variable m:work.can.message;
    procedure send(constant message_in:work.can.message) is
      variable f:wire_frame;
    begin
      f:=encode(message_in);
      for i in 0 to f.count-1 loop peer<=f.bits(i); wait for BIT_TIME; end loop;
      peer<='1'; wait for BIT_TIME/2;
      assert bus_rx='0' report "Review CAN frame not acknowledged" severity failure;
      wait for 13*BIT_TIME;
    end procedure;
  begin
    wait for 2 us; rst<='0'; wait for 20 us;
    m.id:=std_ulogic_vector(to_unsigned(16#1F9#,11)); m.len:="1000";
    m.dat:=x"0001000000008000"; m.dat(63 downto 56):=app_crc(m.dat(55 downto 24)); send(m);
    -- The first HUD establishes health; its ready bit is intentionally masked
    -- while relay_ctrl was unhealthy. Send another after health is established.
    m.dat:=x"0002000000008000"; m.dat(63 downto 56):=app_crc(m.dat(55 downto 24)); send(m);
    assert sign(7 downto 0)=x"80" report "HUD health precondition failed" severity failure;
    assert enabled='0' report "Unexpected enable before command" severity failure;
    m.id:=std_ulogic_vector(to_unsigned(16#1F0#,11)); m.len:="0101";
    m.dat:=x"000100A328000000"; m.dat(63 downto 56):=app_crc(m.dat(55 downto 24)); send(m);
    assert enabled='0' and unsigned(torque)=0
      report "Short command changed torque or enabled steering" severity failure;
    m.len:="1000"; send(m);
    assert enabled='1' and unsigned(torque)=9000
      report "Valid DLC8 command was rejected" severity failure;
    for length in 0 to 7 loop
      m.len:=std_ulogic_vector(to_unsigned(length,4)); m.dat:=x"000200A332000000";
      m.dat(63 downto 56):=app_crc(m.dat(55 downto 24)); send(m);
      assert enabled='0' and unsigned(torque)=9000
        report "Short command updated torque or enabled steering" severity failure;
    end loop;
    report "TEST_PASS dlc0_through_7_rejected_dlc8_accepted";
    m.id:=std_ulogic_vector(to_unsigned(16#1F9#,11)); m.len:="0111";
    m.dat:=x"0003000000000100"; m.dat(63 downto 56):=app_crc(m.dat(55 downto 24)); send(m);
    assert sign(7 downto 0)=x"80"
      report "Short HUD updated display data" severity failure;
    m.len:="1000"; send(m);
    assert sign(7 downto 0)=x"01"
      report "Valid DLC8 HUD was rejected" severity failure;
    report "TEST_PASS short_hud_rejected_dlc8_hud_accepted";
    report "TEST_SUMMARY can_length failures=0"; finish;
  end process;
end architecture;
