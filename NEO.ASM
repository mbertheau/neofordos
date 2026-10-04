; Neo, layers 1-6, for the IBM 5160 and later PCs.
;
; Read this file from the top. A keystroke executes only the resident
; driver, which ends at resident_end. NEOCMD.C is the command program:
; the switches, the messages, and the self-test. It is linked after
; resident_end, and DOS releases it when the driver stays resident.
; Installing and removing the driver stay here, because that is where
; the stack and the open handles have to be exact.
;
; The BIOS keyboard handler stays in place. A BIOS that calls INT 15h
; AH=4Fh is hooked only there. Carry set means the BIOS keeps the scan
; byte in AL. Carry clear means the BIOS discards it. An older XT BIOS
; has no such call, so the driver wraps INT 09h. The wrapper reads port
; 60h without pulsing port 61h bit 7, and the scan byte is still in the
; controller when the BIOS should handle the key.
;
; The driver owns Mod3, Mod4, and the main typing block. Shift, the real
; Ctrl key, left Alt, the function keys, and the system chords stay with
; the BIOS. The keypad stays with the BIOS until Mod3 or Mod4 is held.
; An E0 prefix is passed to the BIOS. The byte after it is kept only when
; it is AltGr, and the prefix bits at 0040:0096 are then cleared. E0 2A
; and E0 AA are the fake shift around a Num Lock arrow. They go back to
; the BIOS and are not a Shift press.
;
; Output is code page 437. A dead key produces the spacing ASCII
; character. Shift on sz produces S, then S, because a capital sz is not
; in the font. Layers 5 and 6 are produced when the font has the glyph.
;
; The cost of a key is one pass through the interrupt, with interrupts
; left off, as the BIOS entered it. The pass is a chain of comparisons
; and a multiply that indexes the layer table. Nothing scans the table,
; and nothing polls. A letter is looked up twice: once to see whether
; capitals apply, and once to load the chosen layer. On a machine that
; uses the 4Fh hook, every other INT 15h call pays for a compare and a
; far jump back to the BIOS. The resident size is resident_end, rounded
; up to a paragraph, and that count includes the PSP.
.MODEL TINY
.CODE
ORG 100h

start:
    jmp init                        ; COM entry. init lives past resident_end


; A resident copy is recognized by the four bytes NEO2 placed
; immediately in front of the hooked entry. The word after those bytes
; is the offset of neo_state in the resident segment. Install, status,
; and unload follow that word, so they never use an address taken from
; the transient copy.
    db 'NEO2'                      ; signature at the hooked entry minus 6
    dw OFFSET neo_state             ; word at the entry minus 2
; INT 15h. AH is the BIOS function. Anything other than 4Fh is returned
; to the saved vector at once. A 4Fh call is one scan byte, make or
; break, in AL. The BIOS has already read port 60h, and this path must
; not read it: the read would empty the controller.
;
; key83 = 0 is the 102-key positions, and only those positions consult the prefix
; flags at 0040:0096. Bit 0 is the E1 prefix and bit 1 is E0. An E1
; sequence is passed back. An E0 byte sets seen_e0 for the decision
; below. When the byte is kept, both prefix bits are cleared.
;
; pass is 1 when the BIOS keeps AL and 0 when this driver keeps the
; scan. The byte is read after the registers are restored. After
; push bp / mov bp,sp the saved flags of this interrupt are at [bp+6]:
; the interrupt frame is IP, CS, flags, and the saved BP sits in front
; of that. Clearing bit 0 of the flag word clears carry. The BIOS then
; discards AL. Leaving the bit set makes the BIOS keep AL.
neo15:
    cmp ah, 4Fh
    je n15_body                     ; AH=4Fh: AL is the scan byte
    jmp dword ptr cs:saved_vec         ; any other AH: far jump, BIOS finishes it
n15_body:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
    inc word ptr cs:scans
    mov bx, 40h
    mov es, bx                      ; ES = BIOS data segment 0040h
    mov byte ptr cs:seen_e0, 0
    cmp byte ptr cs:key83, 0
    jne n15_go                      ; 83-key keyboard never sends E0
    test byte ptr es:[96h], 1       ; 0040:0096 bit 0, the E1 prefix
    jnz n15_pass                    ; E1 sequence: both bytes belong to the BIOS
    test byte ptr es:[96h], 2       ; bit 1, the E0 prefix
    jz n15_go                       ; no prefix: decide on AL alone
    mov byte ptr cs:seen_e0, 1      ; this AL is the byte after E0
n15_go:
    call neo_handle                 ; carry set: BIOS keeps AL
    jc n15_pass
    inc word ptr cs:kept
    cmp byte ptr cs:key83, 0
    jne n15_store                   ; 83-key path has no prefix bits
    and byte ptr es:[96h], 0FCh     ; 0FCh = 11111100b, clear E0 and E1
n15_store:
    call flush_words
    mov byte ptr cs:pass, 0         ; driver kept the scan: clear carry on the way out
    jmp n15_done
n15_pass:
    mov byte ptr cs:pass, 1         ; BIOS keeps AL: leave carry set
n15_done:
    pop es
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax                          ; AL is the scan again, for the BIOS
    cmp byte ptr cs:pass, 0
    jne n15_iret                    ; pass=1: IRET with the flags unchanged
    push bp
    mov bp, sp
    and byte ptr [bp+6], 0FEh       ; 0FEh = 11111110b, flag bit 0 is carry
    pop bp
n15_iret:
    iret

    db 'NEO2'                      ; same signature, in front of the XT hook
    dw OFFSET neo_state
; INT 09h, used only when the BIOS never calls INT 15h AH=4Fh. The scan
; byte is peeked before port 61h is touched. Carry set jumps to the
; saved BIOS handler, which still sees the same byte. Carry clear means
; this driver owns the key: bit 7 of port 61h is pulsed and the other
; bits are put back, the typeahead word is written, and EOI is sent to
; port 20h. The 83-key keyboard has no E0 prefix, so seen_e0 stays clear.
neo09:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
    inc word ptr cs:scans
    in al, 60h                      ; peek. Port 61h bit 7 is not pulsed yet
    mov byte ptr cs:seen_e0, 0      ; an 83-key keyboard has no E0 prefix
    call neo_handle
    jc n09_pass                     ; BIOS must still see this byte in the 8042
    inc word ptr cs:kept
    in al, 61h                      ; keyboard control. Other bits stay
    mov ah, al                      ; AH = original port 61h value
    or al, 80h                      ; bit 7 acknowledges the key
    out 61h, al
    mov al, ah
    out 61h, al                     ; bit 7 back down, other bits unchanged
    call flush_words
    mov al, 20h
    out 20h, al                     ; non-specific EOI to the master PIC
    pop es
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    iret                            ; we acked, so do not chain to the BIOS
n09_pass:
    pop es
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    jmp dword ptr cs:saved_vec         ; BIOS acks port 61h and sends the EOI

