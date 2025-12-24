#!/bin/sh

dd if=../treeos_1sector.img of=bootsector.img bs=512 count=1
dd if=/dev/zero of=padding.img bs=$((2880 * 512 - 512)) count=1
cat bootsector.img padding.img > floppy.img
mkisofs -b floppy.img -o treeos.iso floppy.img

rm -rf dist/
mkdir dist/
cp index.html libv86.js v86.wasm seabios.bin vgabios.bin treeos.iso dist/
