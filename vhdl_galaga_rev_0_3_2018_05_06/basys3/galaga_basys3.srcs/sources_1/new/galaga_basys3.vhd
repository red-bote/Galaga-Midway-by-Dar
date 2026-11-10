---------------------------------------------------------------------------------
-- Basys 3 top level for Galaga
-- Source: galaga_de10_lite.vhd by Dar (darfpga@aol.fr,
--   http://darfpga.blogspot.fr); see that file for its history.
---------------------------------------------------------------------------------
--
-- 10/26/2026: initial Basys 3 release by Red~Bote
--
---------------------------------------------------------------------------------
-- Educational use only
-- Do not redistribute synthesized file with roms
-- Do not redistribute roms whatever the form
-- Use at your own risk
---------------------------------------------------------------------------------
--
-- Main features:
--  Connections:
--   VGA monitor (15 kHz RGB monitor with sw13 up)
--   USB keyboard on the USB-HID host connector
--   Atari-type joystick on Pmod JA
--   PmodAMP2 with speaker on Pmod JXADC (pins 1-6)
--  Controls       keyboard       stick          button
--   left / right  arrows         left / right
--   fire          left ctrl      fire
--   coin          5, 6                          btnU, btnD
--   start1/2      1, 2                          btnL, btnR
--   reset                                       btnC
--  Switches: sw15 audio off, sw14 scanlines, sw13 15 kHz RGB, sw12 test mode
---------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;

entity galaga_basys3 is
port(
  clk  : in  std_logic;
  sw   : in  std_logic_vector(15 downto 0);
  btnC : in  std_logic;
  btnU : in  std_logic;  -- coin
  btnD : in  std_logic;  -- coin
  btnL : in  std_logic;  -- start1
  btnR : in  std_logic;  -- start2

  joy_n   : in  std_logic_vector(4 downto 0);  -- joystick
  ps2_dat : in  std_logic;
  ps2_clk : in  std_logic;

  O_PMODAMP2_AIN   : out std_logic;
  O_PMODAMP2_GAIN  : out std_logic;
  O_PMODAMP2_SHUTD : out std_logic;

  vga_r  : out std_logic_vector(3 downto 0);
  vga_g  : out std_logic_vector(3 downto 0);
  vga_b  : out std_logic_vector(3 downto 0);
  vga_hs : out std_logic;
  vga_vs : out std_logic
);
end galaga_basys3;

architecture struct of galaga_basys3 is

  signal clk_core    : std_logic;
  signal ce18        : std_logic := '0';
  signal ce_pix      : std_logic;
  signal ce_pix_d    : std_logic_vector(4 downto 0) := (others => '0');
  signal ce_x1       : std_logic;
  signal ce_x2       : std_logic;
  signal reset       : std_logic;
  signal mmcm_locked : std_logic;

  signal r      : std_logic_vector(2 downto 0);
  signal g      : std_logic_vector(2 downto 0);
  signal b      : std_logic_vector(1 downto 0);
  signal csync  : std_logic;
  signal blankn : std_logic;
  signal hsync  : std_logic;
  signal vsync  : std_logic;

  signal audio           : std_logic_vector(9 downto 0);
  signal pwm_accumulator : std_logic_vector(12 downto 0);

  signal vga_r_i : std_logic_vector(5 downto 0);
  signal vga_g_i : std_logic_vector(5 downto 0);
  signal vga_b_i : std_logic_vector(5 downto 0);
  signal vga_r_o : std_logic_vector(5 downto 0);
  signal vga_g_o : std_logic_vector(5 downto 0);
  signal vga_b_o : std_logic_vector(5 downto 0);
  signal hsync_o : std_logic;
  signal vsync_o : std_logic;

  signal kbd_intr     : std_logic;
  signal kbd_scancode : std_logic_vector(7 downto 0);
  signal kbd_rel      : std_logic := '0';
  signal kbd_joy      : std_logic_vector(7 downto 0) := (others => '0');
  signal joyPCFRLDU   : std_logic_vector(7 downto 0);

  component scandoubler
  port (
    clk_sys   : in  std_logic;
    scanlines : in  std_logic_vector (1 downto 0);
    ce_x1     : in  std_logic;
    ce_x2     : in  std_logic;
    hs_in     : in  std_logic;
    vs_in     : in  std_logic;
    r_in      : in  std_logic_vector (5 downto 0);
    g_in      : in  std_logic_vector (5 downto 0);
    b_in      : in  std_logic_vector (5 downto 0);
    hs_out    : out std_logic;
    vs_out    : out std_logic;
    r_out     : out std_logic_vector (5 downto 0);
    g_out     : out std_logic_vector (5 downto 0);
    b_out     : out std_logic_vector (5 downto 0)
  );
end component;

signal ps2_clk_meta, ps2_clk_s : std_logic := '1';
signal ps2_dat_meta, ps2_dat_s : std_logic := '1';
signal stick_meta, stick_s     : std_logic_vector(4 downto 0) := (others => '1');
signal btn_meta, btn_s         : std_logic_vector(3 downto 0) := (others => '0');  -- U, D, L, R
attribute ASYNC_REG : string;
attribute ASYNC_REG of ps2_clk_meta, ps2_clk_s, ps2_dat_meta, ps2_dat_s : signal is "TRUE";
attribute ASYNC_REG of stick_meta, stick_s, btn_meta, btn_s : signal is "TRUE";

signal db_in  : std_logic_vector(4 downto 0);
signal btn_db : std_logic_vector(4 downto 0) := (others => '0');
type btn_cnt_t is array (0 to 4) of unsigned(17 downto 0);
signal btn_cnt : btn_cnt_t := (others => (others => '0'));
-- b_test on sw12 (DE10 default '1' = off).
constant B_TEST_DEFAULT : std_logic := '1';
signal b_test_in        : std_logic;
signal scanlines_sel    : std_logic_vector(1 downto 0);
begin

-- DIP switch: b_test
b_test_in <= B_TEST_DEFAULT xor sw(12);  -- test/service mode on sw12

-- core reset: btnC or MMCM not locked
reset <= btnC or not mmcm_locked;

-- Clock 36.864 MHz (signal clk_core): the single clock of the core, scandoubler,
-- keyboard, synchronizers and PWM.
clocks : entity work.clk_wiz_0
port map(
  clk_in1  => clk,
  clk_out1 => clk_core,
  reset    => btnC,
  locked   => mmcm_locked
);

-- ce18: the core's 18.432 MHz clock enable, every other clk_core cycle
process (clk_core)
begin
  if rising_edge(clk_core) then
    ce18 <= not ce18;
  end if;
end process;

-- Galaga
galaga : entity work.galaga
port map(
  clk_core     => clk_core,
  ce18         => ce18,
  ce_pix       => ce_pix,
  reset        => reset,

  video_r      => r,
  video_g      => g,
  video_b      => b,
  video_csync  => csync,
  video_blankn => blankn,
  video_hs     => hsync,
  video_vs     => vsync,
  audio        => audio,

  b_test       => b_test_in,  -- sw12 (up = test/service mode)
  b_svce       => '1',

  coin         => joyPCFRLDU(7),
  start1       => joyPCFRLDU(5),
  left1        => joyPCFRLDU(2),
  right1       => joyPCFRLDU(3),
  fire1        => joyPCFRLDU(4),
  start2       => joyPCFRLDU(6),
  left2        => joyPCFRLDU(2),
  right2       => joyPCFRLDU(3),
  fire2        => joyPCFRLDU(4)
);

-- 31 kHz VGA via the imported MiST scandoubler.
-- Pad the core's 3/3/2-bit RGB to 6 bits by MSB replication; force black during blank.
vga_r_i <= r & r     when blankn = '1' else "000000";
vga_g_i <= g & g     when blankn = '1' else "000000";
vga_b_i <= b & b & b when blankn = '1' else "000000";

-- scandoubler enables: ce_x1 samples mid-pixel, after the core output settles.
-- ce_x2 runs at twice that rate.
process (clk_core)
begin
  if rising_edge(clk_core) then
    ce_pix_d <= ce_pix_d(3 downto 0) & ce_pix;
  end if;
end process;
ce_x1 <= ce_pix_d(1);
ce_x2 <= ce_pix_d(1) or ce_pix_d(4);

-- scanlines: sw14 up = alternate lines at 50%
scanlines_sel <= sw(14) & '0';

-- scandoubler: 15 kHz video to 31 kHz VGA
scandoubler_inst : scandoubler
port map(
  clk_sys   => clk_core,
  scanlines => scanlines_sel,
  ce_x1     => ce_x1,
  ce_x2     => ce_x2,
  hs_in     => hsync,
  vs_in     => vsync,
  r_in      => vga_r_i,
  g_in      => vga_g_i,
  b_in      => vga_b_i,
  hs_out    => hsync_o,
  vs_out    => vsync_o,
  r_out     => vga_r_o,
  g_out     => vga_g_o,
  b_out     => vga_b_o
);

-- video output: scandoubler or 15 kHz RGB (sw13)
vga_r <= r & '0'             when sw(13) = '1' and blankn = '1' else
  vga_r_o(5 downto 2) when sw(13) = '0'                  else
  "0000";
vga_g <= g & '0'             when sw(13) = '1' and blankn = '1' else
  vga_g_o(5 downto 2) when sw(13) = '0'                  else
  "0000";
vga_b <= b & "00"            when sw(13) = '1' and blankn = '1' else
  vga_b_o(5 downto 2) when sw(13) = '0'                  else
  "0000";
vga_hs <= csync   when sw(13) = '1' else hsync_o;
vga_vs <= '1'     when sw(13) = '1' else vsync_o;

-- input synchronizers
process (clk_core)
begin
  if rising_edge(clk_core) then
    ps2_clk_meta <= ps2_clk;
    ps2_clk_s    <= ps2_clk_meta;
    ps2_dat_meta <= ps2_dat;
    ps2_dat_s    <= ps2_dat_meta;
    stick_meta   <= joy_n;
    stick_s      <= stick_meta;
    btn_meta     <= btnU & btnD & btnL & btnR;
    btn_s        <= btn_meta;
  end if;
end process;

-- get scancode from keyboard (on clk_core, the core clock)
keyboard : entity work.io_ps2_keyboard
port map (
  clk       => clk_core,
  kbd_clk   => ps2_clk_s,
  kbd_dat   => ps2_dat_s,
  interrupt => kbd_intr,
  scancode  => kbd_scancode
);

-- key decoder: scancode to kbd_joy
-- kbd_joy bit order matches joyPCFRLDU below: 5 = start1, 6 = start2, 7 = coin.
process (clk_core)
begin
  if rising_edge(clk_core) then
    if kbd_intr = '1' then
      if kbd_scancode = x"F0" then
        kbd_rel <= '1';
      elsif kbd_scancode /= x"E0" then
        kbd_rel <= '0';
        case kbd_scancode is
          when x"6B" => kbd_joy(2) <= not kbd_rel;          -- left arrow
          when x"74" => kbd_joy(3) <= not kbd_rel;          -- right arrow
          when x"14" => kbd_joy(4) <= not kbd_rel;          -- left ctrl: fire
          when x"16" => kbd_joy(5) <= not kbd_rel;          -- 1: start1
          when x"1E" => kbd_joy(6) <= not kbd_rel;          -- 2: start2
          when x"2E" | x"36" => kbd_joy(7) <= not kbd_rel;  -- 5 / 6: coin
          when others => null;
        end case;
      end if;
    end if;
  end if;
end process;

-- Debounce: btn_db follows its input after 2**18 stable ce18 cycles (14.2 ms).
-- The core edge-detects coin and fire, so contact bounce would add presses.
-- Index 4 = stick fire, 3..0 = btnU/D/L/R.
db_in <= (not stick_s(4)) & btn_s;
process(clk_core)
begin
  if rising_edge(clk_core) and ce18 = '1' then
    for i in 0 to 4 loop
      if db_in(i) = btn_db(i) then
        btn_cnt(i) <= (others => '0');
      elsif btn_cnt(i) = (btn_cnt(i)'range => '1') then
        btn_db(i)  <= db_in(i);
        btn_cnt(i) <= (others => '0');
      else
        btn_cnt(i) <= btn_cnt(i) + 1;
      end if;
    end loop;
  end if;
end process;

-- player inputs: keyboard OR stick OR buttons
-- Galaga core takes left/right/fire only (bits 2/3/4); coin=7, start1=5, start2=6.
joyPCFRLDU(0) <= '0';
joyPCFRLDU(1) <= '0';
joyPCFRLDU(2) <= kbd_joy(2) or not stick_s(1);          -- left: left arrow / stick left
joyPCFRLDU(3) <= kbd_joy(3) or not stick_s(0);          -- right: right arrow / stick right
joyPCFRLDU(4) <= kbd_joy(4) or btn_db(4);               -- fire: left ctrl / stick fire (debounced)
joyPCFRLDU(5) <= kbd_joy(5) or btn_db(1);               -- start1: 1 / btnL
joyPCFRLDU(6) <= kbd_joy(6) or btn_db(0);               -- start2: 2 / btnR
joyPCFRLDU(7) <= kbd_joy(7) or btn_db(3) or btn_db(2);  -- coin: 5, 6 / btnU, btnD

-- pwm sound output
process(clk_core)
begin
  if rising_edge(clk_core) and ce18 = '1' then
    pwm_accumulator <= std_logic_vector(unsigned('0' & pwm_accumulator(11 downto 0)) + unsigned('0' & audio & '0'));
  end if;
end process;

-- PmodAMP2: PWM audio, shutdown, fixed 6 dB gain
O_PMODAMP2_AIN   <= pwm_accumulator(12);
O_PMODAMP2_SHUTD <= not sw(15);
O_PMODAMP2_GAIN  <= '1';

end struct;
