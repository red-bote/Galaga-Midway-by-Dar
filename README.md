# Galaga-Midway-by-Dar

Galaga (Namco / Midway), FPGA core by Dar (<http://darfpga.blogspot.fr>), ported to
Digilent Basys 3 (`xc7a35tcpg236-1`). Upstream:
<https://sourceforge.net/projects/darfpga/files/Software%20VHDL/galaga/>
(`vhdl_galaga_rev_0_3_2018_05_06.zip`, rev 0.3).

## Hardware

- Basys 3; VGA monitor (31 kHz, MiST scandoubler) or 15 kHz TV (sw13, not verified).
- Keyboard on the onboard USB HID port.
- Optional: Atari-compatible joystick on Pmod JXADC (pins 1/2/7 = right/left/fire,
  active low, pull-ups in the XDC).
- Optional: [PmodAMP2](https://digilent.com/reference/pmod/pmodamp2/start) on Pmod JA,
  pins 1/2/4.

## Build

Requires gcc, unzip, Vivado 2020.2, and
[openFPGALoader](https://github.com/trabucayre/openFPGALoader) (`make load` only).

```
make help        # list all targets
make roms        # galaga.zip, galagamw.zip from $ROMDIR
make bitstream   # Vivado batch build (runs make roms first if needed)
make load        # program the Basys 3 over USB (SRAM, lost at power-off)
```

Overrides, as make arguments or environment variables:
`VIVADO=<path>/bin/vivado` (default `/tools/Xilinx/Vivado/2020.2/bin/vivado`),
`ROMDIR=<dir>` (default `~/roms`), `ROMZIP=<zip>[,<zip>]`.

ROMs are not included. Do not redistribute roms or anything generated from them.

## IO

Keys follow the MAME defaults. Player 2 shares the player 1 controls.

| Action   | Keyboard     | Basys 3                          |
|----------|--------------|----------------------------------|
| move     | Left / Right | JXADC pins 2 / 1                 |
| fire     | Left Ctrl    | JXADC pin 7                      |
| start 1P | 1            | btnL                             |
| start 2P | 2            | btnR                             |
| coin     | 5 / 6        | btnU / btnD                      |
| reset    |              | btnC                             |
| test     |              | sw12 (test mode; down = default) |
| display  |              | sw13 (down 31 kHz, up 15 kHz)    |
| amp gain |              | sw14 (up gain active)            |
| audio    |              | sw15 (up disabled)               |

## Issues Addressed

- Vivado rejects the background-palette xor width mismatch: operands parenthesized
  (`contrib/patches/galaga_bgpalette_xor_length_fix.patch`).
- Start ignored with credits available: Namco 51XX credit mode re-enabled on each coin
  (`contrib/patches/galaga_credit_mode_fix.patch`).
- No sync for the scandoubler (core hsync/vsync left open): `video_hs` / `video_vs`
  brought out (`contrib/patches/galaga_vga_sync.patch`).
- Joystick fired on press and again on release (the core latches every rising edge of
  fire, so contact bounce counts as a press): JXADC fire and board buttons debounced
  14 ms in the wrapper.
- Vivado rejects MiST `scandoubler.v` as Verilog-2001 (local declarations in unnamed
  blocks, single-value array size): blocks named, full range declared
  (`contrib/basys3/mist_scandoubler.patch`).

## Third-party additions

- MiST `scandoubler.v` (Till Harbaum, GPL-3.0), in `contrib/third_party/mist/`.
  Origin: [mist-devel/mist-modules@147aa5c](https://github.com/mist-devel/mist-modules/blob/147aa5c11b117eaeda3fd9e81dbff2dc5f12cb14/scandoubler.v).
  Vivado fixes in `contrib/basys3/mist_scandoubler.patch`.

## License

- Basys 3 port additions: MIT, see `LICENSE` (scope stated there).
- DarFPGA sources: educational use only; do not redistribute synthesized files with roms
  (see `vhdl_galaga_rev_0_3_2018_05_06/README.txt`).
- T80 CPU (`rtl_T80/`): BSD-style, Daniel Wallner et al.
- MiST `scandoubler.v`: GPL-3.0.
