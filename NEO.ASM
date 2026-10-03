; Neo, layers 1-6, for the IBM 5160 and later PCs.
;
; The BIOS keyboard handler stays in place. On a BIOS that calls
; INT 15h AH=4Fh, that intercept is the only hook: carry set gives the
; byte back to the BIOS, carry clear drops it. On an older XT BIOS the
; INT 09h wrapper reads port 60h without pulsing port 61h bit 7, so the
; scan byte is still there for the BIOS when this driver does not want it.
;
; This driver takes Mod3, Mod4, and the main typing block. Shift, Ctrl,
; left Alt, the function keys, the keypad, and the system chords stay
; with the BIOS. An E0 prefix and the byte after it are not split: the
; prefix is given to the BIOS, and a following byte is kept only when it
; is AltGr. The E0 flag at 0040:0096 is cleared when that byte is kept.
; E0 2A / E0 AA is the fake shift the keyboard sends around a Num Lock
; arrow; it is given back to the BIOS and is not a Shift press.
;
; Characters are code page 437. Dead keys produce the spacing ASCII
; character. Shift on the sz key produces S then S.
; Layers 5 and 6 are used when code page 437 has the character.

.MODEL TINY
.CODE
ORG 100h

start:
    jmp init

; Signature sits immediately in front of whichever entry is hooked.
; The word after it is the offset of neo_state in this segment.
    db 'NEO2'
    dw OFFSET neo_state
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

; --- resident state -------------------------------------------------------
; Offsets from neo_state are used by the transient copy when it reports
; on a copy that is already resident.

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

; Four words per scan code, layers 1..4. Scan codes 00h..56h.
; A word is the typeahead value: low byte ASCII, high byte scan.
; Six words per scan code, layers 1..6. Scan codes 00h..56h.
; A word is the typeahead value: low byte character, high byte scan.
; An empty word produces nothing. Layers 5 and 6 hold only the
; characters code page 437 can draw.
laytab:
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0231h, 02F8h, 0000h, 02A6h, 0000h, 02AAh
    dw 0332h, 0315h, 03FDh, 03A7h, 0000h, 0000h
    dw 0433h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0534h, 05AFh, 0000h, 0000h, 0000h, 0000h
    dw 0635h, 06AEh, 0000h, 06FAh, 0000h, 0000h
    dw 0736h, 0724h, 079Bh, 079Ch, 0000h, 0000h
    dw 0837h, 0000h, 089Dh, 0000h, 0000h, 0000h
    dw 0938h, 0000h, 0000h, 0F09h, 0000h, 09ECh
    dw 0A39h, 0000h, 0000h, 0A2Fh, 0000h, 0000h
    dw 0B30h, 0000h, 0000h, 0B2Ah, 0000h, 0000h
    dw 0C2Dh, 0C2Dh, 0000h, 4A2Dh, 0000h, 0000h
    dw 0D60h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 1078h, 1058h, 0000h, 4900h, 0000h, 0000h
    dw 1176h, 1156h, 115Fh, 0E08h, 0000h, 11FBh
    dw 126Ch, 124Ch, 125Bh, 4800h, 0000h, 0000h
    dw 1363h, 1343h, 135Dh, 5300h, 0000h, 0000h
    dw 1477h, 1457h, 145Eh, 5100h, 0000h, 14EAh
    dw 156Bh, 154Bh, 1521h, 15ADh, 0000h, 0000h
    dw 1668h, 1648h, 163Ch, 4737h, 0000h, 0000h
    dw 1767h, 1747h, 173Eh, 4838h, 0000h, 17E2h
    dw 1866h, 1846h, 183Dh, 4939h, 18EDh, 18E8h
    dw 1971h, 1951h, 1926h, 4E2Bh, 0000h, 0000h
    dw 1AE1h, 0000h, 0000h, 4A2Dh, 0000h, 0000h
    dw 1B27h, 0000h, 1B2Fh, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 1E75h, 1E55h, 1E5Ch, 4700h, 0000h, 0000h
    dw 1F69h, 1F49h, 1F2Fh, 4B00h, 0000h, 0000h
    dw 2061h, 2041h, 207Bh, 5000h, 20E0h, 0000h
    dw 2165h, 2145h, 217Dh, 4D00h, 21EEh, 0000h
    dw 226Fh, 224Fh, 222Ah, 4F00h, 0000h, 0000h
    dw 2373h, 2353h, 233Fh, 23A8h, 23E5h, 23E4h
    dw 246Eh, 244Eh, 2428h, 4B34h, 0000h, 0000h
    dw 2572h, 2552h, 2529h, 4C35h, 0000h, 0000h
    dw 2674h, 2654h, 262Dh, 4D36h, 26E7h, 0000h
    dw 2764h, 2744h, 273Ah, 272Ch, 27EBh, 0000h
    dw 2879h, 2859h, 2840h, 282Eh, 0000h, 0000h
    dw 295Eh, 0000h, 0000h, 0000h, 0000h, 292Eh
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 2C81h, 2C9Ah, 2C23h, 011Bh, 0000h, 0000h
    dw 2D94h, 2D99h, 2D24h, 0F09h, 0000h, 2DEFh
    dw 2E84h, 2E8Eh, 2E7Ch, 5200h, 0000h, 0000h
    dw 2F70h, 2F50h, 2F7Eh, 1C0Dh, 2FE3h, 0000h
    dw 307Ah, 305Ah, 3060h, 0000h, 0000h, 0000h
    dw 3162h, 3142h, 312Bh, 313Ah, 0000h, 0000h
    dw 326Dh, 324Dh, 3225h, 4F31h, 32E6h, 0000h
    dw 332Ch, 332Dh, 3322h, 5032h, 0000h, 0000h
    dw 342Eh, 0000h, 3427h, 5133h, 0000h, 0000h
    dw 356Ah, 354Ah, 353Bh, 353Bh, 0000h, 35E9h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 3920h, 3920h, 3920h, 5230h, 39FFh, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 453Dh, 0000h, 45F7h, 45F0h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 4700h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 4800h, 48EFh, 0000h
    dw 0000h, 0000h, 0000h, 4900h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 4B00h, 0000h, 0000h
    dw 0000h, 0000h, 4C3Ah, 4C00h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 4D00h, 0000h, 0000h
    dw 0000h, 0000h, 4EF1h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 4F00h, 4FF3h, 0000h
    dw 0000h, 0000h, 0000h, 5000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 5100h, 51F2h, 0000h
    dw 0000h, 0000h, 5225h, 5200h, 0000h, 0000h
    dw 0000h, 0000h, 532Ch, 5300h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
    dw 0000h, 0000h, 0000h, 0000h, 0000h, 0000h
