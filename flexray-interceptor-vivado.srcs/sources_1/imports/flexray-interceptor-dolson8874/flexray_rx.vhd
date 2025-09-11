library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.flexray;

entity flexray_rx is
  port (
    clk   : in  std_ulogic;
    rst   : in  std_ulogic;
    rx    : in  std_ulogic;
    msg   : out work.flexray.message;
    ready : out std_ulogic
  );
end entity;



architecture rtl of flexray_rx is

  type state_type is (IDLE, TSS, FSS, HEADER, PAYLOAD, CRC, DONE, SKIP);
  signal state : state_type := IDLE;

  signal tick_counter     : integer range 0 to 7 := 0;
  signal rx_prev          : std_ulogic := '1';

  signal bit_counter      : integer range 0 to 2047 := 0;  -- includes BSS
  signal data_bit_index   : integer range 0 to 2047 := 0;  -- valid bits only
  signal num_bits         : integer range 0 to 2047 := 0;

  signal tmp_msg          : work.flexray.message;
  signal computed_crc     : std_ulogic_vector(23 downto 0) := b"111111101101110010111010";
  signal computed_hdr_crc : std_ulogic_vector(10 downto 0) := b"00000011010";

  signal idle_counter     : integer range 0 to 21 := 0;

begin
  
  -- Tick counter and RX sampling
  mgmt_tick : process(clk,rst)
  variable result_cmp 	: boolean;
  begin
    if rst = '1' then
	  result_cmp := false;
	  
    elsif rising_edge(clk) then
      rx_prev <= rx;

      result_cmp := (tick_counter = 7) or                              -- Update tick counter
	                (rx = '0' and rx_prev = '1' and state = IDLE) or   -- Sync on first falling edge TSS
	                (rx = '1' and rx_prev = '0' and state = TSS);      -- Sync on Frame Start Sequence
					
	  
      if  result_cmp = true then
        tick_counter <= 0;
      else
        tick_counter <= tick_counter + 1;
      end if;

    end if;
  end process;



  fsm_state : process(clk, rst)
  variable var_state : state_type;
  variable rx_sample : std_ulogic;
  begin
    if rst = '1' then
      state <= IDLE;
	  var_state := IDLE;
      ready <= '0';
      bit_counter <= 0;
      data_bit_index <= 0;
	  idle_counter <= 0;

      tmp_msg.flags          <= (others => '0');
      tmp_msg.frame_id       <= (others => '0');
      tmp_msg.payload_length <= (others => '0');
      tmp_msg.header_crc     <= (others => '0');
      tmp_msg.cycle_count    <= (others => '0');
      tmp_msg.data           <= (others => (others => '0'));
      tmp_msg.crc            <= (others => '0');

      computed_crc     <= b"111111101101110010111010";
      computed_hdr_crc <= b"00000011010";

    elsif rising_edge(clk) then
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
	    bit_counter <= bit_counter + 1;
	  
	    if var_state > FSS and var_state <= CRC then
	      if (bit_counter mod 10) < 2 then
  	        var_state := SKIP;
	      end if;
        end if;
	  
  	    if var_state /= SKIP then 
		  data_bit_index <= data_bit_index + 1;
		end if;
	    
	  else 
	    var_state := SKIP;
	  end if;
	  
      case var_state is
	    when SKIP =>
		  null;

        when IDLE =>
          if rx_sample = '0' then
            state <= TSS;
			ready <= '0';
			idle_counter <= 0;
		  else
		    bit_counter <= 0;
			data_bit_index <= 0;
          end if;

        when TSS =>
          if rx_sample = '1' then
            state <= HEADER;
            bit_counter <= 0;
            data_bit_index <= 0;

            tmp_msg.flags          <= (others => '0');
            tmp_msg.frame_id       <= (others => '0');
            tmp_msg.payload_length <= (others => '0');
            tmp_msg.header_crc     <= (others => '0');
            tmp_msg.cycle_count    <= (others => '0');
            tmp_msg.data           <= (others => (others => '0'));
            tmp_msg.crc            <= (others => '0');

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
               tmp_msg.flags(tmp_msg.flags'left - data_bit_index) <= rx_sample;
             when 5 to 15 =>
               tmp_msg.frame_id(tmp_msg.frame_id'left - (data_bit_index - 5)) <= rx_sample;
             when 16 to 22 =>
               tmp_msg.payload_length(tmp_msg.payload_length'left - (data_bit_index - 16)) <= rx_sample;
             when 23 to 33 =>
               tmp_msg.header_crc(tmp_msg.header_crc'left - (data_bit_index - 23)) <= rx_sample;
             when 34 to 39 =>
               tmp_msg.cycle_count(tmp_msg.cycle_count'left - (data_bit_index - 34)) <= rx_sample;
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
             num_bits <= to_integer(unsigned(tmp_msg.payload_length)) * 16;
             data_bit_index <= 0;
             state <= PAYLOAD;
           end if;

        when PAYLOAD =>
           if data_bit_index < num_bits then
             tmp_msg.data(data_bit_index / 8)(7 - (data_bit_index mod 8)) <= rx_sample;

             --CRC 누적
             if (rx_sample xor computed_crc(23)) = '1' then
               computed_crc <= (computed_crc(22 downto 0) & '0') xor b"010111010110110111001011";
             else
               computed_crc <= (computed_crc(22 downto 0) & '0');
             end if;
		   else
		     state <= CRC;
			 data_bit_index <= 1;
			 tmp_msg.crc(tmp_msg.crc'left) <= rx_sample;
           end if;

        when CRC =>
           tmp_msg.crc(tmp_msg.crc'left - data_bit_index) <= rx_sample;
           if data_bit_index = 23 then
             state <= DONE;
			 data_bit_index <= 0;
           end if;
		   
        when DONE =>
          if computed_crc = tmp_msg.crc and tmp_msg.header_crc = computed_hdr_crc then
            ready <= '1';
            msg <= tmp_msg;
          end if;
		  
		  -- wait FES
		  if data_bit_index >= 2 then
            state <= IDLE;
			idle_counter <= 20;
	      end if;
		  
        when others =>
          state <= IDLE;

      end case;
	  
    end if;
  end process;


end architecture;
