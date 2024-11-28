----------------------------------------------------------------------------------
-- Company: Red~Bote
-- Engineer: Glenn Neidermeier
-- 
-- Create Date: 11/28/2024 04:35:03 PM
-- Design Name: 
-- Module Name: galaga_basys3
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
--  Basys 3 port of Galaga Midway by Dar (https://sourceforge.net/projects/darfpga/files/Software%20VHDL/galaga/)
--  Top-level using adaptations from ports for Galaga by Somhi (https://github.com/DECAfpga/Arcade_Galaga)
-- 
-- Dependencies: 
--   Scan Doubler from Galaga by Somhi:
--     https://github.com/DECAfpga/Arcade_Galaga/blob/main/mist/scandoubler.v
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity galaga_basys3 is
    port (
        clk : in std_logic;

        O_PMODAMP2_AIN : out std_logic;
        O_PMODAMP2_GAIN : out std_logic;
        O_PMODAMP2_SHUTD : out std_logic;

        vga_r : out std_logic_vector (3 downto 0);
        vga_g : out std_logic_vector (3 downto 0);
        vga_b : out std_logic_vector (3 downto 0);
        vga_hs : out std_logic;
        vga_vs : out std_logic;

        ps2_clk : in std_logic;
        ps2_dat : in std_logic;
        sw : in std_logic_vector (15 downto 0));
end galaga_basys3;

architecture struct of galaga_basys3 is

    signal reset : std_logic;
    signal clock_36 : std_logic;
    signal clock_12 : std_logic;
    signal clock_18 : std_logic;
    signal clock_9 : std_logic;
    signal clock_6 : std_logic;

    signal r : std_logic_vector(2 downto 0);
    signal g : std_logic_vector(2 downto 0);
    signal b : std_logic_vector(1 downto 0);
    signal csync : std_logic;
    signal blankn : std_logic;
    signal hsync : std_logic;
    signal vsync : std_logic;

    signal audio : std_logic_vector(9 downto 0);
    signal pwm_accumulator : std_logic_vector(12 downto 0);

    signal kbd_intr : std_logic;
    signal kbd_scancode : std_logic_vector(7 downto 0);
    signal joyPCFRLDU : std_logic_vector(7 downto 0);

    signal vga_g_i : std_logic_vector(5 downto 0);
    signal vga_r_i : std_logic_vector(5 downto 0);
    signal vga_b_i : std_logic_vector(5 downto 0);
    signal vga_r_o : std_logic_vector(5 downto 0);
    signal vga_g_o : std_logic_vector(5 downto 0);
    signal vga_b_o : std_logic_vector(5 downto 0);
    signal hsync_o : std_logic;
    signal vsync_o : std_logic;

    component scandoubler
        port (
            clk_sys : in std_logic;
            scanlines : in std_logic_vector (1 downto 0);
            ce_x1 : in std_logic;
            ce_x2 : in std_logic;
            hs_in : in std_logic;
            vs_in : in std_logic;
            r_in : in std_logic_vector (5 downto 0);
            g_in : in std_logic_vector (5 downto 0);
            b_in : in std_logic_vector (5 downto 0);
            hs_out : out std_logic;
            vs_out : out std_logic;
            r_out : out std_logic_vector (5 downto 0);
            g_out : out std_logic_vector (5 downto 0);
            b_out : out std_logic_vector (5 downto 0)
        );
    end component;

    component clk_wiz_0
        port (
            clk_out1 : out std_logic;
            locked : out std_logic;
            clk_in1 : in std_logic
        );
    end component;

    signal slot : std_logic_vector(2 downto 0) := (others => '0');

begin

    reset <= '0'; -- not reset_n;

    u_clk_36 : clk_wiz_0
    port map(
        -- Clock out ports  
        clk_out1 => clock_36,
        -- Status and control signals
        locked => open,
        -- Clock in ports
        clk_in1 => clk
    );

    process (clock_36)
    begin
        if rising_edge(clock_36) then
            clock_12 <= '0';

            clock_18 <= not clock_18;

            if slot = "101" then
                slot <= (others => '0');
            else
                slot <= std_logic_vector(unsigned(slot) + 1);
            end if;

            if slot = "100" or slot = "001" then
                clock_6 <= not clock_6;
            end if;
            if slot = "100" or slot = "001" then
                clock_12 <= '1';
            end if;

        end if;
    end process;

    -- Galaga
    galaga : entity work.galaga
        port map(
            clock_18 => clock_18,
            reset => reset,
            -- tv15Khz_mode => tv15Khz_mode,
            video_r => r,
            video_g => g,
            video_b => b,
            video_csync => csync,
            video_blankn => blankn,
            video_hs => hsync,
            video_vs => vsync,
            audio => audio,

            b_test => '1',
            b_svce => '1',
            coin => joyPCFRLDU(7),
            start1 => joyPCFRLDU(5),
            left1 => joyPCFRLDU(2),
            right1 => joyPCFRLDU(3),
            fire1 => joyPCFRLDU(4),
            start2 => joyPCFRLDU(6),
            left2 => joyPCFRLDU(2),
            right2 => joyPCFRLDU(3),
            fire2 => joyPCFRLDU(4)
        );

    --vga_r <= r&'0'  when blankn = '1' else "0000";
    --vga_g <= g&'0'  when blankn = '1' else "0000";
    --vga_b <= b&"00" when blankn = '1' else "0000";

    ---- synchro composite/ synchro horizontale
    --vga_hs <= csync;
    ---- vga_hs <= csync when tv15Khz_mode = '1' else hsync;
    ---- commutation rapide / synchro verticale
    --vga_vs <= '1';
    ---- vga_vs <= '1'   when tv15Khz_mode = '1' else vsync;

    -- adapt video to 6 bits/color only
    vga_r_i <= r & r when blankn = '1' else "000000";
    vga_g_i <= g & g when blankn = '1' else "000000";
    vga_b_i <= b & b & b when blankn = '1' else "000000";

    -- vga scandoubler
    scandoubler_inst : scandoubler
    port map(
        clk_sys => clock_12, --clock_18, video_clk i clock_36 no funciona
        scanlines => "00", --(00-none 01-25% 10-50% 11-75%)
        ce_x1 => clock_6,
        ce_x2 => '1',
        hs_in => hsync,
        vs_in => vsync,
        r_in => vga_r_i,
        g_in => vga_g_i,
        b_in => vga_b_i,
        hs_out => hsync_o,
        vs_out => vsync_o,
        r_out => vga_r_o,
        g_out => vga_g_o,
        b_out => vga_b_o
    );

    --VGA
    -- adapt video to 4 bits/color only
    vga_r <= vga_r_o (5 downto 2);
    vga_g <= vga_g_o (5 downto 2);
    vga_b <= vga_b_o (5 downto 2);
    vga_hs <= hsync_o;
    vga_vs <= vsync_o;
    -- get scancode from keyboard
    process (reset, clock_18)
    begin
        if reset = '1' then
            clock_9 <= '0';
        else
            if rising_edge(clock_18) then
                clock_9 <= not clock_9;
            end if;
        end if;
    end process;

    keyboard : entity work.io_ps2_keyboard
        port map(
            clk => clock_9,
            kbd_clk => ps2_clk,
            kbd_dat => ps2_dat,
            interrupt => kbd_intr,
            scancode => kbd_scancode
        );

    -- translate scancode to joystick
    joystick : entity work.kbd_joystick
        port map(
            clk => clock_9,
            kbdint => kbd_intr,
            kbdscancode => std_logic_vector(kbd_scancode),
            joyPCFRLDU => joyPCFRLDU
        );

    -- pwm sound output
    process (clock_18)
    begin
        if rising_edge(clock_18) then
            pwm_accumulator <= std_logic_vector(unsigned('0' & pwm_accumulator(11 downto 0)) + unsigned('0' & audio & '0'));
        end if;
    end process;

    -- active-low shutdown pin
    O_PMODAMP2_SHUTD <= sw(14);
    -- gain pin is driven high there is a 6 dB gain, low is a 12 dB gain 
    O_PMODAMP2_GAIN <= sw(15);

    --pwm_audio_out_l <= pwm_accumulator(12);
    --pwm_audio_out_r <= pwm_accumulator(12);
    O_PMODAMP2_AIN <= pwm_accumulator(12);

end struct;
