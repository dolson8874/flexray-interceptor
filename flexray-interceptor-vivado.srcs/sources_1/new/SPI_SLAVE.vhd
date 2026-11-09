--------------------------------------------------------------------------------
-- PROJECT: SPI MASTER AND SLAVE FOR FPGA
--------------------------------------------------------------------------------
-- AUTHORS: Jakub Cabal <jakubcabal@gmail.com>
-- LICENSE: The MIT License, please read LICENSE file
-- WEBSITE: https://github.com/jakubcabal/spi-fpga
--------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

-- THE SPI SLAVE MODULE SUPPORT ONLY SPI MODE 0 (CPOL=0, CPHA=0)!!!

entity SPI_SLAVE is
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
end entity;

architecture RTL of SPI_SLAVE is
    constant BIT_CNT_WIDTH : natural := natural(ceil(log2(real(WORD_SIZE))));
    signal sclk_meta, cs_n_meta, mosi_meta : std_ulogic;
    signal sclk_reg, cs_n_reg, mosi_reg : std_ulogic;
    signal spi_clk_reg : std_ulogic := '0';
    signal spi_clk_redge_en, spi_clk_fedge_en : std_ulogic;
    signal bit_cnt : unsigned(BIT_CNT_WIDTH-1 downto 0) := (others => '0');
    signal rx_shift : std_ulogic_vector(WORD_SIZE-1 downto 0) := (others => '0');
    signal tx_shift, tx_word : std_ulogic_vector(WORD_SIZE-1 downto 0) := (others => '0');
    signal tx_valid, active_valid, completed : std_ulogic := '0';
    signal complete_word, slave_ready : std_ulogic;
    attribute ASYNC_REG : string;
    attribute SHREG_EXTRACT : string;
    attribute IOB : string;
    attribute IOB of MISO : signal is "TRUE";
    attribute ASYNC_REG of sclk_meta, sclk_reg, cs_n_meta, cs_n_reg,
        mosi_meta, mosi_reg : signal is "TRUE";
    attribute SHREG_EXTRACT of sclk_meta, sclk_reg, cs_n_meta, cs_n_reg,
        mosi_meta, mosi_reg : signal is "NO";
begin
    assert WORD_SIZE >= 2 and 2**BIT_CNT_WIDTH = WORD_SIZE
        report "SPI WORD_SIZE must be a power of two and at least two" severity failure;

    sync_ffs_p : process(CLK)
    begin
        if rising_edge(CLK) then
            sclk_meta <= SCLK; cs_n_meta <= CS_N; mosi_meta <= MOSI;
            sclk_reg <= sclk_meta; cs_n_reg <= cs_n_meta; mosi_reg <= mosi_meta;
        end if;
    end process;
    spi_clk_reg_p : process(CLK)
    begin
        if rising_edge(CLK) then
            if RST='1' then spi_clk_reg <= '0';
            else spi_clk_reg <= sclk_reg; end if;
        end if;
    end process;
    spi_clk_redge_en <= sclk_reg and not spi_clk_reg;
    spi_clk_fedge_en <= not sclk_reg and spi_clk_reg;

    -- A mode-0 byte is complete at its final rising edge. Its following
    -- falling edge may coincide with CS release, or not occur before CS.
    complete_word <= '1' when spi_clk_redge_en='1' and cs_n_reg='0' and
        bit_cnt=WORD_SIZE-1 and RST='0' else '0';
    -- Keep a prefetched word until that word, rather than filler, completes.
    -- Data arriving during a filler byte remains pending for the next byte.
    slave_ready <= (not tx_valid or (complete_word and active_valid)) and not RST;
    DIN_RDY <= slave_ready;

    transfer_p : process(CLK)
        variable next_valid : std_ulogic;
        variable next_word : std_ulogic_vector(WORD_SIZE-1 downto 0);
    begin
        if rising_edge(CLK) then
            DOUT_VLD <= '0';
            if RST='1' then
                bit_cnt <= (others => '0'); rx_shift <= (others => '0');
                tx_shift <= (others => '0'); tx_word <= (others => '0');
                tx_valid <= '0'; active_valid <= '0'; completed <= '0';
                DOUT <= (others => '0'); MISO <= '0';
            else
                next_valid := tx_valid; next_word := tx_word;
                if complete_word='1' and active_valid='1' then next_valid := '0'; end if;
                if slave_ready='1' and DIN_VLD='1' then
                    next_word := DIN; next_valid := '1';
                end if;
                tx_word <= next_word; tx_valid <= next_valid;

                if cs_n_reg='1' then
                    bit_cnt <= (others => '0'); rx_shift <= (others => '0'); completed <= '0';
                    -- Partial bytes replay the retained word. Completed bytes
                    -- already released it; do not replay a word received by the master.
                    active_valid <= next_valid;
                    if next_valid='1' then tx_shift <= next_word; MISO <= next_word(WORD_SIZE-1);
                    else tx_shift <= (others => '0'); MISO <= '0'; end if;
                else
                    if spi_clk_redge_en='1' then
                        rx_shift <= rx_shift(WORD_SIZE-2 downto 0) & mosi_reg;
                        if complete_word='1' then
                            DOUT <= rx_shift(WORD_SIZE-2 downto 0) & mosi_reg;
                            DOUT_VLD <= '1'; bit_cnt <= (others => '0'); completed <= '1';
                        else bit_cnt <= bit_cnt+1; end if;
                    end if;
                    if spi_clk_fedge_en='1' then
                        if completed='1' then
                            completed <= '0'; active_valid <= next_valid;
                            if next_valid='1' then tx_shift <= next_word; MISO <= next_word(WORD_SIZE-1);
                            else tx_shift <= (others => '0'); MISO <= '0'; end if;
                        else
                            tx_shift <= tx_shift(WORD_SIZE-2 downto 0) & '0';
                            MISO <= tx_shift(WORD_SIZE-2);
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;
end architecture;