; Resident variables. A command that finds an already resident copy
; adds these offsets to the neo_state pointer stored in front of the
; hook. The public underscore names are the Turbo C names of the
; same bytes. The keystroke path keeps the names without the
; underscore.
;
; key83 is 0 for the 102-key positions and 1 for the 83-key positions.
; mod3a and mod3b are the two Mod3 keys. mod4a and mod4b are the two
; Mod4 keys. A held key repeats, and a repeat must not toggle capitals
; or suspend, so each flag stays 1 while its key is down. caps is this
; driver's capital state. BIOS bit 6 of 0040:0017 matches it, and the
; Caps Lock scan is never passed through, so the BIOS does not fight
; that bit. suspended flips when both Mod3 keys go down together.
; npending is 0, 1, or 2. pending0 and pending1 are the typeahead words
; not yet written. scans counts scan bytes that entered the hook. kept
; counts the bytes this driver kept. saved_vec is the BIOS vector that
; was replaced. hook15 says which vector that was. model_byte is the
; byte at F000:FFFE.

neo_state:
public _key83
_key83 label byte
key83      db 0                    ; +0   0 = 102-key, 1 = 83-key
public _mod3a
_mod3a label byte
mod3a      db 0                    ; +1   first Mod3 key is down
public _mod3b
_mod3b label byte
mod3b      db 0                    ; +2   second Mod3 key is down
public _mod4a
_mod4a label byte
mod4a      db 0                    ; +3   first Mod4 key is down
public _mod4b
_mod4b label byte
mod4b      db 0                    ; +4   second Mod4 key is down
public _caps
_caps label byte
caps       db 0                    ; +5   driver caps, mirrored in 0017 bit 6
public _suspended
_suspended label byte
suspended  db 0                    ; +6   both Mod3 keys: Neo is suspended
public _seen_e0
_seen_e0 label byte
seen_e0    db 0                    ; +7   this scan byte followed an E0
public _npending
_npending label byte
npending   db 0                    ; +8   0, 1, or 2 typeahead words waiting
pass       db 0                    ; +9   1 = the BIOS keeps AL
public _pending0
_pending0 label word
pending0   dw 0                    ; +10  first typeahead word
public _pending1
_pending1 label word
pending1   dw 0                    ; +12  second word, the second S of SS
public _scans
_scans label word
scans      dw 0                    ; +14  scan bytes that entered the hook
public _kept
_kept label word
kept       dw 0                    ; +16  scan bytes this driver kept
saved_vec  label dword
saved_off  dw 0                    ; +18  saved vector offset
saved_seg  dw 0                    ; +20  saved vector segment
hook15     db 0                    ; +22  1 = INT 15h, 0 = INT 09h
public _model_byte
_model_byte label byte
model_byte db 0                    ; +23  byte at F000:FFFE

