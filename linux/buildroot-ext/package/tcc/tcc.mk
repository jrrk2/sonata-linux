################################################################################
#
# tcc (Tiny C Compiler) — riscv32 target build
#
################################################################################

TCC_VERSION = a0f7f54654967aa58df6eb9ae8d074e950d51752
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
		--cross-prefix=$(TARGET_CROSS) \
		--cc="$(TARGET_CC)" \
		--ar="$(TARGET_AR)" \
		--extra-cflags="$(TARGET_CFLAGS)"
endef

define TCC_BUILD_CMDS
	$(MAKE) -C $(@D)
endef

define TCC_INSTALL_TARGET_CMDS
	# Install tcc binary
	$(INSTALL) -D -m 0755 $(@D)/tcc $(TARGET_DIR)/usr/bin/tcc
	# Install tcc runtime library
	$(INSTALL) -D -m 0644 $(@D)/libtcc1.a $(TARGET_DIR)/usr/lib/tcc/libtcc1.a
	# Install tcc internal headers
	mkdir -p $(TARGET_DIR)/usr/lib/tcc/include
	cp $(@D)/include/*.h $(TARGET_DIR)/usr/lib/tcc/include/
	# Install musl C headers from sysroot so tcc can find system headers
	mkdir -p $(TARGET_DIR)/usr/include
	cp -a $(STAGING_DIR)/usr/include/* $(TARGET_DIR)/usr/include/
	# Install CRT files from sysroot so tcc can link executables
	for f in crt1.o crti.o crtn.o; do \
		if [ -f $(STAGING_DIR)/usr/lib/$$f ]; then \
			$(INSTALL) -D -m 0644 $(STAGING_DIR)/usr/lib/$$f \
				$(TARGET_DIR)/usr/lib/$$f; \
		fi; \
	done
endef

$(eval $(generic-package))
