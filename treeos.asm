; Christmas Tree demo.
;
; Written 2019-12-25.
;
; Copyright (c) 2019 Chris Fallin <cfallin@c1f.net>. Released under the GNU GPL
; v3+.
;
; Should run on any PC hardware with a VGA display (but tested only on QEMU).

[bits 16]
[org 0x7c00]
    ; Set up segment registers. We operate in segment 0, and are loaded at offset 0x7c00.
    cli
    jmp 0:.newseg
.newseg:
    mov ax, 0
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7c00
    cld
    sti

    ; Clear screen.
    push es
    mov ax, 0xb800
    mov es, ax
    mov di, 0
    mov cx, 80*25
    mov ax, 0x0f20  ; space, foreground white, background black
    rep stosw
    pop es

    ; Load remaining sectors. Use INT 0x13, AH = 0x02.
    ; Note: DL is set to the boot drive number on entry to the boot sector and
    ; we haven't modified it yet.
    mov ah, 0x02
    mov al, (endtext - seg2 + 511) / 512  ; number of sectors
    mov ch, 0                               ; cylinder (0)
    mov cl, 2                               ; sector (2)
    mov dh, 0                               ; head (0)
    mov bx, seg2
    int 0x13
    jc .err
    jmp seg2

.err:
    mov si, .errmsg
    mov ax, 0xb800
    mov es, ax
    mov di, 0
.errloop:
    lodsb
    cmp al, 0
    jz .errdone
    stosb
    inc di
    loop .errloop

.errdone:
    cli
    hlt
    jmp .errdone

.errmsg:
    db "Could not load remaining sectors of boot program.", 0

    times 510-($-$$) db 0
    db 0x55, 0xaa

seg2:
    ; install our IRQ handler.
    cli
    mov ax, [8*4]
    mov [chained_irq0], ax
    mov ax, [8*4 + 2]
    mov [chained_irq0 + 2], ax
    mov word [8*4], irq0
    mov word [8*4 + 2], 0
    sti

    ; change into VGA mode 0x13 (320x200, 256 colors).
    mov ax, 0x0013
    int 0x10

.mainloop:
    ; keep current tick in bx.
    mov bx, [timer_counter]

    ; clear the buffer.
    mov ax, 0x9000
    mov es, ax
    mov di, 0
    mov ax, 0
    mov cx, 320*200 / 2
    rep stosw

    ; tree: (x,y,z) = (160 + width(t)*cos(w*t+p), height(t), width(t)*sin(w*t+p))
    ;       width(t) = 140*t
    ;       height(t) = 10 + 180*t
    ;       w = 2*pi*5 = 31.415...
    ;       p = 2*pi * tick/36 (0.5 revs/sec) = tick * 0.1745
    ;
    ; project (x,y,z) into (x,y) with: x_disp = x + a_x*z, y_disp = y + a_y*z
    ;                                    where a_x = 0.5, a_y = 0.25
    ;
    ; color: alternate between 0x02 (green) and 0x04 (red).

    ; trace the parametric tree curve.
    mov cx, 0

    fldz
    fstp qword [tree_t]
    
    fldz
.treeloop:
    cmp cx, 1000
    je .treedone
    ; compute t
    fld qword [tree_t]
    fld qword [tree_inc]
    faddp st1, st0
    fstp qword [tree_t]

    ; compute width(t)
    fld qword [tree_t]
    fld qword [tree_width_factor]
    fmulp st1, st0 ; width_factor*t = width(t)
    fstp qword [tree_width]

    ; compute tree_angle
    fld qword [tree_t]
    fld qword [tree_w]
    fmulp st1, st0 ; w*t
    fld qword [tree_p]
    fild dword [timer_counter]
    fmulp st1, st0 ; tick*p
    faddp st1, st0 ; w*t + tick*p
    fstp qword [tree_angle]

    ; compute X
    fld qword [tree_angle]
    fcos  ; st0 = cos(w*t + tick*p)
    fld qword [tree_width]
    fmulp st1, st0 ; st0 = width(t) * cos(...)
    fld qword [tree_width_base]
    faddp st1, st0 ; st0 = width_base + width(t) * cos(...)
    fstp qword [tree_x]

    ; compute Z
    fld qword [tree_angle]
    fsin
    fld qword [tree_width]
    fmulp st1, st0
    fstp qword [tree_z]

    ; compute Y
    fld qword [tree_t]
    fld qword [tree_height_factor]
    fmulp st1, st0
    fld qword [tree_height_base]
    faddp st1, st0
    fstp qword [tree_y]

    ; compute projected 2D coord
    fld qword [tree_x]
    fld qword [tree_z]
    fld qword [tree_x_z_factor]
    fmulp st1, st0
    faddp st1, st0
    fistp word [tree_disp_x]

    fld qword [tree_y]
    fld qword [tree_z]
    fld qword [tree_y_z_factor]
    fmulp st1, st0
    faddp st1, st0
    fistp word [tree_disp_y]

    ; bounding box
    cmp word [tree_disp_y], 200
    jae .clipped
    cmp word [tree_disp_x], 320
    jae .clipped

    ; compute pixel address
    mov ax, [tree_disp_y]
    mov dx, 320
    mul dx
    add ax, [tree_disp_x]
    mov di, ax

    ; compute color
    mov ax, cx
    and ax, 1
    shl ax, 1
    add ax, 2  ; ax = 2 (green) or 4 (red)

    mov [es:di], al
