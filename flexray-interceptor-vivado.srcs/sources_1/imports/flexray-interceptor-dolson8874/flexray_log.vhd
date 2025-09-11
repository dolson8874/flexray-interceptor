library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.flexray;

--
-- fastserial message format
-- SOF 0xCA
-- struct __attribute__((packed)) ftdi_header {
-- uint8_t reserved : 1;
-- uint8_t 	bus : 3;
-- uint8_t 	rejected : 1;
-- uint8_t 	returned : 1;
-- uint8_t 	extended : 1;
-- uint8_t 	unused : 1;
-- uint8_t  flags     : 5;
-- uint16_t frame_id  : 11;
-- uint8_t  length    : 7;
-- uint16_t header_crc: 11;
-- uint8_t  counter   : 6;
-- };
-- add flag  		8 bit for cabana
-- add counter 		8 bit for cabana
-- data 			length
-- CRC 				24 bit

entity flexray_log is
  port (
    i_clk      : in std_ulogic; -- Clock 80Mhz
    i_rst      : in std_ulogic;
    i_ready    : in std_ulogic; -- update msg
    i_busy     : in std_ulogic; -- fastserial_tx busy
    i_bus      : in std_ulogic; -- from_psmc = '0' , from dadc = '1'
    i_msg      : in work.flexray.message; -- flexray message
    o_tx_byte  : out std_ulogic_vector (7 downto 0); -- fastserial_tx data
    o_tx_ready : out std_ulogic; -- fastserial tx ready 
    o_busy     : out std_ulogic); -- in_writing msg this module
end entity flexray_log;
architecture syn of flexray_log is

  type FS_STATE is (FS_IDLE,
    FS_START,
    FS_BUS,
    FS_ADDRH,
    FS_ADDRL,
    FS_LEN,
    FS_CRC,
    FS_COUNTER,
    FS_FLAGS,
    FS_COUNTERX,
    FS_PAYLOAD,
    FS_DONE);

  signal next_state : FS_STATE;

  signal tx_byte   : std_ulogic_vector (7 downto 0);
  signal tx_ready  : std_ulogic;
  signal this_busy : std_ulogic;

  signal send_byte : std_ulogic_vector (7 downto 0);
  signal send_idx  : integer range 0 to 266; -- 6+254+3
  signal send_len  : integer range 0 to 266;
