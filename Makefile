# Based on https://gist.github.com/trosendal/d4646812a43920bfe94e

DEPTAG := 1.0.7
DEPLIBNAME := ed25519_bip32
DEPLOC := https://github.com/spacemeshos/$(DEPLIBNAME)/releases/download
DEPLIB := lib$(DEPLIBNAME)
# Exclude dylib files (we only need the static libs)
EXCLUDE_PATTERN := "LICENSE" "*.so" "*.dylib"
UNZIP_DEST := deps
REAL_DEST := $(shell realpath .)/$(UNZIP_DEST)
DOWNLOAD_DEST := $(UNZIP_DEST)/$(DEPLIB).tar.gz
EXTLDFLAGS := -L$(UNZIP_DEST) -l$(DEPLIBNAME)

# Detect operating system
ifeq ($(OS),Windows_NT)
  SYSTEM := windows
else
  UNAME_S := $(shell uname -s)
  ifeq ($(UNAME_S),Linux)
	SYSTEM := linux
  else ifeq ($(UNAME_S),Darwin)
	SYSTEM := darwin
  else
	$(error Unknown operating system: $(UNAME_S))
  endif
endif

# Default values. Can be overridden on command line, e.g., inside CLI for cross-compilation.
# Note: this Makefile structure theoretically supports cross-compilation using GOOS and GOARCH.
# In practice, however, depending on the host and target OS/architecture, you'll likely run into
# errors in both the compiler and the linker when trying to compile cross-platform.
GOOS ?= $(SYSTEM)
GOARCH ?= unknown

# Detect processor architecture
ifeq ($(GOARCH),unknown)
	UNAME_M := $(shell uname -m)
	ifeq ($(UNAME_M),x86_64)
	  GOARCH := amd64
	else ifneq ($(filter %86,$(UNAME_M)),)
	  $(error Unsupported processor architecture: $(UNAME_M))
	else ifneq ($(filter arm%,$(UNAME_M)),)
	  GOARCH := arm64
	else ifneq ($(filter aarch64%,$(UNAME_M)),)
	  GOARCH := arm64
	else
	  $(error Unknown processor architecture: $(UNAME_M))
	endif
endif

ifeq ($(GOOS),linux)
	MACHINE = linux

	# Linux specific settings
	# We do a static build on Linux using musl toolchain
	CPREFIX = CC=musl-gcc
	LDFLAGS = -linkmode external -extldflags "-static $(EXTLDFLAGS)"
else ifeq ($(GOOS),darwin)
	MACHINE = macos

	# macOS specific settings
	# dynamic build using default toolchain
	LDFLAGS = -extldflags "$(EXTLDFLAGS)"
else ifeq ($(GOOS),windows)
	# static build using default toolchain
	# add a few extra required libs
	LDFLAGS = -linkmode external -extldflags "-static $(EXTLDFLAGS) -lws2_32 -luserenv -lbcrypt"
else
	$(error Unknown operating system: $(GOOS))
endif

ifeq ($(SYSTEM),windows)
	# Windows settings
	# TODO: this is probably unnecessary, most Windows dev environments (including GHA)
	# should support bash
	RM = del /Q /F
	RMDIR = rmdir /S /Q
	MKDIR = mkdir

	FN = $(DEPLIB)_windows-amd64.zip
	DOWNLOAD_DEST = $(UNZIP_DEST)/$(DEPLIB).zip
	EXTRACT = 7z x -y

	# TODO: fix this, it doesn't seem to work as expected
	#EXCLUDES = -x!$(EXCLUDE_PATTERN)
else
	# Linux and macOS settings
	RM = rm -f
	RMDIR = rm -rf
	MKDIR = mkdir -p
	EXCLUDES = $(addprefix --exclude=,$(EXCLUDE_PATTERN))
	EXTRACT = tar -xzf

	ifeq ($(GOARCH),amd64)
		PLATFORM = $(MACHINE)-amd64
	else ifeq ($(GOARCH),arm64)
		PLATFORM = $(MACHINE)-arm64
	else
		$(error Unknown processor architecture: $(GOARCH))
	endif
	FN = $(DEPLIB)_$(PLATFORM).tar.gz
endif

$(UNZIP_DEST): $(DOWNLOAD_DEST)
	cd $(UNZIP_DEST) && $(EXTRACT) ../$(DOWNLOAD_DEST) $(EXCLUDES)

$(DOWNLOAD_DEST):
	$(MKDIR) $(UNZIP_DEST)
	curl -sSfL $(DEPLOC)/v$(DEPTAG)/$(FN) -o $(DOWNLOAD_DEST)

.PHONY: build
build: $(UNZIP_DEST)
	$(CPREFIX) GOOS=$(GOOS) GOARCH=$(GOARCH) CGO_ENABLED=1 go build -ldflags '$(LDFLAGS)'

.PHONY: test
test: $(UNZIP_DEST)
	LD_LIBRARY_PATH=$(REAL_DEST) go test -v -ldflags "-extldflags \"-L$(REAL_DEST) -led25519_bip32\"" ./...

clean:
	$(RM) $(DOWNLOAD_DEST)
	$(RMDIR) $(UNZIP_DEST)