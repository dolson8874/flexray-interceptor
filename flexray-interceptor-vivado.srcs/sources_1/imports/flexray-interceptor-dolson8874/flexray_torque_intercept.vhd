library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.flexray;
entity flexray_torque_intercept is
  generic (SYNC_TIMEOUT_CYCLES : positive := 8000000); -- 100 ms at 80 MHz
  port (
    clk    : in std_ulogic; -- Clock 8x higher than can bitrate
    rst    : in std_ulogic;
    rx     : in std_ulogic;
    torque : in std_ulogic_vector(13 downto 0);
    sign   : in std_ulogic_vector(8 downto 0);
    enable : in std_ulogic;

    tx         : out std_ulogic;
    override   : out std_ulogic;
    sync_debug : out std_ulogic);
end entity flexray_torque_intercept;

architecture syn of flexray_torque_intercept is

  --    byte   xor
  --    10  : x"0B"
  --     8  : x"32"
  --     4  : x"CC"
  --     3  : x"B0"
  --     3  : x"DA"
  --     2  : x"8f"
  --     2  : x"e3"
  --     1  : x"11"
  function crc8_0x1D(
    data   : in std_ulogic_vector; -- unconstrained
    xorval : in std_ulogic_vector(7 downto 0)
  ) return std_ulogic_vector is
    constant POLY : std_ulogic_vector(7 downto 0) := x"1D";
    variable crc  : std_ulogic_vector(7 downto 0) := (others => '0'); -- init=0x00
    variable fb   : std_ulogic;
  begin
    for i in data'range loop
      fb  := crc(7) xor data(i);
      crc := crc(6 downto 0) & '0';
      if fb = '1' then
        crc := crc xor POLY;
      end if;
    end loop;
    return std_ulogic_vector(crc xor xorval);
  end function;
  type pdata_t is array (0 to 9) of std_ulogic_vector(7 downto 0);

  signal lkas_1F0_prev : pdata_t;
  signal lkas_1F1_prev : pdata_t;

  signal enable_sync1, enable_sync2 : std_logic;
  signal sign_sync1, sign_sync2     : std_ulogic_vector(8 downto 0);
  signal torque_sync1, torque_sync2 : std_ulogic_vector(13 downto 0);
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of enable_sync1, enable_sync2, sign_sync1, sign_sync2,
    torque_sync1, torque_sync2 : signal is "TRUE";
  -- Register the selected output bit before the CRC XOR network. The serial
  -- bit is held for eight clocks, so this one-clock internal stage does not
  -- change the transmitted bit or the CRC-field launch time.
  signal override_crc_pending : std_ulogic := '0';
  signal override_crc_bit : std_ulogic := '0';
  type state_type is (IDLE, TSS, FSS, HEADER, PAYLOAD, CRC, DONE, SKIP);
  signal state : state_type := IDLE;

  signal tick_counter : integer range 0 to 7 := 0;
  signal rx_prev      : std_ulogic           := '1';

  signal bit_counter      : integer range 0 to 9 := 0; -- BSS/byte phase, modulo 10
  signal data_bit_index   : integer range 0 to 2047 := 0; -- valid bits only
  signal real_bit_counter : integer range 0 to 4095 := 0; -- 40 header + 2032 payload + CRC/tail
  signal num_bits         : integer range 0 to 2047 := 0;

  signal is_decoded       : std_ulogic;
  signal frame_checked, frame_valid : std_ulogic := '0';
  signal cache_1_valid : std_ulogic := '0';
  signal decode_msg       : work.flexray.message;
  signal computed_crc     : std_ulogic_vector(23 downto 0) := b"111111101101110010111010";
  signal o_computed_crc   : std_ulogic_vector(23 downto 0) := b"111111101101110010111010";
  signal computed_hdr_crc : std_ulogic_vector(10 downto 0) := b"00000011010";

  signal idle_counter      : integer range 0 to 21 := 0;
  signal in_sync           : std_ulogic;
  signal lkas_diff_counter : integer range -15 to 15;
  signal asl_gray_icon     : std_ulogic;
  
  constant TEST_LCA : boolean := false;
  -- D00:9   :0x7   
  -- D01:18  :0x02
  -- 3100:27 :0xe0
  -- 3101:3  :0x80
  -- 3101:18:4 :1 1
  -- 3102:7  :0xff
  -- 3102:9  :??
  -- 3102:19 :0x38
  -- 3102:20 :0x07
  -- 3102:23 :0x20
  -- 3155: ??
  -- 3B01:12 :0x15
  -- 3B10:22 :0x44,0x55