; The layer table is indexed by the physical scan code: the position on
; a German keyboard, not the letter printed on the key. Scan 02h is the
; 1 key. The top letter row, 10h through 1Bh, becomes
; x v l c w k h g f q sz and the acute key. The home row, 1Eh through
; 28h, becomes u i a e o s n r t d y. The bottom row, 2Ch through 35h,
; becomes ue oe ae p z b m , . j. Scan 29h is the key left of 1. Scan
; 39h is the space bar. The keypad scans, 45h and 47h through 53h, are
; reached only while Mod3 or Mod4 is held.
;
; Each row is seven bytes. The first five are the characters for layers
; 1, 2, 3, 5, and 6. The last two are the layer 4 typeahead word. A
; character byte of 00h produces nothing. Any other byte is returned
; with this row's scan code in the high half of the word. Layer 4 is
; stored whole because its scan code is often a different key: an arrow,
; a keypad digit, Tab, Esc, Enter, or Backspace. On the keypad's own
; keys, layer 4 uses the row scan with a zero character, for Home, the
; arrows, Insert, and Delete. That zero is a real key, which is why
; layer 4 is not packed into one byte. The number at the end of a row
; is its scan code.
;
; A dw stores the scan in the high byte and the character in the low
; byte, so dw 02A6h is scan 02h and CP437 A6h. A printable ASCII byte is
; written as that character. A layer 4 word whose character is printable
; ASCII is the scan in the high byte plus that character, so 4A00h + '-'
; is scan 4Ah and '-'. The apostrophe stays 27h. A quoted dollar sign is
; the character, not the end of a DOS string. Bytes that are not ASCII:
; 81 ue, 84 ae, 8E AE, 94 oe, 99 OE, 9A UE, E1 sz, F8 degree, 15
; section, FD superscript 2, A6 feminine ordinal, A7 masculine ordinal,
; AF >>, AE <<, FA middle dot, 9B cent, 9C pound, 9D yen, AD inverted
; exclamation, A8 inverted question, E0 alpha, EE epsilon, EB delta,
; ED phi, E8 Phi, E3 pi, E6 micro, E7 tau, E5 sigma, E4 Sigma, E2
; Gamma, EA Omega, E9 Theta, EC infinity, EF intersection, FB square
; root, AA not, FF no-break space, F7 almost equal, F0 identical, F1
; plus-minus, F3 less-or-equal, F2 greater-or-equal, F6 division.
; 00h in a character byte is an empty cell. 00h as the low byte of a
; layer 4 word is a real key with no ASCII character: an arrow, Home,
; End, Insert, or Delete.
laytab:
    db 00h, 00h, 00h, 00h, 00h  ; 00
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 01
    dw 0000h
    db '1', 0F8h, 00h, 00h, 0AAh  ; 02
    dw 02A6h
    db '2', 15h, 0FDh, 00h, 00h  ; 03
    dw 03A7h
    db '3', 00h, 00h, 00h, 00h  ; 04
    dw 0000h
    db '4', 0AFh, 00h, 00h, 00h  ; 05
    dw 0000h
    db '5', 0AEh, 00h, 00h, 00h  ; 06
    dw 06FAh
    db '6', '$', 9Bh, 00h, 00h  ; 07
    dw 079Ch
    db '7', 00h, 9Dh, 00h, 00h  ; 08
    dw 0000h
    db '8', 00h, 00h, 00h, 0ECh  ; 09
    dw 0F09h
    db '9', 00h, 00h, 00h, 00h  ; 0A
    dw 0A00h + '/'
    db '0', 00h, 00h, 00h, 00h  ; 0B
    dw 0B00h + '*'
    db '-', '-', 00h, 00h, 00h  ; 0C
    dw 4A00h + '-'
    db '`', 00h, 00h, 00h, 00h  ; 0D
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 0E
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 0F
    dw 0000h
    db 'x', 'X', 00h, 00h, 00h  ; 10
    dw 4900h
    db 'v', 'V', '_', 00h, 0FBh  ; 11
    dw 0E08h
    db 'l', 'L', '[', 00h, 00h  ; 12
    dw 4800h
    db 'c', 'C', ']', 00h, 00h  ; 13
    dw 5300h
    db 'w', 'W', '^', 00h, 0EAh  ; 14
    dw 5100h
    db 'k', 'K', '!', 00h, 00h  ; 15
    dw 15ADh
    db 'h', 'H', '<', 00h, 00h  ; 16
    dw 4700h + '7'
    db 'g', 'G', '>', 00h, 0E2h  ; 17
    dw 4800h + '8'
    db 'f', 'F', '=', 0EDh, 0E8h  ; 18
    dw 4900h + '9'
    db 'q', 'Q', '&', 00h, 00h  ; 19
    dw 4E00h + '+'
    db 0E1h, 00h, 00h, 00h, 00h  ; 1A
    dw 4A00h + '-'
    db 27h, 00h, '/', 00h, 00h  ; 1B
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 1C
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 1D
    dw 0000h
    db 'u', 'U', '\', 00h, 00h  ; 1E
    dw 4700h
    db 'i', 'I', '/', 00h, 00h  ; 1F
    dw 4B00h
    db 'a', 'A', '{', 0E0h, 00h  ; 20
    dw 5000h
    db 'e', 'E', '}', 0EEh, 00h  ; 21
    dw 4D00h
    db 'o', 'O', '*', 00h, 00h  ; 22
    dw 4F00h
    db 's', 'S', '?', 0E5h, 0E4h  ; 23
    dw 23A8h
    db 'n', 'N', '(', 00h, 00h  ; 24
    dw 4B00h + '4'
    db 'r', 'R', ')', 00h, 00h  ; 25
    dw 4C00h + '5'
    db 't', 'T', '-', 0E7h, 00h  ; 26
    dw 4D00h + '6'
    db 'd', 'D', ':', 0EBh, 00h  ; 27
    dw 2700h + ','
    db 'y', 'Y', '@', 00h, 00h  ; 28
    dw 2800h + '.'
    db '^', 00h, 00h, 00h, '.'  ; 29
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 2A
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 2B
    dw 0000h
    db 81h, 9Ah, '#', 00h, 00h  ; 2C
    dw 011Bh
    db 94h, 99h, '$', 00h, 0EFh  ; 2D
    dw 0F09h
    db 84h, 8Eh, '|', 00h, 00h  ; 2E
    dw 5200h
    db 'p', 'P', '~', 0E3h, 00h  ; 2F
    dw 1C0Dh
    db 'z', 'Z', '`', 00h, 00h  ; 30
    dw 0000h
    db 'b', 'B', '+', 00h, 00h  ; 31
    dw 3100h + ':'
    db 'm', 'M', '%', 0E6h, 00h  ; 32
    dw 4F00h + '1'
    db ',', '-', '"', 00h, 00h  ; 33
    dw 5000h + '2'
    db '.', 00h, 27h, 00h, 00h  ; 34
    dw 5100h + '3'
    db 'j', 'J', ';', 00h, 0E9h  ; 35
    dw 3500h + ';'
    db 00h, 00h, 00h, 00h, 00h  ; 36
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 37
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 38
    dw 0000h
    db ' ', ' ', ' ', 0FFh, 00h  ; 39
    dw 5200h + '0'
    db 00h, 00h, 00h, 00h, 00h  ; 3A
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 3B
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 3C
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 3D
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 3E
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 3F
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 40
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 41
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 42
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 43
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 44
    dw 0000h
    db 00h, 00h, '=', 0F7h, 0F0h  ; 45
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 46
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 47
    dw 4700h
    db 00h, 00h, 00h, 0EFh, 00h  ; 48
    dw 4800h
    db 00h, 00h, 00h, 00h, 00h  ; 49
    dw 4900h
    db 00h, 00h, 00h, 00h, 00h  ; 4A
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 4B
    dw 4B00h
    db 00h, 00h, ':', 00h, 00h  ; 4C
    dw 4C00h
    db 00h, 00h, 00h, 00h, 00h  ; 4D
    dw 4D00h
    db 00h, 00h, 0F1h, 00h, 00h  ; 4E
    dw 0000h
    db 00h, 00h, 00h, 0F3h, 00h  ; 4F
    dw 4F00h
    db 00h, 00h, 00h, 00h, 00h  ; 50
    dw 5000h
    db 00h, 00h, 00h, 0F2h, 00h  ; 51
    dw 5100h
    db 00h, 00h, '%', 00h, 00h  ; 52
    dw 5200h
    db 00h, 00h, ',', 00h, 00h  ; 53
    dw 5300h
    db 00h, 00h, 00h, 00h, 00h  ; 54
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 55
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 56
    dw 0000h
; Keypad slash arrives as E0 35h, and 35h is also the J key. This row
; has the same seven-byte shape, so the lookup below serves both.
kpslash:
    db 00h, 00h, 0F6h, 00h, 00h
    dw 0000h
; One scan byte enters here. AL may be a make or a break. BL is the
; scan with the break bit removed, and BH is that break bit alone.
; seen_e0 is 1 when the 102-key path saw an E0 prefix on this byte.
; Carry set tells the caller to pass the byte to the BIOS. Carry clear
; tells the caller to keep it. npending is then 0, 1, or 2, and pending0 and
; pending1 are the typeahead words.
neo_handle proc near
    mov bl, al
    and bl, 7Fh                     ; BL = scan. Bit 7 is the break flag
    mov bh, al
    and bh, 80h                     ; BH = 80h on break, 00h on make
    push es
    push si
    mov ax, 40h
    mov es, ax                      ; ES = BIOS data, for 0017h and 0018h
    mov byte ptr cs:npending, 0
    mov word ptr cs:pending0, 0
    mov word ptr cs:pending1, 0
