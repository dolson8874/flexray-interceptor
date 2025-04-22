library ieee;
use ieee.numeric_std.all;
use ieee.std_logic_1164.all;

entity joystick_decoder is
  port(
    clk         : in  std_ulogic;
    rst         : in  std_ulogic;
    rx          : in  std_ulogic;
    tx          : out std_ulogic;
    torque      : out std_ulogic_vector(13 downto 0);
    sign        : out std_ulogic_vector(8 downto 0);
    enable      : out std_ulogic;
    relay       : out std_ulogic;
    debug       : out std_ulogic);
end joystick_decoder;

architecture syn of joystick_decoder is

  component can_rx is
    port (
      clk   : in  std_ulogic;
      rst   : in  std_ulogic;
      rx    : in  std_ulogic;
      tx    : out std_ulogic;
      debug : out std_ulogic;
      msg   : out work.can.message;
      ready : out std_ulogic);
  end component can_rx;

  component can_tx is
	port (
	  clk : in std_ulogic;                -- Clock 8x higher than can bitrate
      rst : in std_ulogic;

      ready : in std_ulogic;
      msg   : in work.can.message;

      busy : out   std_ulogic;
      tx   : out   std_ulogic;
      done : inout std_ulogic);
  end component can_tx;
  
  -- Poly 0x1D, crc 8bit, data 32bit  
  function crc8_4(
        crcIn: in std_ulogic_vector(7 downto 0);
        data: in std_ulogic_vector(31 downto 0))
		
  return std_ulogic_vector is 
	variable crcOut : std_ulogic_vector(7 downto 0);
		
  begin
    crcOut(0) := crcIn(0) xor crcIn(1) xor crcIn(4) xor crcIn(7) xor data(0) xor data(4) xor data(5) xor data(6) xor data(10) xor data(13) xor data(15) xor data(16) xor data(17) xor data(24) xor data(25) xor data(28) xor data(31);
    crcOut(1) := crcIn(1) xor crcIn(2) xor crcIn(5) xor data(1) xor data(5) xor data(6) xor data(7) xor data(11) xor data(14) xor data(16) xor data(17) xor data(18) xor data(25) xor data(26) xor data(29);
    crcOut(2) := crcIn(0) xor crcIn(1) xor crcIn(2) xor crcIn(3) xor crcIn(4) xor crcIn(6) xor crcIn(7) xor data(0) xor data(2) xor data(4) xor data(5) xor data(7) xor data(8) xor data(10) xor data(12) xor data(13) xor data(16) xor data(18) xor data(19) xor data(24) xor data(25) xor data(26) xor data(27) xor data(28) xor data(30) xor data(31);
    crcOut(3) := crcIn(0) xor crcIn(2) xor crcIn(3) xor crcIn(5) xor data(0) xor data(1) xor data(3) xor data(4) xor data(8) xor data(9) xor data(10) xor data(11) xor data(14) xor data(15) xor data(16) xor data(19) xor data(20) xor data(24) xor data(26) xor data(27) xor data(29);
    crcOut(4) := crcIn(0) xor crcIn(3) xor crcIn(6) xor crcIn(7) xor data(0) xor data(1) xor data(2) xor data(6) xor data(9) xor data(11) xor data(12) xor data(13) xor data(20) xor data(21) xor data(24) xor data(27) xor data(30) xor data(31);
    crcOut(5) := crcIn(1) xor crcIn(4) xor crcIn(7) xor data(1) xor data(2) xor data(3) xor data(7) xor data(10) xor data(12) xor data(13) xor data(14) xor data(21) xor data(22) xor data(25) xor data(28) xor data(31);
    crcOut(6) := crcIn(2) xor crcIn(5) xor data(2) xor data(3) xor data(4) xor data(8) xor data(11) xor data(13) xor data(14) xor data(15) xor data(22) xor data(23) xor data(26) xor data(29);
    crcOut(7) := crcIn(0) xor crcIn(3) xor crcIn(6) xor data(3) xor data(4) xor data(5) xor data(9) xor data(12) xor data(14) xor data(15) xor data(16) xor data(23) xor data(24) xor data(27) xor data(30);
	return crcOut xor x"CC";
  end;  
  
  
  -- 500kbps 4000 Hz/10ms, 400000/1sec
  -- 800kbps 6400 Hz/10ms, 640000/1sec
  constant COUNTS_IN_10_MS : integer := 6400; -- 10ms
  constant NUM_MS_TO_DELAY : integer := 100;  -- 100ms
  
  signal msg   : work.can.message;
  signal ready : std_ulogic;
  signal relay_ctrl : std_ulogic;
  
  signal idone : std_ulogic;
  signal ibusy : std_ulogic;
  signal omsg  : work.can.message;
  signal ready_tx : std_ulogic;
  
  signal can_received : std_ulogic;
  signal counter_10ms_en : std_ulogic;
  signal ms_delay_done : std_ulogic;

