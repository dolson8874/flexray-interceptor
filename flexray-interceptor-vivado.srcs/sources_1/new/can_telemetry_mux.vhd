library ieee;
use ieee.std_logic_1164.all;

-- One stable output request, fair arbitration between two queued CAN sources.
entity can_telemetry_mux is
  port (
    clk, rst : in std_ulogic;
    a_valid, b_valid : in std_ulogic;
    a_ready, b_ready : out std_ulogic;
    a_data, b_data : in std_ulogic_vector(78 downto 0);
    m_valid : out std_ulogic;
    m_ready : in std_ulogic;
    m_data : out std_ulogic_vector(78 downto 0)
  );
end entity;
architecture rtl of can_telemetry_mux is
  signal valid, prefer_b, choose_b : std_ulogic := '0';
begin
  choose_b <= b_valid and (prefer_b or not a_valid);
  a_ready <= not valid and not choose_b and not rst;
  b_ready <= not valid and choose_b and not rst;
  m_valid <= valid and not rst;
  process(clk, rst)
  begin
    if rst = '1' then
      valid <= '0'; prefer_b <= '0'; m_data <= (others => '0');
    elsif rising_edge(clk) then
      if valid = '1' then
        if m_ready = '1' then valid <= '0'; end if;
      elsif choose_b = '1' then
        m_data <= b_data; valid <= '1'; prefer_b <= '0';
      elsif a_valid = '1' then
        m_data <= a_data; valid <= '1'; prefer_b <= '1';
      end if;
    end if;
  end process;
end architecture;