; E0 2Ah is the fake left shift around a Num Lock arrow, and it is not
; treated as Shift. The break of that fake key is E0 AAh, which lands
; here with BL = 2Ah as well. Every other byte is offered to claim_mod.
; A modifier this driver owns is kept, break as well as make.
    cmp byte ptr cs:seen_e0, 0
    je nh_mods                      ; no E0: 2Ah would be a real Shift
    cmp bl, 2Ah
    jne nh_mods                     ; E0 of some other key
    jmp nh_pass                     ; phantom shift: BIOS handles it
nh_mods:
    call claim_mod                    ; DL = 1 when this driver owns BL
    or dl, dl
    jz nh_notmod                    ; DL = 0: not Mod3, Mod4, or XT Ctrl
    jmp nh_keep                      ; owned modifier: keep the make and the break
; Suspend passes character keys to the BIOS. Mod3 and Mod4 were
; already kept, so a suspended driver does not release those keys.
nh_notmod:
    cmp byte ptr cs:suspended, 0
    je nh_run                       ; suspended = 0: translate the key
    jmp nh_pass                     ; suspended = 1: character key goes to BIOS
; A Shift make toggles capitals when that Shift's bit is already set in
; 0040:0017 and the other Shift bit is clear. The first make still has
; a clear bit, so it is passed through and the BIOS records it. A later
; make of the same key, which is what the keyboard sends while the key
; is held, finds the bit set and toggles. If both Shift bits are already
; set, the make is passed through and capitals stay as they are. Bit 0
; (01h) is right Shift and bit 1 (02h) is left Shift. caps and BIOS bit
; 6 are inverted together. The Shift scan is then passed through.
nh_run:
    cmp bl, 2Ah                     ; 2Ah is left Shift
    je nh_shift
    cmp bl, 36h                     ; 36h is right Shift
    jne nh_own                      ; anything else may be a character
nh_shift:
    or bh, bh
    jz nh_shmake                    ; BH = 0: this is the make
    jmp nh_pass                     ; Shift break: BIOS clears its own bit
nh_shmake:
    mov al, es:[17h]                ; AL = keyboard flags before this make
    cmp bl, 2Ah
    jne nh_shr                      ; not left Shift, so it is right Shift
    test al, 01h                    ; right Shift already down?
    jz nh_shleft                    ; no: look at the left Shift bit
    jmp nh_pass                     ; both would be down: do not toggle
nh_shleft:
    test al, 02h                    ; left Shift bit already set?
    jnz nh_tog                      ; yes: this make is the repeat, toggle
    jmp nh_pass                     ; first make: BIOS still has to record it
nh_shr:
    test al, 02h                    ; left Shift already down?
    jz nh_shright
    jmp nh_pass                     ; both would be down: do not toggle
nh_shright:
    test al, 01h                    ; right Shift bit already set?
    jnz nh_tog                      ; repeat of right Shift: toggle
    jmp nh_pass                     ; first make of right Shift
; The main typing block is owned on make and on break. The break of an
; owned key is kept and produces nothing. E0 35h is the keypad slash
; rather than J, and the keypad scans are owned only while Mod3 or Mod4
; is down. With neither Mod key down, those scans go to the BIOS.
; The short conditional cannot reach nh_pass from here, so a miss is
; jc to the owner and a near jmp to the pass path.
nh_own:
    cmp byte ptr cs:seen_e0, 0
    je nh_ownb                      ; not an extended key
    cmp bl, 35h                     ; E0 35h is keypad slash, not J
    jne nh_ownb                     ; E0 of a gray key: not the slash
    call kp_layer                   ; carry set when a Mod key claims it
    jc nh_isown
    jmp nh_pass                     ; slash with no Mod key: BIOS types /
nh_ownb:
    call is_typing_block                    ; carry set: BL is in the typing block
    jc nh_isown
    call kp_layer                   ; carry set: Mod key claims this keypad scan
    jc nh_isown
    jmp nh_pass                     ; function key, gray arrow, or plain keypad
nh_isown:
    or bh, bh
    jz nh_char                      ; make: choose a layer and emit
    jmp nh_keep                      ; break of an owned key: emit nothing
nh_tog:
    xor byte ptr cs:caps, 1         ; flip the driver's own capital state
    xor byte ptr es:[17h], 40h      ; 40h is bit 6, the BIOS Caps Lock flag
    jmp nh_pass                     ; then let the BIOS see the Shift scan
; Choose the layer. Mod3 and Mod4 together are layer 6, ahead of either
; key alone. Mod4 alone is layer 4. Mod3 with a Shift bit set is layer
; 5, and that is its own layer: the capital xor is not applied on top.
; Mod3 alone is layer 3. The Shift bits are copied to CH. load_layer
; has to preserve CX, because the letter path tests CH after it returns.
nh_char:
    mov ch, es:[17h]                ; CH = flags. load_layer must preserve CX
    mov al, cs:mod4a
    or al, cs:mod4b
    mov dl, al                      ; DL nonzero if either Mod4 key is down
    mov al, cs:mod3a
    or al, cs:mod3b
    mov cl, al                      ; CL nonzero if either Mod3 key is down
    or al, dl
    jz nh_nomod                     ; neither Mod key: layers 1 and 2
    or cl, cl
    jz nh_only4                     ; Mod4 without Mod3
    or dl, dl
    jz nh_only3                     ; Mod3 without Mod4
    mov dh, 6                       ; both: layer 6, ahead of either alone
    jmp nh_pick
nh_only4:
    mov dh, 4                       ; Mod4 alone is layer 4
    jmp nh_pick
nh_only3:
    test ch, 03h                    ; 03h = both Shift bits
    jz nh_m3                        ; no Shift: plain layer 3
    mov dh, 5                       ; Mod3+Shift is layer 5, not shifted layer 3
    jmp nh_pick
nh_m3:
    mov dh, 3
    jmp nh_pick
; Neither Mod key is down. Ctrl and Alt together are passed through, so
; Ctrl+Alt+Del still reaches the BIOS on the 102-key positions. Alt alone
; writes a zero character with the physical scan in the high byte, the
; same shape the BIOS uses for an Alt combination. Ctrl on a layer-1
; letter writes the control character of that Neo letter. Ctrl on any
; other cell is kept. This block is not used while Mod3 is down, so
; Mod3 wins over Ctrl.
;
; With neither Ctrl nor Alt, layer 1 is loaded and the character is
; classified. A letter then uses layer 2 when caps xor the Shift bits is
; 1. A non-letter uses layer 2 when a Shift bit is set, with no capital
; xor. A letter is a-z, or one of the four layer-1 German bytes: ue
; (81h), ae (84h), oe (94h), and sz (E1h).
nh_nomod:
    test ch, 04h                    ; 04h is bit 2, Ctrl
    jz nh_noctl
    test ch, 08h                    ; 08h is bit 3, Alt
    jz nh_noctl                     ; Ctrl without Alt: maybe a control letter
    jmp nh_pass                     ; Ctrl+Alt, so Ctrl+Alt+Del still works