.clipped:

    inc cx
    jmp .treeloop
.treedone:

    ; paint the text messages now
    mov si, message_points  ; format: (addr, length, bytes)
.msgloop:
    mov di, [si]
    cmp di, 0
    je .msgloop_done
    mov cx, [si+2]
    add si, 4
    rep movsb
    jmp .msgloop
.msgloop_done:

    ; copy the double-buffer into the VGA framebuffer.
    push ds
    push es
    mov ax, 0x9000
    mov ds, ax
    mov ax, 0xa000
    mov es, ax
    mov si, 0
    mov di, 0
    mov cx, 320*200 / 2
    rep movsw
    pop es
    pop ds

.wait_next_tick:
    cmp bx, [timer_counter]
    jnz .mainloop
    jmp .wait_next_tick


irq0:
    push word 0
    push word 0
    push ds
    push ax
    push bx
    mov bx, sp

    ; increment our counter
    mov ax, 0
    mov ds, ax
    add word [timer_counter], 1
    adc word [timer_counter+2], 0

    ; load the chained handler pointer
    mov ax, [chained_irq0]
    mov [bx+6], ax
    mov ax, [chained_irq0+2]
    mov [bx+8], ax

    pop bx
    pop ax
    pop ds

    ; return to the chained handler
    retf

    align 4
chained_irq0:
    dw 0, 0
timer_counter:
    dd 0

; floating-point constant pool:
tree_inc:
    dq 0.001
tree_width_base:
    dq 160.0
tree_width_factor:
    dq 100.0
tree_height_base:
    dq 10.0
tree_height_factor:
    dq 180.0
tree_w:
    dq 31.4159265
tree_p:
    dq 0.1745
tree_x_z_factor:
    dq 0.5
tree_y_z_factor:
    dq 0.25
; parametric curve results:
tree_t:
    dq 0
tree_width:
    dq 0
tree_height:
    dq 0
tree_angle:
    dq 0
tree_x:
    dq 0
tree_y:
    dq 0
tree_z:
    dq 0
tree_disp_x:
    dw 0
tree_disp_y:
    dw 0