begin

  o_tx_byte  <= tx_byte;
  o_tx_ready <= tx_ready;
  o_busy     <= this_busy;

  send_one : process (i_clk, i_rst)

  begin

    if i_rst = '1' then
      tx_byte  <= (others => '0');
      tx_ready <= '0';

    elsif rising_edge(i_clk) then

      case next_state is
        when FS_IDLE | FS_START =>
          tx_ready <= '0';

        when others =>
          -- check fastserial_tx
          if i_busy = '0' then

            if tx_ready = '0' then
              tx_byte  <= send_byte;
              tx_ready <= '1';
            else
              tx_ready <= '0';
            end if;

          else
            if tx_ready = '1' then
              tx_ready <= '0';
            end if;
          end if;

      end case;

    end if;

  end process;

  send_msgs : process (i_clk, i_rst)

    variable len    : integer range 0 to 254;
    variable busnum : std_ulogic_vector (2 downto 0);

    variable send_msg  : work.flexray.message;
    variable send_char : std_ulogic_vector (7 downto 0);
    variable idx       : integer range 0 to 266;

  begin
    if i_rst = '1' then
      send_len <= 0;
      send_idx <= 0;
      idx := 0;

      this_busy <= '1';
      send_char               := (others => '0');
      busnum                  := b"001";
      send_msg.flags          := (others => '0');
      send_msg.frame_id       := (others => '0');
      send_msg.payload_length := (others => '0');
      send_msg.header_crc     := (others => '0');
      send_msg.cycle_count    := (others => '0');
      send_msg.data           := (others => (others => '0'));
      send_msg.crc            := (others => '0');

    elsif rising_edge(i_clk) then

      if i_busy = '0' and tx_ready = '0' then

        case next_state is
          when FS_IDLE =>
            if i_ready = '1' then

              send_msg := i_msg;
              this_busy <= '1';

              if i_bus = '0' then
                busnum := b"000";
              else
                busnum := b"010";
              end if;

            else
              this_busy <= '0';
              idx := 0;
            end if;

          when FS_START =>
            idx := 0;
            send_len <= to_integer(unsigned(send_msg.payload_length)) * 2;

            -- send SOF 
            send_char := x"CA";

          when FS_BUS =>
            -- 0xa0
            idx       := 0;
            send_char := '1' & busnum(2 downto 0) & b"0000";

          when FS_ADDRH =>
            -- 0x00
            send_char := send_msg.flags(4 downto 0) & send_msg.frame_id(10 downto 8);

          when FS_ADDRL =>
            -- 0x03
            send_char := send_msg.frame_id(7 downto 0);
            
          when FS_LEN =>
            -- 00011010 0x1a
            send_char := send_msg.payload_length (6 downto 0) & send_msg.header_crc(10);

          when FS_CRC =>
            -- 11110001	0xf1
            send_char := send_msg.header_crc(9 downto 2);

          when FS_COUNTER =>
            send_char := send_msg.header_crc(1 downto 0) & send_msg.cycle_count(5 downto 0);

            -- include data (for cabana)
          when FS_FLAGS => -- 6
            -- 110101 0x35
            send_char := b"000" & send_msg.flags(4 downto 0);

          when FS_COUNTERX => -- 7
            -- 0x00
            send_char := b"00" & send_msg.cycle_count (5 downto 0);

          when FS_PAYLOAD => -- 8
            -- flexray payload data
            if idx >= 8 and idx < 8 + send_len then
              send_char := std_ulogic_vector(send_msg.data(idx - 8));

              -- flexray crc
            elsif idx = 8 + send_len then
              send_char := send_msg.crc(23 downto 16);

            elsif idx = 9 + send_len then
              send_char := send_msg.crc(15 downto 8);

            elsif idx = 10 + send_len then
              send_char := send_msg.crc(7 downto 0);

            else
              send_char := std_ulogic_vector(to_unsigned(idx, 8));
              --send_char := x"B1";

            end if;

          when FS_DONE =>
            send_len <= 0;
            idx       := 0;
            send_char := (others => '0');
            busnum    := b"010";

            this_busy <= '0';

        end case;

        if next_state /= FS_IDLE then
          send_byte <= send_char;
          idx := idx + 1;
          send_idx <= idx;
        end if;

      end if;

    end if;

  end process;

  manage_state : process (i_clk, i_rst)
  begin
    if i_rst = '1' then
      next_state <= FS_IDLE;

    elsif rising_edge(i_clk) then

      if i_busy = '0' and tx_ready = '0' then

        case next_state is
          when FS_IDLE =>
            if i_ready = '1' then
              next_state <= FS_START;
            end if;

          when FS_START =>
            next_state <= FS_BUS;

          when FS_BUS =>
            next_state <= FS_ADDRH;

          when FS_ADDRH => -- 1		
            next_state <= FS_ADDRL;

          when FS_ADDRL => -- 2
            next_state <= FS_LEN;

          when FS_LEN => -- 3	
            next_state <= FS_CRC;

          when FS_CRC => -- 4
            next_state <= FS_COUNTER;

          when FS_COUNTER => -- 5
            next_state <= FS_FLAGS;

            -- include data (for cabana)
          when FS_FLAGS => -- 6
            next_state <= FS_COUNTERX;

          when FS_COUNTERX => -- 7
            next_state <= FS_PAYLOAD;

          when FS_PAYLOAD => -- 8
            if send_idx = 11 + send_len then
              next_state <= FS_DONE;
            else
              next_state <= FS_PAYLOAD;
            end if;

          when FS_DONE =>
            next_state <= FS_IDLE;

        end case;
      end if; -- tx_ready 

    end if;

  end process;

end architecture syn;