; Neo, layers 1-6, for the IBM 5160 and later PCs.
;
; Read this file from the top. A keystroke executes only the resident
; driver, which ends at resident_end. The installer, the status report,
; and the self-test follow that label. DOS releases them when the
; driver stays resident.
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
; An E0 prefix is given to the BIOS. The byte after it is kept only when
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
    jmp init

; A resident copy is recognized by the four bytes NEO2 placed
; immediately in front of the hooked entry. The word after those bytes
; is the offset of neo_state in the resident segment. Install, status,
; and unload follow that word, so they never use an address taken from
; the transient copy.
    db 'NEO2'
    dw OFFSET neo_state
; INT 15h. AH is the BIOS function. Anything other than 4Fh is returned
; to the saved vector at once. A 4Fh call is one scan byte, make or
; break, in AL. The BIOS has already read port 60h, and this path must
; not read it: the read would empty the controller.
;
; fingers = 0 is the 102-key map, and only that map consults the prefix
; flags at 0040:0096. Bit 0 is the E1 prefix and bit 1 is E0. An E1
; sequence is given back. An E0 byte sets seen_e0 for the decision
; below. When the byte is eaten, both prefix bits are cleared.
;
; give holds the carry decision across the register restores. After
; push bp / mov bp,sp the saved flags of this interrupt are at [bp+6].
; Clearing bit 0 of that word clears carry.
neo15:
    cmp ah, 4Fh
    je n15_body
    jmp dword ptr cs:oldptr
n15_body:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push ds
    push es
    inc word ptr cs:hits
    mov bx, 40h
    mov es, bx
    mov byte ptr cs:seen_e0, 0
    cmp byte ptr cs:fingers, 0
    jne n15_go
    test byte ptr es:[96h], 1
    jnz n15_pass
    test byte ptr es:[96h], 2
    jz n15_go
    mov byte ptr cs:seen_e0, 1
n15_go:
    call neo_handle
    jc n15_pass
    inc word ptr cs:eaten
    cmp byte ptr cs:fingers, 0
    jne n15_store
    and byte ptr es:[96h], 0FCh
n15_store:
    call flush_words
    mov byte ptr cs:give, 0
    jmp n15_done
n15_pass:
    mov byte ptr cs:give, 1
n15_done:
    pop es
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    cmp byte ptr cs:give, 0
    jne n15_iret
    push bp
    mov bp, sp
    and byte ptr [bp+6], 0FEh
    pop bp
n15_iret:
    iret

    db 'NEO2'
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
    inc word ptr cs:hits
    in al, 60h
    mov byte ptr cs:seen_e0, 0
    call neo_handle
    jc n09_pass
    inc word ptr cs:eaten
    in al, 61h
    mov ah, al
    or al, 80h
    out 61h, al
    mov al, ah
    out 61h, al
    call flush_words
    mov al, 20h
    out 20h, al
    pop es
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    iret
n09_pass:
    pop es
    pop ds
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    jmp dword ptr cs:oldptr

; Resident variables. A command that finds an already resident copy
; adds these offsets to the neo_state pointer stored in front of the
; hook.
;
; fingers is 0 for the 102-key map and 1 for the 83-key map. mod3a and
; mod3b are the two Mod3 keys. mod4a and mod4b are the two Mod4 keys.
; A held key repeats, and a repeat must not toggle capitals or suspend,
; so the flag remembers that the key is already down. caps is this
; driver's capital state. BIOS bit 6 of 0040:0017 is kept in step with
; it, and the Caps Lock scan is never passed through, so the BIOS does
; not fight that bit. paused is suspend: both Mod3 keys together invert
; it. nout, nword0, and nword1 are the characters waiting to be written.
; hits counts scan bytes seen, and eaten counts bytes this driver kept.
; oldptr is the BIOS vector that was replaced. hook15 says which vector
; that was. modelb is the byte at F000:FFFE.

