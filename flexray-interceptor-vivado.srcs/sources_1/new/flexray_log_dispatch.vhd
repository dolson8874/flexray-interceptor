library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- One active request plus one pending frame. Keep the active record stable
-- until the logger accepts it; drain pending data without another arrival.
entity flexray_log_dispatch is
  port (
    clk, rst, frame_valid, log_busy : in std_ulogic;
    frame : in work.flexray.message;
    log_req : out std_ulogic;
    log_frame : out work.flexray.message;
    dropped : out std_ulogic_vector(31 downto 0)
  );
end entity;
architecture rtl of flexray_log_dispatch is
  signal request, pending_valid, previous_valid : std_ulogic := '0';
  signal pending : work.flexray.message;
  signal drop_count : unsigned(31 downto 0) := (others => '0');
begin
  log_req <= request; dropped <= std_ulogic_vector(drop_count);
  process(clk, rst)
    variable incoming : boolean;
    variable queued : std_ulogic;
  begin
    if rst = '1' then
      request <= '0'; pending_valid <= '0'; previous_valid <= '0';
      drop_count <= (others => '0');
    elsif rising_edge(clk) then
      incoming := frame_valid = '1' and previous_valid = '0';
      previous_valid <= frame_valid; queued := pending_valid;
      if request = '1' and log_busy = '1' then request <= '0'; end if;
      if request = '0' and log_busy = '0' then
        if queued = '1' then
          log_frame <= pending; request <= '1'; queued := '0';
        elsif incoming then
          log_frame <= frame; request <= '1'; incoming := false;
        end if;
      end if;
      if incoming then
        if queued = '0' then pending <= frame; queued := '1';
        elsif drop_count /= x"FFFFFFFF" then drop_count <= drop_count + 1; end if;
      end if;
      pending_valid <= queued;
    end if;
  end process;
end architecture;
