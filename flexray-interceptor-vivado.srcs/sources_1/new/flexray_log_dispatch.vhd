library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Independent complete-frame queues; the bridge never waits for the logger.
-- Index 0 = BCM-side input, index 1 = DADC input. Only queued heads arbitrate.
entity flexray_log_dispatch is
  generic (QUEUE_DEPTH : positive range 1 to 64 := 32);
  port (
    clk, rst, dadc_valid, bcm_valid, log_busy : in std_ulogic;
    dadc_frame, bcm_frame : in work.flexray.message;
    log_req, log_bus : out std_ulogic;
    log_frame : out work.flexray.message;
    dadc_received, bcm_received, dadc_dropped, bcm_dropped : out std_ulogic_vector(31 downto 0);
    dadc_high_water, bcm_high_water : out std_ulogic_vector(31 downto 0);
    dadc_bytes, bcm_bytes : out std_ulogic_vector(31 downto 0)
  );
end entity;
architecture rtl of flexray_log_dispatch is
  -- Pack the record into a reset-free single-write memory per direction.
  -- Distributed RAM stores wide shallow queues without allocating a separate
  -- flip-flop and input mux for every bit of every frame slot.
  subtype packed_frame_t is std_ulogic_vector(2103 downto 0);
  type frame_queue_t is array (0 to QUEUE_DEPTH-1) of packed_frame_t;
  type pointers_t is array (0 to 1) of natural range 0 to QUEUE_DEPTH-1;
  type counts_t is array (0 to 1) of natural range 0 to QUEUE_DEPTH;
  type counters_t is array (0 to 1) of unsigned(31 downto 0);
  signal dadc_queue, bcm_queue : frame_queue_t;
  attribute RAM_STYLE : string;
  attribute RAM_STYLE of dadc_queue, bcm_queue : signal is "distributed";
  signal heads, tails : pointers_t := (others => 0);
  signal counts, peaks : counts_t := (others => 0);
  signal received, dropped : counters_t := (others => (others => '0'));
  signal wire_bytes : counters_t := (others => (others => '0'));
  signal previous_valid : std_ulogic_vector(1 downto 0) := (others => '0');
  signal request : std_ulogic := '0';
  signal preferred : natural range 0 to 1 := 1;
  function advance(p : natural) return natural is
  begin
    if p = QUEUE_DEPTH-1 then return 0; else return p+1; end if;
  end function;
  function increment(v : unsigned) return unsigned is
  begin
    if v = x"FFFFFFFF" then return v; else return v+1; end if;
  end function;
  function add_bytes(v : unsigned(31 downto 0); m : work.flexray.message) return unsigned is
  begin
    -- Demand includes frames later dropped by a full queue, and log overhead.
    -- Byte totals wrap so continuous rate measurements do not freeze after
    -- approximately 76 minutes of continuous 7.5 MHz SPI traffic.
    return v+shift_left(resize(unsigned(m.payload_length),32),1)+12;
  end function;
  function pack(m : work.flexray.message) return packed_frame_t is
    variable bits : packed_frame_t;
  begin
    bits(2103 downto 2064) := m.flags & m.frame_id & m.payload_length & m.header_crc & m.cycle_count;
    for i in 0 to 254 loop bits(2063-i*8 downto 2056-i*8) := std_ulogic_vector(m.data(i)); end loop;
    bits(23 downto 0) := m.crc;
    return bits;
  end function;
  function unpack(bits : packed_frame_t) return work.flexray.message is
    variable m : work.flexray.message;
  begin
    m.flags := bits(2103 downto 2099); m.frame_id := bits(2098 downto 2088);
    m.payload_length := bits(2087 downto 2081); m.header_crc := bits(2080 downto 2070);
    m.cycle_count := bits(2069 downto 2064);
    for i in 0 to 254 loop m.data(i) := std_logic_vector(bits(2063-i*8 downto 2056-i*8)); end loop;
    m.crc := bits(23 downto 0);
    return m;
  end function;
begin
  log_req <= request;
  dadc_received <= std_ulogic_vector(received(1));
  bcm_received <= std_ulogic_vector(received(0));
  dadc_dropped <= std_ulogic_vector(dropped(1));
  bcm_dropped <= std_ulogic_vector(dropped(0));
  dadc_bytes <= std_ulogic_vector(wire_bytes(1));
  bcm_bytes <= std_ulogic_vector(wire_bytes(0));
  dadc_high_water <= std_ulogic_vector(to_unsigned(peaks(1), 32));
  bcm_high_water <= std_ulogic_vector(to_unsigned(peaks(0), 32));
  process(clk, rst)
    variable used : counts_t;
    variable arrivals : std_ulogic_vector(1 downto 0);
    variable selected : natural range 0 to 1;
  begin
    if rst = '1' then
      request <= '0'; log_bus <= '1'; preferred <= 1;
      heads <= (others => 0); tails <= (others => 0);
      counts <= (others => 0); peaks <= (others => 0);
      received <= (others => (others => '0'));
      dropped <= (others => (others => '0'));
      wire_bytes <= (others => (others => '0'));
      previous_valid <= (others => '0');
      -- Counts/request qualify all data; payload storage needs no reset.
    elsif rising_edge(clk) then
      used := counts;
      arrivals := (dadc_valid & bcm_valid) and not previous_valid;
      previous_valid <= dadc_valid & bcm_valid;
      if request = '1' and log_busy = '1' then request <= '0'; end if;
      if request = '0' and log_busy = '0' then
        selected := preferred;
        if used(selected) = 0 then selected := 1-selected; end if;
        if used(selected) /= 0 then
          if selected = 1 then
            log_frame <= unpack(dadc_queue(heads(1))); log_bus <= '1';
          else
            log_frame <= unpack(bcm_queue(heads(0))); log_bus <= '0';
          end if;
          request <= '1'; preferred <= 1-selected;
          heads(selected) <= advance(heads(selected));
          used(selected) := used(selected)-1;
        end if;
      end if;
      -- Pop before push permits replacement of a full queue's consumed head.
      for source in 0 to 1 loop
        if arrivals(source) = '1' then
          received(source) <= increment(received(source));
          if source=1 then wire_bytes(source)<=add_bytes(wire_bytes(source),dadc_frame);
          else wire_bytes(source)<=add_bytes(wire_bytes(source),bcm_frame);end if;
          if used(source) < QUEUE_DEPTH then
            if source = 1 then dadc_queue(tails(1)) <= pack(dadc_frame);
            else bcm_queue(tails(0)) <= pack(bcm_frame); end if;
            tails(source) <= advance(tails(source));
            used(source) := used(source)+1;
          else
            dropped(source) <= increment(dropped(source));
          end if;
        end if;
        if used(source) > peaks(source) then peaks(source) <= used(source); end if;
      end loop;
      counts <= used;
    end if;
  end process;
end architecture;
