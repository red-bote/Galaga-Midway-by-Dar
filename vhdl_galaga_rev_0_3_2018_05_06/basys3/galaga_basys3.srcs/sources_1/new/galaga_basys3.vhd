---------------------------------------------------------------------------------
-- Basys 3 top level for Galaga by Red~Bote, derived from galaga_de10_lite.vhd by
-- Dar (darfpga@aol.fr, http://darfpga.blogspot.fr); see that file for its
-- history.
---------------------------------------------------------------------------------
--
-- release rev 01 : initial Basys 3 release
--  (23/10/2026)
--
---------------------------------------------------------------------------------
-- Educational use only
-- Do not redistribute synthetized file with roms
-- Do not redistribute roms whatever the form
-- Use at your own risk
---------------------------------------------------------------------------------
-- Main features :
--  PS2 keyboard input @onboard USB HID (PS/2 emulation)
--  Joystick input     @JXADC pins 1/2/7 = right/left/fire (active low)
--  Audio pwm output   @PmodAMP2 on JA pins 1/2/4; sw15 = audio disable, sw14 = gain
--  31kHz VGA via the MiST scandoubler; sw13 = 15kHz TV (csync on hs)
--  Buttons and JXADC fire debounced (14ms)
--
-- Uses 1 MMCM (clk_wiz_0) for 36.864MHz (clock_18 = /2) from 100MHz
--
-- Board buttons :
--   btnC : reset game
--   btnU, btnD : Add coin
--   btnL : Start 1 player
--   btnR : Start 2 players
--
-- Board switches :
--   sw12 : b_test (service/test mode) dip (down = default '1', up inverts)
--   sw13 : 0 = 31kHz VGA, 1 = 15kHz TV (csync on hs)
--
-- Keyboard inputs (MAME defaults) :
--   5, 6 : Add coin
--   2 : Start 2 players
--   1 : Start 1 player
--   LEFT CTRL   : fire
--   RIGHT arrow : move right
--   LEFT  arrow : move left
--
-- Dip switch and other details : see galaga.vhd
---------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

library work;

entity galaga_basys3 is
port(
  clk            : in std_logic;
  btnC           : in std_logic;
  btnU           : in std_logic;
  btnD           : in std_logic;
  btnL           : in std_logic;
  btnR           : in std_logic;
  sw             : in std_logic_vector(15 downto 0);

  vga_r     : out std_logic_vector(3 downto 0);
  vga_g     : out std_logic_vector(3 downto 0);
  vga_b     : out std_logic_vector(3 downto 0);
  vga_hs    : out std_logic;
  vga_vs    : out std_logic;

  JXADC            : in  std_logic_vector(4 downto 0);
  ps2_clk          : in  std_logic;
  ps2_dat          : in  std_logic;
  O_PMODAMP2_AIN   : out std_logic;
  O_PMODAMP2_GAIN  : out std_logic;
  O_PMODAMP2_SHUTD : out std_logic
);
end galaga_basys3;

architecture struct of galaga_basys3 is

  signal clock_36  : std_logic;
  signal clock_18  : std_logic := '0';
  signal clock_18n : std_logic;
  signal clock_12  : std_logic := '0'; -- scandoubler clk_sys (36.864MHz / 3)
  signal slot      : std_logic_vector(2 downto 0) := "000";
  signal db_in     : std_logic_vector(4 downto 0);
  signal btn_db    : std_logic_vector(4 downto 0) := (others => '0');
  type btn_cnt_t is array (0 to 4) of unsigned(17 downto 0);
  signal btn_cnt   : btn_cnt_t := (others => (others => '0'));
  signal reset     : std_logic;
  signal mmcm_locked : std_logic;

  signal r         : std_logic_vector(2 downto 0);
  signal g         : std_logic_vector(2 downto 0);
  signal b         : std_logic_vector(1 downto 0);
  signal csync     : std_logic;
  signal blankn    : std_logic;
  signal hsync     : std_logic;
  signal vsync     : std_logic;
  signal tv15Khz_mode : std_logic;

  signal clock_6   : std_logic := '0'; -- pixel enable (ce_x1)
  signal scanlines : std_logic_vector(1 downto 0) := "00";
  signal ce_x2     : std_logic := '1';
  signal video_ri  : std_logic_vector(5 downto 0);
  signal video_gi  : std_logic_vector(5 downto 0);
  signal video_bi  : std_logic_vector(5 downto 0);
  signal vga_ro    : std_logic_vector(5 downto 0);
  signal vga_go    : std_logic_vector(5 downto 0);
  signal vga_bo    : std_logic_vector(5 downto 0);
  signal vga_hs_o  : std_logic;
  signal vga_vs_o  : std_logic;

  signal audio           : std_logic_vector( 9 downto 0);
  signal pwm_accumulator : std_logic_vector(12 downto 0);
  -- typed concatenations: '&' inside a type conversion is ambiguous (Synth 8-944)
  signal pwm_prev        : std_logic_vector(12 downto 0);
  signal audio_x         : std_logic_vector(11 downto 0);

  -- 2-FF synchronizers for the asynchronous inputs
  signal ps2_clk_meta, ps2_clk_s : std_logic := '1';
  signal ps2_dat_meta, ps2_dat_s : std_logic := '1';
  signal jxadc_meta, jxadc_s     : std_logic_vector(4 downto 0) := (others => '1');
  signal btn_meta, btn_s         : std_logic_vector(3 downto 0) := (others => '0'); -- U, D, L, R
  attribute ASYNC_REG : string;
  attribute ASYNC_REG of ps2_clk_meta, ps2_clk_s, ps2_dat_meta, ps2_dat_s : signal is "TRUE";
  attribute ASYNC_REG of jxadc_meta, jxadc_s, btn_meta, btn_s : signal is "TRUE";

  signal kbd_intr      : std_logic;
  signal kbd_scancode  : std_logic_vector(7 downto 0);
  signal kbd_rel        : std_logic := '0';
  -- kbd_key : 0 up, 1 down, 2 left, 3 right, 4 left ctrl, 5 left alt,
  --           6 '1', 7 '2', 8 '5', 9 '6', 10 '9'
  signal kbd_key        : std_logic_vector(10 downto 0) := (others => '0');
  signal joyPCFRLDU    : std_logic_vector(7 downto 0);

  constant B_TEST_DEFAULT : std_logic := '1';
  signal b_test_in        : std_logic;

begin

  -- btnC resets the MMCM; the core is held in reset until the MMCM locks
  reset <= btnC or not mmcm_locked;
  clock_18n <= not clock_18;

  tv15Khz_mode <= sw(13);
  b_test_in    <= B_TEST_DEFAULT xor sw(12); -- dip on spare sw12, down = default

  -- Clock 36.864MHz, halved to clock_18 for galaga core
  clocks : entity work.clk_wiz_0
  port map(
    clk_in1  => clk,
    clk_out1 => clock_36,
    reset    => btnC,
    locked   => mmcm_locked
  );

  process (reset, clock_36)
  begin
    if reset='1' then
      clock_18  <= '0';
    else
      if rising_edge(clock_36) then
        clock_18  <= not clock_18;
      end if;
    end if;
  end process;

  -- synchronize asynchronous inputs to the core clock
  process(clock_18)
  begin
    if rising_edge(clock_18) then
      ps2_clk_meta <= ps2_clk;      ps2_clk_s <= ps2_clk_meta;
      ps2_dat_meta <= ps2_dat;      ps2_dat_s <= ps2_dat_meta;
      jxadc_meta   <= JXADC;        jxadc_s   <= jxadc_meta;
      btn_meta     <= btnU & btnD & btnL & btnR;
      btn_s        <= btn_meta;
    end if;
  end process;

  -- debounce buttons and JXADC fire (pressed = '1'): stable for 2**18 clock_18 cycles
  -- (14 ms)
  db_in <= (not jxadc_s(4)) & btn_s;
  process(clock_18)
  begin
    if rising_edge(clock_18) then
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

  -- Galaga
  galaga : entity work.galaga
  port map(
    clock_18     => clock_18,
    reset        => reset,
  -- tv15Khz_mode => tv15Khz_mode,
    video_r      => r,
    video_g      => g,
    video_b      => b,
    video_csync  => csync,
    video_blankn => blankn,
    video_hs     => hsync,
    video_vs     => vsync,
    audio        => audio,

    b_test       => b_test_in,
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

  -- scandoubler clocks : clock_12 (clk_sys) and clock_6 (ce_x1, 6.144MHz) from a
  -- mod-6 counter on clock_36
  process (clock_36)
  begin
    if rising_edge(clock_36) then
      clock_12 <= '0';
      if slot = "101" then
        slot <= (others => '0');
      else
        slot <= slot + '1';
      end if;
      if slot = "100" or slot = "001" then
        clock_6  <= not clock_6;
        clock_12 <= '1';
      end if;
    end if;
  end process;

  -- adapt video to 6bits/color for the scandoubler, black during blank
  video_ri <= r&"000"  when blankn = '1' else "000000";
  video_gi <= g&"000"  when blankn = '1' else "000000";
  video_bi <= b&"0000" when blankn = '1' else "000000";

  -- 31kHz VGA : MiST scandoubler
  scandoubler : entity work.scandoubler
  port map (
    clk_sys   => clock_12,
    scanlines => scanlines,
    ce_x1     => clock_6, -- pixel enable
    ce_x2     => ce_x2,   -- clk_sys is 2 x pixel rate
    hs_in     => hsync,
    vs_in     => vsync,
    r_in      => video_ri,
    g_in      => video_gi,
    b_in      => video_bi,
    hs_out    => vga_hs_o,
    vs_out    => vga_vs_o,
    r_out     => vga_ro,
    g_out     => vga_go,
    b_out     => vga_bo
  );

  -- adapt video to 4bits/color only
  vga_r <= video_ri(5 downto 2) when tv15Khz_mode = '1' else vga_ro(5 downto 2);
  vga_g <= video_gi(5 downto 2) when tv15Khz_mode = '1' else vga_go(5 downto 2);
  vga_b <= video_bi(5 downto 2) when tv15Khz_mode = '1' else vga_bo(5 downto 2);

  -- synchro composite/ synchro horizontale
  vga_hs <= csync when tv15Khz_mode = '1' else vga_hs_o;
  -- commutation rapide / synchro verticale
  vga_vs <= '1'   when tv15Khz_mode = '1' else vga_vs_o;

  -- get scancode from keyboard

  keyboard : entity work.io_ps2_keyboard
  port map (
    clk       => clock_18, -- use same clock as main core
    kbd_clk   => ps2_clk_s,
    kbd_dat   => ps2_dat_s,
    interrupt => kbd_intr,
    scancode  => kbd_scancode
  );

  -- translate scancode to keys (MAME default keys, PS/2 set 2 codes)
  -- F0 marks a release; E0 is ignored, as in kbd_joystick (keypad 8/2/4/6
  -- also act as arrows, Right Ctrl/Alt as Left Ctrl/Alt).
  process(clock_18)
  begin
    if rising_edge(clock_18) then
      if kbd_intr = '1' then
        if kbd_scancode = x"F0" then
          kbd_rel <= '1';
        elsif kbd_scancode /= x"E0" then
          kbd_rel <= '0';
          if kbd_scancode = x"75" then kbd_key(0)  <= not kbd_rel; end if; -- up arrow
          if kbd_scancode = x"72" then kbd_key(1)  <= not kbd_rel; end if; -- down arrow
          if kbd_scancode = x"6B" then kbd_key(2)  <= not kbd_rel; end if; -- left arrow
          if kbd_scancode = x"74" then kbd_key(3)  <= not kbd_rel; end if; -- right arrow
          if kbd_scancode = x"14" then kbd_key(4)  <= not kbd_rel; end if; -- left ctrl
          if kbd_scancode = x"11" then kbd_key(5)  <= not kbd_rel; end if; -- left alt
          if kbd_scancode = x"16" then kbd_key(6)  <= not kbd_rel; end if; -- 1
          if kbd_scancode = x"1E" then kbd_key(7)  <= not kbd_rel; end if; -- 2
          if kbd_scancode = x"2E" then kbd_key(8)  <= not kbd_rel; end if; -- 5
          if kbd_scancode = x"36" then kbd_key(9)  <= not kbd_rel; end if; -- 6
          if kbd_scancode = x"46" then kbd_key(10) <= not kbd_rel; end if; -- 9
        end if;
      end if;
    end if;
  end process;

  -- merge keyboard, JXADC joystick (active low) and debounced buttons; player 2
  -- mirrors player 1 as on the DE10-lite top
  joyPCFRLDU(0) <= '0';
  joyPCFRLDU(1) <= '0';
  joyPCFRLDU(2) <= kbd_key(2) or not jxadc_s(1);              -- left  (JXADC2)
  joyPCFRLDU(3) <= kbd_key(3) or not jxadc_s(0);              -- right (JXADC1)
  joyPCFRLDU(4) <= kbd_key(4) or btn_db(4);                   -- fire : left ctrl or JXADC7 (debounced)
  joyPCFRLDU(5) <= kbd_key(6) or btn_db(1);                   -- start 1 : 1 or btnL
  joyPCFRLDU(6) <= kbd_key(7) or btn_db(0);                   -- start 2 : 2 or btnR
  joyPCFRLDU(7) <= kbd_key(8) or kbd_key(9) or btn_db(3) or btn_db(2); -- coin : 5, 6, btnU, btnD

  -- pwm sound output
  pwm_prev <= '0' & pwm_accumulator(11 downto 0);
  audio_x  <= '0' & audio & '0';

  process(clock_18)
  begin
    if rising_edge(clock_18) then
      pwm_accumulator  <=  std_logic_vector(unsigned(pwm_prev) + unsigned(audio_x));
    end if;
  end process;

  O_PMODAMP2_AIN   <= pwm_accumulator(12);
  O_PMODAMP2_SHUTD <= not sw(15); -- sw15 up = amp shut down (audio disabled)
  O_PMODAMP2_GAIN  <= not sw(14); -- sw14 up = gain active (GAIN active low)

end struct;
