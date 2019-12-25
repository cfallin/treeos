.PHONY: all
all: treeos.img floppy.img

treeos.img: treeos.asm
	nasm -fbin -o treeos.img treeos.asm

floppy.img: treeos.img
	rm -f floppy.img
	dd if=/dev/zero of=floppy.img bs=1024 count=1440
	dd if=treeos.img of=floppy.img conv=notrunc

.PHONY: clean
clean:
	rm -f treeos.img floppy.img

.PHONY: qemu
qemu: floppy.img
	qemu-system-x86_64 -fda floppy.img
