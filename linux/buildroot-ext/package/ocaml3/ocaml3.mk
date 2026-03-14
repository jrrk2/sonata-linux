################################################################################
#
# ocaml3 — OCaml 3.07 bytecode interpreter + toplevel
#
# Two-stage build:
#   1. HOST_OCAML3: builds native ocaml on the host to produce bytecode
#      (ocaml toplevel, stdlib.cma — these are architecture-independent)
#   2. OCAML3: cross-compiles ocamlrun (the bytecode interpreter, a C program)
#      and installs everything to the target rootfs.
#
################################################################################

OCAML3_VERSION = 3.07-pl2
OCAML3_SITE = https://github.com/ocaml/ocaml.git
OCAML3_SITE_METHOD = git
OCAML3_LICENSE = LGPL-2.1-or-later WITH OCaml-linking-exception
OCAML3_LICENSE_FILES = LICENSE
OCAML3_DEPENDENCIES = host-ocaml3

HOST_OCAML3_LICENSE = LGPL-2.1-or-later WITH OCaml-linking-exception

# ---------- HOST BUILD (native OCaml for bytecode generation) ----------------

define HOST_OCAML3_CONFIGURE_CMDS
	# OCaml 3.07's configure is too old for modern systems.
	# Write config files manually (same approach used for manual build).

	# config/Makefile — host native build
	cat > $(@D)/config/Makefile <<'HOSTMK'
PREFIX=/usr
BINDIR=$(PREFIX)/bin
LIBDIR=$(PREFIX)/lib/ocaml
STUBLIBDIR=$(LIBDIR)/stublibs
MANDIR=$(PREFIX)/man
BYTECC=gcc
BYTECCCOMPOPTS=-O2 -std=gnu89 -DOCAML_STDLIB_DIR='"/usr/lib/ocaml"'
BYTECCLINKOPTS=
BYTECCLIBS=-lpthread
BYTERUN=ocamlrun
CCLIBS=-lm
RANLIB=ranlib
RANLIBCMD=ranlib
ARCMD=ar
SO=a
CUSTOM_IF_NOT_SHARED=-custom
SHAREDCCCOMPOPTS=
MKSHAREDLIB=echo
MKSHAREDLIBRPATH=echo
ARCH=none
MODEL=default
SYSTEM=unknown
NATIVECC=gcc
NATIVECCCOMPOPTS=-O2 -std=gnu89
NATIVECCLINKOPTS=
NATIVECCLIBS=
ASFLAGS=
ASPP=gcc -c
ASPPFLAGS=
SUPPORTS_SHARED_LIBRARIES=no
DYNLINKOPTS=
OTHERLIBRARIES=unix str num dynlink bigarray
DEBUGGER=
CC_PROFILE=
SYSTHREAD_SUPPORT=false
PARTIALLD=ld -r
PACKLD=ld -r
HOSTMK

	# config/m.h — 64-bit host (standard for modern build machines)
	cat > $(@D)/config/m.h <<'HOSTM'
#define ARCH_SIXTYFOUR
#undef ARCH_BIG_ENDIAN
#undef ARCH_ALIGN_DOUBLE
#define SIZEOF_INT 4
#define SIZEOF_LONG 8
#define SIZEOF_SHORT 2
#define ARCH_INT64_TYPE long
#define ARCH_UINT64_TYPE unsigned long
#define ARCH_INT64_PRINTF_FORMAT "l"
#undef ARCH_ALIGN_INT64
#undef NONSTANDARD_DIV_MOD
HOSTM

	# config/s.h — Unix/POSIX features
	cat > $(@D)/config/s.h <<'HOSTS'
