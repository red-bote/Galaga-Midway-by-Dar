# Galaga-Midway-by-Dar
Galaga Midway by Dar ported to Basys 3 Artix-7 FPGA Trainer Board 

7/2026 (Red-Bote) I used OpenCode/Big Pickle to fix the keyboard issue described below.

## Controls (PS/2 keyboard, JB header)

| Input | Key | Scancode |
|-------|-----|----------|
| Up | ↑ | 0x75 |
| Down | ↓ | 0x72 |
| Left | ← | 0x6B |
| Right | → | 0x74 |
| Fire | Space | 0x29 |
| Coin | F3 | 0x04 |
| Start 1 | F1 | 0x05 |
| Start 2 | F2 | 0x06 |

## Known Issues

### Start 1 / Start 2 not working after coin

**Root cause:** The Galaga core's Namco 51XX emulation has a `cs51XX_credit_mode` flag that gates the start1/start2 inputs. After CPU initialization this flag is set to `0` (switch mode). The hardware coin detection increments the credit counter but did not re-enable credit mode, so start inputs were ignored even with credits available.

**Fix** (`rtl_dar/galaga.vhd:848`): Added `cs51XX_credit_mode <= '1'` inside the hardware coin edge detection block, so any coin insert automatically re-enables credit mode.

### Keyboard randomly sticking to the right (and maybe to the left)

