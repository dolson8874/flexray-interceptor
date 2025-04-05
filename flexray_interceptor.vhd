library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_unsigned.all;
use work.flexray;


entity flexray_interceptor is
  port (
    clk : in std_ulogic;                -- Clock 8x higher than can bitrate
    rst : in std_ulogic;

    rx_0    : in  std_ulogic;
    tx_0    : out std_ulogic;
    tx_en_0 : out std_ulogic;

    rx_1    : in  std_ulogic;
    tx_1    : out std_ulogic;
    tx_en_1 : out std_ulogic;
    
    rx       : out std_ulogic; 				
    tx       : in  std_ulogic;
    override : in  std_ulogic;
	
	 
	 -- send fastserial
	tx_busy  : in std_ulogic;			-- fastserial_tx in writing
	send_log : out std_ulogic_vector(7 downto 0);
	ready    : out std_ulogic
	);
end entity flexray_interceptor;


architecture syn of flexray_interceptor is

  component flexray_rx is
  port (
    clk   : in  std_ulogic;             -- Clock 8x higher than can bitrate
    rst   : in  std_ulogic;
    rx    : in  std_ulogic;
    msg   : out work.flexray.message;
    ready : out std_ulogic);
  end component flexray_rx;


  component flexray_log is
  port (
    i_clk   	: in std_ulogic;             			-- Clock 80Mhz
    i_rst   	: in std_ulogic;
	i_ready 	: in std_ulogic;						-- update msg
	i_busy		: in std_ulogic;						-- fastserial_tx busy
	i_bus		: in std_ulogic;						-- from_psmc = '0' , from dadc = '1'
    i_msg  		: in work.flexray.message;				-- flexray message
	o_tx_byte	: out std_ulogic_vector (7 downto 0);	-- fastserial_tx data
	o_tx_ready  : out std_ulogic;						-- fastserial tx ready 
    o_busy 		: out std_ulogic);
  end component flexray_log;  
  
  
  signal s_tx_0 : std_ulogic;
  signal s_tx_1 : std_ulogic;

  signal tx_0_delayed : std_ulogic_vector(7 downto 0);
  signal tx_1_delayed : std_ulogic_vector(7 downto 0);
  
  -- for flexray_rx
  -- signal msg_psmc : work.flexray.message;
  signal msg_dadc : work.flexray.message;
  -- signal ready_psmc : std_ulogic;
  signal ready_dadc : std_ulogic;
  
  -- for flexray_log module
  signal log_ready : std_ulogic;
  signal log_busy : std_ulogic;
  signal log_bus : std_ulogic;
  -- signal log_msg :  work.flexray.message;
  
  -- for fastserial_tx
  signal tx_byte : std_ulogic_vector(7 downto 0);
  signal tx_ready : std_ulogic;  
  
  
	
begin
  -- for log 
  -- rx_psmc : flexray_rx port map (clk => clk, rst => rst, rx => rx_0, msg => msg_psmc, ready => ready_psmc);
  -- ready_psmc <= '0';
  -- rx_psmc : flexray_rx port map (clk => clk, rst => rst, rx => rx_0, msg => msg_dadc, ready => ready_dadc);
  -- rx_dadc : flexray_rx port map (clk => clk, rst => rst, rx => rx_1, msg => msg_dadc, ready => ready_dadc);
  
  rx_dadc : flexray_rx port map (clk => clk, rst => rst, rx => s_tx_0, msg => msg_dadc, ready => ready_dadc);
  tx_log  : flexray_log port map(i_clk => clk, i_rst => rst, i_ready => log_ready, i_busy => tx_busy, 
                              i_bus => log_bus, i_msg => msg_dadc, 
                              o_tx_byte => tx_byte, o_tx_ready=> tx_ready, o_busy => log_busy);
								 
	
  tx_0 <= s_tx_0;
  tx_1 <= s_tx_1;
  
  -- flexray_log -> fastserial_tx
  send_log <= tx_byte;
  ready <= tx_ready;
  
  
  flexray_rx_log : process (clk, rst)
  -- flexray_rx_log : process (rst, ready_dadc, log_busy)
  
  variable ready_prev : std_ulogic;
  variable tmpid : integer;
  begin
	if rst = '1' then
		log_ready <= '0';
		ready_prev := '0';
		
	elsif rising_edge(clk) then
	-- else	
		if log_busy = '0' then
			if log_ready = '0' then
				-- and to_integer(unsigned(msg_dadc.frame_id)) >=  16#2000#
				-- if ready_dadc = '1' and ready_prev = '0'  then
				if ready_dadc = '1' and ready_prev = '0'  then
                    
				    case msg_dadc.frame_id is
					  when b"00000011111" | b"00000110001" =>
						log_bus <= '1';
						log_ready <= '1';
                      when others =>
                        log_bus <= '1';
                        log_ready <=  '1';
                     end case;  
				else
					log_ready <= '0';
				end if;
				
			else
				null;
			end if;
			
		else
			if log_ready = '1'  then
				log_ready <= '0';
			else
				null;
			end if;
		end if;
		
		ready_prev := ready_dadc;
		
	end if;
  
  end process;
  
  

  manage_enables : process(clk, rst)
    variable bus_0_idle_counter : integer range 0 to 80;
    variable bus_1_idle_counter : integer range 0 to 80;
  begin
    if rst = '1' then
      tx_en_0 <= '0';
      tx_en_1 <= '0';

      bus_0_idle_counter := 80;
      bus_1_idle_counter := 80;
    elsif rising_edge(clk) then
      if s_tx_0 = '0' then
        bus_0_idle_counter := 0;
        tx_en_0            <= '0';
      else
        if bus_0_idle_counter < 80 then
          bus_0_idle_counter := bus_0_idle_counter + 1;
          tx_en_0            <= '0';
        else
          tx_en_0 <= '1';
        end if;
      end if;

      if s_tx_1 = '0' then
        bus_1_idle_counter := 0;
        tx_en_1            <= '0';
      else
        if bus_1_idle_counter < 80 then
          bus_1_idle_counter := bus_1_idle_counter + 1;
          tx_en_1            <= '0';
        else
          tx_en_1 <= '1';
        end if;
      end if;

    end if;

  end process;

  

  intercept : process (clk, rst)
  begin
    if rst = '1' then
      rx   <= '1';

      tx_0_delayed <= (others => '0');
      tx_1_delayed <= (others => '0');


    elsif rising_edge(clk) then
      tx_0_delayed <= tx_0_delayed(6 downto 0) & s_tx_0;
      tx_1_delayed <= tx_1_delayed(6 downto 0) & s_tx_1;

      rx <= rx_1;
			
      if override = '1' then
        s_tx_0 <= tx;
      else
        if rx_1 = '0' and tx_1_delayed = b"11111111" then
          s_tx_0 <= '0';
        else
          s_tx_0 <= '1';
        end if;
      end if;

      if rx_0 = '0' and tx_0_delayed = b"11111111" then
        s_tx_1 <= '0';
      else
        s_tx_1 <= '1';
      end if;
      
    end if;
  end process;
  
  
end architecture syn;
