OBJS = \
	kern/bio.o\
	build/console.o\
	kern/exec.o\
	kern/file.o\
	build/ide.o\
	kern/fs.o\
	kern/ioapic.o\
	kern/kalloc.o\
	build/kbd.o\
	kern/lapic.o\
	kern/log.o\
	kern/main.o\
	kern/mp.o\
	kern/picirq.o\
	kern/pipe.o\
	kern/proc.o\
	kern/spinlock.o\
	build/string.o\
	kern/swtch.o\
	kern/syscall.o\
	kern/sysfile.o\
	kern/sysproc.o\
	kern/timer.o\
	kern/trapasm.o\
	kern/trap.o\
	kern/uart.o\
	kern/vectors.o\
	kern/vm.o\

# Cross-compiling (e.g., on Mac OS X)
# TOOLPREFIX = i386-jos-elf-

# Using native tools (e.g., on X86 Linux)
#TOOLPREFIX =

# Try to infer the correct TOOLPREFIX if not set
ifndef TOOLPREFIX
TOOLPREFIX := $(shell if i386-jos-elf-objdump -i 2>&1 | grep '^elf32-i386$$' >/dev/null 2>&1; \
	then echo 'i386-jos-elf-'; \
	elif objdump -i 2>&1 | grep 'elf32-i386' >/dev/null 2>&1; \
	then echo ''; \
	else echo "***" 1>&2; \
	echo "*** Error: Couldn't find an i386-*-elf version of GCC/binutils." 1>&2; \
	echo "*** Is the directory with i386-jos-elf-gcc in your PATH?" 1>&2; \
	echo "*** If your i386-*-elf toolchain is installed with a command" 1>&2; \
	echo "*** prefix other than 'i386-jos-elf-', set your TOOLPREFIX" 1>&2; \
	echo "*** environment variable to that prefix and run 'make' again." 1>&2; \
	echo "*** To turn off this error, run 'gmake TOOLPREFIX= ...'." 1>&2; \
	echo "***" 1>&2; exit 1; fi)
endif

# If the makefile can't find QEMU, specify its path here
# QEMU = qemu-system-i386

# Try to infer the correct QEMU
ifndef QEMU
QEMU = $(shell if which qemu > /dev/null; \
	then echo qemu; exit; \
	elif which qemu-system-i386 > /dev/null; \
	then echo qemu-system-i386; exit; \
	else \
	qemu=/Applications/Q.app/Contents/MacOS/i386-softmmu.app/Contents/MacOS/i386-softmmu; \
	if test -x $$qemu; then echo $$qemu; exit; fi; fi; \
	echo "***" 1>&2; \
	echo "*** Error: Couldn't find a working QEMU executable." 1>&2; \
	echo "*** Is the directory containing the qemu binary in your PATH" 1>&2; \
	echo "*** or have you tried setting the QEMU variable in Makefile?" 1>&2; \
	echo "***" 1>&2; exit 1)
endif

CC = $(TOOLPREFIX)gcc
AS = $(TOOLPREFIX)gas
LD = $(TOOLPREFIX)ld
OBJCOPY = $(TOOLPREFIX)objcopy
OBJDUMP = $(TOOLPREFIX)objdump
#CFLAGS = -fno-pic -static -fno-builtin -fno-strict-aliasing -O2 -Wall -MD -ggdb -m32 -Werror -fno-omit-frame-pointer
CFLAGS = -fno-pic -static -fno-builtin -fno-strict-aliasing -fvar-tracking -fvar-tracking-assignments -O0 -g -Wall -MD -gdwarf-2 -m32 -fno-omit-frame-pointer
CFLAGS += $(shell $(CC) -fno-stack-protector -E -x c /dev/null >/dev/null 2>&1 && echo -fno-stack-protector)
CFLAGS += -I. -Iinclude -Iboot -Idrivers
ASFLAGS = -m32 -gdwarf-2 -Wa,-divide -I. -Iinclude -Iboot -Idrivers
# FreeBSD ld wants ``elf_i386_fbsd''
LDFLAGS += -m $(shell $(LD) -V | grep elf_i386 2>/dev/null)

xv6.img: bootblock kernel fs.img
	dd if=/dev/zero of=xv6.img count=10000
	dd if=bootblock of=xv6.img conv=notrunc
	dd if=kernel of=xv6.img seek=1 conv=notrunc

swap.img: xv6.img
	dd if=/dev/zero of=swap.img bs=1M count=128

xv6memfs.img: bootblock kernelmemfs
	dd if=/dev/zero of=xv6memfs.img count=10000
	dd if=bootblock of=xv6memfs.img conv=notrunc
	dd if=kernelmemfs of=xv6memfs.img seek=1 conv=notrunc

