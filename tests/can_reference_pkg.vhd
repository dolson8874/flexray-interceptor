library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package can_reference is
  type wire_frame is record
    bits : std_ulogic_vector(0 to 159);
    count : natural;
    final_crc_stuff : boolean;
  end record;
  function encode(m : work.can.message; corrupt_crc : boolean := false) return wire_frame;
end package;

package body can_reference is
  -- Offline reference: construct the complete logical frame first, divide by
  -- the CRC polynomial, then stuff it. No DUT state/counters are reused.
  function encode(m : work.can.message; corrupt_crc : boolean := false) return wire_frame is
    variable result : wire_frame;
    variable logical_bits : std_ulogic_vector(0 to 97) := (others => '0');
    variable dividend : std_ulogic_vector(0 to 112) := (others => '0');
    constant poly : std_ulogic_vector(0 to 15) := "1100010110011001";
    variable body_length, run : natural;
    variable last_bit : std_ulogic := '1';
  begin
    result.bits := (others => '1'); result.count := 0; result.final_crc_stuff := false;
    body_length := 19 + to_integer(unsigned(m.len)) * 8;
    logical_bits(1 to 11) := m.id;
    logical_bits(15 to 18) := m.len;
    for i in 19 to body_length - 1 loop logical_bits(i) := m.dat(82 - i); end loop;
    dividend(0 to body_length - 1) := logical_bits(0 to body_length - 1);
    for i in 0 to body_length - 1 loop
      if dividend(i) = '1' then
        for j in 0 to 15 loop dividend(i + j) := dividend(i + j) xor poly(j); end loop;
      end if;
    end loop;
    logical_bits(body_length to body_length + 14) := dividend(body_length to body_length + 14);
    if corrupt_crc then logical_bits(body_length) := not logical_bits(body_length); end if;
    run := 0;
    for i in 0 to body_length + 14 loop
      result.bits(result.count) := logical_bits(i); result.count := result.count + 1;
      if last_bit = logical_bits(i) then run := run + 1; else run := 1; end if;
      last_bit := logical_bits(i);
      if run = 5 then
        last_bit := not last_bit;
        result.bits(result.count) := last_bit; result.count := result.count + 1;
        run := 1;
        if i = body_length + 14 then result.final_crc_stuff := true; end if;
      end if;
    end loop;
    result.bits(result.count) := '1'; result.count := result.count + 1; -- CRC delimiter
    return result;
  end function;
end package body;