neo_state:
fingers db 0
mod3a   db 0
mod3b   db 0
mod4a   db 0
mod4b   db 0
caps    db 0
paused  db 0
seen_e0 db 0
nout    db 0
give    db 0
nword0  dw 0
nword1  dw 0
hits    dw 0
eaten   dw 0
oldptr  label dword
oldoff  dw 0
oldseg  dw 0
hook15  db 0
modelb  db 0

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
laytab:
    db 00h, 00h, 00h, 00h, 00h  ; 00
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 01
    dw 0000h
    db 31h, 0F8h, 00h, 00h, 0AAh  ; 02
    dw 02A6h
    db 32h, 15h, 0FDh, 00h, 00h  ; 03
    dw 03A7h
    db 33h, 00h, 00h, 00h, 00h  ; 04
    dw 0000h
    db 34h, 0AFh, 00h, 00h, 00h  ; 05
    dw 0000h
    db 35h, 0AEh, 00h, 00h, 00h  ; 06
    dw 06FAh
    db 36h, 24h, 9Bh, 00h, 00h  ; 07
    dw 079Ch
    db 37h, 00h, 9Dh, 00h, 00h  ; 08
    dw 0000h
    db 38h, 00h, 00h, 00h, 0ECh  ; 09
    dw 0F09h
    db 39h, 00h, 00h, 00h, 00h  ; 0A
    dw 0A2Fh
    db 30h, 00h, 00h, 00h, 00h  ; 0B
    dw 0B2Ah
    db 2Dh, 2Dh, 00h, 00h, 00h  ; 0C
    dw 4A2Dh
    db 60h, 00h, 00h, 00h, 00h  ; 0D
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 0E
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 0F
    dw 0000h
    db 78h, 58h, 00h, 00h, 00h  ; 10
    dw 4900h
    db 76h, 56h, 5Fh, 00h, 0FBh  ; 11
    dw 0E08h
    db 6Ch, 4Ch, 5Bh, 00h, 00h  ; 12
    dw 4800h
    db 63h, 43h, 5Dh, 00h, 00h  ; 13
    dw 5300h
    db 77h, 57h, 5Eh, 00h, 0EAh  ; 14
    dw 5100h
    db 6Bh, 4Bh, 21h, 00h, 00h  ; 15
    dw 15ADh
    db 68h, 48h, 3Ch, 00h, 00h  ; 16
    dw 4737h
    db 67h, 47h, 3Eh, 00h, 0E2h  ; 17
    dw 4838h
    db 66h, 46h, 3Dh, 0EDh, 0E8h  ; 18
    dw 4939h
    db 71h, 51h, 26h, 00h, 00h  ; 19
    dw 4E2Bh
    db 0E1h, 00h, 00h, 00h, 00h  ; 1A
    dw 4A2Dh
    db 27h, 00h, 2Fh, 00h, 00h  ; 1B
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 1C
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 1D
    dw 0000h
    db 75h, 55h, 5Ch, 00h, 00h  ; 1E
    dw 4700h
    db 69h, 49h, 2Fh, 00h, 00h  ; 1F
    dw 4B00h
    db 61h, 41h, 7Bh, 0E0h, 00h  ; 20
    dw 5000h
    db 65h, 45h, 7Dh, 0EEh, 00h  ; 21
    dw 4D00h
    db 6Fh, 4Fh, 2Ah, 00h, 00h  ; 22
    dw 4F00h
    db 73h, 53h, 3Fh, 0E5h, 0E4h  ; 23
    dw 23A8h
    db 6Eh, 4Eh, 28h, 00h, 00h  ; 24
    dw 4B34h
    db 72h, 52h, 29h, 00h, 00h  ; 25
    dw 4C35h
    db 74h, 54h, 2Dh, 0E7h, 00h  ; 26
    dw 4D36h
    db 64h, 44h, 3Ah, 0EBh, 00h  ; 27
    dw 272Ch
    db 79h, 59h, 40h, 00h, 00h  ; 28
    dw 282Eh
    db 5Eh, 00h, 00h, 00h, 2Eh  ; 29
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 2A
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 2B
    dw 0000h
    db 81h, 9Ah, 23h, 00h, 00h  ; 2C
    dw 011Bh
    db 94h, 99h, 24h, 00h, 0EFh  ; 2D
    dw 0F09h
    db 84h, 8Eh, 7Ch, 00h, 00h  ; 2E
    dw 5200h
    db 70h, 50h, 7Eh, 0E3h, 00h  ; 2F
    dw 1C0Dh
    db 7Ah, 5Ah, 60h, 00h, 00h  ; 30
    dw 0000h
    db 62h, 42h, 2Bh, 00h, 00h  ; 31
    dw 313Ah
    db 6Dh, 4Dh, 25h, 0E6h, 00h  ; 32
    dw 4F31h
    db 2Ch, 2Dh, 22h, 00h, 00h  ; 33
    dw 5032h
    db 2Eh, 00h, 27h, 00h, 00h  ; 34
    dw 5133h
    db 6Ah, 4Ah, 3Bh, 00h, 0E9h  ; 35
    dw 353Bh
    db 00h, 00h, 00h, 00h, 00h  ; 36
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 37
    dw 0000h
    db 00h, 00h, 00h, 00h, 00h  ; 38
    dw 0000h
    db 20h, 20h, 20h, 0FFh, 00h  ; 39
    dw 5230h
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
    db 00h, 00h, 3Dh, 0F7h, 0F0h  ; 45
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
    db 00h, 00h, 3Ah, 00h, 00h  ; 4C
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
    db 00h, 00h, 25h, 00h, 00h  ; 52
    dw 5200h
    db 00h, 00h, 2Ch, 00h, 00h  ; 53
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
; Carry set tells the caller to give the byte to the BIOS. Carry clear
; tells the caller to drop it. nout is then 0, 1, or 2, and nword0 and
; nword1 are the typeahead words.
neo_handle proc near
    mov bl, al
    and bl, 7Fh
    mov bh, al
    and bh, 80h
    push es
    push si
    mov ax, 40h
    mov es, ax
    mov byte ptr cs:nout, 0
    mov word ptr cs:nword0, 0
    mov word ptr cs:nword1, 0
; E0 2Ah is the fake left shift around a Num Lock arrow, and it is not
; treated as Shift. Every other byte is offered to try_mod. A modifier
; this driver owns is eaten, break as well as make.
    cmp byte ptr cs:seen_e0, 0
    je nh_mods
    cmp bl, 2Ah
    jne nh_mods
    jmp nh_pass
nh_mods:
    call try_mod
    or dl, dl
    jz nh_notmod
    jmp nh_eat
; Suspend gives character keys back to the BIOS. Mod3 and Mod4 were
; already eaten, so a suspended driver does not release those keys.
nh_notmod:
    cmp byte ptr cs:paused, 0
    je nh_run
    jmp nh_pass
; A Shift make toggles capitals when that Shift's bit is already set in
; 0040:0017 and the other Shift bit is clear. The first make still has
; a clear bit, so it is passed through and the BIOS records it. A later
; make of the same key, which is what the keyboard sends while the key
; is held, finds the bit set and toggles. If both Shift bits are already
; set, the make is passed through and capitals stay as they are. Bit 0
; is right Shift and bit 1 is left Shift. caps and BIOS bit 6 are
; inverted together. The Shift scan is then passed through.
nh_run:
    cmp bl, 2Ah
    je nh_shift
    cmp bl, 36h
    jne nh_own
nh_shift:
    or bh, bh
    jz nh_shmake
    jmp nh_pass
nh_shmake:
    mov al, es:[17h]
    cmp bl, 2Ah
    jne nh_shr
    test al, 01h
    jz nh_shleft
    jmp nh_pass
nh_shleft:
    test al, 02h
    jnz nh_tog
    jmp nh_pass
nh_shr:
    test al, 02h
    jz nh_shright
    jmp nh_pass
nh_shright:
    test al, 01h
    jnz nh_tog
    jmp nh_pass
; The main typing block is owned on make and on break. The break of an
; owned key is eaten and produces nothing. E0 35h is the keypad slash
; rather than J, and the keypad scans are owned only while Mod3 or Mod4
; is down. With neither Mod key down, those scans go to the BIOS.
nh_own:
    cmp byte ptr cs:seen_e0, 0
    je nh_ownb
    cmp bl, 35h
    jne nh_ownb
    call kp_layer
    jc nh_isown
    jmp nh_pass
nh_ownb:
    call owned_p
    jc nh_isown
    call kp_layer
    jc nh_isown
    jmp nh_pass
nh_isown:
    or bh, bh
    jz nh_char
    jmp nh_eat
nh_tog:
    xor byte ptr cs:caps, 1
    xor byte ptr es:[17h], 40h
    jmp nh_pass
; Choose the layer. Mod3 and Mod4 together are layer 6, ahead of either
; key alone. Mod4 alone is layer 4. Mod3 with a Shift bit set is layer
; 5, and that is its own layer: the capital xor is not applied on top.
; Mod3 alone is layer 3. The Shift bits are copied to CH. load_layer
; has to preserve CX, because the letter path tests CH after it returns.
nh_char:
    mov ch, es:[17h]
    mov al, cs:mod4a
    or al, cs:mod4b
    mov dl, al
    mov al, cs:mod3a
    or al, cs:mod3b
    mov cl, al
    or al, dl
    jz nh_nomod
    or cl, cl
    jz nh_only4
    or dl, dl
    jz nh_only3
    mov dh, 6
    jmp nh_pick