; data points for "Merry Christmas / cfallin 2019" message
message_points:
    ; 32x8 pixels: "Merry"
    dw 200 + 10*320, 32
    db 2, 0, 0, 0, 0, 0, 2, 0, 4, 4, 4, 4, 0, 2, 2, 2, 0, 0, 4, 4, 4, 0, 0, 2, 0, 0, 0, 0, 0, 2, 0, 0
    dw 200 + 11*320, 32
    db 2, 2, 0, 0, 0, 2, 2, 0, 4, 0, 0, 0, 0, 2, 0, 0, 2, 0, 4, 0, 0, 4, 0, 0, 2, 0, 0, 0, 2, 0, 0, 0
    dw 200 + 12*320, 32
    db 2, 0, 2, 0, 2, 0, 2, 0, 4, 0, 0, 0, 0, 2, 0, 0, 2, 0, 4, 0, 0, 4, 0, 0, 0, 2, 0, 2, 0, 0, 0, 0
    dw 200 + 13*320, 32
    db 2, 0, 0, 2, 0, 0, 2, 0, 4, 0, 0, 0, 0, 2, 0, 2, 0, 0, 4, 0, 4, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0
    dw 200 + 14*320, 32
    db 2, 0, 0, 0, 0, 0, 2, 0, 4, 4, 4, 0, 0, 2, 2, 2, 0, 0, 4, 4, 4, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0
    dw 200 + 15*320, 32
    db 2, 0, 0, 0, 0, 0, 2, 0, 4, 0, 0, 0, 0, 2, 2, 0, 0, 0, 4, 4, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0
    dw 200 + 16*320, 32
    db 2, 0, 0, 0, 0, 0, 2, 0, 4, 0, 0, 0, 0, 2, 0, 2, 0, 0, 4, 0, 4, 0, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0
    dw 200 + 17*320, 32
    db 2, 0, 0, 0, 0, 0, 2, 0, 4, 4, 4, 4, 0, 2, 0, 0, 2, 0, 4, 0, 0, 4, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0
    ; 52x8 pixels: "Christmas"
    dw 240 + 10*320, 52
    db 0, 4, 4, 4, 0, 0, 2, 0, 0, 0, 2, 0, 4, 4, 4, 0, 0, 2, 2, 2, 0, 0, 4, 4, 4, 0, 0, 2, 2, 2, 2, 2, 0, 4, 0, 0, 0, 0, 0, 4, 0, 0, 0, 2, 0, 0, 0, 0, 4, 4, 4, 0
    dw 240 + 11*320, 52
    db 4, 0, 0, 0, 4, 0, 2, 0, 0, 0, 2, 0, 4, 0, 0, 4, 0, 0, 2, 0, 0, 4, 0, 0, 0, 4, 0, 0, 0, 2, 0, 0, 0, 4, 4, 0, 0, 0, 4, 4, 0, 0, 2, 0, 2, 0, 0, 4, 0, 0, 0, 4
    dw 240 + 12*320, 52
    db 4, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 0, 4, 0, 0, 4, 0, 0, 2, 0, 0, 4, 0, 0, 0, 0, 0, 0, 0, 2, 0, 0, 0, 4, 0, 4, 0, 4, 0, 4, 0, 2, 0, 0, 0, 2, 0, 4, 0, 0, 0, 0
    dw 240 + 13*320, 52
    db 4, 0, 0, 0, 0, 0, 2, 2, 2, 2, 2, 0, 4, 0, 4, 0, 0, 0, 2, 0, 0, 0, 4, 4, 0, 0, 0, 0, 0, 2, 0, 0, 0, 4, 0, 0, 4, 0, 0, 4, 0, 2, 0, 0, 0, 2, 0, 0, 4, 4, 0, 0
    dw 240 + 14*320, 52
    db 4, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 0, 4, 4, 4, 0, 0, 0, 2, 0, 0, 0, 0, 0, 4, 4, 0, 0, 0, 2, 0, 0, 0, 4, 0, 0, 0, 0, 0, 4, 0, 2, 2, 2, 2, 2, 0, 0, 0, 0, 4, 4
    dw 240 + 15*320, 52
    db 4, 0, 0, 0, 0, 0, 2, 0, 0, 0, 2, 0, 4, 4, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 4, 0, 0, 0, 2, 0, 0, 0, 4, 0, 0, 0, 0, 0, 4, 0, 2, 0, 0, 0, 2, 0, 0, 0, 0, 0, 4
    dw 240 + 16*320, 52
    db 4, 0, 0, 0, 4, 0, 2, 0, 0, 0, 2, 0, 4, 0, 4, 0, 0, 0, 2, 0, 0, 4, 0, 0, 0, 4, 0, 0, 0, 2, 0, 0, 0, 4, 0, 0, 0, 0, 0, 4, 0, 2, 0, 0, 0, 2, 0, 4, 0, 0, 0, 4
    dw 240 + 17*320, 52
    db 0, 4, 4, 4, 0, 0, 2, 0, 0, 0, 2, 0, 4, 0, 0, 4, 0, 2, 2, 2, 0, 0, 4, 4, 4, 0, 0, 0, 0, 2, 0, 0, 0, 4, 0, 0, 0, 0, 0, 4, 0, 2, 0, 0, 0, 2, 0, 0, 4, 4, 4, 0

    ; 36x6 pixels: "cfallin"
    dw 280 + 24*320, 36
    db 0, 0, 0, 0, 0, 7, 7, 0, 0, 0, 0, 0, 0, 0, 7, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 7, 7, 0, 0, 7, 0, 0, 0, 7, 7, 0
    dw 280 + 25*320, 36
    db 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 0, 7, 0, 7, 0, 7, 0, 0, 0, 0, 0, 0, 0, 7, 0, 7, 7, 0, 0, 7, 0, 7, 0
    dw 280 + 26*320, 36
    db 0, 7, 7, 0, 7, 7, 7, 0, 0, 7, 7, 7, 0, 0, 7, 0, 7, 0, 0, 0, 7, 7, 7, 0, 0, 0, 0, 0, 0, 7, 0, 0, 7, 0, 7, 0
    dw 280 + 27*320, 36
    db 7, 0, 0, 0, 0, 7, 0, 0, 7, 0, 0, 7, 0, 0, 7, 0, 7, 0, 7, 0, 7, 0, 0, 7, 0, 0, 0, 0, 0, 7, 0, 0, 0, 7, 7, 0
    dw 280 + 28*320, 36
    db 7, 0, 0, 0, 0, 7, 0, 0, 7, 0, 0, 7, 0, 0, 7, 0, 7, 0, 7, 0, 7, 0, 0, 7, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 7, 0
    dw 280 + 29*320, 36
    db 0, 7, 7, 0, 0, 7, 0, 0, 7, 7, 7, 7, 7, 0, 7, 0, 7, 0, 7, 0, 7, 0, 0, 7, 0, 0, 0, 0, 7, 7, 7, 0, 7, 7, 7, 0

    dw 0, 0, 0
endtext:
