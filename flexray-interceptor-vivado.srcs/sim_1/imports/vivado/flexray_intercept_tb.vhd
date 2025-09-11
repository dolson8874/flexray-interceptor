library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity flexray_intercept_tb is
end flexray_intercept_tb;

architecture tb of flexray_intercept_tb is
  component flexray_interceptor is
    port (
      clk      : in  std_ulogic;
      rst      : in  std_ulogic;
      rx_0     : in  std_ulogic;
      tx_0     : out std_ulogic;
      tx_en_0  : out std_ulogic;
      rx_1     : in  std_ulogic;
      tx_1     : out std_ulogic;
      tx_en_1  : out std_ulogic;
      rx       : out std_ulogic;
      tx       : in  std_ulogic;
      override : in  std_ulogic;
      
      -- send fastserial
      tx_busy  : in std_ulogic;			-- fastserial_tx in writing
      send_log : out std_ulogic_vector(7 downto 0);
      ready    : out std_ulogic      
      );
      
  end component flexray_interceptor;

  component flexray_syn_packet is
    port (
      clk : in  std_ulogic;
      rst : in  std_ulogic;
      o   : out std_ulogic);
  end component flexray_syn_packet;

  component flexray_torque_intercept is
    port (
      clk           : in  std_ulogic;     -- Clock 8x higher than can bitrate
      rst           : in  std_ulogic;
      rx            : in  std_ulogic;
      torque        : in  std_ulogic_vector(13 downto 0);
      sign          : in  std_ulogic_vector(8 downto 0);
      enable        : in  std_ulogic;
        
      tx            : out std_ulogic;
      override      : out std_ulogic;
      sync_debug     : out std_ulogic);
  end component flexray_torque_intercept;

  component SPI_SLAVE is
    Generic (
        WORD_SIZE : natural := 8 -- size of transfer word in bits, must be power of two
    );
    Port (
        CLK      : in  std_ulogic; -- system clock
        RST      : in  std_ulogic; -- high active synchronous reset
        -- SPI SLAVE INTERFACE
        SCLK     : in  std_ulogic; -- SPI clock
        CS_N     : in  std_ulogic; -- SPI chip select, active in low
        MOSI     : in  std_ulogic; -- SPI serial data from master to slave
        MISO     : out std_ulogic; -- SPI serial data from slave to master
        -- USER INTERFACE
        DIN      : in  std_ulogic_vector(WORD_SIZE-1 downto 0); -- data for transmission to SPI master
        DIN_VLD  : in  std_ulogic; -- when DIN_VLD = 1, data for transmission are valid
        DIN_RDY  : out std_ulogic; -- when DIN_RDY = 1, SPI slave is ready to accept valid data for transmission
        DOUT     : out std_ulogic_vector(WORD_SIZE-1 downto 0); -- received data from SPI master
        DOUT_VLD : out std_ulogic  -- when DOUT_VLD = 1, received data are valid
    );
  end component;



  component flexray_generator is
    port (channel_0 : out std_ulogic);
  end component flexray_generator;


  function to_bv(slv : std_ulogic_vector) return bit_vector is
    variable bv : bit_vector(slv'range);
  begin
    for i in slv'range loop
      if slv(i) = '1' then
        bv(i) := '1';
      else
        bv(i) := '0';
      end if;
    end loop;
    return bv;
  end;


  constant tb_clk_period : time       := 12.5 ns;  -- 8x bitrate 80 Mhz
  signal tb_clk          : std_ulogic := '0';

  signal rst : std_ulogic := '1';

  signal channel_0 : std_ulogic;

  signal rx : std_ulogic;
  signal tx : std_ulogic;
  signal override : std_ulogic;

  signal rx_0    : std_ulogic;
  signal tx_0    : std_ulogic;
  signal tx_en_0 : std_ulogic;
  signal rx_1    : std_ulogic;
  signal tx_1    : std_ulogic;
  signal tx_en_1 : std_ulogic;

  signal torque   : std_ulogic_vector(13 downto 0);
  signal sign     : std_ulogic_vector(8 downto 0);
  signal enable   : std_ulogic;
  signal tx_busy  : std_ulogic := '0';
  signal send_log : std_ulogic_vector(7 downto 0);
  signal ready    : std_ulogic;
  signal sync_debug : std_ulogic;
  
  -- SPI_SLAVE
  signal tb_sclk : std_ulogic := '0';
  signal sdout : std_ulogic_vector(7 downto 0);
  signal svld : std_ulogic;
  signal smosi : std_ulogic;
  signal smiso : std_ulogic;
  signal spics : std_ulogic;


begin
  dut : flexray_interceptor port map(clk => tb_clk, rst => rst,
                                     rx_0  => rx_0, tx_0 => tx_0, tx_en_0 => tx_en_0,
                                     rx_1  => rx_1, tx_1 => tx_1, tx_en_1 => tx_en_1,
                                     rx => rx, tx => tx, override => override,
                                     tx_busy => tx_busy, send_log => send_log, ready => ready);
                                     
  la_dump : flexray_generator port map(channel_0 => channel_0);
  -- la_dump : flexray_syn_packet port map(clk => tb_clk, rst => rst, o => channel_0);

  intercept : flexray_torque_intercept port map(clk => tb_clk, rst => rst, rx => rx, 
                                                torque => torque, sign => sign, enable => enable,
                                                tx => tx, override => override, sync_debug=> sync_debug);

  spi_tx : SPI_SLAVE  port map(CLK => tb_clk, RST => rst, SCLK => tb_sclk, CS_N => spics, 
	                             MOSI => smosi, MISO => smiso, DIN => send_log, DIN_VLD => ready, 
								 DIN_RDY => tx_busy, DOUT => sdout, DOUT_VLD => svld);  

  rx_1 <= channel_0;
  rx_0 <= '1';
  torque <=  b"000011" & x"FF";
  enable <= '1';
  sign <= b"1" & x"00";
  
  --spics <= '0';
  
  
  spi_master_proc : process
    constant TOTAL_BYTES : integer := 512;
    constant BITS_PER_BYTE : integer := 8;
    variable read_buffer : std_ulogic_vector(8 * TOTAL_BYTES - 1 downto 0);
    variable bit_cnt     : integer := 0;
    variable byte_val : std_ulogic_vector(7 downto 0);		
    variable lineout : string(1 to TOTAL_BYTES*2+TOTAL_BYTES-1); -- "xx xx xx ..." 형식
    variable pos : integer := 1;
	
	begin
      -- 1. Idle 상태 대기
      spics <= '1';
      tb_sclk <= '0';
      smosi <= '0';
      wait for 200 ns;

      -- 2. CS_N low로 활성화
      spics <= '0';
      wait for 50 ns;

	  read_buffer := (others => '0');
      bit_cnt := 0;
	  
      for i in 0 to TOTAL_BYTES - 1 loop
      -- 한 바이트(8비트) 읽기
        for b in 7 downto 0 loop
          smosi <= '0';
          tb_sclk <= '0';
          wait for 50 ns;
          tb_sclk <= '1';
          wait for 50 ns;
          -- SCLK 상승에지에서 smiso를 읽음
		  byte_val(b) := smiso; 
          bit_cnt := bit_cnt + 1;
        end loop;
		
		report "SPI readByte [" & integer'image(i) & "]: " & to_hstring(to_bv(byte_val));
		
      end loop;

      -- 4. CS_N high로 비활성화
      spics <= '1';
      tb_sclk <= '0';
      smosi <= '0';
 
    end process;


 

  clock_proc : process
  begin
    -- Perform reset
    wait for tb_clk_period / 2;
    tb_clk <= '1';
    wait for tb_clk_period / 2;
    rst    <= '0';
    tb_clk <= '0';

    for i in 1 to 8 loop
      wait for tb_clk_period / 2;
      tb_clk <= not tb_clk;
      wait for tb_clk_period / 2;
      tb_clk <= not tb_clk;
    end loop;

    for i in 1 to 20 * 50 * 3 * 256 * 8 loop
      tb_clk <= not tb_clk;
      wait for tb_clk_period / 2;
      tb_clk <= not tb_clk;
      wait for tb_clk_period / 2;
    end loop;
    wait;
  end process;
end tb;