nh_only4:
    mov dh, 4
    jmp nh_pick
nh_only3:
    test ch, 03h
    jz nh_m3
    mov dh, 5
    jmp nh_pick
nh_m3:
    mov dh, 3
    jmp nh_pick
; Neither Mod key is down. Ctrl and Alt together are passed through, so
; Ctrl+Alt+Del still reaches the BIOS on the 102-key map. Alt alone
; writes a zero character with the physical scan in the high byte, the
; same shape the BIOS uses for an Alt combination. Ctrl on a layer-1
; letter writes the control character of that Neo letter. Ctrl on any
; other cell is eaten. This block is not used while Mod3 is down, so
; Mod3 wins over Ctrl.
;
; With neither Ctrl nor Alt, layer 1 is loaded and the character is
; classified. A letter then uses layer 2 when caps xor the Shift bits is
; 1. A non-letter uses layer 2 when a Shift bit is set, with no capital
; xor. A letter is a-z, or one of the four layer-1 German bytes: ue
; (81h), ae (84h), oe (94h), and sz (E1h).
nh_nomod:
    test ch, 04h
    jz nh_noctl
    test ch, 08h
    jz nh_noctl
    jmp nh_pass
nh_noctl:
    test ch, 08h
    jnz nh_alt
    test ch, 04h
    jnz nh_ctrl
    mov dh, 1
    call load_layer
    mov cl, al
    call is_letter
    jc nh_let
    test ch, 03h
    jz nh_pick
    mov dh, 2
    jmp nh_pick
nh_let:
    mov ah, 0
    test ch, 03h
    jz nh_ns
    mov ah, 1
nh_ns:
    mov al, cs:caps
    xor al, ah
    jz nh_low
    mov dh, 2
    jmp nh_pick
nh_low:
    mov dh, 1
; Shift on sz has no single capital in this font, so it writes S and
; then S, both under the sz scan. Every other cell is loaded once. An
; empty cell writes nothing and does not fall back to another layer.
; The Insert word 5200h also toggles bit 7 of 0040:0017. Delete is
; 5300h and changes no flag.
nh_pick:
    cmp bl, 1Ah
    jne nh_one
    cmp dh, 2
    jne nh_one
    mov word ptr cs:nword0, 1A53h
    mov word ptr cs:nword1, 1A53h
    mov byte ptr cs:nout, 2
    jmp nh_eat
nh_one:
    call load_layer
    or ax, ax
    jz nh_eat
    mov cs:nword0, ax
    mov byte ptr cs:nout, 1
    cmp ax, 5200h
    jne nh_eat
    xor byte ptr es:[17h], 80h
    jmp nh_eat
nh_alt:
    mov ah, bl
    xor al, al
    mov cs:nword0, ax
    mov byte ptr cs:nout, 1
    jmp nh_eat
nh_ctrl:
    mov dh, 1
    call load_layer
    cmp al, 'a'
    jb nh_eat
    cmp al, 'z'
    ja nh_eat
    and al, 1Fh
    mov ah, bl
    mov cs:nword0, ax
    mov byte ptr cs:nout, 1
nh_eat:
    clc
    jmp nh_leave
nh_pass:
    stc
nh_leave:
    pop si
    pop es
    ret
neo_handle endp

; Decide whether BL is a modifier this driver owns. DL is 1 when it is.
; On the 102-key map, Mod3 is Caps Lock (3Ah) and the # key (2Bh).
; Mod4 is the < key (56h) and AltGr (E0 38h). On the 83-key map, Mod3
; is the key left of A (1Dh) and the # key (2Bh). Mod4 is Alt (38h).
; The wide key right of the space bar (3Ah) is not passed to the BIOS.
; Its make sets the Ctrl bits, 0040:0017 bit 2 and 0040:0018 bit 0, and
; its break clears them. A make that finds the key already down returns
; without toggling suspend or capitals. Suspend flips only on the make
; that finds the other Mod3 key already down.
try_mod proc near
    xor dl, dl
    cmp byte ptr cs:fingers, 0
    jne tm_xt
    cmp bl, 3Ah
    jne tm_m3r
    jmp tm_m3a
tm_xt:
    cmp bl, 1Dh
    jne tm_m3r
tm_m3a:
    mov dl, 1
    or bh, bh
    jnz tm_m3a_up
    cmp byte ptr cs:mod3a, 0
    je tm_3a_new
    ret
tm_3a_new:
    mov byte ptr cs:mod3a, 1
    cmp byte ptr cs:mod3b, 0
    jne tm_3a_both
    ret
tm_3a_both:
    xor byte ptr cs:paused, 1
    ret
tm_m3a_up:
    mov byte ptr cs:mod3a, 0
    jmp tm_ret
tm_m3r:
    cmp bl, 2Bh
    jne tm_m4
    mov dl, 1
    or bh, bh
    jnz tm_m3b_up
    cmp byte ptr cs:mod3b, 0
    je tm_3b_new
    ret
tm_3b_new:
    mov byte ptr cs:mod3b, 1
    cmp byte ptr cs:mod3a, 0
    jne tm_3b_both
    ret
tm_3b_both:
    xor byte ptr cs:paused, 1
    ret
tm_m3b_up:
    mov byte ptr cs:mod3b, 0
    jmp tm_ret
tm_m4:
    cmp byte ptr cs:fingers, 0
    jne tm_xt4
    cmp bl, 56h
    jne tm_agr
    mov dl, 1
    or bh, bh
    jnz tm_m4a_up
    mov byte ptr cs:mod4a, 1
    jmp tm_ret
tm_m4a_up:
    mov byte ptr cs:mod4a, 0
    jmp tm_ret
tm_agr:
    cmp byte ptr cs:seen_e0, 0
    je tm_ret
    cmp bl, 38h
    jne tm_ret
    mov dl, 1
    or bh, bh
    jnz tm_m4b_up
    mov byte ptr cs:mod4b, 1
    jmp tm_ret
tm_m4b_up:
    mov byte ptr cs:mod4b, 0
    jmp tm_ret
tm_xt4:
    cmp bl, 38h
    jne tm_xtc
    mov dl, 1
    or bh, bh
    jnz tm_x4_up
    mov byte ptr cs:mod4b, 1
    jmp tm_ret
tm_x4_up:
    mov byte ptr cs:mod4b, 0
    jmp tm_ret
tm_xtc:
    cmp bl, 3Ah
    jne tm_ret
    mov dl, 1
    or bh, bh
    jnz tm_xc_up
    or byte ptr es:[17h], 04h
    or byte ptr es:[18h], 01h
    jmp tm_ret
tm_xc_up:
    and byte ptr es:[17h], 0FBh
    and byte ptr es:[18h], 0FEh
tm_ret:
    ret
try_mod endp

; Carry set when BL is on the main typing block: the space bar, the key
; left of 1, the number row through the acute key, the three letter
; rows. The keypad, the function keys, and both Shift keys are outside
; these ranges.
owned_p proc near
    cmp bl, 39h
    je ow_y
    cmp bl, 29h
    je ow_y
    cmp bl, 02h
    jb ow_n
    cmp bl, 0Dh
    jbe ow_y
    cmp bl, 10h
    jb ow_n
    cmp bl, 1Bh
    jbe ow_y
    cmp bl, 1Eh
    jb ow_n
    cmp bl, 28h
    jbe ow_y
    cmp bl, 2Ch
    jb ow_n
    cmp bl, 35h
    jbe ow_y
ow_n:
    clc
    ret
ow_y:
    stc
    ret
owned_p endp

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
    cmp bl, 35h
    jne ll_main
    mov si, OFFSET kpslash
    jmp ll_idx
ll_main:
    cmp bl, 56h
    ja ll_z
    mov al, bl
    xor ah, ah
    push cx
    mov cx, ax
    shl ax, 1
    shl ax, 1
    shl ax, 1
    sub ax, cx
    pop cx
    mov si, OFFSET laytab
    add si, ax
ll_idx:
    cmp dh, 4
    je ll_w4
    mov al, dh
    dec al
    cmp dh, 4
    jb ll_add
    dec al
ll_add:
    xor ah, ah
    add si, ax
    mov al, cs:[si]
    or al, al
    jz ll_z
    mov ah, bl
    ret
ll_w4:
    mov ax, cs:[si+5]
    ret
ll_z:
    xor ax, ax
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
    or al, cs:mod4b
    jz kp_no
    cmp byte ptr cs:seen_e0, 0
    jne kp_ext
    cmp bl, 37h
    je kp_yes
    cmp bl, 45h
    je kp_yes
    cmp bl, 47h
    jb kp_no
    cmp bl, 53h
    ja kp_no
kp_yes:
    stc
    ret
kp_ext:
    cmp bl, 35h
    je kp_yes
kp_no:
    clc
    ret
kp_layer endp

; Carry set when AL is a letter for the capital rule: a through z, or
; ue, ae, oe, or sz on layer 1.
is_letter proc near
    cmp al, 'a'
    jb il_g
    cmp al, 'z'
    ja il_g
    stc
    ret
il_g:
    cmp al, 81h
    je il_y
    cmp al, 84h
    je il_y
    cmp al, 94h
    je il_y
    cmp al, 0E1h
    je il_y
    clc
    ret
il_y:
    stc
    ret
is_letter endp

; Write the one or two words neo_handle prepared. A full typeahead
; buffer drops the word. The caller has already decided to eat the scan
; byte, so the key is not handed back when the buffer cannot take it.
flush_words proc near
    cmp byte ptr cs:nout, 0
    je fw_ret
    mov ax, cs:nword0
    call neo_put
    cmp byte ptr cs:nout, 2
    jb fw_ret
    mov ax, cs:nword1
    call neo_put
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
neo_put proc near
    push bp
    push ds
    push bx
    push cx
    push dx
    push di
    pushf
    cli
    mov bx, 40h
    mov ds, bx
    mov bx, ds:[80h]
    mov cx, ds:[82h]
    cmp bx, 1Eh
    jb put_def
    cmp cx, bx
    jbe put_def
    cmp cx, 0A0h
    ja put_def
    test bl, 1
    jnz put_def
    test cl, 1
    jnz put_def
    jmp put_have
put_def:
    mov bx, 1Eh
    mov cx, 3Eh
put_have:
    mov di, ds:[1Ch]
    mov dx, di
    add dx, 2
    cmp dx, cx
    jb put_nw
    mov dx, bx
put_nw:
    cmp dx, ds:[1Ah]
    je put_full
    mov [di], ax
    mov ds:[1Ch], dx
    xor bp, bp
    jmp put_out
put_full:
    mov bp, 1
put_out:
    popf
    pop di
    pop dx
    pop cx
    pop bx
    pop ds
    or bp, bp
    pop bp
    jnz put_stc
    clc
    ret
put_stc:
    stc
    ret
neo_put endp

; Stack for the keyboard interrupt and for the INT 21h that ends
; installation. The installer points SS:SP at resident_end only after
; the banner has been printed and the open handles have been closed.
    dw 64 dup (0)
resident_end:

; From here on, nothing stays resident.
;
; /H prints the command list. /T runs the self-test and returns the
; fail count as the DOS error level. /U removes a resident copy. A
; plain NEO, when a copy is already resident, prints the counters.
; /XT forces the 83-key finger map and /AT forces the 102-key map.
; Neither switch chooses the interrupt. The model byte does that for
; the fingers, and the BIOS feature byte does that for the hook.
init:
    call parse_cmd
    cmp byte ptr want_h, 0
    je init_go
    mov dx, OFFSET help_txt
    call say
    mov ax, 4C00h
    int 21h
init_go:
    cmp byte ptr want_t, 0
    je init_u
    call self_test
    mov ah, 4Ch
    mov al, test_rc
    int 21h
init_u:
    call find_res
    jc init_not
    cmp byte ptr want_u, 0
    je init_busy
    call unload
    mov ax, 4C00h
    int 21h
init_not:
    cmp byte ptr want_u, 0
    je init_install
    mov dx, OFFSET not_txt
    call say
    mov ax, 4C01h
    int 21h
init_busy:
    call show_status
    mov ax, 4C01h
    int 21h
; Model bytes FF, FE, FD, and FB are the 83-key finger map. Every other
; model byte is the 102-key map. Feature bit 4 of the table returned by
; INT 15h AH=C0h means the BIOS calls AH=4Fh. detect leaves BX alone
; across that call, because the table pointer comes back in ES:BX.
;
; The saved vector is read with AH=35h and written with AH=25h. Handles
; 0 through 19 are closed after the banner. AH=31h would otherwise keep
; a redirected standard output open, and the next write would continue
; at the end of the banner. The stack moves to resident_end, and DX
; becomes the resident size in paragraphs. The PSP is inside that size,
; because a COM's CS is the PSP and resident_end is an offset from CS.
init_install:
    call detect
    cmp byte ptr force, 1
    jne inst_f2
    mov byte ptr fingers, 1
    jmp inst_hook
