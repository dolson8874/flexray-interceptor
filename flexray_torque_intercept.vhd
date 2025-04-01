library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.flexray;

entity flexray_torque_intercept is
  port (
    clk           : in  std_ulogic;     -- Clock 8x higher than can bitrate
    rst           : in  std_ulogic;
    rx            : in  std_ulogic;
    torque        : in  std_ulogic_vector(13 downto 0);
    sign          : in  std_ulogic_vector(8 downto 0);
    enable        : in  std_ulogic;
        
    tx            : out std_ulogic;
    override      : out std_ulogic;
    sync_debug     : out std_ulogic);
end entity flexray_torque_intercept;


architecture syn of flexray_torque_intercept is


  -- Poly 0x1D, crc 8bit, data 80bit 
  function crc8_10(
        crcIn: in std_ulogic_vector(7 downto 0);
        data: in std_ulogic_vector(79 downto 0))
		
  return std_ulogic_vector is 
	variable crcOut : std_ulogic_vector(7 downto 0);
		
  begin
    crcOut(0) := crcIn(0) xor crcIn(1) xor crcIn(2) xor crcIn(3) xor crcIn(4) xor crcIn(6) xor crcIn(7) xor data(0) xor data(4) xor data(5) xor data(6) xor data(10) xor data(13) xor data(15) xor data(16) xor data(17) xor data(24) xor data(25) xor data(28) xor data(31) xor data(34) xor data(35) xor data(37) xor data(38) xor data(39) xor data(42) xor data(48) xor data(50) xor data(52) xor data(53) xor data(55) xor data(56) xor data(58) xor data(60) xor data(61) xor data(64) xor data(66) xor data(67) xor data(72) xor data(73) xor data(74) xor data(75) xor data(76) xor data(78) xor data(79);
    crcOut(1) := crcIn(1) xor crcIn(2) xor crcIn(3) xor crcIn(4) xor crcIn(5) xor crcIn(7) xor data(1) xor data(5) xor data(6) xor data(7) xor data(11) xor data(14) xor data(16) xor data(17) xor data(18) xor data(25) xor data(26) xor data(29) xor data(32) xor data(35) xor data(36) xor data(38) xor data(39) xor data(40) xor data(43) xor data(49) xor data(51) xor data(53) xor data(54) xor data(56) xor data(57) xor data(59) xor data(61) xor data(62) xor data(65) xor data(67) xor data(68) xor data(73) xor data(74) xor data(75) xor data(76) xor data(77) xor data(79);
    crcOut(2) := crcIn(0) xor crcIn(1) xor crcIn(5) xor crcIn(7) xor data(0) xor data(2) xor data(4) xor data(5) xor data(7) xor data(8) xor data(10) xor data(12) xor data(13) xor data(16) xor data(18) xor data(19) xor data(24) xor data(25) xor data(26) xor data(27) xor data(28) xor data(30) xor data(31) xor data(33) xor data(34) xor data(35) xor data(36) xor data(38) xor data(40) xor data(41) xor data(42) xor data(44) xor data(48) xor data(53) xor data(54) xor data(56) xor data(57) xor data(61) xor data(62) xor data(63) xor data(64) xor data(67) xor data(68) xor data(69) xor data(72) xor data(73) xor data(77) xor data(79);
    crcOut(3) := crcIn(0) xor crcIn(3) xor crcIn(4) xor crcIn(7) xor data(0) xor data(1) xor data(3) xor data(4) xor data(8) xor data(9) xor data(10) xor data(11) xor data(14) xor data(15) xor data(16) xor data(19) xor data(20) xor data(24) xor data(26) xor data(27) xor data(29) xor data(32) xor data(36) xor data(38) xor data(41) xor data(43) xor data(45) xor data(48) xor data(49) xor data(50) xor data(52) xor data(53) xor data(54) xor data(56) xor data(57) xor data(60) xor data(61) xor data(62) xor data(63) xor data(65) xor data(66) xor data(67) xor data(68) xor data(69) xor data(70) xor data(72) xor data(75) xor data(76) xor data(79);
    crcOut(4) := crcIn(0) xor crcIn(2) xor crcIn(3) xor crcIn(5) xor crcIn(6) xor crcIn(7) xor data(0) xor data(1) xor data(2) xor data(6) xor data(9) xor data(11) xor data(12) xor data(13) xor data(20) xor data(21) xor data(24) xor data(27) xor data(30) xor data(31) xor data(33) xor data(34) xor data(35) xor data(38) xor data(44) xor data(46) xor data(48) xor data(49) xor data(51) xor data(52) xor data(54) xor data(56) xor data(57) xor data(60) xor data(62) xor data(63) xor data(68) xor data(69) xor data(70) xor data(71) xor data(72) xor data(74) xor data(75) xor data(77) xor data(78) xor data(79);
    crcOut(5) := crcIn(0) xor crcIn(1) xor crcIn(3) xor crcIn(4) xor crcIn(6) xor crcIn(7) xor data(1) xor data(2) xor data(3) xor data(7) xor data(10) xor data(12) xor data(13) xor data(14) xor data(21) xor data(22) xor data(25) xor data(28) xor data(31) xor data(32) xor data(34) xor data(35) xor data(36) xor data(39) xor data(45) xor data(47) xor data(49) xor data(50) xor data(52) xor data(53) xor data(55) xor data(57) xor data(58) xor data(61) xor data(63) xor data(64) xor data(69) xor data(70) xor data(71) xor data(72) xor data(73) xor data(75) xor data(76) xor data(78) xor data(79);
    crcOut(6) := crcIn(0) xor crcIn(1) xor crcIn(2) xor crcIn(4) xor crcIn(5) xor crcIn(7) xor data(2) xor data(3) xor data(4) xor data(8) xor data(11) xor data(13) xor data(14) xor data(15) xor data(22) xor data(23) xor data(26) xor data(29) xor data(32) xor data(33) xor data(35) xor data(36) xor data(37) xor data(40) xor data(46) xor data(48) xor data(50) xor data(51) xor data(53) xor data(54) xor data(56) xor data(58) xor data(59) xor data(62) xor data(64) xor data(65) xor data(70) xor data(71) xor data(72) xor data(73) xor data(74) xor data(76) xor data(77) xor data(79);
    crcOut(7) := crcIn(0) xor crcIn(1) xor crcIn(2) xor crcIn(3) xor crcIn(5) xor crcIn(6) xor data(3) xor data(4) xor data(5) xor data(9) xor data(12) xor data(14) xor data(15) xor data(16) xor data(23) xor data(24) xor data(27) xor data(30) xor data(33) xor data(34) xor data(36) xor data(37) xor data(38) xor data(41) xor data(47) xor data(49) xor data(51) xor data(52) xor data(54) xor data(55) xor data(57) xor data(59) xor data(60) xor data(63) xor data(65) xor data(66) xor data(71) xor data(72) xor data(73) xor data(74) xor data(75) xor data(77) xor data(78);
	
	return crcOut xor x"0B";
  end;

  -- Poly 0x1D, crc 8bit, data 64bit 
  function crc8_8(
        crcIn: in std_ulogic_vector(7 downto 0);
        data: in std_ulogic_vector(63 downto 0))
		
  return std_ulogic_vector is 
	variable crcOut : std_ulogic_vector(7 downto 0);
		
  begin
    crcOut(0) := crcIn(0) xor crcIn(2) xor crcIn(4) xor crcIn(5) xor data(0) xor data(4) xor data(5) xor data(6) xor data(10) xor data(13) xor data(15) xor data(16) xor data(17) xor data(24) xor data(25) xor data(28) xor data(31) xor data(34) xor data(35) xor data(37) xor data(38) xor data(39) xor data(42) xor data(48) xor data(50) xor data(52) xor data(53) xor data(55) xor data(56) xor data(58) xor data(60) xor data(61);
    crcOut(1) := crcIn(0) xor crcIn(1) xor crcIn(3) xor crcIn(5) xor crcIn(6) xor data(1) xor data(5) xor data(6) xor data(7) xor data(11) xor data(14) xor data(16) xor data(17) xor data(18) xor data(25) xor data(26) xor data(29) xor data(32) xor data(35) xor data(36) xor data(38) xor data(39) xor data(40) xor data(43) xor data(49) xor data(51) xor data(53) xor data(54) xor data(56) xor data(57) xor data(59) xor data(61) xor data(62);
    crcOut(2) := crcIn(0) xor crcIn(1) xor crcIn(5) xor crcIn(6) xor crcIn(7) xor data(0) xor data(2) xor data(4) xor data(5) xor data(7) xor data(8) xor data(10) xor data(12) xor data(13) xor data(16) xor data(18) xor data(19) xor data(24) xor data(25) xor data(26) xor data(27) xor data(28) xor data(30) xor data(31) xor data(33) xor data(34) xor data(35) xor data(36) xor data(38) xor data(40) xor data(41) xor data(42) xor data(44) xor data(48) xor data(53) xor data(54) xor data(56) xor data(57) xor data(61) xor data(62) xor data(63);
    crcOut(3) := crcIn(0) xor crcIn(1) xor crcIn(4) xor crcIn(5) xor crcIn(6) xor crcIn(7) xor data(0) xor data(1) xor data(3) xor data(4) xor data(8) xor data(9) xor data(10) xor data(11) xor data(14) xor data(15) xor data(16) xor data(19) xor data(20) xor data(24) xor data(26) xor data(27) xor data(29) xor data(32) xor data(36) xor data(38) xor data(41) xor data(43) xor data(45) xor data(48) xor data(49) xor data(50) xor data(52) xor data(53) xor data(54) xor data(56) xor data(57) xor data(60) xor data(61) xor data(62) xor data(63);
    crcOut(4) := crcIn(0) xor crcIn(1) xor crcIn(4) xor crcIn(6) xor crcIn(7) xor data(0) xor data(1) xor data(2) xor data(6) xor data(9) xor data(11) xor data(12) xor data(13) xor data(20) xor data(21) xor data(24) xor data(27) xor data(30) xor data(31) xor data(33) xor data(34) xor data(35) xor data(38) xor data(44) xor data(46) xor data(48) xor data(49) xor data(51) xor data(52) xor data(54) xor data(56) xor data(57) xor data(60) xor data(62) xor data(63);
    crcOut(5) := crcIn(1) xor crcIn(2) xor crcIn(5) xor crcIn(7) xor data(1) xor data(2) xor data(3) xor data(7) xor data(10) xor data(12) xor data(13) xor data(14) xor data(21) xor data(22) xor data(25) xor data(28) xor data(31) xor data(32) xor data(34) xor data(35) xor data(36) xor data(39) xor data(45) xor data(47) xor data(49) xor data(50) xor data(52) xor data(53) xor data(55) xor data(57) xor data(58) xor data(61) xor data(63);
    crcOut(6) := crcIn(0) xor crcIn(2) xor crcIn(3) xor crcIn(6) xor data(2) xor data(3) xor data(4) xor data(8) xor data(11) xor data(13) xor data(14) xor data(15) xor data(22) xor data(23) xor data(26) xor data(29) xor data(32) xor data(33) xor data(35) xor data(36) xor data(37) xor data(40) xor data(46) xor data(48) xor data(50) xor data(51) xor data(53) xor data(54) xor data(56) xor data(58) xor data(59) xor data(62);
    crcOut(7) := crcIn(1) xor crcIn(3) xor crcIn(4) xor crcIn(7) xor data(3) xor data(4) xor data(5) xor data(9) xor data(12) xor data(14) xor data(15) xor data(16) xor data(23) xor data(24) xor data(27) xor data(30) xor data(33) xor data(34) xor data(36) xor data(37) xor data(38) xor data(41) xor data(47) xor data(49) xor data(51) xor data(52) xor data(54) xor data(55) xor data(57) xor data(59) xor data(60) xor data(63);
	
	return crcOut xor x"32";
  end;
  
  -- Poly 0x1D, crc 8bit, data 32bit  
  function crc8_4(
        crcIn: in std_ulogic_vector(7 downto 0);
        data: in std_ulogic_vector(31 downto 0))
		
  return std_ulogic_vector is 
	variable crcOut : std_ulogic_vector(7 downto 0);
		
  begin
    crcOut(0) := crcIn(0) xor crcIn(1) xor crcIn(4) xor crcIn(7) xor data(0) xor data(4) xor data(5) xor data(6) xor data(10) xor data(13) xor data(15) xor data(16) xor data(17) xor data(24) xor data(25) xor data(28) xor data(31);
    crcOut(1) := crcIn(1) xor crcIn(2) xor crcIn(5) xor data(1) xor data(5) xor data(6) xor data(7) xor data(11) xor data(14) xor data(16) xor data(17) xor data(18) xor data(25) xor data(26) xor data(29);
    crcOut(2) := crcIn(0) xor crcIn(1) xor crcIn(2) xor crcIn(3) xor crcIn(4) xor crcIn(6) xor crcIn(7) xor data(0) xor data(2) xor data(4) xor data(5) xor data(7) xor data(8) xor data(10) xor data(12) xor data(13) xor data(16) xor data(18) xor data(19) xor data(24) xor data(25) xor data(26) xor data(27) xor data(28) xor data(30) xor data(31);
    crcOut(3) := crcIn(0) xor crcIn(2) xor crcIn(3) xor crcIn(5) xor data(0) xor data(1) xor data(3) xor data(4) xor data(8) xor data(9) xor data(10) xor data(11) xor data(14) xor data(15) xor data(16) xor data(19) xor data(20) xor data(24) xor data(26) xor data(27) xor data(29);
    crcOut(4) := crcIn(0) xor crcIn(3) xor crcIn(6) xor crcIn(7) xor data(0) xor data(1) xor data(2) xor data(6) xor data(9) xor data(11) xor data(12) xor data(13) xor data(20) xor data(21) xor data(24) xor data(27) xor data(30) xor data(31);
    crcOut(5) := crcIn(1) xor crcIn(4) xor crcIn(7) xor data(1) xor data(2) xor data(3) xor data(7) xor data(10) xor data(12) xor data(13) xor data(14) xor data(21) xor data(22) xor data(25) xor data(28) xor data(31);
    crcOut(6) := crcIn(2) xor crcIn(5) xor data(2) xor data(3) xor data(4) xor data(8) xor data(11) xor data(13) xor data(14) xor data(15) xor data(22) xor data(23) xor data(26) xor data(29);
    crcOut(7) := crcIn(0) xor crcIn(3) xor crcIn(6) xor data(3) xor data(4) xor data(5) xor data(9) xor data(12) xor data(14) xor data(15) xor data(16) xor data(23) xor data(24) xor data(27) xor data(30);
	return crcOut xor x"CC";
  end;   
  
  -- Poly 0x1D, crc 8bit, data 24bit  
  function crc8_3(
        crcIn: in std_ulogic_vector(7 downto 0);
        data: in std_ulogic_vector(23 downto 0))
		
  return std_ulogic_vector is 
	variable crcOut : std_ulogic_vector(7 downto 0);
		
  begin
    crcOut(0) := crcIn(0) xor crcIn(1) xor data(0) xor data(4) xor data(5) xor data(6) xor data(10) xor data(13) xor data(15) xor data(16) xor data(17);
    crcOut(1) := crcIn(0) xor crcIn(1) xor crcIn(2) xor data(1) xor data(5) xor data(6) xor data(7) xor data(11) xor data(14) xor data(16) xor data(17) xor data(18);
    crcOut(2) := crcIn(0) xor crcIn(2) xor crcIn(3) xor data(0) xor data(2) xor data(4) xor data(5) xor data(7) xor data(8) xor data(10) xor data(12) xor data(13) xor data(16) xor data(18) xor data(19);
    crcOut(3) := crcIn(0) xor crcIn(3) xor crcIn(4) xor data(0) xor data(1) xor data(3) xor data(4) xor data(8) xor data(9) xor data(10) xor data(11) xor data(14) xor data(15) xor data(16) xor data(19) xor data(20);
    crcOut(4) := crcIn(4) xor crcIn(5) xor data(0) xor data(1) xor data(2) xor data(6) xor data(9) xor data(11) xor data(12) xor data(13) xor data(20) xor data(21);
    crcOut(5) := crcIn(5) xor crcIn(6) xor data(1) xor data(2) xor data(3) xor data(7) xor data(10) xor data(12) xor data(13) xor data(14) xor data(21) xor data(22);
    crcOut(6) := crcIn(6) xor crcIn(7) xor data(2) xor data(3) xor data(4) xor data(8) xor data(11) xor data(13) xor data(14) xor data(15) xor data(22) xor data(23);
    crcOut(7) := crcIn(0) xor crcIn(7) xor data(3) xor data(4) xor data(5) xor data(9) xor data(12) xor data(14) xor data(15) xor data(16) xor data(23);
	
	return crcOut xor x"B0";
  end;  
  
  
    -- Poly 0x1D, crc 8bit, data 24bit  
    -- 0x1d poly x^8+x^4+x^3+x^2+x^0
    -- XOR 0xDA
  function crc8_3_0(
        crcIn: in std_ulogic_vector(7 downto 0);
        data: in std_ulogic_vector(23 downto 0))
		
  return std_ulogic_vector is 
	variable crcOut : std_ulogic_vector(7 downto 0);
		
  begin
    crcOut(0) := crcIn(0) xor crcIn(1) xor data(0) xor data(4) xor data(5) xor data(6) xor data(10) xor data(13) xor data(15) xor data(16) xor data(17);
    crcOut(1) := crcIn(0) xor crcIn(1) xor crcIn(2) xor data(1) xor data(5) xor data(6) xor data(7) xor data(11) xor data(14) xor data(16) xor data(17) xor data(18);
    crcOut(2) := crcIn(0) xor crcIn(2) xor crcIn(3) xor data(0) xor data(2) xor data(4) xor data(5) xor data(7) xor data(8) xor data(10) xor data(12) xor data(13) xor data(16) xor data(18) xor data(19);
    crcOut(3) := crcIn(0) xor crcIn(3) xor crcIn(4) xor data(0) xor data(1) xor data(3) xor data(4) xor data(8) xor data(9) xor data(10) xor data(11) xor data(14) xor data(15) xor data(16) xor data(19) xor data(20);
    crcOut(4) := crcIn(4) xor crcIn(5) xor data(0) xor data(1) xor data(2) xor data(6) xor data(9) xor data(11) xor data(12) xor data(13) xor data(20) xor data(21);
    crcOut(5) := crcIn(5) xor crcIn(6) xor data(1) xor data(2) xor data(3) xor data(7) xor data(10) xor data(12) xor data(13) xor data(14) xor data(21) xor data(22);
    crcOut(6) := crcIn(6) xor crcIn(7) xor data(2) xor data(3) xor data(4) xor data(8) xor data(11) xor data(13) xor data(14) xor data(15) xor data(22) xor data(23);
    crcOut(7) := crcIn(0) xor crcIn(7) xor data(3) xor data(4) xor data(5) xor data(9) xor data(12) xor data(14) xor data(15) xor data(16) xor data(23);	
	return crcOut xor x"DA";
  end;  
  
  -- Poly 0x1D, crc 8bit, data 16bit  
  function crc8_2(
        crcIn: in std_ulogic_vector(7 downto 0);
        data: in std_ulogic_vector(15 downto 0))
		
  return std_ulogic_vector is 
	variable crcOut : std_ulogic_vector(7 downto 0);
		
  begin
    crcOut(0) := crcIn(2) xor crcIn(5) xor crcIn(7) xor data(0) xor data(4) xor data(5) xor data(6) xor data(10) xor data(13) xor data(15);
    crcOut(1) := crcIn(3) xor crcIn(6) xor data(1) xor data(5) xor data(6) xor data(7) xor data(11) xor data(14);
    crcOut(2) := crcIn(0) xor crcIn(2) xor crcIn(4) xor crcIn(5) xor data(0) xor data(2) xor data(4) xor data(5) xor data(7) xor data(8) xor data(10) xor data(12) xor data(13);
    crcOut(3) := crcIn(0) xor crcIn(1) xor crcIn(2) xor crcIn(3) xor crcIn(6) xor crcIn(7) xor data(0) xor data(1) xor data(3) xor data(4) xor data(8) xor data(9) xor data(10) xor data(11) xor data(14) xor data(15);
    crcOut(4) := crcIn(1) xor crcIn(3) xor crcIn(4) xor crcIn(5) xor data(0) xor data(1) xor data(2) xor data(6) xor data(9) xor data(11) xor data(12) xor data(13);
    crcOut(5) := crcIn(2) xor crcIn(4) xor crcIn(5) xor crcIn(6) xor data(1) xor data(2) xor data(3) xor data(7) xor data(10) xor data(12) xor data(13) xor data(14);
    crcOut(6) := crcIn(0) xor crcIn(3) xor crcIn(5) xor crcIn(6) xor crcIn(7) xor data(2) xor data(3) xor data(4) xor data(8) xor data(11) xor data(13) xor data(14) xor data(15);
    crcOut(7) := crcIn(1) xor crcIn(4) xor crcIn(6) xor crcIn(7) xor data(3) xor data(4) xor data(5) xor data(9) xor data(12) xor data(14) xor data(15);	
	return crcOut xor x"8f";
  end;
  
  -- 0xd01-2 0x1d, xor 0xe3
  function crc8_2_1(
        crcIn: in std_ulogic_vector(7 downto 0);
        data: in std_ulogic_vector(15 downto 0))
		
  return std_ulogic_vector is 
	variable crcOut : std_ulogic_vector(7 downto 0);
		
  begin
    crcOut(0) := crcIn(2) xor crcIn(5) xor crcIn(7) xor data(0) xor data(4) xor data(5) xor data(6) xor data(10) xor data(13) xor data(15);
    crcOut(1) := crcIn(3) xor crcIn(6) xor data(1) xor data(5) xor data(6) xor data(7) xor data(11) xor data(14);
    crcOut(2) := crcIn(0) xor crcIn(2) xor crcIn(4) xor crcIn(5) xor data(0) xor data(2) xor data(4) xor data(5) xor data(7) xor data(8) xor data(10) xor data(12) xor data(13);
    crcOut(3) := crcIn(0) xor crcIn(1) xor crcIn(2) xor crcIn(3) xor crcIn(6) xor crcIn(7) xor data(0) xor data(1) xor data(3) xor data(4) xor data(8) xor data(9) xor data(10) xor data(11) xor data(14) xor data(15);
    crcOut(4) := crcIn(1) xor crcIn(3) xor crcIn(4) xor crcIn(5) xor data(0) xor data(1) xor data(2) xor data(6) xor data(9) xor data(11) xor data(12) xor data(13);
    crcOut(5) := crcIn(2) xor crcIn(4) xor crcIn(5) xor crcIn(6) xor data(1) xor data(2) xor data(3) xor data(7) xor data(10) xor data(12) xor data(13) xor data(14);
    crcOut(6) := crcIn(0) xor crcIn(3) xor crcIn(5) xor crcIn(6) xor crcIn(7) xor data(2) xor data(3) xor data(4) xor data(8) xor data(11) xor data(13) xor data(14) xor data(15);
    crcOut(7) := crcIn(1) xor crcIn(4) xor crcIn(6) xor crcIn(7) xor data(3) xor data(4) xor data(5) xor data(9) xor data(12) xor data(14) xor data(15);	
	return crcOut xor x"e3";
  end;    
  
  
  -- Poly 0x1D, crc 8bit, data 16bit  
  function crc8_1(
        crcIn: in std_ulogic_vector(7 downto 0);
        data: in std_ulogic_vector(7 downto 0))
		
  return std_ulogic_vector is 
	variable crcOut : std_ulogic_vector(7 downto 0);
		
  begin
    crcOut(0) := crcIn(0) xor crcIn(4) xor crcIn(5) xor crcIn(6) xor data(0) xor data(4) xor data(5) xor data(6);
    crcOut(1) := crcIn(1) xor crcIn(5) xor crcIn(6) xor crcIn(7) xor data(1) xor data(5) xor data(6) xor data(7);
    crcOut(2) := crcIn(0) xor crcIn(2) xor crcIn(4) xor crcIn(5) xor crcIn(7) xor data(0) xor data(2) xor data(4) xor data(5) xor data(7);
    crcOut(3) := crcIn(0) xor crcIn(1) xor crcIn(3) xor crcIn(4) xor data(0) xor data(1) xor data(3) xor data(4);
    crcOut(4) := crcIn(0) xor crcIn(1) xor crcIn(2) xor crcIn(6) xor data(0) xor data(1) xor data(2) xor data(6);
    crcOut(5) := crcIn(1) xor crcIn(2) xor crcIn(3) xor crcIn(7) xor data(1) xor data(2) xor data(3) xor data(7);
    crcOut(6) := crcIn(2) xor crcIn(3) xor crcIn(4) xor data(2) xor data(3) xor data(4);
    crcOut(7) := crcIn(3) xor crcIn(4) xor crcIn(5) xor data(3) xor data(4) xor data(5);
	return crcOut xor x"11";
  end;  
  
  type pdata_t is array (0 to 9) of std_ulogic_vector(7 downto 0);
  
  signal lkas_1F0_prev : pdata_t;     
  signal lkas_1F1_prev : pdata_t;

