################################################################################
#
# tcc (Tiny C Compiler) — riscv32 target build
#
################################################################################

TCC_VERSION = f7e187ef8084d49fd458a5ecba54868cce24f62c
TCC_SITE = https://github.com/jrrk2/tinycc.git
TCC_SITE_METHOD = git
TCC_LICENSE = LGPL-2.1+
TCC_LICENSE_FILES = COPYING

# tcc's configure is a hand-written shell script, not autoconf.
# We must call it explicitly with cross-compilation settings.

define TCC_CONFIGURE_CMDS
	cd $(@D) && ./configure \
		--prefix=/usr \
		--cpu=riscv32 \
		--targetos=Linux \
		--cross-prefix=$(TARGET_CROSS) \
		--config-musl \
		--elfinterp=/lib/ld-musl-riscv32.so.1 \
		--crtprefix=/usr/lib \
		--sysincludepaths=/usr/include \
		--libpaths=/usr/lib/tcc:/usr/lib \
		--with-libgcc \
		--extra-cflags="$(TARGET_CFLAGS)"
	$(SED) 's|"libgcc_s.so.1"|"/usr/lib/libgcc.a"|' $(@D)/config.h
endef

# Path to the cross-compiler's libgcc.a (for target installation)
TCC_LIBGCC := $(dir $(shell $(TARGET_CC) -print-libgcc-file-name))libgcc.a

define TCC_BUILD_CMDS
	# c2str.exe is a build-time code generator (converts tccdefs.h to C strings).
	# It must run on the host, so build it with the host compiler before cross-make.
	$(HOSTCC) -DC2STR $(@D)/conftest.c -o $(@D)/c2str.exe
	# riscv32-libtcc1-usegcc=yes: build libtcc1.a with cross-gcc instead of tcc
	# (the just-built tcc is a riscv32 binary that can't run on the build host)
	$(MAKE) -C $(@D) riscv32-libtcc1-usegcc=yes
endef

define TCC_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/tcc $(TARGET_DIR)/usr/bin/tcc
	$(INSTALL) -D -m 0644 $(@D)/libtcc1.a $(TARGET_DIR)/usr/lib/tcc/libtcc1.a
	$(INSTALL) -d $(TARGET_DIR)/usr/lib/tcc/include
	cp -a $(@D)/include/*.h $(TARGET_DIR)/usr/lib/tcc/include/
	# Install musl C library development files needed by tcc
	$(INSTALL) -d $(TARGET_DIR)/usr/include
	cp -a $(STAGING_DIR)/usr/include/* $(TARGET_DIR)/usr/include/
	# Install CRT files for linking
	$(INSTALL) -D -m 0644 $(STAGING_DIR)/lib/crt1.o $(TARGET_DIR)/usr/lib/crt1.o
	$(INSTALL) -D -m 0644 $(STAGING_DIR)/lib/crti.o $(TARGET_DIR)/usr/lib/crti.o
	$(INSTALL) -D -m 0644 $(STAGING_DIR)/lib/crtn.o $(TARGET_DIR)/usr/lib/crtn.o
	# Install libc.a for static linking (libc.so already in /lib)
	$(INSTALL) -D -m 0644 $(STAGING_DIR)/lib/libc.a $(TARGET_DIR)/usr/lib/libc.a
	# Install libgcc.a (provides __divdi3, __extenddftf2, etc. needed by musl)
	$(INSTALL) -D -m 0644 $(TCC_LIBGCC) $(TARGET_DIR)/usr/lib/libgcc.a
endef

$(eval $(generic-package))
