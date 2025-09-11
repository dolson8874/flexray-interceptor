-- 
-- reference
-- https://www.hackster.io/MichalsTC/how-to-use-the-fast-serial-mode-on-a-ftdi-ft2232h-7f0682
--
-- FTDI fast serial tx  for FTDI
--
-- FSCLK - input into 
-- FSDI - Data In, TX input pin, default high 
-- FSCT - Clear to Send.  High if ready to send.
-- From Data Sheet: 4.8.2 
-- Notes :-
-- 4.8.2 Incoming Fast Serial Data
-- An external device is allowed to send data into the FT2232H if FSCTS is high. On receipt of a zero START
-- bit on FSDI, the FT2232H will drop FSCTS on the next positive clock edge. The data from bits 0 to 7 are
-- then clocked in (LSB first). The last bit (DEST) determines where the data will be written to. The data can
-- be sent to either channel A or to channel B. If DEST= ‘0’, the data is sent to channel A, (assuming
-- channel A is enabled for fast serial mode, otherwise the data is sent to channel B). If DEST= ‘1’ the data
-- is sent to channel B, (assuming channel B is enabled for fast serial mode, otherwise the data will go to
-- channel A. (Either channel A, channel B or both channels must be enabled as fast serial mode or the
-- function is disabled). This is illustrated in Figure 4.15.
--
-- 1. The first bit input (Start bit) is always 0.
-- 2. FSDI is always received LSB first.
-- 3. The last received serial bit is the destination bit (DEST).It indicates which channel the data should
--    go to. A ‘0’ means that it should go to channel A, a ‘1’ means that it should go to channel B.
-- 4. The target device should ensure that CTS is high before it sends data. CTS goes low after data bit
--    0 (D0) and stays low until the chip can accept more data.
--
--
--
-- Serial data stream:
--
-- Start Bit | DO | D1 | D2 | D3 | D4 | D5 | D6 | D7 | DEST |
--
-- Start Bit is low.  DEST is 1, for Port B .. 
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.flexray;

entity fastserial_tx is
  port (
	i_rst	: in std_ulogic;
	i_clk   : in std_ulogic;    
	i_fsclk : in std_ulogic;
	i_fscts : in std_ulogic;
	i_data  : in std_ulogic_vector(7 downto 0);
	i_write : in std_ulogic;

    
	o_busy : out std_ulogic;
	o_fsdi : out std_ulogic);
end entity fastserial_tx;



architecture syn of fastserial_tx is

  type STATE_TYPE is (START, 
						WAIT_FOR_FCTS_LOW, 
						WAIT_FOR_FCTS_HIGH,
  						BIT_ZERO, 
  						BIT_ONE, 
  						BIT_TWO, 
  						BIT_THREE, 
  						BIT_FOUR, 
  						BIT_FIVE, 
  						BIT_SIX, 
  						BIT_SEVEN, 
  						BIT_DEST, 
  						DONE, 
  						IDLE);
  signal busy : std_ulogic;
  signal fsdi : std_ulogic; 
  signal lcl_data : std_ulogic_vector (7 downto 0);
  signal state : STATE_TYPE;
  
begin

  o_busy <= busy; 
  o_fsdi <= fsdi;
  
  
  send_onebyte : process(i_clk, i_rst)
	
	variable q_fscts : std_ulogic;

  begin
	 
    if i_rst = '1' then
    	lcl_data <= b"11111111";
		q_fscts := '0';
		busy <= '0';
		fsdi <= '1';
		state <= IDLE;

    elsif rising_edge(i_clk) then

		q_fscts := i_fscts;

    	case state is
    		when IDLE => 
				fsdi <= '1';
					
				if i_write = '1' and q_fscts = '1' then
					busy <= '1';
					state <= START;
					lcl_data <= i_data;		
				else
					state <= IDLE;
				end if;
    		
    		when START => 
    		    if q_fscts = '1' and i_fsclk = '1' then
					-- send start bit 0
					fsdi <= '0';	
					state <= BIT_ZERO;
				end if;
    		      		
    		when WAIT_FOR_FCTS_LOW =>
						    
    			-- wait for FSCTS to drop then start sending data *
    			if q_fscts ='0' and i_fsclk = '1' then
					state <= BIT_TWO;
					fsdi <= lcl_data(0);
					lcl_data <= '1' & lcl_data(7 downto 1);
    			end if;
    	
    	   when BIT_DEST =>
    	  		if q_fscts = '0' and i_fsclk = '1' then
    	  			fsdi <= '1';
    	  			state <= WAIT_FOR_FCTS_HIGH;
    	  		end if;
			when WAIT_FOR_FCTS_HIGH =>
				if q_fscts = '1' then
					state <= DONE;
				end if;
						
    	   when DONE =>
    	  		if q_fscts = '1' and i_fsclk = '1' then
    	  			lcl_data <= b"11111111";
    	  			busy <= '0';
    	  			state <= IDLE; 
    	  		end if;
    	   when others =>
    	  		if state >= BIT_ZERO and state <= BIT_SEVEN then
					    
					-- wait for FSCTS to drop then start sending data
    	  			if i_fsclk = '1' then								
						case state is
							when BIT_ZERO => state <= WAIT_FOR_FCTS_LOW;
							when BIT_ONE  => state <= BIT_TWO;
							when BIT_TWO  => state <= BIT_THREE;
							when BIT_THREE  => state <= BIT_FOUR;
							when BIT_FOUR  => state <= BIT_FIVE;
							when BIT_FIVE  => state <= BIT_SIX;
							when BIT_SIX  => state <= BIT_SEVEN;
							when BIT_SEVEN  => state <= BIT_DEST;
								
							when others => state <= IDLE;
						end case;
									
    	  				fsdi <= lcl_data(0);
    	  				lcl_data <= '1' & lcl_data(7 downto 1);
								
    	  			end if;
    	  		end if;
    	end case;

    end if;
    

  end process;

end architecture;
