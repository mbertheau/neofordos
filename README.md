# Neo

A DOS keyboard driver that makes a PC keyboard type the [Neo 2](https://neo-layout.org/) layout. It covers the characters needed for ASCII, the international characters on a German keyboard, and programming punctuation. Output is code page 437.

It runs on an IBM 5160. It also runs on later PCs, such as a 386, whose BIOS calls INT 15h AH=4Fh. The BIOS keyboard handler stays in place.

## Keys

On a 102-key keyboard, Mod3 is Caps Lock and the `#` key. Mod4 is the `<` key and AltGr.

On an 83-key keyboard, Mod3 is the key left of A and the `#` key. Mod4 is Alt. The wide key to the right of the space bar is Ctrl.

Holding one Shift key toggles capitals for letters when the key repeats. Both Mod3 keys together suspend Neo and pass character keys to the BIOS. Shift, the real Ctrl key, left Alt, and the function keys stay with the BIOS. The keypad stays with the BIOS until Mod3 or Mod4 is held.

Mod3 with Shift is layer 5. Mod3 with Mod4 is layer 6. Dead keys produce the spacing ASCII character. Shift on `ß` produces `S` then `S`. A character is produced when code page 437 can draw it. The euro sign, typographic quotes, and dashes are not in that font.

Load Neo after `KEYB`, or leave `KEYB` out. If the letters do not move, the active BIOS handler is not calling `INT 15h AH=4Fh`.

## Commands

| Command | Effect |
|---|---|
| `NEO` | Install. When Neo is already resident, print the counters. |
| `NEO /U` | Remove Neo. |
| `NEO /T` | Run the self-test and exit. |
| `NEO /H` | Print the command list. |
| `NEO /XT` | Install with 83-key positions. |
| `NEO /AT` | Install with 102-key positions. |

The key positions follow the BIOS model byte. `FF`, `FE`, `FD`, and `FB` are 83-key. Every other model byte is 102-key. The hook is chosen separately: a BIOS that calls `INT 15h AH=4Fh` is hooked there, and an older XT BIOS gets a thin `INT 09h` wrapper. `NEO /XT` and `NEO /AT` change only those positions.

## Building

The resident driver is 8086 assembly for Turbo Assembler 2.01. The commands and the self-test are Turbo C 2.01, tiny model, also limited to the 8086. Do not enable 186 instructions. `TASM`, `TLINK`, and `TCC` must be on the path, with the Turbo Assembler directory first so its linker is the one that runs. `NEO.ASM`, `NEOCMD.C`, and `BUILD.BAT` use CR LF line endings.

From the source directory, run `BUILD`. The `NEO.COM` in the repository is a build of this source.
