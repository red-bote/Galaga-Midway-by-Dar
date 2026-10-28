---------------------------------------------------------------------------------
-- Galaga sound machine by Dar (darfpga@aol.fr)
-- http://darfpga.blogspot.fr
---------------------------------------------------------------------------------
-- 3 voices frequency/waveform synthetizer
--
-- Original hardware done with only one 4 bits sequential adder to realise
-- one 20 bits adder and two 16 bits adder.
--
-- Too nice and clever to be done another way, just doing it the same way!
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity sound_machine is
port(
  clk_core     : in std_logic; -- 36.864 MHz
  ce18         : in std_logic; -- 18.432 MHz clock enable
  hcnt         : in std_logic_vector(5 downto 0);
  ena          : in std_logic;
  cpu_addr     : in std_logic_vector(3 downto 0);
  cpu_do       : in std_logic_vector(3 downto 0);
  ram_0_we     : in std_logic;
  ram_1_we     : in std_logic;
  audio        : out std_logic_vector(9 downto 0)
);
end sound_machine;

architecture struct of sound_machine is

  signal ce18n : std_logic;
  signal snd_seq_addr_h     : std_logic_vector(7 downto 0);
  signal snd_seq_addr_rom   : std_logic_vector(7 downto 0);
  signal snd_samples_addr_h   : std_logic_vector(7 downto 0);
  signal snd_samples_addr_rom : std_logic_vector(7 downto 0);
  signal snd_ram_addr : std_logic_vector(3 downto 0);
  signal snd_ram_di   : std_logic_vector(3 downto 0);
  signal snd_ram_0_we : std_logic;
  signal snd_ram_1_we : std_logic;
  signal snd_ram_0_do : std_logic_vector(3 downto 0);
  signal snd_ram_1_do : std_logic_vector(3 downto 0);

  signal snd_seq_addr : std_logic_vector(7 downto 0);
  signal snd_seq_do   : std_logic_vector(7 downto 0);

  signal snd_samples_addr : std_logic_vector(7 downto 0);
  signal snd_samples_do   : std_logic_vector(7 downto 0);

  signal sum      : std_logic_vector(4 downto 0) := (others => '0');
  signal sum_r    : std_logic_vector(4 downto 0) := (others => '0');
  signal sum_3_rr : std_logic := '0';

  signal samples_ch0 : std_logic_vector(3 downto 0);
  signal samples_ch1 : std_logic_vector(3 downto 0);
  signal samples_ch2 : std_logic_vector(3 downto 0);
  signal volume_ch0  : std_logic_vector(3 downto 0);
  signal volume_ch1  : std_logic_vector(3 downto 0);
  signal volume_ch2  : std_logic_vector(3 downto 0);

begin

  ce18n <= not ce18;

  snd_seq_addr <= '0' & not ram_0_we & hcnt(5 downto 0);

  snd_ram_addr <= cpu_addr when (ram_0_we = '1' or ram_1_we = '1') else hcnt(5 downto 2);
  snd_ram_di   <= cpu_do   when (ram_0_we = '1' or ram_1_we = '1') else sum_r(3 downto 0);

  snd_ram_0_we <= (not snd_seq_do(1) and ena) or ram_0_we ;
  snd_ram_1_we <= ram_1_we;

  sum <= ('0' & snd_ram_0_do) + ('0' & snd_ram_1_do) + ("0000" & sum_r(4));

  process (clk_core)
  begin
    if rising_edge(clk_core) and ce18 = '1' and ena = '1' then
      if snd_seq_do(3) = '0' then
        sum_r <= (others => '0');
        sum_3_rr <= '0';
      elsif snd_seq_do(0) = '0' then
        sum_r <= sum;
        sum_3_rr <= sum_r(3);
      end if ;

      snd_samples_addr <= snd_ram_0_do(2 downto 0) & sum_r(3 downto 0) & sum_3_rr;

      if snd_seq_do(2) = '0' then
        if hcnt(5 downto 2) = X"5" then
          samples_ch0 <= snd_samples_do(3 downto 0);
          volume_ch0  <= snd_ram_1_do;
        end if;
        if hcnt(5 downto 2) = X"A" then
          samples_ch1 <= snd_samples_do(3 downto 0);
          volume_ch1  <= snd_ram_1_do;
        end if;
        if hcnt(5 downto 2) = X"F" then
          samples_ch2 <= snd_samples_do(3 downto 0);
          volume_ch2  <= snd_ram_1_do;
        end if;
      end if;

      audio <= ("00" & samples_ch0) * volume_ch0 +
      ("00" & samples_ch1) * volume_ch1 +
      ("00" & samples_ch2) * volume_ch2;

    end if;
  end process;

  -- sound register RAM0
  sound_ram_0 : entity work.gen_ram
  generic map( dWidth => 4, aWidth => 4)
  port map(
    clk  => clk_core,
    ce   => ce18n,
    we   => snd_ram_0_we,
    addr => snd_ram_addr,
    d    => snd_ram_di,
    q    => snd_ram_0_do
  );

  -- sound register RAM1
  sound_ram_1 : entity work.gen_ram
  generic map( dWidth => 4, aWidth => 4)
  port map(
    clk  => clk_core,
    ce   => ce18n,
    we   => snd_ram_1_we,
    addr => snd_ram_addr,
    d    => snd_ram_di,
    q    => snd_ram_1_do
  );

  -- ROM address hold: the ROMs sample every clk_core edge; between enabled edges they
  -- read the held address, so their output changes only on a ce18n enable.
  process (clk_core)
  begin
    if rising_edge(clk_core) and ce18n = '1' then
      snd_samples_addr_h <= snd_samples_addr;
      snd_seq_addr_h     <= snd_seq_addr;
    end if;
  end process;
  snd_samples_addr_rom <= snd_samples_addr when ce18n = '1' else snd_samples_addr_h;
  snd_seq_addr_rom     <= snd_seq_addr     when ce18n = '1' else snd_seq_addr_h;

  -- sound samples ROM
  sound_samples : entity work.sound_samples
  port map(
    clk  => clk_core,
    addr => snd_samples_addr_rom,
    data => snd_samples_do
  );

  -- sound compute sequencer ROM
  sound_seq : entity work.sound_seq
  port map(
    clk  => clk_core,
    addr => snd_seq_addr_rom,
    data => snd_seq_do
  );

end struct;