begin

  intercept : process (clk, rst)
    variable rx_prev      : std_ulogic;
    variable tick_counter : integer range 0 to 7;
    variable idle_counter : integer range 0 to 20;
    variable in_progress  : std_ulogic;
    variable in_tss       : std_ulogic;
    variable in_fss       : std_ulogic;
    variable in_frame     : std_ulogic;
    variable in_bss       : std_ulogic;

    variable bit_counter      : integer;  -- TODO: put range oentity flexray_torque_intercept isn this
    variable real_bit_counter : integer;  -- TODO: put range on this

    variable tmp_msg : work.flexray.message;

    variable computed_header_crc : std_ulogic_vector(10 downto 0);
    variable computed_crc        : std_ulogic_vector(23 downto 0);
    variable num_bits            : integer range 0 to 2039;

    variable is_overriding : std_ulogic;
    variable next_tx       : std_ulogic;

    type data_t is array (0 to 255) of        std_ulogic_vector(7 downto 0);
    variable override_data : data_t;
    variable override_mask : data_t;

    variable in_sync      : std_ulogic;
    variable sync_counter : integer range 0 to 3;
	
	variable lkas_ready : std_ulogic;
	variable lkas_enable : std_ulogic;
	variable lkas_enprev : std_ulogic;
	variable lkas_torque : std_ulogic_vector(13 downto 0);
	variable lkas_counter : integer range 0 to 15;
	variable lkas_cycle_counter : integer range 0 to 3;
	variable lkas_diff_counter : integer range -15 to 15;
    variable lkas_cruise_on : std_ulogic;
    variable lkas_moveH_EnTorqL_CruiseOnL_EntorqH : std_ulogic;
    variable asl_gray_icon : std_ulogic;
    

  begin
    if rst = '1' then
      rx_prev          := '1';
      in_progress      := '0';
      bit_counter      := 0;
      tick_counter     := 0;
      idle_counter     := 20;
      in_tss           := '0';
      in_fss           := '0';
      in_frame         := '0';
      in_bss           := '0';
      real_bit_counter := 0;
      tx               <= '1';
      next_tx          := '1';
      asl_gray_icon    := '0';

      is_overriding := '0';

      computed_header_crc := (others => '0');
      computed_crc        := (others => '0');

      tmp_msg.flags          := (others => '0');
      tmp_msg.frame_id       := (others => '0');
      tmp_msg.payload_length := (others => '0');
      tmp_msg.header_crc     := (others => '0');
      tmp_msg.cycle_count    := (others => '0');
      tmp_msg.data           := (others => (others => '0'));
      tmp_msg.crc            := (others => '0');

      override_data := (others => (others => '0'));
      override_mask := (others => (others => '0'));

      in_sync      := '0';
      -- sync_counter := 0;
	  -- cycle_counter 1,5,9,13 ... counter MOD 4 = 1 
	  sync_counter := 1;		
      sync_debug        <= '0';
	  
	  lkas_ready := '0';
	  lkas_enable := '0';
	  lkas_enprev := '0';
	  lkas_torque := (others => '0');
	  lkas_cycle_counter := 0;
	  lkas_diff_counter := 0;
      lkas_cruise_on := '0';
      lkas_moveH_EnTorqL_CruiseOnL_EntorqH := '0';

    elsif rising_edge(clk) then
	
	  lkas_ready := sign(7);
	  
	  if lkas_enable = '0' and real_bit_counter <= 40 then
	    lkas_enable := enable;
		
		if enable = '1' then
	      lkas_torque := torque;
		--else
		--  lkas_torque := b"01100101000";  -- 0x328 (808)
	    end if;
	  end if;
	  	  
      num_bits := to_integer(unsigned(tmp_msg.payload_length)) * 16;

      -- Update tick counter
      if tick_counter = 7 then
        tick_counter := 0;
      else
        tick_counter := tick_counter + 1;
      end if;

      -- Sync on first falling edge
      if rx = '0' and rx_prev = '1' and in_progress = '0' then
        tick_counter := 0;
      end if;

      -- Sync on Frame Start Sequence
      if rx = '1' and rx_prev = '0' and in_tss = '1' then
        tick_counter := 0;
      end if;

      if tick_counter = 0 then
        -- Header of message passed, decide if we need to override
        if real_bit_counter >= 40 then
          -- Only override if ID matches, the counter is 0 and we are enabled and
          -- in sync
		  -- if in_sync = '1' and enable = '1' and tmp_msg.frame_id = b"00001000001" and sync_counter = to_integer(unsigned(tmp_msg.cycle_count)) mod 4 then
          -- if in_sync = '1' and enable = '1' and tmp_msg.frame_id = b"00000100111" and sync_counter = to_integer(unsigned(tmp_msg.cycle_count)) mod 4 then
		  
		  -- 0x1F 
		  if in_sync = '1' and lkas_enable = '1' and tmp_msg.frame_id = b"00000011111" then
		    
			is_overriding := '1';
			-- lkas_torque := torque;
			
			-- lkas_cruise_on := sign(7);
			   
			
			lkas_cycle_counter :=  to_integer(unsigned(tmp_msg.cycle_count)) mod 4;
			
            lkas_counter := to_integer(unsigned(tmp_msg.cycle_count(5 downto 2))) - lkas_diff_counter;

            
			if lkas_cycle_counter = 0 then
               -- not used for test
               is_overriding := '1';  
               override_data := (others => (others => '0'));
               override_mask := (others => (others => '0'));
			   
               -- lkas_1F0_prev := tmp_msg.data(6)(0) & b"00" & tmp_msg.data(7)(7 downto 3);
               
		       -- LANDROVER Defender LKAS msg
		       
		       -- LANDROVER Defender LKAS msg
		       -- 1 torque counter
		       override_data(1) := b"0001" & std_ulogic_vector(to_unsigned(lkas_counter, 4)) ( 3 downto 0);
		       override_mask(1) := x"FF";
		       
		       override_data(2) := x"00";	
		       override_mask(2) := x"FF";
		       
		       override_data(3) := x"00";	
		       override_mask(3) := x"FF";		  
		        
		       override_data(4) := x"00";	
		       override_mask(4) := x"FF";
		       
		       override_data(5) := x"00";  
		       override_mask(5) := x"FF";
		        
		       -- override_data(6) := x"00";	-- bit4,2 : 0
			   -- 6:4 Above5KmH_LkasL_CruiseOnL_LkasH == CruiseOn
			   -- 6:3 CruiseOnH_LkasL == 0
			   -- 6:2 Above5KmHLkasLow_CruiseOnL_LkasH_xxxH == CruiseOn
			   -- 6:1 CruiseOnH_LkasL_xxlow == '0'
			   if 0 = to_integer(unsigned(tmp_msg.cycle_count)) mod 8 then
			     override_data(6) := b"000" & lkas_cruise_on & '0' & lkas_cruise_on &  '0' & '0';
			   else
			     override_data(6) := lkas_1F0_prev(0);
			   end if;
			   
		       override_mask(6) := x"FF";
		       
		       -- override_data(7) := x"00";	
			   -- bit 1 : 0 Above5KmHCruiseOnLkasH_Under5KmLCruiseOffLkasL == CruiseOn
			   if lkas_cruise_on = '1' then
			     if 0 = to_integer(unsigned(tmp_msg.cycle_count)) mod 12 then
				   override_data(7) := lkas_1F0_prev(1);
			     else
			       override_data(7) := b"000000" & lkas_cruise_on & '0';
				 end if;
			   else
			     override_data(7) := b"000000" & lkas_cruise_on & '0';
		       end if; 
			   override_mask(7) := x"FF";
		        
		       override_data(8) := x"00";	
		       override_mask(8) := x"FF";		  
		        
		       override_data(0) := crc8_8(b"00000000",  -- 0 torq crc (1~6)  poly=0x1d, init=0x00, xor=0x32
		       						override_data(1) & override_data(2) & override_data(3) &
		       						override_data(4) & override_data(5) & override_data(6) &
		       						override_data(7) & override_data(8)
		       						); 
		       override_mask(0) := x"FF";
		        
		       
		       -- 14 flag torque counter
		       override_data(14) := b"0000" & override_data(1)(3 downto 0);
		       override_mask(14) := x"FF";
		        
		       -- 15 torque data bit 7:1 bit5 always 1, bit2~0 : torque msb 3bit
               override_data(15) := b"10" & torque(13 downto 8);			   
		       override_mask(15) := x"FF";
		       
		       -- 16 torq data last 8bit
			   override_data(16) := torque(7 downto 0);
		       override_mask(16) := x"FF";
		        
		       -- 13 flag crc poly = 0x1d, crc 8bit, xor 0xb0
		       override_data(13) := crc8_3(b"00000000",  
		       						override_data(14) & override_data(15) & 
		       						override_data(16)
		       						); 
		       override_mask(13) := x"FF";
		
			
		    elsif lkas_cycle_counter = 1  then
               override_data := (others => (others => '0'));
               override_mask := (others => (others => '0'));				

               is_overriding := '1';
			   
		       override_data(1) := b"0000" & std_ulogic_vector(to_unsigned(lkas_counter, 4)) ( 3 downto 0);
		       override_mask(1) := x"FF";	
 
               override_mask(2) := x"FF";
			   override_mask(3) := x"FF";
			   override_mask(4) := x"FF";
			   override_mask(5) := x"FF";
			   override_mask(6) := x"FF";
			   override_mask(7) := x"FF";
			   override_mask(8) := x"FF";

		       override_data(9) := x"7b";
		       override_mask(9) := x"FF";

		       override_data(10) := x"08";
		       override_mask(10) := x"FF";		

               
               if lkas_cruise_on = '1' then
			     if 1 = to_integer(unsigned(tmp_msg.cycle_count)) mod 12 then
				   override_data(2) := lkas_1F1_prev(0);
				 else
				   override_data(2) := x"00";
				 end if;
			   else
			     override_data(2) := x"00";
			   end if;
			   
			   override_data(3) := lkas_1F1_prev(1);
			   override_data(4) := lkas_1F1_prev(2);
			   override_data(5) := lkas_1F1_prev(3);
			   override_data(6) := lkas_1F1_prev(4);
			   override_data(7) := lkas_1F1_prev(5);
			   override_data(8) := lkas_1F1_prev(6);
			   override_data(9) := lkas_1F1_prev(7);
			   override_data(10) := lkas_1F1_prev(8);
			   
			   
		       override_data(0) := crc8_10(b"00000000",  
		       						override_data(1) & override_data(2) & override_data(3) & 
									override_data(4) & override_data(5) & override_data(6) & 
									override_data(7) & override_data(8) & override_data(9) &
									override_data(10)
		       						); 
		       override_mask(0) := x"FF";	

		       override_data(16) := b"0001" & std_ulogic_vector(to_unsigned(lkas_counter, 4)) ( 3 downto 0);
		       override_mask(16) := x"FF";	
			   
			   -- 0x48 | cruise_on
		       override_data(17) := b"0100100" & lkas_cruise_on;
		       override_mask(17) := x"FF";				   
			   
		       -- 15 flag crc poly = 0x1d, crc 8bit, xor 0x8f
		       override_data(15) := crc8_2(b"00000000",  
		       						override_data(16) & override_data(17) 
		       						); 
		       override_mask(15) := x"FF";		
               
            elsif lkas_cycle_counter = 3 then   
               override_data := (others => (others => '0'));
               override_mask := (others => (others => '0'));            
			   
               is_overriding := '0';
               
		       override_data(9) := b"0000" & std_ulogic_vector(to_unsigned(lkas_counter, 4)) ( 3 downto 0);
		       override_mask(9) := x"FF";
               
               override_data(10) := b"10000" & torque(10 downto 8);			   
		       override_mask(10) := x"FF";
		       
			   override_data(11) := torque(7 downto 0);
		       override_mask(11) := x"FF";
               
		       override_data(8) := crc8_3_0(b"00000000",  
		       						override_data(9) & override_data(10) & override_data(11));
								 
		       override_mask(8) := x"FF";			   
               
		       if real_bit_counter = 66 + num_bits then
                 -- override end
				 lkas_enable := '0';
               end if;	
               
			else
			      is_overriding := '0';
                  override_data := (others => (others => '0'));
                  override_mask := (others => (others => '0'));			
			end if;
			
		  -- 0x31 counter 0
          elsif in_sync = '1' and tmp_msg.frame_id = b"00000110001" 
                and 0 = to_integer(unsigned(tmp_msg.cycle_count)) mod 4 then
				
			   -- cruise on
			   lkas_cruise_on := tmp_msg.data(21)(0);	
               
          -- LKAS Green line
		  -- frame id=0x31 sync_id=1/8 00:pass 11:white 01:green 10:red 
		  elsif in_sync = '1' and tmp_msg.frame_id = b"00000110001" 
                and 1 = to_integer(unsigned(tmp_msg.cycle_count)) mod 8 then
             
               override_data := (others => (others => '0'));
               override_mask := (others => (others => '0'));	
			
               if sign(5 downto 0) /= b"000000" then
			     is_overriding := '1';
               end if;
			   
			   --  override_data(2) := b"010000" & sign(4 downto 3);
			   if sign(4 downto 3) /= b"00" then
			     override_data(2) := b"000000" & sign(4 downto 3);
		         override_mask(2) := x"03";	
			   end if;
	
	           if sign(1 downto 0) /= b"00" then
			     override_data(3) := b"000000" & sign(1 downto 0);
		         override_mask(3) := x"03";
			   end if;
			
               -- for blinker_lr, ASL gray icon status
               asl_gray_icon := tmp_msg.data(9)(5);
            
			   -- right blindSpot
		       if sign(5) = '1' then
			   end if;
			
               -- left blindSpot
			   if sign(2) = '1' then
			   end if;
              
            
          -- TEST 0xD01
		  -- frame id=0x0d sync_id=1/4 
		  elsif in_sync = '1' and tmp_msg.frame_id = b"00000001101"  
			    and 1 = to_integer(unsigned(tmp_msg.cycle_count)) mod 4 then
				
               override_data := (others => (others => '0'));
               override_mask := (others => (others => '0'));	
            
               -- Steering Assist Icon
               if lkas_ready = '1'  then
                 is_overriding := '1';
                 
			     if lkas_enable = '1' then
			       override_data(15) := b"01000000";
			       override_mask(15) := x"40";			 
			     else
			       override_data(15) := b"01100000";
			       override_mask(15) := x"60";
                 end if;
                 
			   end if;
			
               -- blinker left, right
               if asl_gray_icon = '1' then
                 is_overriding := '1';
			     override_data(7) := b"000" & asl_gray_icon & b"0000";
			     override_mask(7) := x"10";                 
               end if;

               
			   -- if lkas_enable = '1' then
		         -- override_data(1) := b"0001" & std_ulogic_vector(to_unsigned(lkas_counter, 4)) ( 3 downto 0);
                 -- override_mask(1) := x"FF"; 
			
		         -- override_data(0) := crc8_1(b"00000000",  
			                        -- override_data(1) 
		       						-- ); 
                 -- override_mask(0) := x"FF";	

                 -- override_mask(0) := x"00"; override_mask(1) := x"00";	
			  
			  
		         -- override_data(9) := b"0000" & std_ulogic_vector(to_unsigned(lkas_counter, 4)) ( 3 downto 0);
                 -- override_mask(9) := x"FF";
			  
		         -- override_data(10) := b"10000000";
                 -- override_mask(10) := x"FF"; 
			
		         -- override_data(8) := crc8_2_1(b"00000000",  
			                        -- override_data(9) & override_data(10)
		       						-- ); 
                 -- override_mask(8) := x"FF";	

                 -- override_mask(8) := x"00"; override_mask(9) := x"00"; override_mask(10) := x"00";
			  
			   -- end if;
			
          else
            is_overriding := '0';
          end if;
			
          -- Counter
          -- override_data(25):= x"4" & tmp_msg.cycle_count(5 downto 2);
          -- override_mask(25) := x"FF";
		  
		  -- THIS IS WHERE YOU BUILD THE REST OF THE PACKET
        end if;
        

        -- Handle BSS
        if is_overriding = '1' then
          is_overriding := '0';

          if (bit_counter mod 10 = 0) then
            in_bss := '1';
          elsif (bit_counter mod 10 = 1) then
            in_bss := '1';
          else
            in_bss := '0';
          end if;

          -- No BSS when at end of message
          if real_bit_counter >= 64 + num_bits then
            in_bss := '0';
          end if;


          if in_bss = '0' then
            if real_bit_counter >= 40 and real_bit_counter <= 40 + num_bits - 1 then
              next_tx := override_data((real_bit_counter - 40) / 8)(7 - (real_bit_counter - 40) mod 8);

              if override_mask((real_bit_counter - 40) / 8)(7 - (real_bit_counter - 40) mod 8) = '1' then
                is_overriding := '1';
              end if;

            elsif real_bit_counter >= 40 + num_bits and real_bit_counter <= 63 + num_bits then
              next_tx       := computed_crc(computed_crc'left - (real_bit_counter - 40 - num_bits));
              is_overriding := '1';
            elsif real_bit_counter = 64 + num_bits then
              is_overriding := '0';
            elsif real_bit_counter = 65 + num_bits then
              is_overriding := '0';
            elsif real_bit_counter = 66 + num_bits then
              is_overriding := '0';
              idle_counter  := 20;
            end if;


            if is_overriding = '1' then
              bit_counter      := bit_counter + 1;
              real_bit_counter := real_bit_counter + 1;

              if real_bit_counter >= 40 and real_bit_counter <= 40 + num_bits - 1 then
                if (next_tx xor computed_crc(23)) = '1' then
                  computed_crc := (computed_crc(22 downto 0) & '0') xor b"010111010110110111001011";
                else
                  computed_crc := (computed_crc(22 downto 0) & '0');
                end if;
              end if;
            end if;
          end if;

          tx <= next_tx;
        end if;

      end if;

      override <= is_overriding;

      -- Sample at 50%
      if tick_counter = 3 and is_overriding = '0' then
        -- Signal is idle, increase idle counter
        if rx = '1' and idle_counter < 20 then
          idle_counter := idle_counter + 1;
        end if;

        -- Reset if idle
        if idle_counter = 20 then
          in_progress      := '0';
          bit_counter      := 0;
          real_bit_counter := 0;
          in_tss           := '0';
          in_fss           := '0';
          in_frame         := '0';
          in_bss           := '0';
          is_overriding    := '0';
        end if;

        -- Signal is not idle, set in progress
        if rx = '0' then
          -- First bit
          if in_progress = '0' then
            in_tss := '1';
          end if;

          in_progress  := '1';
          idle_counter := 0;
        end if;

        if in_progress = '1' then

          if in_fss = '1' then
            -- TODO Assert that rx is 1
            in_fss   := '0';
            in_frame := '1';

            -- Clear tmp_message
            tmp_msg.flags          := (others => '0');
            tmp_msg.frame_id       := (others => '0');
            tmp_msg.payload_length := (others => '0');
            tmp_msg.header_crc     := (others => '0');
            tmp_msg.cycle_count    := (others => '0');
            tmp_msg.data           := (others => (others => '0'));
            tmp_msg.crc            := (others => '0');

            computed_header_crc := b"00000011010";
            computed_crc        := b"111111101101110010111010";

            bit_counter      := 0;
            real_bit_counter := 0;
			override_mask := (others => (others => '0'));
          end if;

          -- TSS is done, we go into FSS
          if rx = '1' and in_tss = '1' then
            in_tss := '0';
            in_fss := '1';
          end if;

          -- Handle BSS
          if in_tss = '0' and in_fss = '0' then
            if (bit_counter mod 10 = 0) then
              -- TODO check if 1
              in_bss := '1';
            elsif (bit_counter mod 10 = 1) then
              -- TODO check if 0
              in_bss := '1';
            else
              in_bss := '0';
            end if;
          else
            in_bss := '0';
          end if;

          if in_frame = '1' then
            bit_counter := bit_counter + 1;
          end if;

          -- Update header CRC
          if in_tss = '0' and in_bss = '0' and real_bit_counter >= 3 and real_bit_counter <= 22 then
            if (rx xor computed_header_crc(10)) = '1' then
              computed_header_crc := (computed_header_crc(9 downto 0) & '0') xor b"01110000101";
            else
              computed_header_crc := (computed_header_crc(9 downto 0) & '0');
            end if;
          end if;

          -- Update CRC
          if in_tss = '0' and in_bss = '0' and real_bit_counter >= 0 and real_bit_counter <= 40 + num_bits - 1 then
            if (rx xor computed_crc(23)) = '1' then
              computed_crc := (computed_crc(22 downto 0) & '0') xor b"010111010110110111001011";
            else
              computed_crc := (computed_crc(22 downto 0) & '0');
            end if;
          end if;

          
          if in_bss = '0' and in_tss = '0' and in_fss = '0' then
            if real_bit_counter >= 0 and real_bit_counter <= 4 then
              tmp_msg.flags(tmp_msg.flags'left - (real_bit_counter - 0)) := rx;
            elsif real_bit_counter >= 5 and real_bit_counter <= 15 then
              tmp_msg.frame_id(tmp_msg.frame_id'left - (real_bit_counter - 5)) := rx;
            elsif real_bit_counter >= 16 and real_bit_counter <= 22 then
              tmp_msg.payload_length(tmp_msg.payload_length'left - (real_bit_counter - 16)) := rx;
            elsif real_bit_counter >= 23 and real_bit_counter <= 33 then
              tmp_msg.header_crc(tmp_msg.header_crc'left - (real_bit_counter - 23)) := rx;
            elsif real_bit_counter >= 34 and real_bit_counter <= 39 then
              tmp_msg.cycle_count(tmp_msg.cycle_count'left - (real_bit_counter - 34)) := rx;
            elsif real_bit_counter >= 40 and real_bit_counter <= 40 + num_bits - 1 then
              tmp_msg.data((real_bit_counter - 40) / 8)(7 - (real_bit_counter - 40) mod 8) := rx;
            elsif real_bit_counter >= 40 + num_bits and real_bit_counter <= 63 + num_bits then
              tmp_msg.crc(tmp_msg.crc'left - (real_bit_counter - 40 - num_bits)) := rx;
            elsif real_bit_counter >= 64 + num_bits and computed_crc = tmp_msg.crc then
    
              -- Check if this is the correct message to sync on
              -- if tmp_msg.frame_id = b"00001000001" and tmp_msg.data(33) = x"70" then
			  -- LANDROVER DEFENDER 0x1F header_counter 0,4,8 ... 
			  if tmp_msg.frame_id = b"00000011111" and tmp_msg.data(25) = x"60" 
				  and tmp_msg.data(15) = x"23"  and tmp_msg.data(16) = x"28" then
                
				lkas_diff_counter := to_integer(unsigned(tmp_msg.cycle_count(5 downto 2))) - to_integer(unsigned(tmp_msg.data(1)(3 downto 0)));
				sync_counter := 0;
                in_sync      := '1';
                sync_debug   <= '1';
				
              end if;

            end if;

            real_bit_counter := real_bit_counter + 1;
          end if;
        end if;

      end if;

      rx_prev := rx;
    end if;
  end process;


  decode_only : process (clk, rst)
    variable rx_prev      : std_ulogic;
    variable tick_counter : integer range 0 to 7;
    variable idle_counter : integer range 0 to 20;
    variable in_progress  : std_ulogic;
    variable in_tss       : std_ulogic;
    variable in_fss       : std_ulogic;
    variable in_frame     : std_ulogic;
    variable in_bss       : std_ulogic;

    variable bit_counter      : integer;  -- TODO: put range oentity flexray_torque_intercept isn this
    variable real_bit_counter : integer;  -- TODO: put range on this

    variable tmp_msg : work.flexray.message;

    variable computed_header_crc : std_ulogic_vector(10 downto 0);
    variable computed_crc        : std_ulogic_vector(23 downto 0);
    variable num_bits            : integer range 0 to 2039;

    variable is_overriding : std_ulogic;
    variable next_tx       : std_ulogic;


    variable in_sync      : std_ulogic;
    variable sync_counter : integer range 0 to 3;
	
	variable lkas_diff_counter : integer range -15 to 15;
    

  begin
    if rst = '1' then
      rx_prev          := '1';
      in_progress      := '0';
      bit_counter      := 0;
      tick_counter     := 0;
      idle_counter     := 20;
      in_tss           := '0';
      in_fss           := '0';
      in_frame         := '0';
      in_bss           := '0';
      real_bit_counter := 0;

      computed_header_crc := (others => '0');
      computed_crc        := (others => '0');

      tmp_msg.flags          := (others => '0');
      tmp_msg.frame_id       := (others => '0');
      tmp_msg.payload_length := (others => '0');
      tmp_msg.header_crc     := (others => '0');
      tmp_msg.cycle_count    := (others => '0');
      tmp_msg.data           := (others => (others => '0'));
      tmp_msg.crc            := (others => '0');


	  sync_counter := 0;		
	  
	  lkas_diff_counter := 0;
      lkas_1F0_prev <= (others => (others => '0'));
	  lkas_1F1_prev <= (others => (others => '0'));

    elsif rising_edge(clk) then
	
      num_bits := to_integer(unsigned(tmp_msg.payload_length)) * 16;

      -- Update tick counter
      if tick_counter = 7 then
        tick_counter := 0;
      else
        tick_counter := tick_counter + 1;
      end if;

      -- Sync on first falling edge
      if rx = '0' and rx_prev = '1' and in_progress = '0' then
        tick_counter := 0;
      end if;

      -- Sync on Frame Start Sequence
      if rx = '1' and rx_prev = '0' and in_tss = '1' then
        tick_counter := 0;
      end if;

      if tick_counter = 0 then
        -- Header of message passed, decide if we need to override
        if real_bit_counter >= 40 then
			
          -- Counter
          -- override_data(25):= x"4" & tmp_msg.cycle_count(5 downto 2);
          -- override_mask(25) := x"FF";
		  
		  -- THIS IS WHERE YOU BUILD THE REST OF THE PACKET
        end if;
        
      end if;


      -- Sample at 50%
      if tick_counter = 3 and is_overriding = '0' then
      
        -- Signal is idle, increase idle counter
        if rx = '1' and idle_counter < 20 then
          idle_counter := idle_counter + 1;
        end if;

        -- Reset if idle
        if idle_counter = 20 then
          in_progress      := '0';
          bit_counter      := 0;
          real_bit_counter := 0;
          in_tss           := '0';
          in_fss           := '0';
          in_frame         := '0';
          in_bss           := '0';
          is_overriding    := '0';
        end if;

        -- Signal is not idle, set in progress
        if rx = '0' then
          -- First bit
          if in_progress = '0' then
            in_tss := '1';
          end if;

          in_progress  := '1';
          idle_counter := 0;
        end if;

        if in_progress = '1' then

          if in_fss = '1' then
            -- TODO Assert that rx is 1
            in_fss   := '0';
            in_frame := '1';

            -- Clear tmp_message
            tmp_msg.flags          := (others => '0');
            tmp_msg.frame_id       := (others => '0');
            tmp_msg.payload_length := (others => '0');
            tmp_msg.header_crc     := (others => '0');
            tmp_msg.cycle_count    := (others => '0');
            tmp_msg.data           := (others => (others => '0'));
            tmp_msg.crc            := (others => '0');

            computed_header_crc := b"00000011010";
            computed_crc        := b"111111101101110010111010";

            bit_counter      := 0;
            real_bit_counter := 0;
          end if;

          -- TSS is done, we go into FSS
          if rx = '1' and in_tss = '1' then
            in_tss := '0';
            in_fss := '1';
          end if;

          -- Handle BSS
          if in_tss = '0' and in_fss = '0' then
            if (bit_counter mod 10 = 0) then
              -- TODO check if 1
              in_bss := '1';
            elsif (bit_counter mod 10 = 1) then
              -- TODO check if 0
              in_bss := '1';
            else
              in_bss := '0';
            end if;
          else
            in_bss := '0';
          end if;

          if in_frame = '1' then
            bit_counter := bit_counter + 1;
          end if;

          -- Update header CRC
          if in_tss = '0' and in_bss = '0' and real_bit_counter >= 3 and real_bit_counter <= 22 then
            if (rx xor computed_header_crc(10)) = '1' then
              computed_header_crc := (computed_header_crc(9 downto 0) & '0') xor b"01110000101";
            else
              computed_header_crc := (computed_header_crc(9 downto 0) & '0');
            end if;
          end if;

          -- Update CRC
          if in_tss = '0' and in_bss = '0' and real_bit_counter >= 0 and real_bit_counter <= 40 + num_bits - 1 then
            if (rx xor computed_crc(23)) = '1' then
              computed_crc := (computed_crc(22 downto 0) & '0') xor b"010111010110110111001011";
            else
              computed_crc := (computed_crc(22 downto 0) & '0');
            end if;
     
          end if;

          
          if in_bss = '0' and in_tss = '0' and in_fss = '0' then
            if real_bit_counter >= 0 and real_bit_counter <= 4 then
              tmp_msg.flags(tmp_msg.flags'left - (real_bit_counter - 0)) := rx;
            elsif real_bit_counter >= 5 and real_bit_counter <= 15 then
              tmp_msg.frame_id(tmp_msg.frame_id'left - (real_bit_counter - 5)) := rx;
            elsif real_bit_counter >= 16 and real_bit_counter <= 22 then
              tmp_msg.payload_length(tmp_msg.payload_length'left - (real_bit_counter - 16)) := rx;
            elsif real_bit_counter >= 23 and real_bit_counter <= 33 then
              tmp_msg.header_crc(tmp_msg.header_crc'left - (real_bit_counter - 23)) := rx;
            elsif real_bit_counter >= 34 and real_bit_counter <= 39 then
              tmp_msg.cycle_count(tmp_msg.cycle_count'left - (real_bit_counter - 34)) := rx;
            elsif real_bit_counter >= 40 and real_bit_counter <= 40 + num_bits - 1 then
              tmp_msg.data((real_bit_counter - 40) / 8)(7 - (real_bit_counter - 40) mod 8) := rx;
            elsif real_bit_counter >= 40 + num_bits and real_bit_counter <= 63 + num_bits then
              tmp_msg.crc(tmp_msg.crc'left - (real_bit_counter - 40 - num_bits)) := rx;
            elsif real_bit_counter >= 64 + num_bits and computed_crc = tmp_msg.crc then
    
              -- Check if this is the correct message to sync on
              -- if tmp_msg.frame_id = b"00001000001" and tmp_msg.data(33) = x"70" then
			  -- LANDROVER DEFENDER 0x1F header_counter 0,4,8 ... 
			  if tmp_msg.frame_id = b"00000011111" and tmp_msg.data(25) = x"60" then
					--  and tmp_msg.data(15) = x"23"  and tmp_msg.data(16) = x"28" then
                
                sync_counter := to_integer(unsigned(tmp_msg.cycle_count)) mod 4;
                case  sync_counter is
                    when 0 =>
                        lkas_diff_counter := to_integer(unsigned(tmp_msg.cycle_count(5 downto 2))) - to_integer(unsigned(tmp_msg.data(1)(3 downto 0)));
                        lkas_1F0_prev(0) <= std_ulogic_vector(tmp_msg.data(6));
						lkas_1F0_prev(1) <= std_ulogic_vector(tmp_msg.data(7));
                    when 1 =>
                        lkas_1F1_prev(0) <= std_ulogic_vector(tmp_msg.data(2));
						lkas_1F1_prev(1) <= std_ulogic_vector(tmp_msg.data(3));
						lkas_1F1_prev(2) <= std_ulogic_vector(tmp_msg.data(4));
						lkas_1F1_prev(3) <= std_ulogic_vector(tmp_msg.data(5));
						lkas_1F1_prev(4) <= std_ulogic_vector(tmp_msg.data(6));
						lkas_1F1_prev(5) <= std_ulogic_vector(tmp_msg.data(7));
						lkas_1F1_prev(6) <= std_ulogic_vector(tmp_msg.data(8));
						lkas_1F1_prev(7) <= std_ulogic_vector(tmp_msg.data(9));
						lkas_1F1_prev(8) <= std_ulogic_vector(tmp_msg.data(10));
                    when others =>
                        sync_counter := 0;
                end case;
                     
				sync_counter := 0;
                in_sync      := '1';
				
              end if;

            end if;

            real_bit_counter := real_bit_counter + 1;
          end if;
        end if;

      end if;

      rx_prev := rx;
    end if;
  end process;
end architecture syn;