inst_f2:
    cmp byte ptr force, 2
    jne inst_hook
    mov byte ptr fingers, 0
inst_hook:
    cmp byte ptr has4f, 0
    je inst_09
    mov byte ptr hook15, 1
    mov ax, 3515h
    int 21h
    mov cs:oldoff, bx
    mov cs:oldseg, es
    cli
    push ds
    push cs
    pop ds
    mov dx, OFFSET neo15
    mov ax, 2515h
    int 21h
    pop ds
    sti
    jmp inst_msg
inst_09:
    mov byte ptr hook15, 0
    mov ax, 3509h
    int 21h
    mov cs:oldoff, bx
    mov cs:oldseg, es
    cli
    push ds
    push cs
    pop ds
    mov dx, OFFSET neo09
    mov ax, 2509h
    int 21h
    pop ds
    sti
inst_msg:
    call say_banner
    xor bx, bx
inst_close:
    mov ah, 3Eh
    int 21h
    inc bx
    cmp bx, 20
    jb inst_close
    cli
    mov ax, cs
    mov ss, ax
    mov sp, OFFSET resident_end
    sti
    mov dx, OFFSET resident_end
    add dx, 15
    mov cl, 4
    shr dx, cl
    mov ax, 3100h
    int 21h

; Transient state and the commands. None of this is addressable once
; the driver has stayed resident.

want_u  db 0
envseg  dw 0
want_t  db 0
want_h  db 0
force   db 0
has4f   db 0
test_rc db 0
fails   dw 0
passes  dw 0
save17  db 0
save18  db 0
line    db 90 dup (0)

say proc near
    mov ah, 09h
    int 21h
    ret
say endp

parse_cmd proc near
    mov si, 81h
    mov cl, ds:[80h]
    xor ch, ch
    jcxz pc_done
pc_top:
    mov al, [si]
    cmp al, '/'
    jne pc_next
    mov al, [si+1]
    and al, 0DFh
    cmp al, 'U'
    jne pc_t
    mov byte ptr want_u, 1
    jmp pc_skip
pc_t:
    cmp al, 'T'
    jne pc_h
    mov byte ptr want_t, 1
    jmp pc_skip
pc_h:
    cmp al, 'H'
    je pc_help
    cmp al, '?'
    je pc_help
    cmp al, 'X'
    jne pc_a
    mov al, [si+2]
    and al, 0DFh
    cmp al, 'T'
    jne pc_bad
    mov byte ptr force, 1
    jmp pc_skip
pc_a:
    cmp al, 'A'
    jne pc_bad
    mov al, [si+2]
    and al, 0DFh
    cmp al, 'T'
    jne pc_bad
    mov byte ptr force, 2
    jmp pc_skip
pc_help:
    mov byte ptr want_h, 1
    jmp pc_skip
pc_bad:
    mov byte ptr want_h, 1
pc_skip:
    inc si
    loop pc_sk2
    jmp pc_done
pc_sk2:
    mov al, [si]
    cmp al, ' '
    je pc_top
    jmp pc_skip
pc_next:
    inc si
    loop pc_top
pc_done:
    ret
parse_cmd endp

; Look for a resident copy on INT 15h first, then on INT 09h. Carry
; clear means ES:BX is the hooked entry. The signature is the four
; bytes at ES:BX-6. The state offset is the word at ES:BX-2.
find_res proc near
    mov ax, 3515h
    int 21h
    call sig_at
    jnc fr_ok
    mov ax, 3509h
    int 21h
    call sig_at
    jnc fr_ok
    stc
    ret
fr_ok:
    clc
    ret
find_res endp

sig_at proc near
    cmp byte ptr es:[bx-6], 'N'
    jne sa_no
    cmp byte ptr es:[bx-5], 'E'
    jne sa_no
    cmp byte ptr es:[bx-4], 'O'
    jne sa_no
    cmp byte ptr es:[bx-3], '2'
    jne sa_no
    clc
    ret
sa_no:
    stc
    ret
sig_at endp

detect proc near
    mov ax, 0F000h
    mov es, ax
    mov al, es:[0FFFEh]
    mov cs:modelb, al
    mov byte ptr cs:fingers, 0
    cmp al, 0FFh
    je det_xt
    cmp al, 0FEh
    je det_xt
    cmp al, 0FDh
    je det_xt
    cmp al, 0FBh
    je det_xt
    jmp det_c0
det_xt:
    mov byte ptr cs:fingers, 1
det_c0:
    mov byte ptr has4f, 0
    mov ah, 0C0h
    stc
    int 15h
    jc det_done
    test byte ptr es:[bx+5], 10h
    jz det_done
    mov byte ptr has4f, 1
det_done:
    ret
detect endp

; Put the saved vector back, free the resident PSP, and free its
; environment if the word at PSP:2Ch is not zero. The message is printed
; with DS equal to this transient segment. The vector write uses the
; BIOS segment in DS, and a message printed before DS is restored would
; dump that segment instead of the text.
unload proc near
    mov si, es:[bx-2]
    mov ax, es:[2Ch]
    mov envseg, ax
    mov dx, es:[si + (oldoff - neo_state)]
    mov cx, es:[si + (oldseg - neo_state)]
    push es
    mov ds, cx
    mov ax, 2509h
    cmp byte ptr es:[si + (hook15 - neo_state)], 0
    je ul_set
    mov ax, 2515h
ul_set:
    cli
    int 21h
    sti
    pop es
    mov ah, 49h
    int 21h
    push cs
    pop ds
    mov ax, envseg
    or ax, ax
    jz ul_say
    mov es, ax
    mov ah, 49h
    int 21h
ul_say:
    mov dx, OFFSET gone_txt
    call say
    ret
unload endp

show_status proc near
    mov si, es:[bx-2]
    mov dx, OFFSET busy_txt
    call say
    mov ax, es:[si + (hits - neo_state)]
    call printd
    mov dx, OFFSET calls_mid
    call say
    mov ax, es:[si + (eaten - neo_state)]
    call printd
    mov dx, OFFSET crlf
    call say
    mov dx, OFFSET stat_caps
    call say
    mov al, es:[si + (caps - neo_state)]
    call onoff
    mov dx, OFFSET stat_pause
    call say
    mov al, es:[si + (paused - neo_state)]
    call onoff
    mov dx, OFFSET stat_m3
    call say
    mov al, es:[si + (mod3a - neo_state)]
    or al, es:[si + (mod3b - neo_state)]
    call onoff
    mov dx, OFFSET stat_m4
    call say
    mov al, es:[si + (mod4a - neo_state)]
    or al, es:[si + (mod4b - neo_state)]
    call onoff
    mov dx, OFFSET crlf
    call say
    mov dx, OFFSET how_off
    call say
    ret