nh_noctl:
    test ch, 08h
    jnz nh_alt                      ; Alt without Ctrl
    test ch, 04h
    jnz nh_ctrl                     ; Ctrl without Alt
    mov dh, 1                       ; neither: start from layer 1
    call load_layer                 ; AL = character, AH = scan
    mov cl, al                      ; CL keeps it. is_letter reads AL
    call is_letter                  ; carry set: a-z, ue, ae, oe, or sz
    jc nh_let
    test ch, 03h                    ; non-letter: any Shift bit?
    jz nh_pick                      ; no: emit layer 1, DH is still 1
    mov dh, 2                       ; yes: layer 2, and do not xor caps
    jmp nh_pick
nh_let:
    mov ah, 0                       ; AH will be 1 only when a Shift is down
    test ch, 03h
    jz nh_ns
    mov ah, 1
nh_ns:
    mov al, cs:caps
    xor al, ah                      ; caps XOR shift. 0 stays on layer 1
    jz nh_low
    mov dh, 2                       ; the xor came out 1: capital layer
    jmp nh_pick
nh_low:
    mov dh, 1                       ; falls into nh_pick
; Shift on sz has no single capital in this font, so it writes S and
; then S, both under the sz scan. Every other cell is loaded once. An
; empty cell writes nothing and does not fall back to another layer.
; The Insert word 5200h also toggles bit 7 of 0040:0017. Delete is
; 5300h and changes no flag.
nh_pick:
    cmp bl, 1Ah                     ; 1Ah is the sz key
    jne nh_one
    cmp dh, 2                       ; only layer 2 wants the capital sz
    jne nh_one
    mov word ptr cs:pending0, 1A53h   ; scan 1Ah, character 'S'
    mov word ptr cs:pending1, 1A53h   ; second 'S'
    mov byte ptr cs:npending, 2
    jmp nh_keep
nh_one:
    call load_layer                 ; AX = typeahead word, or 0 if empty
    or ax, ax
    jz nh_keep                       ; empty cell: keep the scan, emit nothing
    mov cs:pending0, ax
    mov byte ptr cs:npending, 1
    cmp ax, 5200h                   ; scan 52h, character 00h: Insert
    jne nh_keep
    xor byte ptr es:[17h], 80h      ; 80h is bit 7, the Insert flag
    jmp nh_keep
nh_alt:
    mov ah, bl                      ; high byte = the physical scan
    xor al, al                      ; low byte = 0, the BIOS Alt-key shape
    mov cs:pending0, ax
    mov byte ptr cs:npending, 1
    jmp nh_keep
nh_ctrl:
    mov dh, 1                       ; control character comes from layer 1
    call load_layer
    cmp al, 'a'
    jb nh_keep                       ; not a Neo letter: keep it, emit nothing
    cmp al, 'z'
    ja nh_keep
    and al, 1Fh                     ; 'a'..'z' to 01h..1Ah, Ctrl-A..Ctrl-Z
    mov ah, bl                      ; high byte stays the physical scan
    mov cs:pending0, ax
    mov byte ptr cs:npending, 1
nh_keep:
    clc                             ; caller keeps this scan byte
    jmp nh_leave
nh_pass:
    stc                             ; caller passes this scan byte to the BIOS
nh_leave:
    pop si
    pop es
    ret
neo_handle endp

; Decide whether BL is a modifier this driver owns. DL is 1 when it is.
; On the 102-key positions, Mod3 is Caps Lock (3Ah) and the # key (2Bh).
; Mod4 is the < key (56h) and AltGr (E0 38h). On the 83-key positions, Mod3
; is the key left of A (1Dh) and the # key (2Bh). Mod4 is Alt (38h).
; The wide key right of the space bar (3Ah) is not passed to the BIOS.
; Its make sets the Ctrl bits, 0040:0017 bit 2 and 0040:0018 bit 0, and
; its break clears them. A make that finds the key already down returns
; without toggling suspend or capitals. Suspend flips only on the make
; that finds the other Mod3 key already down.
claim_mod proc near
    xor dl, dl                      ; DL = 0 until a key is claimed
    cmp byte ptr cs:key83, 0
    jne cm_xt                       ; 83-key: Mod3 is 1Dh, not 3Ah
    cmp bl, 3Ah                     ; 102-key Mod3: Caps Lock
    jne cm_m3r
    jmp cm_m3a
cm_xt:
    cmp bl, 1Dh                     ; 83-key Mod3: the key left of A
    jne cm_m3r                      ; not it: 2Bh is the other Mod3 on both maps
cm_m3a:
    mov dl, 1                       ; claimed. The caller keeps the byte
    or bh, bh
    jnz cm_m3a_up                   ; BH = 80h: break, just clear the flag
    cmp byte ptr cs:mod3a, 0
    je cm_3a_new                    ; first make
    ret                             ; repeat: do not toggle suspend again
cm_3a_new:
    mov byte ptr cs:mod3a, 1
    cmp byte ptr cs:mod3b, 0
    jne cm_3a_both                  ; the other Mod3 is already down
    ret
cm_3a_both:
    xor byte ptr cs:suspended, 1       ; both Mod3 keys: flip suspend
    ret
cm_m3a_up:
    mov byte ptr cs:mod3a, 0
    jmp cm_ret
cm_m3r:
    cmp bl, 2Bh                     ; 2Bh is the # key, Mod3 on both maps
    jne cm_m4
    mov dl, 1
    or bh, bh
    jnz cm_m3b_up
    cmp byte ptr cs:mod3b, 0
    je cm_3b_new
    ret                             ; repeat of this Mod3 key
cm_3b_new:
    mov byte ptr cs:mod3b, 1
    cmp byte ptr cs:mod3a, 0
    jne cm_3b_both
    ret
cm_3b_both:
    xor byte ptr cs:suspended, 1
    ret
cm_m3b_up:
    mov byte ptr cs:mod3b, 0
    jmp cm_ret
cm_m4:
    cmp byte ptr cs:key83, 0
    jne cm_xt4                      ; 83-key Mod4 is Alt, not the < key
    cmp bl, 56h                     ; 102-key Mod4: the < key
    jne cm_agr
    mov dl, 1
    or bh, bh
    jnz cm_m4a_up
    mov byte ptr cs:mod4a, 1        ; a repeat just stores 1 again
    jmp cm_ret
