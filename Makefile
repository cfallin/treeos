.PHONY: all
all: treeos.img floppy.img

treeos.img: treeos.asm
	nasm -fbin -o treeos.img treeos.asm

treeos_1sector.img: treeos_1sector.asm
	nasm -fbin -o treeos_1sector.img treeos_1sector.asm

floppy.img: treeos.img
	rm -f floppy.img
	dd if=/dev/zero of=floppy.img bs=1024 count=1440
	dd if=treeos.img of=floppy.img conv=notrunc

floppy_1sector.img: treeos_1sector.img
	rm -f floppy_1sector.img
	dd if=/dev/zero of=floppy_1sector.img bs=1024 count=1440
	dd if=treeos_1sector.img of=floppy_1sector.img conv=notrunc

.PHONY: clean
clean:
	rm -f treeos.img floppy.img treeos_1sector.img floppy_1sector.img

.PHONY: qemu
qemu: floppy.img
	qemu-system-x86_64 -fda floppy.img

.PHONY: qemu_1sector
qemu_1sector: floppy_1sector.img
	qemu-system-x86_64 -fda floppy_1sector.img