show_status endp

onoff proc near
    mov dx, OFFSET off_txt
    or al, al
    jz oo_say
    mov dx, OFFSET on_txt
oo_say:
    call say
    ret
onoff endp

printd proc near
    push ax
    push bx
    push cx
    push dx
    xor cx, cx
    mov bx, 10
pd1:
    xor dx, dx
    div bx
    push dx
    inc cx
    or ax, ax
    jnz pd1
pd2:
    pop dx
    add dl, '0'
    mov ah, 02h
    int 21h
    loop pd2
    pop dx
    pop cx
    pop bx
    pop ax
    ret
printd endp

say_banner proc near
    mov dx, OFFSET ban1
    call say
    cmp byte ptr cs:fingers, 0
    jne ban_xt
    mov dx, OFFSET ban_at
    call say
    jmp ban_hook
ban_xt:
    mov dx, OFFSET ban_xtt
    call say
ban_hook:
    cmp byte ptr has4f, 0
    je ban_09
    mov dx, OFFSET ban4
    jmp ban_rest
ban_09:
    mov dx, OFFSET ban9
ban_rest:
    call say
    mov dx, OFFSET ban2
    call say
    ret
say_banner endp

; The self-test calls neo_handle directly. It does not generate
; interrupts and it does not require the driver to be resident. Each
; case plants the BIOS flags and the modifier state, passes one scan
; byte, and compares the carry flag, the words, and the flags that
; should remain. The BIOS keyboard flags are restored afterwards.
self_test proc near
    call detect
    mov dx, OFFSET t_model
    call say
    mov al, cs:modelb
    call hexbyte
    mov dx, OFFSET crlf
    call say
    mov dx, OFFSET t_no4
    cmp byte ptr has4f, 0
    je st_4
    mov dx, OFFSET t_yes4
st_4:
    call say
    mov ax, 40h
    mov es, ax
    mov al, es:[17h]
    mov save17, al
    mov al, es:[18h]
    mov save18, al
    mov si, OFFSET cases
st_loop:
    cmp byte ptr [si], 0FFh
    je st_buf
    call one_case
    add si, 23
st_skip:
    lodsb
    or al, al
    jnz st_skip
    jmp st_loop
st_buf:
    call buf_case
    call xt_ctrl_case
    mov al, save17
    mov es:[17h], al
    mov al, save18
    mov es:[18h], al
    mov dx, OFFSET t_pass
    call say
    mov ax, passes
    call printd
    mov dx, OFFSET t_fail
    call say
    mov ax, fails
    call printd
    mov dx, OFFSET crlf
    call say
    mov byte ptr test_rc, 0
    cmp word ptr fails, 0
    je st_ok
    mov byte ptr test_rc, 1
st_ok:
    ret
self_test endp

; SI points at one case. The 23-byte header is the scan, the value to
; plant at 0040:0017, the six modifier and mode bytes, the E0 flag, the
; expected carry, the expected word count, the two expected words, and
; the seven bytes of state expected afterwards. An ASCIZ name follows.
; ES is the BIOS data segment.
one_case proc near
    push si
    mov al, [si+1]
    mov es:[17h], al
    mov byte ptr es:[18h], 0
    mov al, [si+2]
    mov cs:mod3a, al
    mov al, [si+3]
    mov cs:mod3b, al
    mov al, [si+4]
    mov cs:mod4a, al
    mov al, [si+5]
    mov cs:mod4b, al
    mov al, [si+6]
    mov cs:caps, al
    mov al, [si+7]
    mov cs:paused, al
    mov al, [si+8]
    mov cs:fingers, al
    mov al, [si+9]
    mov cs:seen_e0, al
    mov al, [si]
    call neo_handle
    pushf
    pop ax
    and al, 1
    mov ah, [si+10]
    cmp al, ah
    jne oc_bad
    mov al, cs:nout
    cmp al, [si+11]
    jne oc_bad
    cmp byte ptr [si+11], 0
    je oc_st
    mov ax, cs:nword0
    cmp ax, [si+12]
    jne oc_bad
    cmp byte ptr [si+11], 2
    jb oc_st
    mov ax, cs:nword1
    cmp ax, [si+14]
    jne oc_bad
oc_st:
    mov al, es:[17h]
    cmp al, [si+16]
    jne oc_bad
    mov al, cs:caps
    cmp al, [si+17]
    jne oc_bad
    mov al, cs:mod3a
    cmp al, [si+18]
    jne oc_bad
    mov al, cs:mod3b
    cmp al, [si+19]
    jne oc_bad
    mov al, cs:mod4a
    cmp al, [si+20]
    jne oc_bad
    mov al, cs:mod4b
    cmp al, [si+21]
    jne oc_bad
    mov al, cs:paused
    cmp al, [si+22]
    jne oc_bad
    inc word ptr passes
    mov dx, OFFSET ok_txt
    call say
    jmp oc_name
oc_bad:
    inc word ptr fails
    mov dx, OFFSET bad_txt
    call say
oc_name:
    pop si
    push si
    add si, 23
oc_nl:
    mov dl, [si]
    or dl, dl
    jz oc_end
    mov ah, 02h
    int 21h
    inc si
    jmp oc_nl
oc_end:
    mov dx, OFFSET crlf
    call say
    pop si
    ret
one_case endp

; neo_put is checked against the live BIOS buffer: one known word is
; written, the tail slot is compared, and the previous tail is restored.
buf_case proc near
    mov ax, 40h
    mov es, ax
    mov bx, es:[1Ch]
    mov di, es:[bx]
    push bx
    push di
    mov ax, 0ABCDh
    call neo_put
    jc bc_full
    pop di
    pop bx
    cmp word ptr es:[bx], 0ABCDh
    jne bc_mismatch
    mov es:[bx], di
    mov es:[1Ch], bx
    inc word ptr passes
    mov dx, OFFSET ok_txt
    call say
    mov dx, OFFSET buf_name
    call say
    ret
bc_full:
    pop di
    pop bx
    jmp bc_bad
bc_mismatch:
    mov es:[bx], di
    mov es:[1Ch], bx
bc_bad:
    inc word ptr fails
    mov dx, OFFSET bad_txt
    call say
    mov dx, OFFSET buf_name
    call say
    ret
buf_case endp