; Keypad slash is E0 35, the same scan as the J key.
kpslash:
    dw 0000h, 0000h, 35F6h, 0000h, 0000h, 0000h
; AL = scan byte, which may be a break or a prefix.
; seen_e0 is 1 when 0040:0096 says the previous byte was E0.
; Carry set: the caller gives this byte to the BIOS.
; Carry clear: the caller drops it. nout is 0, 1, or 2 and the words
; are the typeahead entries.
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
nh_notmod:
    cmp byte ptr cs:paused, 0
    je nh_run
    jmp nh_pass
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

; DL = 1 when this byte is a modifier this driver owns.
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

; Carry set when BL is a key on the main typing block.
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

; BL = scan, DH = layer 1..6. Returns the typeahead word in AX.
; E0 35 is the keypad slash, not the J key.
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
    shl cx, 1
    shl cx, 1
    add ax, cx
    pop cx
    mov si, OFFSET laytab
    add si, ax
ll_idx:
    mov al, dh
    dec al
    xor ah, ah
    shl ax, 1
    add si, ax
    mov ax, cs:[si]
    ret
ll_z:
    xor ax, ax
    ret
load_layer endp

; Carry set when a keypad key should follow the Neo layer.
; Plain keypad keys stay with the BIOS.
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

; Carry set for a-z and the four German letters on layer 1.
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

; Store AX in the BIOS typeahead. Carry set if the buffer is full.
; The caller's interrupt flag is restored. BP holds the full/empty
; result across that restore.
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

    dw 64 dup (0)
resident_end:

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

; --- transient -------------------------------------------------------------

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

; ES:BX = hooked entry, carry clear, when a resident copy is found.
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

; SI = case record. ES = 40h.
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

; Case header, 23 bytes, then an ASCIZ name:
; scan f17 m3a m3b m4a m4b caps paused fingers e0 pass nout
; dw w0, w1
; exp17 expcaps expm3a expm3b expm4a expm4b exppaused
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
