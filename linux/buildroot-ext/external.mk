include $(sort $(wildcard $(BR2_EXTERNAL_SONATALINUX_PATH)/package/*/*.mk))

# macOS fix: zlib's configure on Darwin sets Apple libtool as AR (can't handle
# ELF) and uses -dynamiclib for shared libs (macOS-only, fails with cross-gcc).
# Disable the entire Darwin case so the default *) case is used instead,
# which sets LDSHARED="$cc -shared" and leaves AR alone.
define LIBZLIB_FIX_DARWIN_CONFIGURE
	$(SED) 's/Darwin\* | darwin\* | \*-darwin\*)/DISABLED_macOS)/' $(@D)/configure
endef
LIBZLIB_POST_EXTRACT_HOOKS += LIBZLIB_FIX_DARWIN_CONFIGURE

# Only install as, ld, and their shared lib dependencies from binutils.
# Full target install adds ~16MB of tools, headers, and duplicates.
define BINUTILS_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/gas/as-new $(TARGET_DIR)/usr/bin/as
	$(INSTALL) -D -m 0755 $(@D)/ld/ld-new $(TARGET_DIR)/usr/bin/ld
	cp -d $(@D)/bfd/.libs/libbfd-*.so $(TARGET_DIR)/usr/lib/
	cp -d $(@D)/opcodes/.libs/libopcodes-*.so $(TARGET_DIR)/usr/lib/
	cp -d $(@D)/libsframe/.libs/libsframe.so* $(TARGET_DIR)/usr/lib/
	cp -d $(@D)/libctf/.libs/libctf.so* $(TARGET_DIR)/usr/lib/
endef
