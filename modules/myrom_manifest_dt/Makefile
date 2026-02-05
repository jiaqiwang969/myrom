#
# Build a pongoOS module out-of-tree (MyROM v0.2: DeviceTree manifest).
#
# This mirrors pongoOS' example module Makefile, but uses PONGOOS_DIR to locate
# headers/newlib inside the pongoOS submodule checkout.
#
ifndef $(HOST_OS)
	ifeq ($(OS),Windows_NT)
		HOST_OS = Windows
	else
		HOST_OS := $(shell uname -s)
	endif
endif

ifeq ($(HOST_OS),Darwin)
	EMBEDDED_CC         ?= xcrun -sdk iphoneos clang
	STRIP               ?= strip
	STAT                ?= stat -L -f %z
else
ifeq ($(HOST_OS),Linux)
	EMBEDDED_CC         ?= clang
	EMBEDDED_LDFLAGS    ?= -fuse-ld=/usr/bin/ld64
	STRIP               ?= cctools-strip
	STAT                ?= stat -L -c %s
endif
endif

PONGOOS_DIR            ?= ../../checkra1n_research/pongoOS
DEP                    := $(PONGOOS_DIR)/newlib
LIB                    := $(DEP)/aarch64-none-darwin
BUILD                  := build

# General options
EMBEDDED_LD_FLAGS      ?= -nostdlib -static -Wl,-fatal_warnings -Wl,-dead_strip -Wl,-Z $(EMBEDDED_LDFLAGS)
EMBEDDED_CC_FLAGS      ?= --target=arm64-apple-ios12.0 -Wall -Wunused-label -Werror -O3 -flto -ffreestanding -fno-stack-protector -U__nonnull -nostdlibinc -DTARGET_OS_OSX=0 -DTARGET_OS_MACCATALYST=0 -I$(LIB)/include $(EMBEDDED_LD_FLAGS) $(EMBEDDED_CFLAGS)

# Module options
MODULE_LDFLAGS         ?= -Wl,-kext
MODULE_CC_FLAGS        ?= -I$(PONGOOS_DIR)/apple-include/ -I$(PONGOOS_DIR)/example/include/ $(MODULE_LDFLAGS)

MODULE_C               := main.c

.PHONY: all clean

all: $(BUILD)/myrom_manifest_dt

$(BUILD)/myrom_manifest_dt: Makefile $(MODULE_C) | $(BUILD)
	$(EMBEDDED_CC) -o $@ $(EMBEDDED_CC_FLAGS) $(MODULE_CC_FLAGS) $(MODULE_C)

$(BUILD):
	mkdir -p $@

clean:
	rm -rf $(BUILD)