begin

  sync_debug <= not (asl_gray_icon and in_sync);
  
  sync_joystic : process (clk, rst)
  begin
    if rst = '1' then
      enable_sync1 <= '0';
      enable_sync2 <= '0';
      sign_sync1   <= (others => '0');
      sign_sync2   <= (others => '0');
      torque_sync1 <= (others => '0');
      torque_sync2 <= (others => '0');
    else
      if rising_edge(clk) then
        enable_sync1 <= enable; -- CDC first
        enable_sync2 <= enable_sync1; -- CDC Second

        sign_sync1 <= sign;
        sign_sync2 <= sign_sync1;

        torque_sync1 <= torque;
        torque_sync2 <= torque_sync1;
      end if;
    end if;
  end process;
  
  intercept : process (clk, rst)
    variable in_bss        : std_ulogic;
    variable is_overriding : std_ulogic;
    variable next_tx       : std_ulogic;

    type data_t is array (0 to 255) of std_ulogic_vector(7 downto 0);
    variable override_data : data_t;
    variable override_mask : data_t;

    variable lkas_ready                           : std_ulogic;
    variable frame_in_sync : std_ulogic := '0';
    variable frame_cache_1_valid : std_ulogic := '0';
    variable frame_sign : std_ulogic_vector(8 downto 0) := (others => '0');
    variable lkas_enable                          : std_ulogic;
    variable lkas_enprev                          : std_ulogic;
    variable lkas_torque                          : std_ulogic_vector(13 downto 0);
    variable lkas_counter                         : integer range 0 to 15;
    variable lkas_cycle_counter                   : integer range 0 to 3;
    variable lkas_cruise_on                       : std_ulogic;
    variable lkas_moveH_EnTorqL_CruiseOnL_EntorqH : std_ulogic;

    variable v_computed_crc     : std_ulogic_vector(23 downto 0);
    variable crc_delta : std_ulogic_vector(23 downto 0);
    variable result_cmp         : boolean;
    variable tick_cnt           : integer range 0 to 7    := 0;
    variable v_real_bit_counter : integer range 0 to 4095 := 0;
  begin
    if rst = '1' then

      tx <= '1';
      override <= '0';
      tick_cnt := 0;
      v_real_bit_counter := 0;
      result_cmp := false;
      next_tx := '1';
      in_bss  := '0';

      is_overriding := '0';

      v_computed_crc := (others => '0');
      crc_delta := (others => '0');
      override_crc_pending <= '0';
      override_crc_bit <= '0';

      override_data := (others => (others => '0'));
      override_mask := (others => (others => '0'));

      lkas_ready                           := '0';
      frame_in_sync := '0';
      frame_cache_1_valid := '0';
      frame_sign := (others => '0');
      lkas_enable                          := '0';
      lkas_enprev                          := '0';
      lkas_torque                          := (others => '0');
      lkas_cycle_counter                   := 0;
      lkas_cruise_on                       := '0';
      lkas_moveH_EnTorqL_CruiseOnL_EntorqH := '0';
      asl_gray_icon <= '0';

    elsif rising_edge(clk) then

      override_crc_pending <= '0';
      if override_crc_pending = '1' then
        if (override_crc_bit xor v_computed_crc(23)) = '1' then
          v_computed_crc := (v_computed_crc(22 downto 0) & '0') xor b"010111010110110111001011";
        else
          v_computed_crc := v_computed_crc(22 downto 0) & '0';
        end if;
        o_computed_crc <= v_computed_crc;
      end if;

      result_cmp := (tick_cnt = 7) or -- Update tick counter
        (rx = '0' and rx_prev = '1' and state = IDLE) or -- Sync on first falling edge
        (rx = '1' and rx_prev = '0' and state = TSS); -- Sync on Frame Start Sequence
      if result_cmp = true then
        tick_cnt := 0;
      else
        tick_cnt := tick_cnt + 1;
      end if;

      -- Refresh permission during the header, including a falling enable.
      -- Hold the decision through the payload/CRC so an already-started
      -- modification finishes as a complete frame.
      if real_bit_counter <= 39 then
        frame_in_sync := in_sync;
        frame_cache_1_valid := cache_1_valid;
        frame_sign := sign_sync2;
        if enable_sync2 = '0' or frame_in_sync = '0' then
          lkas_enable := '0';
        else
          lkas_enable := '1';
          lkas_torque := torque_sync2;
        end if;
      end if;
      lkas_ready := frame_sign(7);

      if tick_cnt = 0 then
        v_real_bit_counter := real_bit_counter;

        if v_real_bit_counter = 40 then
          v_computed_crc := computed_crc;
        end if;

        -- Header of message passed, decide if we need to override
        if v_real_bit_counter >= 40 then
          lkas_cycle_counter := to_integer(unsigned(decode_msg.cycle_count)) mod 4;
          lkas_counter       := (to_integer(unsigned(decode_msg.cycle_count(5 downto 2))) - lkas_diff_counter) mod 16;
            
          -- 0x1F 
          if frame_in_sync = '1' and lkas_enable = '1' and decode_msg.frame_id = b"00000011111"
             and (lkas_cycle_counter /= 1 or frame_cache_1_valid = '1') then

            is_overriding      := '1';

            if lkas_cycle_counter = 0 then
              is_overriding := '1';

              if v_real_bit_counter = 40 then
                override_data := (others => (others => '0'));
                override_mask := (others => (others => '0'));

                -- LANDROVER Defender LKAS msg
                -- 1 torque counter
                -- override_data(1) := b"0001" & std_ulogic_vector(to_unsigned(lkas_counter, 4)) ( 3 downto 0);
                override_data(1) := b"0001" & (std_ulogic_vector(to_unsigned(lkas_counter, 4))); -- vivado
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
                if 0 = to_integer(unsigned(decode_msg.cycle_count)) mod 8 then
                  override_data(6) := b"000" & lkas_cruise_on & '0' & lkas_cruise_on & '0' & '0';
                else
                  override_data(6) := lkas_1F0_prev(0);
                end if;

                override_mask(6) := x"FF";

                -- override_data(7) := x"00";	
                -- bit 1 : 0 Above5KmHCruiseOnLkasH_Under5KmLCruiseOffLkasL == CruiseOn
                if lkas_cruise_on = '1' then
                  if work.flexray.cycle_phase_12(decode_msg.cycle_count, 0) then
                    override_data(7) := lkas_1F0_prev(1);
                  else
                    override_data(7) := b"000000" & lkas_cruise_on & '0';
                  end if;
                else
                  override_data(7) := b"000000" & lkas_cruise_on & '0';
                end if;

                override_mask(7) := x"FF";
                
                if TEST_LCA then
                  override_data(6) := b"000" & lkas_cruise_on & '0' & lkas_cruise_on & '0' & '0'; 
                  override_data(7) := b"000000" & lkas_cruise_on & '0';                
                end if;

                override_data(8) := x"00";
                override_mask(8) := x"FF";
                override_data(0) := crc8_0x1D (override_data(1) & override_data(2) & override_data(3) &
                                               override_data(4) & override_data(5) & override_data(6) &
                                               override_data(7) & override_data(8),
                                               x"32"
                                    );
                override_mask(0) := x"FF";

                -- 14 flag torque counter
                override_data(14) := b"0000" & override_data(1)(3 downto 0);
                override_mask(14) := x"FF";

                -- 15 torque data , bit2~0 : torque msb 3bit
                override_data(15) := b"10" & lkas_torque(13 downto 8);
                override_mask(15) := x"FF";

                -- 16 torq data last 8bit
                override_data(16) := lkas_torque(7 downto 0);
                override_mask(16) := x"FF";

              end if;

              if v_real_bit_counter = 41 then
                -- 13 flag crc poly = 0x1d, crc 8bit, xor 0xb0
                override_data(13) := crc8_0x1D(override_data(14) & override_data(15) & override_data(16), x"B0");
                override_mask(13) := x"FF";
              end if;
            elsif lkas_cycle_counter = 1 then

              is_overriding := '1';

              if v_real_bit_counter = 40 then
                override_data := (others => (others => '0'));
                override_mask := (others => (others => '0'));

                override_data(1) := b"0000" & (std_ulogic_vector(to_unsigned(lkas_counter, 4))); -- viviado
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
                  if work.flexray.cycle_phase_12(decode_msg.cycle_count, 1) then
                    override_data(2) := lkas_1F1_prev(0);
                  else
                    override_data(2) := x"00";
                  end if;
                else
                  override_data(2) := x"00";
                end if;

                override_data(3)  := lkas_1F1_prev(1);
                override_data(4)  := lkas_1F1_prev(2);
                override_data(5)  := lkas_1F1_prev(3);
                override_data(6)  := lkas_1F1_prev(4);
                override_data(7)  := lkas_1F1_prev(5);
                override_data(8)  := lkas_1F1_prev(6);
                override_data(9)  := lkas_1F1_prev(7);
                override_data(10) := lkas_1F1_prev(8);

                override_data(0) := crc8_0x1D (
                override_data(1) & override_data(2) & override_data(3) &
                override_data(4) & override_data(5) & override_data(6) &
                override_data(7) & override_data(8) & override_data(9) &
                override_data(10),
                x"0b"
                );
                override_mask(0) := x"FF";

                -- override_data(16) := b"0001" & std_ulogic_vector(to_unsigned(lkas_counter, 4)) ( 3 downto 0);
                override_data(16) := b"0001" & (std_ulogic_vector(to_unsigned(lkas_counter, 4))); -- vivoado
                override_mask(16) := x"FF";

                -- 0x48 | cruise_on
                override_data(17) := b"0100100" & lkas_cruise_on;
                override_mask(17) := x"FF";
              end if;

              if v_real_bit_counter = 41 then
                -- 15 flag crc poly = 0x1d, crc 8bit, xor 0x8f
                override_data(15) := crc8_0x1D(override_data(16) & override_data(17),x"8f");
                override_mask(15) := x"FF";
              end if;

            elsif lkas_cycle_counter = 3 then
              -- Reserved/pass-through in the existing design. Do not create
              -- unused replacement bytes or enable a previously dormant path.
              override_data := (others => (others => '0'));
              override_mask := (others => (others => '0'));

              is_overriding := '0';

              if v_real_bit_counter = 66 + num_bits then
                -- override end
                lkas_enable := '0';
              end if;

            else
              is_overriding := '0';
              override_data := (others => (others => '0'));
              override_mask := (others => (others => '0'));
            end if;


            -- 0x3155 counter 
          elsif frame_in_sync = '1' and decode_msg.frame_id = b"00000110001"
            and 5 = to_integer(unsigned(decode_msg.cycle_count)) mod 16 then

            override_data := (others => (others => '0'));
            override_mask := (others => (others => '0'));
            is_overriding     := '0';
            
            if TEST_LCA and lkas_ready = '1' then
              is_overriding     := '1';
              override_data(0) := x"3b"; -- 20250610 Test LFA below 50Km
              override_mask(0) := x"ff";
              
              override_data(5) := x"7f"; -- 20250610 Test LFA below 50Km
              override_mask(5) := x"ff";  
              
              override_data(11) := x"04"; -- 20250610 Test LFA below 50Km
              override_mask(11) := x"ff";
              
              override_data(12) := x"80"; -- 20250610 Test LFA below 50Km
              override_mask(12) := x"ff";              
            end if;
            
            -- 0x31 counter 0
          elsif frame_in_sync = '1' and decode_msg.frame_id = b"00000110001"
            and 0 = lkas_cycle_counter then

            -- cruise on
            lkas_cruise_on := decode_msg.data(21)(0);
            
            override_data := (others => (others => '0'));
            override_mask := (others => (others => '0'));
            
            
            if TEST_LCA and lkas_ready = '1' then
              is_overriding     := '1';
              override_data(25) := x"e0"; -- 20250610 Test LFA below 50Km
              override_mask(25) := x"ff";  
            end if;

            -- LKAS Green line
            -- frame id=0x31 sync_id=1/8 00:pass 11:white 01:green 10:red 
          elsif frame_in_sync = '1' and decode_msg.frame_id = b"00000110001"
            and 1 = to_integer(unsigned(decode_msg.cycle_count)) mod 8 then

            override_data := (others => (others => '0'));
            override_mask := (others => (others => '0'));
            
            if frame_sign(5 downto 0) /= b"000000" or lkas_enable = '1' then
              is_overriding     := '1';
              
              if TEST_LCA and lkas_ready = '1' then
                override_data(1) := x"80"; -- 20250822 Test LFA below 50Km
                override_mask(1) := x"ff";              

                override_data(16) := x"40"; -- 20260129 Test LFA below 50Km
                override_mask(16) := x"40";    
              end if;
            end if;
            
            if frame_sign(4 downto 3) /= b"00" then
              override_data(2) := b"000000" & frame_sign(4 downto 3);
              override_mask(2) := x"03";
            end if;

            if frame_sign(1 downto 0) /= b"00" then
              override_data(3) := b"000000" & frame_sign(1 downto 0);
              override_mask(3) := x"03";
            end if;

            -- for blinker_lr, ASL gray icon status
            asl_gray_icon <= decode_msg.data(9)(5);

            -- right blindSpot
            if frame_sign(5) = '1' then
            end if;

            -- left blindSpot
            if frame_sign(2) = '1' then
            end if;
            
            -- 0x31 counter 2 25hz
          elsif TEST_LCA and frame_in_sync = '1' and decode_msg.frame_id = b"00000110001"
            and 2 = to_integer(unsigned(decode_msg.cycle_count)) mod 8 then

            if lkas_ready = '1' then
              is_overriding := '1';
              
              override_data := (others => (others => '0'));
              override_mask := (others => (others => '0'));            
              
              override_data(5) := x"ff"; -- 20250610 Test LFA below 50Km
              override_mask(5) := x"ff";  
              override_data(17) := x"38"; -- 20250610 Test LFA below 50Km
              override_mask(17) := x"ff";              
              override_data(18) := x"07"; -- 20250610 Test LFA below 50Km
              override_mask(18) := x"ff";                       
              override_data(21) := x"20"; -- 2025061 Test LFA below 50Km 3102:23
              override_mask(21) := x"ff";               
            end if;
            
          -- 0x3b10 counter 0 50Hz 0x3b10
          -- 20250610 Test LFA below 50Km
           elsif TEST_LCA and frame_in_sync = '1' and decode_msg.frame_id = b"00000111011"
             and (lkas_cycle_counter = 0) then

             override_data := (others => (others => '0'));
             override_mask := (others => (others => '0')); 

             if lkas_enable = '1' then       
               is_overriding := '1';
               override_data(20) := x"55"; -- 20250610 Test LFA below 50Km
               override_mask(20) := x"ff"; 
             elsif lkas_ready = '1' then
               is_overriding := '1';
               override_data(20) := x"44"; -- 20250610 Test LFA below 50Km
               override_mask(20) := x"ff";                
             end if;
       
          -- 0x3b01 counter 1 100Hz
          -- 20250610 Test LFA below 50Km
           -- elsif TEST_LCA and in_sync = '1' and decode_msg.frame_id = b"00000111011"
             -- and (lkas_cycle_counter = 1 or lkas_cycle_counter = 3) then

             -- if lkas_enable = '1' then
               -- is_overriding := '1';
              
               -- if v_real_bit_counter = 40 then
                 -- override_data := (others => (others => '0'));
                 -- override_mask := (others => (others => '0'));              

                 -- override_data(9) := b"0000" & (std_ulogic_vector(to_unsigned(lkas_counter, 4)));
                 -- override_mask(9) := x"ff";   
                
                 -- override_data(10) := x"15"; -- 20250610 Test LFA below 50Km
                 -- override_mask(10) := x"ff";   
                
                 -- override_data(11) := x"dc"; -- 20250610 Test LFA below 50Km
                 -- override_mask(11) := x"ff";          

                 -- override_data(12) := x"05"; -- 20250610 Test LFA below 50Km
                 -- override_mask(12) := x"ff";                     

                 -- override_data(13) := x"dc"; -- 20250610 Test LFA below 50Km
                 -- override_mask(13) := x"ff";  
                
                 -- override_data(14) := x"0f"; -- 20250610 Test LFA below 50Km
                 -- override_mask(14) := x"ff";  

                 -- override_data(15) := x"a0"; -- 20250610 Test LFA below 50Km
                 -- override_mask(15) := x"ff";                  

                 -- override_data(8) := crc8_0x1D(override_data(9) & override_data(10) & 
                                               -- override_data(11) & override_data(12) &
                                               -- override_data(13) & override_data(14) &
                                               -- override_data(15),
                                               -- x"B4");
                 -- override_mask(8) := x"ff";              
               -- end if;
             -- end if;
            
          -- TEST below 50Km
          -- frame id=0x0d sync_id=0/4 
          elsif TEST_LCA and frame_in_sync = '1' and decode_msg.frame_id = b"00000001101" and
            0 = lkas_cycle_counter then

            if lkas_ready = '1' then
              is_overriding := '1';
              --if v_real_bit_counter = 40 then
                override_data := (others => (others => '0'));
                override_mask := (others => (others => '0'));
                
                override_data(7) := x"07";  -- 20250823 Test LFA below 50Km 
                override_mask(7) := x"ff";
              --end if;
              
            end if;            

          -- frame id=0x0d sync_id=1/4 
          elsif frame_in_sync = '1' and decode_msg.frame_id = b"00000001101" and
            1 = lkas_cycle_counter then

            if v_real_bit_counter = 40 then
              override_data := (others => (others => '0'));
              override_mask := (others => (others => '0'));
            end if;

            -- Steering Assist Icon
            if lkas_ready = '1' then
              is_overriding := '1';

              if TEST_LCA then
                override_data(16) := x"02"; -- 20250823 Test LFA below 50Km
                override_mask(16) := x"ff";   
              end if;

              --if v_real_bit_counter = 40 then
                if lkas_enable = '1' then
                  override_data(15) := b"00100000";
                  override_mask(15) := x"20";
                else
                  override_data(15) := b"01100000";
                  override_mask(15) := x"60";
                end if;
              --end if;
            end if;

            -- hazard light by asl handle button (blinker left, right) 
            if asl_gray_icon = '1' then
              is_overriding := '1';

              --if v_real_bit_counter = 40 then
                override_data(7) := b"000" & asl_gray_icon & b"0000";
                override_mask(7) := x"10";
              --end if;
            end if;
          else
            is_overriding := '0';
          end if;

        end if; -- v_real_bit_counter >= 40

        -- Handle BSS
        if is_overriding = '1' then
          is_overriding := '0';

          if (bit_counter mod 10) < 2 then
            in_bss := '1';
          else
            in_bss := '0';
          end if;

          -- No BSS when at end of message
          if v_real_bit_counter >= 64 + num_bits then
            in_bss := '0';
          end if;

          if in_bss = '0' then
            if v_real_bit_counter >= 40 and v_real_bit_counter <= 40 + num_bits - 1 then
              -- PAYLOAD
              next_tx := override_data((v_real_bit_counter - 40) / 8)(7 - (v_real_bit_counter - 40) mod 8);

              if override_mask((v_real_bit_counter - 40) / 8)(7 - (v_real_bit_counter - 40) mod 8) = '1' then
                is_overriding := '1';
              end if;

            elsif v_real_bit_counter >= 40 + num_bits and v_real_bit_counter <= 63 + num_bits then
              -- Apply the CRC difference to the received CRC, retaining any
              -- input CRC error instead of turning a corrupt frame valid.
              if v_real_bit_counter = 40 + num_bits then
                crc_delta := computed_crc xor v_computed_crc;
              end if;
              next_tx := rx xor crc_delta(23 - (v_real_bit_counter - 40 - num_bits));
              is_overriding := '1';
            elsif v_real_bit_counter = 64 + num_bits then -- FES
              is_overriding := '0';
            elsif v_real_bit_counter = 65 + num_bits then
              is_overriding := '0';
            elsif v_real_bit_counter = 66 + num_bits then
              is_overriding := '0';
            end if;

            -- calc CRC 24bit
            if is_overriding = '1' then
              if v_real_bit_counter >= 40 and v_real_bit_counter <= 40 + num_bits - 1 then
                override_crc_bit <= next_tx;
                override_crc_pending <= '1';
              end if;
            end if;

            o_computed_crc <= v_computed_crc;

          end if; -- in_bss == 0

          tx <= next_tx;
        end if; -- overrideing = 1

      end if; -- end if tick_counter = 0

      override <= is_overriding;

      -- Sample at 50%
      if tick_cnt = 3 and is_overriding = '0' and v_real_bit_counter >= 40 then
        -- Update CRC
        if in_bss = '0' and v_real_bit_counter >= 0 and v_real_bit_counter <= 40 + num_bits - 1 then
          if (rx xor v_computed_crc(23)) = '1' then
            v_computed_crc := (v_computed_crc(22 downto 0) & '0') xor b"010111010110110111001011";
          else
            v_computed_crc := (v_computed_crc(22 downto 0) & '0');
          end if;
        end if;

        o_computed_crc <= v_computed_crc;
      end if;

    end if;
  end process;

  -- Tick counter and RX sampling
  mgmt_tick : process (clk, rst)
    variable result_cmp : boolean;
  begin
    if rst = '1' then
      result_cmp := false;
      tick_counter <= 0;
      rx_prev <= '1';

    elsif rising_edge(clk) then
      rx_prev <= rx;

      result_cmp := (tick_counter = 7) or -- Update tick counter
        (rx = '0' and rx_prev = '1' and state = IDLE) or -- Sync on first falling edge
        (rx = '1' and rx_prev = '0' and state = TSS); -- Sync on Frame Start Sequence
        
      if result_cmp = true then
        tick_counter <= 0;
      else
        tick_counter <= tick_counter + 1;
      end if;

    end if;
  end process;

  decode : process (clk, rst)
    variable var_state : state_type;
    variable rx_sample : std_ulogic;
  begin
    if rst = '1' then
      state <= IDLE;
      var_state := IDLE;
      is_decoded       <= '0';
      bit_counter      <= 0;
      real_bit_counter <= 0;
      num_bits <= 0;
      frame_checked <= '0'; frame_valid <= '0';
      data_bit_index   <= 0;
      idle_counter     <= 0;

      decode_msg.flags          <= (others => '0');
      decode_msg.frame_id       <= (others => '0');
      decode_msg.payload_length <= (others => '0');
      decode_msg.header_crc     <= (others => '0');
      decode_msg.cycle_count    <= (others => '0');
      decode_msg.data           <= (others => (others => '0'));
      decode_msg.crc            <= (others => '0');

      computed_crc     <= b"111111101101110010111010";
      computed_hdr_crc <= b"00000011010";

    elsif rising_edge(clk) then
      frame_checked <= '0'; frame_valid <= '0';
      if tick_counter = 2 then

        var_state := state;

        rx_sample := rx;

        -- Signal is idle, increase idle counter
        if rx_sample = '1' and idle_counter < 20 then
          idle_counter <= idle_counter + 1;
        else
          if idle_counter = 20 then
            -- idle timeout
            var_state := IDLE;
            state <= IDLE;
          end if;
          idle_counter <= 0;
        end if;

        -- Handle BSS	  
        if bit_counter = 9 then bit_counter <= 0;
        else bit_counter <= bit_counter + 1; end if;

        if var_state > FSS and var_state <= CRC then
          if (bit_counter mod 10) < 2 then
            var_state := SKIP;
          end if;
        end if;

        if var_state /= SKIP and var_state /= TSS then
          data_bit_index   <= data_bit_index + 1;
          real_bit_counter <= real_bit_counter + 1;
        end if;

      else
        var_state := SKIP;
      end if;

      case var_state is
        when SKIP =>
          null;

        when IDLE =>
          if rx_sample = '0' then
            state        <= TSS;
            is_decoded   <= '0';
            idle_counter <= 0;
          else
            bit_counter      <= 0;
            data_bit_index   <= 0;
            real_bit_counter <= 0;
          end if;

        when TSS =>
          if rx_sample = '1' then
            state            <= HEADER;
            bit_counter      <= 0;
            data_bit_index   <= 0;
            real_bit_counter <= 0;

            decode_msg.flags          <= (others => '0');
            decode_msg.frame_id       <= (others => '0');
            decode_msg.payload_length <= (others => '0');
            decode_msg.header_crc     <= (others => '0');
            decode_msg.cycle_count    <= (others => '0');
            decode_msg.data           <= (others => (others => '0'));
            decode_msg.crc            <= (others => '0');

            computed_crc     <= b"111111101101110010111010";
            computed_hdr_crc <= b"00000011010";
          end if;

        when FSS =>
          -- frame start
          state <= HEADER;

        when HEADER =>
          -- 유효 데이터 수신
          case data_bit_index is
            when 0 to 4 =>
              decode_msg.flags(decode_msg.flags'left - data_bit_index) <= rx_sample;
            when 5 to 15 =>
              decode_msg.frame_id(decode_msg.frame_id'left - (data_bit_index - 5)) <= rx_sample;
            when 16 to 22 =>
              decode_msg.payload_length(decode_msg.payload_length'left - (data_bit_index - 16)) <= rx_sample;
            when 23 to 33 =>
              decode_msg.header_crc(decode_msg.header_crc'left - (data_bit_index - 23)) <= rx_sample;
            when 34 to 39 =>
              decode_msg.cycle_count(decode_msg.cycle_count'left - (data_bit_index - 34)) <= rx_sample;
            when others => null;
          end case;
          -- CRC 누적
          if data_bit_index <= 39 then
            if (rx_sample xor computed_crc(23)) = '1' then
              computed_crc <= (computed_crc(22 downto 0) & '0') xor b"010111010110110111001011";
            else
              computed_crc <= (computed_crc(22 downto 0) & '0');
            end if;
          end if;

          if data_bit_index >= 3 and data_bit_index <= 22 then
            if (rx_sample xor computed_hdr_crc(10)) = '1' then
              computed_hdr_crc <= (computed_hdr_crc(9 downto 0) & '0') xor b"01110000101";
            else
              computed_hdr_crc <= (computed_hdr_crc(9 downto 0) & '0');
            end if;
          end if;

          if data_bit_index = 39 then
            num_bits       <= to_integer(unsigned(decode_msg.payload_length)) * 16;
            data_bit_index <= 0;
            state          <= PAYLOAD;
          end if;

        when PAYLOAD =>
          if data_bit_index < num_bits then
            decode_msg.data(data_bit_index / 8)(7 - (data_bit_index mod 8)) <= rx_sample;

            --CRC 누적
            if (rx_sample xor computed_crc(23)) = '1' then
              computed_crc <= (computed_crc(22 downto 0) & '0') xor b"010111010110110111001011";
            else
              computed_crc <= (computed_crc(22 downto 0) & '0');
            end if;
          else
            state                               <= CRC;
            data_bit_index                      <= 1;
            decode_msg.crc(decode_msg.crc'left) <= rx_sample;
          end if;

        when CRC =>
          decode_msg.crc(decode_msg.crc'left - data_bit_index) <= rx_sample;
          if data_bit_index = 23 then
            state          <= DONE;
            data_bit_index <= 0;
          end if;

        when DONE =>
          if data_bit_index = 0 then
            frame_checked <= '1';
            if computed_crc = decode_msg.crc and decode_msg.header_crc = computed_hdr_crc then
              frame_valid <= '1';
            end if;
          end if;
          if computed_crc = decode_msg.crc and decode_msg.header_crc = computed_hdr_crc then
            is_decoded <= '1';
          end if;

          -- wait FES
          if data_bit_index >= 2 then
            state        <= IDLE;
            idle_counter <= 20;
          end if;

        when others =>
          state <= IDLE;

      end case;

    end if;
  end process;
  
  
  prev_copy : process (clk, rst)
    variable age : natural range 0 to SYNC_TIMEOUT_CYCLES := 0;
    variable cache_age : natural range 0 to SYNC_TIMEOUT_CYCLES := 0;
    variable phase : natural range 0 to 3;
    variable expected_counter : natural range 0 to 15;
  begin
    if rst = '1' then
      age := 0; cache_age := 0;
      in_sync <= '0'; lkas_diff_counter <= 0; cache_1_valid <= '0';
      lkas_1F0_prev <= (others => (others => '0'));
      lkas_1F1_prev <= (others => (others => '0'));
    elsif rising_edge(clk) then
      if age < SYNC_TIMEOUT_CYCLES then age := age + 1; end if;
      if cache_age < SYNC_TIMEOUT_CYCLES then cache_age := cache_age + 1; end if;
      if cache_age = SYNC_TIMEOUT_CYCLES then cache_1_valid <= '0'; end if;
      if age = SYNC_TIMEOUT_CYCLES then
        in_sync <= '0'; cache_1_valid <= '0';
      end if;
      if frame_checked = '1' and decode_msg.frame_id = b"00000011111" then
        if frame_valid = '0' or unsigned(decode_msg.payload_length) < 13 then
          in_sync <= '0'; cache_1_valid <= '0';
        elsif decode_msg.data(25) = x"60" then
          phase := to_integer(unsigned(decode_msg.cycle_count(1 downto 0)));
          case phase is
            when 0 =>
              age := 0; -- only a fresh reference frame refreshes synchronization
              lkas_1F0_prev(0) <= std_ulogic_vector(decode_msg.data(6));
              lkas_1F0_prev(1) <= std_ulogic_vector(decode_msg.data(7));
              if decode_msg.data(15) = x"23" and decode_msg.data(16) = x"28" then
                lkas_diff_counter <= (to_integer(unsigned(decode_msg.cycle_count(5 downto 2))) -
                  to_integer(unsigned(decode_msg.data(1)(3 downto 0)))) mod 16;
                in_sync <= '1';
              elsif in_sync = '1' then
                expected_counter := (to_integer(unsigned(decode_msg.cycle_count(5 downto 2))) - lkas_diff_counter) mod 16;
                if to_integer(unsigned(decode_msg.data(1)(3 downto 0))) /= expected_counter then
                  in_sync <= '0'; cache_1_valid <= '0';
                end if;
              end if;
            when 1 =>
              for i in 0 to 8 loop
                lkas_1F1_prev(i) <= std_ulogic_vector(decode_msg.data(i + 2));
              end loop;
              -- A cycle-1 cache has its own expiry; other phases cannot keep
              -- an old snapshot alive when this multiplexed frame is absent.
              if in_sync = '1' and age < SYNC_TIMEOUT_CYCLES then
                cache_1_valid <= '1'; cache_age := 0;
              end if;
            when others => null;
          end case;
        end if;
      end if;
    end if;
  end process;

end architecture syn;