cm_m4a_up:
    mov byte ptr cs:mod4a, 0
    jmp cm_ret
cm_agr:
    cmp byte ptr cs:seen_e0, 0
    je cm_ret                       ; 38h without E0 is left Alt: not ours
    cmp bl, 38h                     ; E0 38h is AltGr
    jne cm_ret
    mov dl, 1
    or bh, bh
    jnz cm_m4b_up
    mov byte ptr cs:mod4b, 1
    jmp cm_ret
cm_m4b_up:
    mov byte ptr cs:mod4b, 0
    jmp cm_ret
cm_xt4:
    cmp bl, 38h                     ; 83-key Mod4: Alt, no E0 on this keyboard
    jne cm_xtc
    mov dl, 1
    or bh, bh
    jnz cm_x4_up
    mov byte ptr cs:mod4b, 1
    jmp cm_ret
cm_x4_up:
    mov byte ptr cs:mod4b, 0
    jmp cm_ret
cm_xtc:
    cmp bl, 3Ah                     ; 83-key: wide key right of the space bar
    jne cm_ret                      ; not ours. DL is still 0
    mov dl, 1
    or bh, bh
    jnz cm_xc_up
    or byte ptr es:[17h], 04h       ; bit 2 of 0040:0017, Ctrl
    or byte ptr es:[18h], 01h       ; bit 0 of 0040:0018, left Ctrl
    jmp cm_ret
cm_xc_up:
    and byte ptr es:[17h], 0FBh     ; 0FBh = 11111011b, clear Ctrl
    and byte ptr es:[18h], 0FEh     ; 0FEh = 11111110b, clear left Ctrl
cm_ret:
    ret
claim_mod endp

; Carry set when BL is on the main typing block: the space bar, the key
; left of 1, the number row through the acute key, the three letter
; rows. The keypad, the function keys, and both Shift keys are outside
; these ranges.
is_typing_block proc near
    cmp bl, 39h                     ; space bar
    je tb_y
    cmp bl, 29h                     ; key left of 1
    je tb_y
    cmp bl, 02h                     ; below the 1 key: Esc and nothing
    jb tb_n
    cmp bl, 0Dh                     ; 1 through the acute key. 0Eh is Backspace
    jbe tb_y
    cmp bl, 10h                     ; 0Eh and 0Fh are Backspace and Tab
    jb tb_n
    cmp bl, 1Bh                     ; Q row through the + key. 1Ch is Enter
    jbe tb_y
    cmp bl, 1Eh                     ; 1Ch Enter, 1Dh Ctrl
    jb tb_n
    cmp bl, 28h                     ; A row through the ae key
    jbe tb_y
    cmp bl, 2Ch                     ; 2Ah is left Shift and 2Bh is the # key
    jb tb_n
    cmp bl, 35h                     ; Y row through J. 36h is right Shift
    jbe tb_y
tb_n:
    clc                             ; keypad, function keys, and Shift are outside
    ret
tb_y:
    stc
    ret
is_typing_block endp

; BL is the scan and DH is the layer, 1 through 6. AX comes back as the
; typeahead word, or zero when the cell is empty. E0 35h reads kpslash
; instead of the J row.
;
; A row is seven bytes, so the row address is laytab + scan*7. The
; multiply is three shifts and a subtract, which is all an 8086 can do
; with this factor. CX is saved around it. The caller keeps the Shift
; flags in CH and reads them after this returns. Layers 1, 2, and 3
; are bytes 0, 1, and 2. Layers 5 and 6 are bytes 3 and 4. A nonzero
; byte is returned with BL in the high half. Layer 4 is the word at
; byte 5 of the row. On an odd row that word is not aligned. An 8086
; reads it anyway.
load_layer proc near
    cmp byte ptr cs:seen_e0, 0
    je ll_main
    cmp bl, 35h                     ; E0 35h is keypad slash, not the J row
    jne ll_main
    mov si, OFFSET kpslash          ; SI = that one row. Skip scan*7
    jmp ll_idx
ll_main:
    cmp bl, 56h                     ; 56h is the < key, the last row
    ja ll_z                         ; F7 and above are not in the table
    mov al, bl                      ; AX = scan, zero-extended
    xor ah, ah
    push cx                         ; CH holds the Shift flags for the caller
    mov cx, ax                      ; CX = scan
    shl ax, 1
    shl ax, 1
    shl ax, 1                       ; AX = scan*8. 8086 has no shift-immediate
    sub ax, cx                      ; AX = scan*7, the row stride
    pop cx                          ; CH is the Shift flags again
    mov si, OFFSET laytab
    add si, ax                      ; SI = row for this scan
ll_idx:
    cmp dh, 4
    je ll_w4                        ; layer 4 is the word, not a character byte
    mov al, dh
    dec al                          ; layer 1, 2, 3 -> byte 0, 1, 2
    cmp dh, 4
    jb ll_add                       ; layers 1..3 need no further adjust
    dec al                          ; layer 5, 6 -> byte 3, 4 (the word is skipped)
ll_add:
    xor ah, ah
    add si, ax                      ; SI = the character byte
    mov al, cs:[si]
    or al, al
    jz ll_z                         ; 00h: empty cell
    mov ah, bl                      ; AH = this row's scan, AL = character
    ret
ll_w4:
    mov ax, cs:[si+5]               ; the layer 4 word. Odd rows are unaligned
    ret
ll_z:
    xor ax, ax                      ; empty: caller emits nothing
    ret
load_layer endp

; Carry set when this keypad scan should follow the Neo layer. With
; neither Mod3 nor Mod4 down, the keypad stays with the BIOS. The
; claimed scans are * (37h), Num Lock (45h), 7 through Del (47h through
; 53h), and keypad slash (E0 35h). The gray arrow keys are E0 plus an
; arrow scan. They fail the E0 test here, so they stay arrows.
kp_layer proc near
    mov al, cs:mod3a
    or al, cs:mod3b
    or al, cs:mod4a
    or al, cs:mod4b                 ; AL nonzero if any Mod key is down
    jz kp_no                        ; none: the keypad stays with the BIOS
    cmp byte ptr cs:seen_e0, 0
    jne kp_ext                      ; E0: only slash is claimed, not gray arrows
    cmp bl, 37h                     ; keypad *
    je kp_yes
    cmp bl, 45h                     ; Num Lock
    je kp_yes
    cmp bl, 47h                     ; 47h is keypad 7 / Home
    jb kp_no                        ; 46h is Scroll Lock, not claimed
    cmp bl, 53h                     ; 53h is keypad Del
    ja kp_no