bootblock: boot/bootasm.S boot/bootmain.c
	$(CC) $(CFLAGS) -fno-pic -O -nostdinc -I. -c boot/bootmain.c
	$(CC) $(CFLAGS) -fno-pic -nostdinc -I. -c boot/bootasm.S
	$(LD) $(LDFLAGS) -N -e start -Ttext 0x7C00 -o bootblock.o bootasm.o bootmain.o
	$(OBJDUMP) -S bootblock.o > bootblock.asm
	$(OBJCOPY) -S -O binary -j .text bootblock.o bootblock
	tools/sign.pl bootblock

entryother: kern/entryother.S
	$(CC) $(CFLAGS) -fno-pic -nostdinc -I. -c kern/entryother.S
	$(LD) $(LDFLAGS) -N -e start -Ttext 0x7000 -o bootblockother.o entryother.o
	$(OBJCOPY) -S -O binary -j .text bootblockother.o entryother
	$(OBJDUMP) -S bootblockother.o > entryother.asm

initcode: kern/initcode.S
	$(CC) $(CFLAGS) -nostdinc -I. -c kern/initcode.S
	$(LD) $(LDFLAGS) -N -e start -Ttext 0 -o initcode.out initcode.o
	$(OBJCOPY) -S -O binary initcode.out initcode
	$(OBJDUMP) -S initcode.o > initcode.asm

kernel: $(OBJS) kern/entry.o entryother initcode kern/kernel.ld
	$(LD) $(LDFLAGS) -T kern/kernel.ld -o kernel kern/entry.o $(OBJS) -b binary initcode entryother
	$(OBJDUMP) -S kernel > kernel.asm
	$(OBJDUMP) -t kernel | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > kernel.sym

build/%.o: user/%.c
	@mkdir -p build
	$(CC) $(CFLAGS) -c -o $@ $<

build/%.o: drivers/%.c
	@mkdir -p build
	$(CC) $(CFLAGS) -c -o $@ $<

build/%.o: programs/%.c
	@mkdir -p build
	$(CC) $(CFLAGS) -c -o $@ $<

build/%.o: kern/%.c
	@mkdir -p build
	$(CC) $(CFLAGS) -c -o $@ $<

build/%.o: lib/%.c
	@mkdir -p build
	$(CC) $(CFLAGS) -c -o $@ $<

build/%.o: lib/%.S
	@mkdir -p build
	$(CC) $(ASFLAGS) -c -o $@ $<


# kernelmemfs is a copy of kernel that maintains the
# disk image in memory instead of writing to a disk.
# This is not so useful for testing persistent storage or
# exploring disk buffering implementations, but it is
# great for testing the kernel on real hardware without
# needing a scratch disk.
MEMFSOBJS = $(filter-out ide.o,$(OBJS)) memide.o
kernelmemfs: $(MEMFSOBJS) entry.o entryother initcode kernel.ld fs.img
	$(LD) $(LDFLAGS) -T kernel.ld -o kernelmemfs entry.o  $(MEMFSOBJS) -b binary initcode entryother fs.img
	$(OBJDUMP) -S kernelmemfs > kernelmemfs.asm
	$(OBJDUMP) -t kernelmemfs | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > kernelmemfs.sym

tags: $(OBJS) entryother.S _init
	etags *.S *.c

kern/vectors.S: tools/vectors.pl
	perl tools/vectors.pl > kern/vectors.S

ULIB = build/ulib.o build/usys.o build/printf.o build/umalloc.o

_%: build/%.o $(ULIB)
	$(LD) $(LDFLAGS) -N -e main -Ttext 0 -o $@ $^
	$(OBJDUMP) -S $@ > build/$*.asm
	$(OBJDUMP) -t $@ | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > build/$*.sym

_forktest: build/forktest.o $(ULIB)
	# forktest has less library code linked in - needs to be small
	# in order to be able to max out the proc table.
	$(LD) $(LDFLAGS) -N -e main -Ttext 0 -o _forktest build/forktest.o build/ulib.o build/usys.o
	$(OBJDUMP) -S _forktest > build/forktest.asm

mkfs: tools/mkfs.c include/fs.h
	gcc -Werror -Wall -o mkfs tools/mkfs.c

# Prevent deletion of intermediate files, e.g. cat.o, after first build, so
# that disk image changes after first build are persistent until clean.  More
# details:
# http://www.gnu.org/software/make/manual/html_node/Chained-Rules.html
.PRECIOUS: %.o

UPROGS=\
	_cat\
	_echo\
	_forktest\
	_grep\
	_init\
	_kill\
	_ln\
	_ls\
	_mkdir\
	_rm\
	_sh\
	_stressfs\
	_usertests\
	_wc\
	_zombie\
	_halt\
	_loop\

