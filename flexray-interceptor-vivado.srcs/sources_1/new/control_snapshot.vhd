library ieee;
use ieee.std_logic_1164.all;

-- One-entry bundled-data mailbox. The source holds the whole control word
-- until the destination has captured it and returned an acknowledgement.
-- Intermediate source updates coalesce into the next complete snapshot.
entity control_snapshot is
  port (
    src_clk, dst_clk, rst : in std_ulogic;
    torque_in : in std_ulogic_vector(13 downto 0);
    sign_in : in std_ulogic_vector(8 downto 0);
    enable_in : in std_ulogic;
    torque_out : out std_ulogic_vector(13 downto 0);
    sign_out : out std_ulogic_vector(8 downto 0);
    enable_out : out std_ulogic
  );
end entity;
architecture rtl of control_snapshot is
  signal held_data, delivered_data : std_ulogic_vector(23 downto 0) := (others => '0');
  signal request_toggle, ack_toggle : std_ulogic := '0';
  signal request_meta, request_sync, ack_meta, ack_sync : std_ulogic := '0';
  signal source_reset_pipe, dest_reset_pipe : std_ulogic_vector(1 downto 0) := (others => '1');
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of request_meta, request_sync, ack_meta, ack_sync,
    source_reset_pipe, dest_reset_pipe : signal is "TRUE";
  attribute KEEP_HIERARCHY : string;
  attribute KEEP_HIERARCHY of rtl : architecture is "yes";
begin
  torque_out <= delivered_data(23 downto 10);
  sign_out <= delivered_data(9 downto 1);
  enable_out <= delivered_data(0);
  process(src_clk, rst)
  begin
    if rst = '1' then source_reset_pipe <= (others => '1');
    elsif rising_edge(src_clk) then source_reset_pipe <= source_reset_pipe(0) & '0'; end if;
  end process;
  process(dst_clk, rst)
  begin
    if rst = '1' then dest_reset_pipe <= (others => '1');
    elsif rising_edge(dst_clk) then dest_reset_pipe <= dest_reset_pipe(0) & '0'; end if;
  end process;
  process(src_clk, source_reset_pipe(1))
  begin
    if source_reset_pipe(1) = '1' then
      held_data <= (others => '0'); request_toggle <= '0'; ack_meta <= '0'; ack_sync <= '0';
    elsif rising_edge(src_clk) then
      ack_meta <= ack_toggle; ack_sync <= ack_meta;
      if request_toggle = ack_sync and held_data /= (torque_in & sign_in & enable_in) then
        held_data <= torque_in & sign_in & enable_in;
        request_toggle <= not request_toggle;
      end if;
    end if;
  end process;
  process(dst_clk, dest_reset_pipe(1))
  begin
    if dest_reset_pipe(1) = '1' then
      delivered_data <= (others => '0'); ack_toggle <= '0';
      request_meta <= '0'; request_sync <= '0';
    elsif rising_edge(dst_clk) then
      request_meta <= request_toggle; request_sync <= request_meta;
      if request_sync /= ack_toggle then
        delivered_data <= held_data; ack_toggle <= request_sync;
      end if;
    end if;
  end process;
end architecture;
