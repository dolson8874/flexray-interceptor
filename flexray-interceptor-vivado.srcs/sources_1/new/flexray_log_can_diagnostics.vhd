library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Eight version-2 CAN pages carry a coherent 48-byte statistics snapshot.
-- Every page carries six bytes of the snapshot. No SPI format change.
-- An independent 0x2F record carries firmware identity (no snapshot sequence).
-- Reuse the bounded/expiring async CAN collector with a locally generated
-- eight-byte record (not a received FlexRay frame or an on-wire FlexRay ID).
entity flexray_log_can_diagnostics is
  generic (
    ENABLED : boolean := false;
    CAN_ID : natural range 0 to 2047 := 16#1FA#;
    PERIOD_CYCLES : positive := 80000000;
    MAX_AGE_CYCLES : positive := 80000000
  );
  port (
    src_clk, dst_clk, rst : in std_ulogic;
    stats : in std_ulogic_vector(383 downto 0);
    m_valid : out std_ulogic;
    m_ready : in std_ulogic;
    m_data : out std_ulogic_vector(78 downto 0);
    dropped_full, dropped_stale : out std_ulogic_vector(31 downto 0)
  );
end entity;

architecture rtl of flexray_log_can_diagnostics is
  -- Release identity: update for every distributed bitstream/source release.
  -- BUILD_ID is an explicitly assigned release number, not a Git hash.
  constant FW_MAJOR : natural range 0 to 255 := 1;
  constant FW_MINOR : natural range 0 to 255 := 0;
  constant FW_PATCH : natural range 0 to 255 := 0;
  constant BUILD_ID : std_ulogic_vector(31 downto 0) := x"00000001";
  signal snapshot : std_ulogic_vector(383 downto 0) := (others => '0');
  signal sequence_number : unsigned(7 downto 0) := (others => '1');
  signal timer : natural range 0 to PERIOD_CYCLES-1 := 0;
  signal page : natural range 0 to 8 := 0;
  signal active, frame_valid : std_ulogic := '0';
  signal frame : work.flexray.message;
begin
  assert PERIOD_CYCLES >= 32 report "Diagnostic period too short for eight pages" severity failure;
  frame.flags <= (others => '0'); frame.frame_id <= (others => '0');
  frame.payload_length <= "0000100"; frame.header_crc <= (others => '0');
  frame.cycle_count <= (others => '0'); frame.crc <= (others => '0');
  process(src_clk, rst)
    variable value : std_ulogic_vector(47 downto 0);
  begin
    if rst = '1' then
      timer <= 0; page <= 0; active <= '0'; frame_valid <= '0';
      snapshot <= (others => '0'); sequence_number <= (others => '1');
      frame.data <= (others => (others => '0'));
    elsif rising_edge(src_clk) then
      frame_valid <= '0';
      if ENABLED then
        if timer = PERIOD_CYCLES-1 then
          timer <= 0; snapshot <= stats; sequence_number <= sequence_number+1;
          active <= '1'; page <= 0;
        else timer <= timer+1; end if;
        if active = '1' and frame_valid = '0' then
          if page = 8 then
            frame.data(0) <= x"2F";
            frame.data(1) <= std_logic_vector(to_unsigned(FW_MAJOR, 8));
            frame.data(2) <= std_logic_vector(to_unsigned(FW_MINOR, 8));
            frame.data(3) <= std_logic_vector(to_unsigned(FW_PATCH, 8));
            for byte_index in 0 to 3 loop
              frame.data(4+byte_index) <= std_logic_vector(BUILD_ID(byte_index*8+7 downto byte_index*8));
            end loop;
          else
            value := snapshot(page*48+47 downto page*48);
            frame.data(0) <= std_logic_vector(to_unsigned(16#20#+page, 8));
            frame.data(1) <= std_logic_vector(sequence_number);
            for byte_index in 0 to 5 loop
              frame.data(2+byte_index) <= std_logic_vector(value(byte_index*8+7 downto byte_index*8));
            end loop;
          end if;
          frame_valid <= '1';
          if page = 8 then active <= '0'; else page <= page+1; end if;
        end if;
      end if;
    end if;
  end process;
  collector : entity work.flexray_can_queue generic map (
    ENABLED => ENABLED, FRAME_ID => 0, CAN_ID => CAN_ID, BYTE_COUNT => 8,
    MIN_CAPTURE_CYCLES => 0, MAX_AGE_CYCLES => MAX_AGE_CYCLES)
  port map (
    src_clk => src_clk, dst_clk => dst_clk, rst => rst,
    frame_valid => frame_valid, frame => frame,
    m_valid => m_valid, m_ready => m_ready, m_data => m_data,
    dropped_full => dropped_full, dropped_stale => dropped_stale);
end architecture;
