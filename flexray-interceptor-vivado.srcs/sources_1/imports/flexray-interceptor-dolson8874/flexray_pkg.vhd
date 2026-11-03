library ieee;
use ieee.std_logic_1164.all;

package flexray is
  type data_t is array (0 to 254) of std_logic_vector(7 downto 0);

  type message is record
    flags          : std_ulogic_vector(4 downto 0);
    frame_id       : std_ulogic_vector(10 downto 0);
    payload_length : std_ulogic_vector(6 downto 0);
    header_crc     : std_ulogic_vector(10 downto 0);
    cycle_count    : std_ulogic_vector(5 downto 0);
    data           : data_t;
    crc            : std_ulogic_vector(23 downto 0);
  end record message;
  -- Equivalent to cycle mod 12 = phase for phase 0/1. Decode the six-bit
  -- domain directly instead of placing an integer remainder in the bit path.
  function cycle_phase_12(c : std_ulogic_vector(5 downto 0); phase : natural) return boolean;
end package flexray;

package body flexray is
  function cycle_phase_12(c : std_ulogic_vector(5 downto 0); phase : natural) return boolean is
  begin
    case c(5 downto 2) is
      when "0000" | "0011" | "0110" | "1001" | "1100" | "1111" =>
        case phase is
          when 0 => return c(1 downto 0) = "00";
          when 1 => return c(1 downto 0) = "01";
          when others => return false;
        end case;
      when others => return false;
    end case;
  end function;
end package body flexray;