fs.img: mkfs README.md $(UPROGS)
	./mkfs fs.img README.md $(UPROGS)

-include *.d
# -include */*.d

clean:
	rm -rf build
	rm -f *.tex *.dvi *.idx *.aux *.log *.ind *.ilg \
	*.o *.d *.asm *.sym vectors.S bootblock entryother \
	drivers/*.o drivers/*.d programs/*.o programs/*.d lib/*.o \
	lib/*.d user/*.o user/*.d kern/*.d kern/*.o\
	initcode initcode.out kernel xv6.img fs.img swap.img kernelmemfs mkfs \
	.gdbinit \
	$(UPROGS)

# make a printout
FILES = $(shell grep -v '^\#' docs/runoff.list)
PRINT = docs/runoff.list docs/runoff.spec README.md docs/toc.hdr docs/toc.ftr $(FILES)

xv6.pdf: $(PRINT)
	docs/runoff
	ls -l xv6.pdf

print: xv6.pdf

# run in emulators

bochs : fs.img xv6.img
	if [ ! -e .bochsrc ]; then ln -s dot-bochsrc .bochsrc; fi
	bochs -q

# try to generate a unique GDB port
GDBPORT = $(shell expr `id -u` % 5000 + 25000)
# QEMU's gdb stub command line changed in 0.11
QEMUGDB = $(shell if $(QEMU) -help | grep -q '^-gdb'; \
	then echo "-gdb tcp::$(GDBPORT)"; \
	else echo "-s -p $(GDBPORT)"; fi)
ifndef CPUS
CPUS := 2
endif
#QEMUOPTS = -hdb fs.img xv6.img -smp $(CPUS) -m 512 $(QEMUEXTRA)
QEMUOPTS = -drive file=swap.img,index=2,format=raw -drive file=fs.img,index=1,format=raw -drive file=xv6.img,index=0,format=raw -smp $(CPUS) -m 512 $(QEMUEXTRA)
qemu: fs.img xv6.img swap.img
	$(QEMU) -serial mon:stdio $(QEMUOPTS)

qemu-memfs: xv6memfs.img
	$(QEMU) xv6memfs.img -smp $(CPUS) -m 256

qemu-nox: fs.img xv6.img swap.img
	$(QEMU) -nographic $(QEMUOPTS)

.gdbinit: tools/.gdbinit.tmpl
	sed "s/localhost:1234/localhost:$(GDBPORT)/" < $^ > $@

qemu-gdb: fs.img xv6.img swap.img .gdbinit
	@echo "*** Now run 'gdb'." 1>&2
	$(QEMU) -serial mon:stdio $(QEMUOPTS) -S $(QEMUGDB)

qemu-nox-gdb: fs.img xv6.img swap.img .gdbinit
	@echo "*** Now run 'gdb'." 1>&2
	$(QEMU) -nographic $(QEMUOPTS) -S $(QEMUGDB)

# CUT HERE
# prepare dist for students
# after running make dist, probably want to
# rename it to rev0 or rev1 or so on and then
# check in that version.
#
# EXTRA=\
# 	mkfs.c ulib.c user.h cat.c echo.c forktest.c grep.c kill.c\
# 	ln.c ls.c mkdir.c rm.c stressfs.c usertests.c wc.c zombie.c\
# 	printf.c umalloc.c\
# 	README.md dot-bochsrc *.pl toc.* runoff runoff1 runoff.list\
# 	.gdbinit.tmpl gdbutil\
#
# dist:
# 	rm -rf dist
# 	mkdir dist
# 	for i in $(FILES); \
# 	do \
# 		grep -v PAGEBREAK $$i >dist/$$i; \
# 	done
# 	sed '/CUT HERE/,$$d' Makefile >dist/Makefile
# 	echo >dist/runoff.spec
# 	cp $(EXTRA) dist
#
# dist-test:
# 	rm -rf dist
# 	make dist
# 	rm -rf dist-test
# 	mkdir dist-test
# 	cp dist/* dist-test
# 	cd dist-test; $(MAKE) print
# 	cd dist-test; $(MAKE) bochs || true
# 	cd dist-test; $(MAKE) qemu
#
# # update this rule (change rev#) when it is time to
# # make a new revision.
# tar:
# 	rm -rf /tmp/xv6
# 	mkdir -p /tmp/xv6
# 	cp dist/* dist/.gdbinit.tmpl /tmp/xv6
# 	(cd /tmp; tar cf - xv6) | gzip >xv6-rev9.tar.gz  # the next one will be 9 (6/27/15)
#
# .PHONY: dist-test dist
