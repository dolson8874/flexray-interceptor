library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_crc8_func is
end entity;

architecture tb of tb_crc8_func is
  --------------------------------------------------------------------
  -- MSB-first, poly=0x1D, init=0x00, xorout=0x32
  --------------------------------------------------------------------
  function crc8_0x1D(
    data   : in std_ulogic_vector;                     -- unconstrained
    xorval : in std_ulogic_vector(7 downto 0) := x"32" -- 최종 XOR
  ) return std_ulogic_vector is
    constant POLY : std_ulogic_vector(7 downto 0) := x"1D";
    variable crc  : std_ulogic_vector(7 downto 0) := (others => '0'); -- init=0x00
    variable fb   : std_ulogic;
  begin
    -- data가 (63 downto 0)라면 63→0 순으로 처리됨
    for i in data'range loop
      fb  := crc(7) xor data(i);
      crc := crc(6 downto 0) & '0';
      if fb = '1' then
        crc := crc xor POLY;
      end if;
    end loop;
    return std_ulogic_vector(unsigned(crc) xor unsigned(xorval));
  end function;

  -- 헥사 출력 보조
  function nib_to_char(n: std_logic_vector(3 downto 0)) return character is
  begin
    case n is
      when "0000" => return '0';
      when "0001" => return '1';
      when "0010" => return '2';
      when "0011" => return '3';
      when "0100" => return '4';
      when "0101" => return '5';
      when "0110" => return '6';
      when "0111" => return '7';
      when "1000" => return '8';
      when "1001" => return '9';
      when "1010" => return 'A';
      when "1011" => return 'B';
      when "1100" => return 'C';
      when "1101" => return 'D';
      when "1110" => return 'E';
      when others => return 'F';
    end case;
  end;

  function u8_to_hex(u: std_ulogic_vector(7 downto 0)) return string is
    variable v : std_logic_vector(7 downto 0) := std_logic_vector(u);
    variable s : string(1 to 2);
  begin
    s(1) := nib_to_char(v(7 downto 4));
    s(2) := nib_to_char(v(3 downto 0));
    return s;
  end;

  --------------------------------------------------------------------
  -- 테스트 벡터 (헥사 리터럴 + 폭 일치)
  --------------------------------------------------------------------
  -- constant MSG0 : std_ulogic_vector(79 downto 0) := x"06000000000000007b08";
  -- constant MSG1 : std_ulogic_vector(79 downto 0) := x"05000000000000007b08";
  -- constant MSG2 : std_ulogic_vector(79 downto 0) := x"04000000000000007b08";
  -- constant MSG3 : std_ulogic_vector(79 downto 0) := x"03000000000000007b08";
  
  constant MSG0 : std_ulogic_vector(63 downto 0) := x"1b00000000140000";
  constant MSG1 : std_ulogic_vector(23 downto 0) := x"0ba39c";
  constant MSG2 : std_ulogic_vector(23 downto 0) := x"0fa381";
  constant MSG3 : std_ulogic_vector(23 downto 0) := x"0ea381";  

begin
  process
    variable got : std_ulogic_vector(7 downto 0);
  begin
    got := crc8_0x1D(MSG0, x"32");  report "TC0 CRC=0x" & u8_to_hex(got);
    got := crc8_0x1D(MSG1, x"b0");  report "TC1 CRC=0x" & u8_to_hex(got);
    got := crc8_0x1D(MSG2, x"b0");  report "TC2 CRC=0x" & u8_to_hex(got);
    got := crc8_0x1D(MSG3, x"b0");  report "TC3 CRC=0x" & u8_to_hex(got);

    assert false report "All tests completed" severity failure;
    wait;
  end process;
end architecture;