kp_yes:
    stc                             ; caller treats BL as a Neo key
    ret
kp_ext:
    cmp bl, 35h                     ; E0 35h keypad slash. E0 48h is a gray arrow
    je kp_yes
kp_no:
    clc
    ret
kp_layer endp

; Carry set when AL is a letter for the capital rule: a through z, or
; ue, ae, oe, or sz on layer 1.
is_letter proc near
    cmp al, 'a'
    jb il_g                         ; digits and punctuation are not letters
    cmp al, 'z'
    ja il_g
    stc
    ret
il_g:
    cmp al, 81h                     ; CP437 ue
    je il_y
    cmp al, 84h                     ; ae
    je il_y
    cmp al, 94h                     ; oe
    je il_y
    cmp al, 0E1h                    ; sz
    je il_y
    clc                             ; a non-letter uses Shift directly, no caps xor
    ret
il_y:
    stc
    ret
is_letter endp

; Write the one or two words neo_handle prepared. A full typeahead
; buffer does not store the word. The caller has already decided to
; keep the scan byte, so the key is not passed back when the buffer
; cannot take it.
flush_words proc near
    cmp byte ptr cs:npending, 0
    je fw_ret                       ; kept key with an empty cell
    mov ax, cs:pending0               ; AX = character in AL, scan in AH
    call store_word                    ; carry set means the buffer was full
    cmp byte ptr cs:npending, 2
    jb fw_ret                       ; one word is the normal key
    mov ax, cs:pending1               ; second word is the second S of SS
    call store_word                    ; full buffer: word not stored; the scan stays kept
fw_ret:
    ret
flush_words endp

; Store AX in the BIOS typeahead. Carry set means the buffer was full
; and the word was not stored. The buffer is a ring of words, low byte
; character and high byte scan. Its start and end are 0040:0080 and
; 0040:0082 on a machine that has relocated it. Those two words are
; trusted only when the start is at least 001Eh, the end is above the
; start and at most 00A0h, and both are even. Otherwise the buffer is
; the original 001Eh through 003Eh. The head is 0040:001A and the tail
; is 0040:001C. The next tail is where the word is written. If that
; next tail would meet the head, the buffer is full.
;
; Interrupts are off for the update and are then restored to whatever
; state the caller had. POPF restores that state, and a later POP does
; not change the flags, so the full-or-empty result is held in BP and
; tested after BP itself is popped. This routine does not enable
; interrupts on its own. The keyboard interrupt is already running with
; them off, and it should stay that way until the BIOS is finished.
store_word proc near
    push bp
    push ds
    push bx
    push cx
    push dx
    push di
    pushf
    cli
    mov bx, 40h
    mov ds, bx                      ; DS = BIOS data. Offsets below are from 0040h
    mov bx, ds:[80h]                ; 0040:0080, buffer start, if the BIOS moved it
    mov cx, ds:[82h]                ; 0040:0082, buffer end
    cmp bx, 1Eh
    jb st_def                      ; start below 001Eh is not the keyboard buffer
    cmp cx, bx
    jbe st_def                     ; end must be above the start
    cmp cx, 0A0h
    ja st_def                      ; end past 00A0h is outside the BIOS data area
    test bl, 1
    jnz st_def                     ; a word buffer is even
    test cl, 1
    jnz st_def
    jmp st_have                    ; BX = start, CX = end
st_def:
    mov bx, 1Eh                     ; original buffer, 0040:001E
    mov cx, 3Eh                     ; through 0040:003E
st_have:
    mov di, ds:[1Ch]                ; DI = tail, the next word to fill
    mov dx, di
    add dx, 2                       ; DX = the tail after this word
    cmp dx, cx
    jb st_nw                       ; still inside the buffer
    mov dx, bx                      ; wrapped to the start
st_nw:
    cmp dx, ds:[1Ah]                ; 0040:001A is the head
    je st_full                     ; next tail would meet the head
    mov [di], ax                    ; store character, then scan
    mov ds:[1Ch], dx                ; publish the new tail
    xor bp, bp                      ; BP = 0: stored. POP does not change flags
    jmp st_out
st_full:
    mov bp, 1                       ; BP = 1: the word was not stored
st_out:
    popf                            ; interrupts back to the caller's state
    pop di
    pop dx
    pop cx
    pop bx
    pop ds
    or bp, bp                       ; test the saved result, now that BP is free
    pop bp
    jnz st_stc                     ; the OR result survives the POP
    clc
    ret
st_stc:
    stc                             ; caller ignores this; the scan is already kept
    ret
store_word endp

; Stack for the keyboard interrupt and for the INT 21h that ends
; installation. The installer points SS:SP at resident_end only after
; the banner has been printed and the open handles have been closed.
    dw 64 dup (0)
resident_end:

; From here on, nothing stays resident. NEOCMD.C is linked after this
; point and calls the wrappers below. A wrapper does one interrupt or
; one memory access. The C code decides what to print and which command
; to run. go_resident does not return.

EXTRN _neo_main:NEAR

init:
    call _neo_main
    mov ax, 4C00h
    int 21h

; Turbo C passes arguments on the stack and expects a near return value
; in AX. SI and DI belong to the caller. A byte argument arrives as a
; word; the value is in the low half.

public _dos_exit
_dos_exit proc near
    push bp
    mov bp, sp
    mov al, [bp+4]
    mov ah, 4Ch
    int 21h
_dos_exit endp

public _putch
_putch proc near
    push bp
    mov bp, sp
    mov dl, [bp+4]
    mov ah, 02h
    int 21h
    pop bp
    ret
_putch endp

public _print
_print proc near
    push bp
    mov bp, sp
    mov dx, [bp+4]
    mov ah, 09h
    int 21h
    pop bp
    ret
_print endp

public _peekb
_peekb proc near
    push bp
    mov bp, sp
    push es
    mov es, [bp+4]
    mov bx, [bp+6]
    mov al, es:[bx]
    xor ah, ah
    pop es
    pop bp
    ret
_peekb endp

public _pokeb
_pokeb proc near
    push bp
    mov bp, sp
    push es
    mov es, [bp+4]
    mov bx, [bp+6]
    mov al, [bp+8]
    mov es:[bx], al
    pop es
    pop bp
    ret
_pokeb endp

public _peekw
_peekw proc near
    push bp
    mov bp, sp
    push es
    mov es, [bp+4]
    mov bx, [bp+6]
    mov ax, es:[bx]
    pop es
    pop bp
    ret
