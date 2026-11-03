library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
package flexray_reference is
  procedure send_frame(signal wire_rx : out std_ulogic;
    constant identifier : natural; constant cycle : natural;
    constant bad_crc : boolean := false;
    constant neutral : boolean := true; constant message_counter : integer := -1;
    constant crc_error_bit : natural range 0 to 23 := 0;
    constant corrupt_payload_bit : integer range -1 to 207 := -1;
    constant payload_words : natural range 0 to 127 := 13);
end package;
package body flexray_reference is
  procedure send_frame(signal wire_rx : out std_ulogic;
    constant identifier : natural; constant cycle : natural;
    constant bad_crc : boolean := false;
    constant neutral : boolean := true; constant message_counter : integer := -1;
    constant crc_error_bit : natural range 0 to 23 := 0;
    constant corrupt_payload_bit : integer range -1 to 207 := -1;
    constant payload_words : natural range 0 to 127 := 13) is
    variable header : std_ulogic_vector(39 downto 0);
    variable hc : std_ulogic_vector(10 downto 0) := std_ulogic_vector(to_unsigned(26, 11));
    variable crc : std_ulogic_vector(23 downto 0) := x"FEDCBA";
    variable payload : work.flexray.data_t := (others => (others => '0'));
    procedure bit_out(b : std_ulogic) is
    begin wire_rx <= b; wait for 100 ns; end procedure;
    procedure byte_out(b : std_ulogic_vector(7 downto 0)) is
    begin
      bit_out('1'); bit_out('0');
      for j in 7 downto 0 loop bit_out(b(j)); end loop;
    end procedure;
    procedure crc_in(b : std_ulogic) is
    begin
      if (b xor crc(23)) = '1' then crc := (crc(22 downto 0) & '0') xor x"5D6DCB";
      else crc := crc(22 downto 0) & '0'; end if;
    end procedure;
  begin
    for j in 26 to 253 loop payload(j) := std_logic_vector(to_unsigned(j,8)); end loop;
    payload(15) := x"23"; payload(16) := x"28"; payload(25) := x"60";
    if not neutral then payload(15) := x"24"; end if;
    if message_counter < 0 then payload(1) := std_logic_vector(to_unsigned(cycle / 4, 8));
    else payload(1) := std_logic_vector(to_unsigned(message_counter, 8)); end if;
    header := "00000" & std_ulogic_vector(to_unsigned(identifier, 11)) & std_ulogic_vector(to_unsigned(payload_words,7)) &
      "00000000000" & std_ulogic_vector(to_unsigned(cycle, 6));
    for j in 36 downto 17 loop
      if (header(j) xor hc(10)) = '1' then hc := (hc(9 downto 0) & '0') xor "01110000101";
      else hc := hc(9 downto 0) & '0'; end if;
    end loop;
    header(16 downto 6) := hc;
    for j in 39 downto 0 loop crc_in(header(j)); end loop;
    for j in 0 to payload_words*2-1 loop for k in 7 downto 0 loop crc_in(payload(j)(k)); end loop; end loop;
    if bad_crc then crc(crc_error_bit) := not crc(crc_error_bit); end if;
    if corrupt_payload_bit >= 0 then
      payload(corrupt_payload_bit / 8)(7 - corrupt_payload_bit mod 8) :=
        not payload(corrupt_payload_bit / 8)(7 - corrupt_payload_bit mod 8);
    end if;
    for j in 1 to 9 loop bit_out('0'); end loop;
    bit_out('1');
    for j in 0 to 4 loop byte_out(header(39 - 8 * j downto 32 - 8 * j)); end loop;
    for j in 0 to payload_words*2-1 loop byte_out(std_ulogic_vector(payload(j))); end loop;
    for j in 0 to 2 loop byte_out(crc(23 - 8 * j downto 16 - 8 * j)); end loop;
    bit_out('0'); bit_out('1');
  end procedure;
end package body;