; On the 83-key map, scan 3Ah must set the two Ctrl bits, and the break
; BAh must clear them. The scan is eaten in both cases.
xt_ctrl_case proc near
    mov byte ptr es:[17h], 0
    mov byte ptr es:[18h], 0
    mov byte ptr cs:fingers, 1
    mov byte ptr cs:seen_e0, 0
    mov byte ptr cs:paused, 0
    mov al, 3Ah
    call neo_handle
    mov al, es:[17h]
    cmp al, 04h
    jne xc_bad
    mov al, es:[18h]
    cmp al, 01h
    jne xc_bad
    mov al, 0BAh
    call neo_handle
    mov al, es:[17h]
    cmp al, 0
    jne xc_bad
    mov al, es:[18h]
    cmp al, 0
    jne xc_bad
    inc word ptr passes
    mov dx, OFFSET ok_txt
    call say
    mov dx, OFFSET xtc_name
    call say
    ret
xc_bad:
    inc word ptr fails
    mov dx, OFFSET bad_txt
    call say
    mov dx, OFFSET xtc_name
    call say
    ret
xt_ctrl_case endp

hexbyte proc near
    push ax
    push dx
    mov ah, al
    mov cl, 4
    shr al, cl
    call hexdig
    mov dl, al
    mov ah, 02h
    int 21h
    pop dx
    pop ax
    push ax
    push dx
    call hexdig
    mov dl, al
    mov ah, 02h
    int 21h
    pop dx
    pop ax
    ret
hexbyte endp

hexdig proc near
    and al, 0Fh
    add al, '0'
    cmp al, '9'
    jbe hd_ret
    add al, 7
hd_ret:
    ret
hexdig endp

help_txt db 'Neo keyboard, code page 437.', 13, 10
    db 'NEO        install', 13, 10
    db 'NEO /U     remove', 13, 10
    db 'NEO /T     self-test', 13, 10
    db 'NEO /XT    83-key finger positions', 13, 10
    db 'NEO /AT    102-key finger positions', 13, 10
    db '$'

not_txt db 'Neo is not resident.', 13, 10, '$'
gone_txt db 'Neo removed.', 13, 10, '$'
busy_txt db 'Neo is already resident.', 13, 10, 'Calls $'
calls_mid db ', kept $'
crlf db 13, 10, '$'
stat_caps db 'Caps $'
stat_pause db '  Pause $'
stat_m3 db '  Mod3 $'
stat_m4 db '  Mod4 $'
on_txt db 'on$'
off_txt db 'off$'
how_off db 'NEO /U removes it.', 13, 10, '$'
ok_txt db 'OK  $'
bad_txt db 'FAIL $'
buf_name db 'buffer', 13, 10, '$'
xtc_name db 'xt-ctrl', 13, 10, '$'
t_model db 'Model $'
t_yes4 db 'INT 15h/4Fh yes', 13, 10, '$'
t_no4 db 'INT 15h/4Fh no', 13, 10, '$'
t_pass db 'passed $'
t_fail db ' failed $'

ban1 db 'Neo is resident. Code page 437.', 13, 10, '$'
ban_at db 'Mod3: Caps Lock and the # key. Mod4: the < key and AltGr.', 13, 10, '$'
ban_xtt db '83-key: Mod3 is the key left of A and the # key.', 13, 10
    db 'Mod4 is Alt. Ctrl is the wide key right of the space bar.', 13, 10, '$'
ban4 db 'Hooked INT 15h AH=4Fh.', 13, 10, '$'
ban9 db 'Hooked INT 09h. The BIOS still handles every other key.', 13, 10, '$'
ban2 db 'Both Shift keys: capitals. Both Mod3 keys: suspend.', 13, 10
    db 'NEO /U removes it. Run NEO again to see the counters.', 13, 10, '$'

; One case is 23 header bytes and then an ASCIZ name. neo_handle is
; called with the scan in AL and the planted state around it. The
; expected words are the typeahead values, low byte character and high
; byte scan.
TCASE MACRO sc, f17, m3a, m3b, m4a, m4b, cap, pau, fing, e0, pass, nout, w0, w1, e17, ecap, em3a, em3b, em4a, em4b, epau, nam
    db sc, f17, m3a, m3b, m4a, m4b, cap, pau, fing, e0, pass, nout
    dw w0, w1
    db e17, ecap, em3a, em3b, em4a, em4b, epau
    db nam, 0
ENDM

