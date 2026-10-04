# Neo

A DOS keyboard driver that makes a PC keyboard type the [Neo 2](https://neo-layout.org/) layout. It covers the characters needed for ASCII, the international characters on a German keyboard, and programming punctuation. Output is code page 437.

It runs on an IBM 5160. It also runs on later PCs, such as a 386, whose BIOS calls INT 15h AH=4Fh. The BIOS keyboard handler stays in place.

## A keystroke

A scan byte names the physical key position, not the letter printed on the key. Scan 20h is the key a German keyboard labels A. Bit 7 clear means the key went down. Bit 7 set means the key went up. The press of this key is the byte 20h. The release is the byte A0h.

DOS reads keystrokes from a ring of words in the BIOS data area. The low byte is the character. The high byte is the scan code. Neo keeps the press of scan 20h and writes the word 2061h. That word is scan 20h and the character a.

A BIOS that calls INT 15h with AH=4Fh has already read the keyboard. Neo sees the scan byte in register AL. Carry set means the BIOS keeps the byte. Carry clear means the BIOS discards it.

An older BIOS has no such call. Neo wraps INT 09h, the keyboard interrupt. It reads port 60h. When Neo keeps the key, it pulses bit 7 of port 61h. That pulse acknowledges the key. Neo then writes 20h to port 20h so the next key can interrupt.

Neo stays resident. It replaces the hooked interrupt vector with its own address, then exits through INT 21h with AH=31h. The keystroke code remains in memory after the command finishes.

For a letter, upper case is caps exclusive-or Shift. For any other character, upper case is Shift alone.

| Modifier | Layer |
|---|---|
| No Mod key, lower case | 1 |
| No Mod key, upper case | 2 |
| Mod3 alone | 3 |
| Mod4 alone | 4 |
| Mod3 with Shift | 5 |
| Mod3 with Mod4 | 6 |

Layer 5 does not also take capitals. Shift does not change layer 6.

A dead key normally waits for the next character. Neo emits the spacing character at once. The caret and the backtick are those characters.

Alt writes the physical scan in the high byte and 00h in the low byte. Scan 20h with Alt writes 2000h. The shortcut follows the German key position.

## Keys

On a 102-key keyboard, Mod3 is Caps Lock and the `#` key. Mod4 is the `<` key and AltGr.

On an 83-key keyboard, Mod3 is the key left of A and the `#` key. Mod4 is Alt. The wide key to the right of the space bar is Ctrl.

Holding one Shift key toggles capitals for letters when the key repeats. Both Mod3 keys together suspend Neo and pass character keys to the BIOS. Shift, the real Ctrl key, left Alt, and the function keys stay with the BIOS. The keypad stays with the BIOS until Mod3 or Mod4 is held.

Shift on `ß` produces `S` then `S`. A character is produced when code page 437 can draw it. The euro sign, typographic quotes, and dashes are not in that font.

Load Neo after `KEYB`, or leave `KEYB` out. If the letters do not move, the active BIOS handler is not calling `INT 15h AH=4Fh`.

## Commands

| Command | Effect |
|---|---|
| `NEO` | Install. When Neo is already resident, print the counters. |
| `NEO /U` | Remove Neo. |
| `NEO /H` | Print the command list. |
| `NEO /XT` | Install with 83-key positions. |
| `NEO /AT` | Install with 102-key positions. |

The key positions follow the BIOS model byte. `FF`, `FE`, `FD`, and `FB` are 83-key. Every other model byte is 102-key. The hook is chosen separately: a BIOS that calls `INT 15h AH=4Fh` is hooked there, and an older XT BIOS gets a thin `INT 09h` wrapper. `NEO /XT` and `NEO /AT` change only those positions.

## Building

The resident driver is 8086 assembly for Turbo Assembler 2.01. The commands are Turbo C in `NEOCMD.C`, linked into `NEO.COM`. The self-test is Turbo C in `NEOTST.C`, linked with the same driver into `NEOTST.COM`. Both are tiny model, limited to the 8086. Do not enable 186 instructions. `TASM`, `TLINK`, and `TCC` must be on the path, with the Turbo Assembler directory first so its linker is the one that runs. `NEO.ASM`, `NEOCMD.C`, `NEOTST.C`, and `BUILD.BAT` use CR LF line endings.

From the source directory, run `BUILD`. The `NEO.COM` and `NEOTST.COM` in the repository are builds of this source.
