TreeOS: a 16-bit bootsector Christmas tree demo
===============================================

Welcome to TreeOS! This is a very simple, hacky, but working, "demo" that draws
a spinning Christmas tree and a small message while running on bare PC hardware
(no underlying operating system), using only standard VGA hardware. Merry
Christmas!

![Screenshot of TreeOS running inside QEMU](screenshot.png?raw=true)

This demo is a bootable floppy disk. it is pure 16-bit code, and uses the BIOS
to load data from the boot disk and change the video mode, before operating
directly on the VGA framebuffer. It uses a standard 320x200 256-color mode (VGA
mode 13h). This *should* work on any reasonable PC hardware at all, though I've
only tested it on a virtual machine (QEMU).

Building and Running under QEMU
===============================

You will need `nasm` to assemble. If you have `nasm` and `qemu` installed, you
should be able to just `make qemu` on Linux. E.g., on Ubuntu:

    apt install nasm qemu-system-x86

    cd treeos/
    make qemu

License
=======

Released under GNU GPL v3+. Copyright (c) 2019 by Chris Fallin
&lt;cfallin@c1f.net&gt;.
