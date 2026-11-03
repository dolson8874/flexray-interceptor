library ieee;
use ieee.std_logic_1164.all;

-- Separate observation path; CAN backpressure never stalls the FlexRay bridge.
entity flexray_can_telemetry is
  generic (
    ENABLED : boolean := false;
    FRAME_ID : natural range 0 to 2047 := 0;
    CYCLE_MASK : natural range 0 to 63 := 0;
    CYCLE_VALUE : natural range 0 to 63 := 0;
    CAN_ID : natural range 0 to 2047 := 0;
    BYTE_COUNT : positive range 1 to 8 := 8;
    BYTE_0 : natural range 0 to 253 := 0;
    BYTE_1 : natural range 0 to 253 := 1;
    BYTE_2 : natural range 0 to 253 := 2;
    BYTE_3 : natural range 0 to 253 := 3;
    BYTE_4 : natural range 0 to 253 := 4;
    BYTE_5 : natural range 0 to 253 := 5;
    BYTE_6 : natural range 0 to 253 := 6;
    BYTE_7 : natural range 0 to 253 := 7;
    MIN_CAPTURE_CYCLES : natural := 8000000;
    MAX_AGE_CYCLES : positive := 8000000
  );
  port (
    src_clk, dst_clk, rst, rx : in std_ulogic;
    m_valid : out std_ulogic;
    m_ready : in std_ulogic;
    m_data : out std_ulogic_vector(78 downto 0);
    dropped_full, dropped_stale : out std_ulogic_vector(31 downto 0)
  );
end entity;
architecture rtl of flexray_can_telemetry is
  signal frame : work.flexray.message;
  signal frame_valid : std_ulogic;
begin
  enabled_path : if ENABLED generate
    observer : entity work.flexray_rx port map (
      clk => src_clk, rst => rst, rx => rx, msg => frame, ready => frame_valid);
    collector : entity work.flexray_can_queue generic map (
      ENABLED => true, FRAME_ID => FRAME_ID, CYCLE_MASK => CYCLE_MASK, CYCLE_VALUE => CYCLE_VALUE,
      CAN_ID => CAN_ID, BYTE_COUNT => BYTE_COUNT,
      BYTE_0 => BYTE_0, BYTE_1 => BYTE_1, BYTE_2 => BYTE_2, BYTE_3 => BYTE_3,
      BYTE_4 => BYTE_4, BYTE_5 => BYTE_5, BYTE_6 => BYTE_6, BYTE_7 => BYTE_7,
      MIN_CAPTURE_CYCLES => MIN_CAPTURE_CYCLES, MAX_AGE_CYCLES => MAX_AGE_CYCLES)
    port map (
      src_clk => src_clk, dst_clk => dst_clk, rst => rst, frame => frame, frame_valid => frame_valid,
      m_valid => m_valid, m_ready => m_ready, m_data => m_data,
      dropped_full => dropped_full, dropped_stale => dropped_stale);
  end generate;
  disabled_path : if not ENABLED generate
    m_valid <= '0'; m_data <= (others => '0');
    dropped_full <= (others => '0'); dropped_stale <= (others => '0');
  end generate;
end architecture;