cases:
    TCASE 20h, 00h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2061h, 0000h, 00h, 0, 0, 0, 0, 0, 0, 'a'
    TCASE 20h, 01h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2041h, 0000h, 01h, 0, 0, 0, 0, 0, 0, 'A'
    TCASE 20h, 00h, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 207Bh, 0000h, 00h, 0, 1, 0, 0, 0, 0, 'lbrace'
    TCASE 20h, 00h, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 5000h, 0000h, 00h, 0, 0, 0, 1, 0, 0, 'down'
    TCASE 13h, 04h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1303h, 0000h, 04h, 0, 0, 0, 0, 0, 0, 'ctrl-c'
    TCASE 12h, 04h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 120Ch, 0000h, 04h, 0, 0, 0, 0, 0, 0, 'ctrl-l'
    TCASE 1Ah, 01h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2, 1A53h, 1A53h, 01h, 0, 0, 0, 0, 0, 0, 'SS'
    TCASE 02h, 01h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 02F8h, 0000h, 01h, 0, 0, 0, 0, 0, 0, 'degree'
    TCASE 03h, 01h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0315h, 0000h, 01h, 0, 0, 0, 0, 0, 0, 'section'
    TCASE 2Eh, 00h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2E84h, 0000h, 00h, 0, 0, 0, 0, 0, 0, 'ae'
    TCASE 2Eh, 01h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2E8Eh, 0000h, 01h, 0, 0, 0, 0, 0, 0, 'AE'
    TCASE 2Ch, 00h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2C81h, 0000h, 00h, 0, 0, 0, 0, 0, 0, 'ue'
    TCASE 10h, 00h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1078h, 0000h, 00h, 0, 0, 0, 0, 0, 0, 'x'
    TCASE 2Ah, 02h, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0000h, 0000h, 42h, 1, 0, 0, 0, 0, 0, 'caps-chord'
    TCASE 3Ah, 00h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0000h, 0000h, 00h, 0, 1, 0, 0, 0, 0, 'mod3-down'
    TCASE 0BAh, 00h, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0000h, 0000h, 00h, 0, 0, 0, 0, 0, 0, 'mod3-up'
    TCASE 39h, 00h, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 5230h, 0000h, 00h, 0, 0, 0, 1, 0, 0, 'kp0'
    TCASE 16h, 00h, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 4737h, 0000h, 00h, 0, 0, 0, 1, 0, 0, 'kp7'
    TCASE 20h, 00h, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 2041h, 0000h, 00h, 1, 0, 0, 0, 0, 0, 'caps-a'
    TCASE 20h, 01h, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 2061h, 0000h, 01h, 1, 0, 0, 0, 0, 0, 'caps-shift-a'
    TCASE 14h, 00h, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 145Eh, 0000h, 00h, 0, 1, 0, 0, 0, 0, 'caret'
    TCASE 0Ch, 00h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0C2Dh, 0000h, 00h, 0, 0, 0, 0, 0, 0, 'hyphen'
    TCASE 20h, 08h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2000h, 0000h, 08h, 0, 0, 0, 0, 0, 0, 'alt-pos'
    TCASE 2Fh, 00h, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 1C0Dh, 0000h, 00h, 0, 0, 0, 1, 0, 0, 'enter'
    TCASE 2Ch, 00h, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 011Bh, 0000h, 00h, 0, 0, 0, 1, 0, 0, 'esc'
    TCASE 11h, 00h, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0E08h, 0000h, 00h, 0, 0, 0, 1, 0, 0, 'backspace'
    TCASE 3Bh, 00h, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0000h, 0000h, 00h, 0, 0, 0, 0, 0, 0, 'f1'
    TCASE 1Dh, 00h, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0000h, 0000h, 00h, 0, 1, 0, 0, 0, 0, 'xt-mod3'
    TCASE 1Dh, 00h, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0000h, 0000h, 00h, 0, 0, 0, 0, 0, 0, 'at-ctrl'
    TCASE 38h, 00h, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0000h, 0000h, 00h, 0, 0, 0, 0, 1, 0, 'altgr'
    TCASE 38h, 00h, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0000h, 0000h, 00h, 0, 0, 0, 0, 0, 0, 'left-alt'
    TCASE 20h, 0Ch, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0000h, 0000h, 0Ch, 0, 0, 0, 0, 0, 0, 'ctrl-alt'
    TCASE 20h, 04h, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 207Bh, 0000h, 04h, 0, 1, 0, 0, 0, 0, 'mod3-over-ctrl'
    TCASE 04h, 01h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0000h, 0000h, 01h, 0, 0, 0, 0, 0, 0, 'shift-3'
    TCASE 05h, 01h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 05AFh, 0000h, 01h, 0, 0, 0, 0, 0, 0, 'raquo'
    TCASE 2Eh, 00h, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2E7Ch, 0000h, 00h, 0, 1, 0, 0, 0, 0, 'pipe'
    TCASE 2Eh, 00h, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 5200h, 0000h, 80h, 0, 0, 0, 1, 0, 0, 'insert'
    TCASE 2Bh, 00h, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0000h, 0000h, 00h, 0, 1, 1, 0, 0, 1, 'suspend'
    TCASE 20h, 00h, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0, 0000h, 0000h, 00h, 0, 0, 0, 0, 0, 1, 'paused-letter'
    TCASE 2Ah, 02h, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0000h, 0000h, 02h, 0, 0, 0, 0, 0, 0, 'phantom-shift'
    TCASE 2Ah, 03h, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0000h, 0000h, 03h, 0, 0, 0, 0, 0, 0, 'shift-repeat'
    TCASE 0A0h, 00h, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0000h, 0000h, 00h, 0, 0, 0, 0, 0, 0, 'letter-break'
    TCASE 0E0h, 00h, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0000h, 0000h, 00h, 0, 0, 0, 0, 0, 0, 'prefix'
    TCASE 27h, 00h, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 272Ch, 0000h, 00h, 0, 0, 0, 1, 0, 0, 'comma'
    TCASE 28h, 00h, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2840h, 0000h, 00h, 0, 1, 0, 0, 0, 0, 'at'
    TCASE 28h, 00h, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 282Eh, 0000h, 00h, 0, 0, 0, 1, 0, 0, 'dot'
    TCASE 03h, 00h, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 03FDh, 0000h, 00h, 0, 1, 0, 0, 0, 0, 'sup2'
    TCASE 20h, 01h, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 20E0h, 0000h, 01h, 0, 1, 0, 0, 0, 0, 'alpha'
    TCASE 09h, 00h, 1, 0, 1, 0, 0, 0, 0, 0, 0, 1, 09ECh, 0000h, 00h, 0, 1, 0, 1, 0, 0, 'inf'
    TCASE 11h, 00h, 1, 0, 1, 0, 0, 0, 0, 0, 0, 1, 11FBh, 0000h, 00h, 0, 1, 0, 1, 0, 0, 'sqrt'
    TCASE 4Fh, 01h, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 4FF3h, 0000h, 01h, 0, 1, 0, 0, 0, 0, 'le'
    TCASE 51h, 01h, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 51F2h, 0000h, 01h, 0, 1, 0, 0, 0, 0, 'ge'
    TCASE 4Eh, 00h, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 4EF1h, 0000h, 00h, 0, 1, 0, 0, 0, 0, 'plusminus'
    TCASE 39h, 01h, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 39FFh, 0000h, 01h, 0, 1, 0, 0, 0, 0, 'nbsp'
    TCASE 02h, 00h, 1, 0, 1, 0, 0, 0, 0, 0, 0, 1, 02AAh, 0000h, 00h, 0, 1, 0, 1, 0, 0, 'not'
    TCASE 35h, 00h, 1, 0, 0, 0, 0, 0, 0, 1, 0, 1, 35F6h, 0000h, 00h, 0, 1, 0, 0, 0, 0, 'divide'
    TCASE 35h, 00h, 0, 0, 0, 0, 0, 0, 0, 1, 1, 0, 0000h, 0000h, 00h, 0, 0, 0, 0, 0, 0, 'kp-slash'
    TCASE 47h, 00h, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0000h, 0000h, 00h, 0, 0, 0, 0, 0, 0, 'kp7-bios'
    TCASE 09h, 00h, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0F09h, 0000h, 00h, 0, 0, 0, 1, 0, 0, 'tab'
    TCASE 48h, 00h, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 4800h, 0000h, 00h, 0, 0, 0, 1, 0, 0, 'kp-up'
    TCASE 4Ch, 00h, 0, 0, 1, 0, 0, 0, 0, 0, 0, 1, 4C00h, 0000h, 00h, 0, 0, 0, 1, 0, 0, 'kp-begin'
    TCASE 1Ah, 00h, 0, 0, 0, 0, 1, 0, 0, 0, 0, 2, 1A53h, 1A53h, 00h, 1, 0, 0, 0, 0, 0, 'caps-sz'
    TCASE 1Bh, 00h, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1B2Fh, 0000h, 00h, 0, 1, 0, 0, 0, 0, 'slash'
    db 0FFh

END start