#define OCAML_OS_TYPE "Unix"
#define OCAML_STDLIB_DIR "/usr/lib/ocaml"
#define POSIX_SIGNALS
#undef BSD_SIGNALS
#undef HAS_SIGSETMASK
#undef HAS_TERMCAP
#define HAS_STRERROR
#undef SUPPORT_DYNAMIC_LINKING
#define HAS_SOCKETS
#define HAS_SOCKLEN_T
#define HAS_UNISTD
#define HAS_DIRENT
#define HAS_REWINDDIR
#define HAS_LOCKF
#define HAS_MKFIFO
#define HAS_GETCWD
#define HAS_GETWD
#define HAS_GETPRIORITY
#define HAS_UTIME
#define HAS_UTIMES
#define HAS_DUP2
#define HAS_FCHMOD
#define HAS_TRUNCATE
#define HAS_SYS_SELECT_H
#define HAS_SELECT
#define HAS_SYMLINK
#define HAS_WAITPID
#define HAS_WAIT4
#define HAS_GETGROUPS
#define HAS_SETGROUPS
#define HAS_TERMIOS
#define HAS_ASYNC_IO
#define HAS_SETITIMER
#define HAS_GETHOSTNAME
#define HAS_UNAME
#define HAS_GETTIMEOFDAY
#define HAS_MKTIME
#define HAS_SETSID
#define HAS_PUTENV
#define HAS_LOCALE
#define HAS_MMAP
#define HAS_GETDELIM
#define HAS_SNPRINTF
HOSTS
endef

define HOST_OCAML3_BUILD_CMDS
	# Build the full OCaml system (compiler, toplevel, stdlib).
	# ocamlmklib may fail — it's not needed for bytecode.
	$(MAKE) -C $(@D) world 2>&1 || true
	# Verify critical outputs exist
	test -f $(@D)/boot/ocamlrun
	test -f $(@D)/toplevel/ocaml
	test -f $(@D)/stdlib/stdlib.cma
endef

