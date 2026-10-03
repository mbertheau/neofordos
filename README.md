# Neo

A DOS keyboard driver that makes a PC keyboard type the [Neo 2](https://neo-layout.org/) layout. It covers the characters needed for ASCII, the international characters on a German keyboard, and programming punctuation. Output is code page 437.

It runs on an IBM 5160 and on a 486. The BIOS keyboard handler stays in place.

## Keys

On a 102-key keyboard, Mod3 is Caps Lock and the `#` key. Mod4 is the `<` key and AltGr.

On an 83-key keyboard, Mod3 is the key left of A and the `#` key. Mod4 is Alt. The wide key to the right of the space bar is Ctrl.

Both Shift keys together toggle capitals for letters. Both Mod3 keys together suspend Neo and give character keys back to the BIOS. Shift, the real Ctrl key, left Alt, the function keys, and the keypad stay with the BIOS.

Dead keys produce the spacing ASCII character. Shift on `ß` produces `S` then `S`. These are not included: superscripts, the euro sign, typographic quotes, and the Greek and math layers.

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

The finger map follows the BIOS model byte. `FF`, `FE`, `FD`, and `FB` are 83-key. Every other model byte is 102-key. The hook is chosen separately: a BIOS that calls `INT 15h AH=4Fh` is hooked there, and an older XT BIOS gets a thin `INT 09h` wrapper. `NEO /XT` and `NEO /AT` change only the finger map.

`NEO.COM` in this tree is a build of `NEO.ASM` made with Turbo Assembler 2.01.

## Building

The source is 8086 assembly. Turbo Assembler 2.01 and its linker are required. Do not enable 186 instructions. The 5160 is an 8088.

`NEO.ASM` and `BUILD.BAT` use CR LF line endings. Copy both into a directory on the DOS path, or into `C:\SRC` when `C:\TASM` is the Turbo Assembler 2.01 directory:

```
C:
CD \SRC
BUILD
```

`BUILD.BAT` runs `TASM /ml NEO.ASM`, links a COM file with `TLINK /t`, then runs `NEO /T`. The assembler and linker transcript goes to `BUILD.LOG`. The self-test transcript goes to `NEO.LOG`. A successful log contains `TASM_OK`, `LINK_OK`, and `TEST_OK`. The DOS exit code of the emulator is not the result.

By hand:

```
C:\TASM\TASM /ml NEO.ASM
C:\TASM\TLINK /t NEO.OBJ
NEO /T
```

On this machine the compilers live under `~/DOS`, mounted as `C:` in DOSBox. `~/DOS/dosbox-run.conf` runs `C:\RUN.BAT` and exits. Point that batch at `BUILD.BAT`, or replace its commands with the three lines above. DOSBox needs `DISPLAY`.

## Files

| File | Purpose |
|---|---|
| `NEO.ASM` | Driver source. |
| `NEO.COM` | Built driver. |
| `BUILD.BAT` | Assemble, link, and self-test. |
| `LICENSE` | MIT license. |