begin
  rx_obj : can_rx port map (clk => clk, rst => rst, rx => rx, ready => ready, msg => msg, tx => tx);
  --tx_obj : can_tx port map (clk => clk, rst => rst, ready => ready_tx, 
  --                           msg => omsg, busy => ibusy , tx => tx, done => idone); 
  
  debug <= not can_received;
  --relay <= relay_ctrl;
  relay <= '0';
  
  timebase : process (clk, rst)
    variable counter : integer range 0 to COUNTS_IN_10_MS := 0;
	
  begin
    if rst = '1' then
	  counter := 0;
	  counter_10ms_en <= '0';
    elsif rising_edge(clk) then
      counter_10ms_en <= '0';
      if counter < (COUNTS_IN_10_MS-1) then
        counter := counter + 1;
      else
        counter_10ms_en <= '1';
        counter := 0;
      end if;
    end if;
  end process timebase;

    
  -- canbus health check for flexray bypass relay 
  manage_relay : process (clk, rst)
    variable ms_delay : integer range 0 to NUM_MS_TO_DELAY := 0;
  begin
    if rst = '1' then
	  relay_ctrl <= '1';    -- active low
	  ms_delay := 0;
    elsif rising_edge(clk) then
	
	  if can_received = '1' then
        relay_ctrl <= '0'; 	-- active low
	    ms_delay := 0;
		
      else

        if counter_10ms_en = '1' then
          if ms_delay < (NUM_MS_TO_DELAY-1) then
            ms_delay := ms_delay + 1;
          else 
            relay_ctrl <= '1'; 
            ms_delay := 0;
          end if;
        end if;
	  
	    -- debug <= blinker;
		
	  end if;
	  
    end if;
  end process;
  


  check_can : process(clk, rst)
  variable prev_counter : std_ulogic_vector(7 downto 0);
  variable crc_data     : std_ulogic_vector(7 downto 0);
  begin
    if rst = '1' then
      -- Reset stuff
      torque      <= (others => '0');
      sign        <= (others => '0');
      enable      <= '0';
      can_received <= '0';
	  prev_counter := (others => '0');
	  crc_data := (others => '0');
	 
    elsif rising_edge(clk) then
	 
      -- Recv message on ready
        if ready = '1' then
		  crc_data := crc8_4(b"00000000", msg.dat(55 downto 24)); 
		  
		  if msg.id = b"00111110000" then   -- 0x1F0 LKAS AngleTorque
		
		    -- can frame_id 0x1F0
		    -- # steer offset 9000 0x2328
		    -- #       crc   counter     en torq  torq        
		    -- #       0      1     2     3        4     5     6     7
		    -- dat = [ 0xeb, 0xff, 0xff, 0x23,    0x28, 0x00, 0x00, 0x00 ]
		    --        63~56  55~48 47~40 39~32   31~24  23~16 15~8  7~0
		
			if crc_data = msg.dat(63 downto 56) then
									
		      -- Decode msg from the joystick
		      torque <= msg.dat(37 downto 24);
		      enable <= msg.dat(39);
			  
			else
			  enable <= '0';
			end if;
			
		  elsif msg.id = b"00111111001" then   -- 0x1F9   HUD msg			
		    -- can frame_id 0x1F9
		    -- # steer offset 9000 0x2328
		    -- #       crc   counter     en torq              HUD
		    -- #       0      1     2     3        4     5     6     7
		    -- dat = [ 0xeb, 0xff, 0xff, 0x23,    0x28, 0x00, 0x00, 0x00 ]
		    --        63~56  55~48 47~40 39~32   31~24  23~16 15~8  7~0

			if crc_data = msg.dat(63 downto 56) then
									
		      -- Decode msg from the joystick
		      sign <= relay_ctrl & msg.dat(15 downto 8); 
		      enable <= msg.dat(39);
			  
			else
			  enable <= '0';
			end if;
			
            -- check can health 
            if prev_counter = msg.dat(55 downto 48) then
		      can_received <= '0';
		    else
		      can_received <= '1';
              prev_counter := msg.dat(55 downto 48);
            end if;	
			
          else	
		    --radar data
            --enable <= '0';
          end if;		  
		  
		else
		  can_received <= '0';
		end if;
    end if;
  end process;

end architecture syn;