_peekw endp

public _pokew
_pokew proc near
    push bp
    mov bp, sp
    push es
    mov es, [bp+4]
    mov bx, [bp+6]
    mov ax, [bp+8]
    mov es:[bx], ax
    pop es
    pop bp
    ret
_pokew endp

; Carry set means the BIOS keeps this scan byte. neo_handle leaves the
; carry flag set for that and clear when this driver keeps the byte.
public _run_scan
_run_scan proc near
    push bp
    mov bp, sp
    mov al, [bp+4]                  ; C passes the scan as a word; the byte is in AL
    call neo_handle                 ; carry survives the near RET
    jc rs_pass                      ; carry set: BIOS would keep the byte
    xor ax, ax                      ; AX = 0: this driver kept it
    jmp rs_out
rs_pass:
    mov ax, 1                       ; AX = 1: the byte is passed through
rs_out:
    pop bp
    ret
_run_scan endp

; Carry set means the typeahead buffer was full and the word was not
; stored. store_word saves and restores DS.
public _store_word
_store_word proc near
    push bp
    mov bp, sp
    mov ax, [bp+4]                  ; the typeahead word
    call store_word
    jc ws_full                      ; carry set: the ring was full
    xor ax, ax
    jmp ws_out
ws_full:
    mov ax, 1
ws_out:
    pop bp
    ret
_store_word endp

; AH=35h returns the vector in ES:BX. BX is not saved across that call:
; the vector offset is the value the call returns there.
public _read_vector
_read_vector proc near
    push bp
    mov bp, sp
    push di
    mov ax, [bp+4]                  ; AL = vector number, 09h or 15h
    mov ah, 35h                     ; DOS get interrupt vector
    int 21h                         ; returns ES:BX. BX is not saved across it
    mov di, [bp+6]                  ; pointer to the offset word
    mov [di], bx
    mov di, [bp+8]                  ; pointer to the segment word
    mov [di], es
    pop di
    pop bp
    ret
_read_vector endp

; INT 15h AH=C0h returns its table in ES:BX. BX must not be saved across
; that interrupt. AX is 1 when feature bit 4 is set, which means the
; BIOS calls INT 15h AH=4Fh.
public _has_4f
_has_4f proc near
    push si
    push di
    mov ah, 0C0h                    ; return the BIOS configuration table
    stc                             ; a BIOS that ignores C0h leaves carry set
    int 15h                         ; ES:BX = table. Do not push BX around this
    jc no_4f                        ; no table
    test byte ptr es:[bx+5], 10h    ; feature byte 1, bit 4: INT 15h AH=4Fh
    jz no_4f
    mov ax, 1
    jmp out_4f
no_4f:
    xor ax, ax                      ; AX = 0: hook INT 09h instead
out_4f:
    pop di
    pop si
    ret
_has_4f endp

; Restore the saved vector, free the resident PSP, then free the
; environment at that PSP's offset 2Ch when the word is not zero. DS is
; the BIOS segment during the vector write, and it is this program's
; segment again before the return, so the caller can print.
public _remove_neo
_remove_neo proc near
    push bp
    mov bp, sp
    push si
    mov es, [bp+4]                  ; ES = resident PSP / segment
    mov bx, [bp+6]                  ; BX = hooked entry
    mov si, es:[bx-2]               ; SI = neo_state offset in that segment
    mov ax, es:[2Ch]                ; PSP:002Ch is the environment segment
    mov cs:envseg, ax
    mov dx, es:[si + (saved_off - neo_state)]  ; DX = saved vector offset
    mov cx, es:[si + (saved_seg - neo_state)]  ; CX = saved vector segment
    push es                         ; keep the resident PSP across the set-vector
    mov ds, cx                      ; AH=25h reads DS:DX
    mov ax, 2509h                   ; default: put back INT 09h
    cmp byte ptr es:[si + (hook15 - neo_state)], 0
    je rm_set                       ; hook15 = 0: it was INT 09h
    mov ax, 2515h                   ; hook15 = 1: it was INT 15h
rm_set:
    cli
    int 21h
    sti
    pop es                          ; ES = resident PSP again
    mov ah, 49h                     ; free that memory block
    int 21h
    push cs
    pop ds                          ; DS = this transient program, for the caller
    mov ax, cs:envseg
    or ax, ax
    jz rm_done                      ; no environment paragraph
    mov es, ax
    mov ah, 49h                     ; free the environment
    int 21h
rm_done:
    pop si
    pop bp
    ret
_remove_neo endp

; Hook INT 15h or INT 09h, close handles 0 through 19, move the stack to
; resident_end, and stay resident. The banner has already been printed.
; The argument is read before the stack moves. This does not return.
public _go_resident
_go_resident proc near
    push bp
    mov bp, sp
    cmp word ptr [bp+4], 0
    je gr_09                        ; argument 0: the BIOS has no AH=4Fh
    mov byte ptr cs:hook15, 1       ; remember that the hooked vector is 15h
    mov ax, 3515h                   ; read the current INT 15h
    int 21h                         ; ES:BX = BIOS handler
    mov cs:saved_off, bx
    mov cs:saved_seg, es
    cli
    push ds
    push cs
    pop ds                          ; AH=25h takes the new handler from DS:DX
    mov dx, OFFSET neo15
    mov ax, 2515h
    int 21h
    pop ds
    sti
    jmp gr_close
gr_09:
    mov byte ptr cs:hook15, 0
    mov ax, 3509h
    int 21h
    mov cs:saved_off, bx
    mov cs:saved_seg, es
    cli
    push ds
    push cs
    pop ds
    mov dx, OFFSET neo09
    mov ax, 2509h
    int 21h
    pop ds
    sti
gr_close:
    xor bx, bx                      ; BX = handle. 0 is stdin
gr_loop:
    mov ah, 3Eh                     ; close. A failure is ignored
    int 21h
    inc bx
    cmp bx, 20                      ; handles 0 through 19. 20 decimal
    jb gr_loop                      ; leave stdout closed so AH=31h cannot keep it
    cli
    mov ax, cs
    mov ss, ax                      ; the DOS stack is about to be freed
    mov sp, OFFSET resident_end     ; the 64 words just below this label
    sti
    mov dx, OFFSET resident_end
    add dx, 15                      ; round the offset up
    mov cl, 4
    shr dx, cl                      ; DX = paragraphs from the PSP, which is CS
    mov ax, 3100h                   ; stay resident, exit code 0. Does not return
    int 21h
_go_resident endp

envseg dw 0

END start