define HOST_OCAML3_INSTALL_CMDS
	# Host install is just for the target package to find the files.
	# Copy ocaml toplevel bytecode and stdlib to a staging area.
	mkdir -p $(HOST_DIR)/share/ocaml3
	cp $(@D)/toplevel/ocaml $(HOST_DIR)/share/ocaml3/ocaml
	cp $(@D)/stdlib/stdlib.cma $(HOST_DIR)/share/ocaml3/
	cp $(@D)/stdlib/std_exit.cmo $(HOST_DIR)/share/ocaml3/
	cp $(@D)/stdlib/camlheader $(HOST_DIR)/share/ocaml3/
	cp $(@D)/stdlib/*.cmi $(HOST_DIR)/share/ocaml3/
endef

# ---------- TARGET BUILD (cross-compiled ocamlrun) ---------------------------

define OCAML3_CONFIGURE_CMDS
	# config/Makefile — riscv32 cross-compilation
	cat > $(@D)/config/Makefile <<TARGETMK
PREFIX=/usr
BINDIR=\$$(PREFIX)/bin
LIBDIR=\$$(PREFIX)/lib/ocaml
STUBLIBDIR=\$$(LIBDIR)/stublibs
MANDIR=\$$(PREFIX)/man
BYTECC=$(TARGET_CC)
BYTECCCOMPOPTS=-O2 -DOCAML_STDLIB_DIR='"/usr/lib/ocaml"'
BYTECCLINKOPTS=-static
BYTERUN=ocamlrun
CCLIBS=-lm
RANLIB=$(TARGET_RANLIB)
RANLIBCMD=$(TARGET_RANLIB)
ARCMD=$(TARGET_AR)
SO=a
CUSTOM_IF_NOT_SHARED=-custom
SHAREDCCCOMPOPTS=
MKSHAREDLIB=echo
MKSHAREDLIBRPATH=echo
ARCH=none
MODEL=default
SYSTEM=linux
NATIVECC=$(TARGET_CC)
NATIVECCCOMPOPTS=-O2
NATIVECCLINKOPTS=
NATIVECCLIBS=
ASFLAGS=
ASPP=$(TARGET_CC) -c
ASPPFLAGS=
SUPPORTS_SHARED_LIBRARIES=no
DYNLINKOPTS=
OTHERLIBRARIES=
DEBUGGER=
CC_PROFILE=
SYSTHREAD_SUPPORT=false
PARTIALLD=$(TARGET_LD) -r
PACKLD=$(TARGET_LD) -r
TARGETMK

	# config/m.h — riscv32 (32-bit, little-endian)
	cat > $(@D)/config/m.h <<'TARGETM'
#undef ARCH_SIXTYFOUR
#undef ARCH_BIG_ENDIAN
#undef ARCH_ALIGN_DOUBLE
#define SIZEOF_INT 4
#define SIZEOF_LONG 4
#define SIZEOF_SHORT 2
#define ARCH_INT64_TYPE long long
#define ARCH_UINT64_TYPE unsigned long long
#define ARCH_INT64_PRINTF_FORMAT "ll"
#undef ARCH_ALIGN_INT64
#undef NONSTANDARD_DIV_MOD
TARGETM

	# config/s.h — Linux/musl
	cat > $(@D)/config/s.h <<'TARGETS'
#define OCAML_OS_TYPE "Unix"
#define OCAML_STDLIB_DIR "/usr/lib/ocaml"
#define POSIX_SIGNALS
#undef BSD_SIGNALS
#undef HAS_SIGSETMASK
#undef HAS_TERMCAP
#define HAS_STRERROR
#undef SUPPORT_DYNAMIC_LINKING
#define HAS_SOCKETS
#define HAS_SOCKLEN_T
#define HAS_UNISTD
#define HAS_DIRENT
#define HAS_REWINDDIR
#define HAS_LOCKF
#define HAS_MKFIFO
#define HAS_GETCWD
#define HAS_GETWD
#define HAS_GETPRIORITY
#define HAS_UTIME
#define HAS_UTIMES
#define HAS_DUP2
#define HAS_FCHMOD
#define HAS_TRUNCATE
#define HAS_SYS_SELECT_H
#define HAS_SELECT
#define HAS_SYMLINK
#define HAS_WAITPID
#define HAS_WAIT4
#define HAS_GETGROUPS
#define HAS_SETGROUPS
#define HAS_TERMIOS
#define HAS_ASYNC_IO
#define HAS_SETITIMER
#define HAS_GETHOSTNAME
#define HAS_UNAME
#define HAS_GETTIMEOFDAY
#define HAS_MKTIME
#define HAS_SETSID
#define HAS_PUTENV
#define HAS_LOCALE
#define HAS_MMAP
#define HAS_GETDELIM
#define HAS_SNPRINTF
TARGETS
endef

define OCAML3_BUILD_CMDS
	# Only build the bytecode runtime (ocamlrun) for the target.
	# Everything else (toplevel, stdlib) comes from the host build.
	$(MAKE) -C $(@D)/byterun all
endef

define OCAML3_INSTALL_TARGET_CMDS
	# Install cross-compiled ocamlrun (bytecode interpreter)
	$(INSTALL) -D -m 0755 $(@D)/byterun/ocamlrun \
		$(TARGET_DIR)/usr/bin/ocamlrun
	$(TARGET_STRIP) $(TARGET_DIR)/usr/bin/ocamlrun

	# Install host-built OCaml toplevel (bytecode, arch-independent)
	$(INSTALL) -D -m 0755 $(HOST_DIR)/share/ocaml3/ocaml \
		$(TARGET_DIR)/usr/bin/ocaml
	# Fix shebang to use target ocamlrun
	sed -i '1s|.*|#!/usr/bin/ocamlrun|' $(TARGET_DIR)/usr/bin/ocaml

	# Install standard library
	mkdir -p $(TARGET_DIR)/usr/lib/ocaml
	cp $(HOST_DIR)/share/ocaml3/stdlib.cma $(TARGET_DIR)/usr/lib/ocaml/
	cp $(HOST_DIR)/share/ocaml3/std_exit.cmo $(TARGET_DIR)/usr/lib/ocaml/
	cp $(HOST_DIR)/share/ocaml3/camlheader $(TARGET_DIR)/usr/lib/ocaml/
	cp $(HOST_DIR)/share/ocaml3/*.cmi $(TARGET_DIR)/usr/lib/ocaml/

	# Set OCAMLLIB environment variable
	mkdir -p $(TARGET_DIR)/etc/profile.d
	echo "export OCAMLLIB='/usr/lib/ocaml'" \
		> $(TARGET_DIR)/etc/profile.d/ocaml.sh
endef

$(eval $(generic-package))
$(eval $(host-generic-package))
