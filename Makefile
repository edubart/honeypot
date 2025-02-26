CXX = gcc
WARN_CXXFLAGS = -Wall -Wextra -Wpedantic -Wformat -Werror=format-security
OPT_CXXFLAGS = -O1
HARDEN_CXXFLAGS = \
	-D_FORTIFY_SOURCE=3 \
	-D_GLIBCXX_ASSERTIONS \
	-ftrivial-auto-var-init=zero \
	-fstack-protector-strong \
	-fstack-clash-protection \
	-fno-strict-aliasing \
	-fno-strict-overflow \
	-fPIE
CXXFLAGS += \
	-std=c++20 \
	-fno-exceptions \
	-fno-rtti \
	$(WARN_CXXFLAGS) \
	$(OPT_CXXFLAGS)

HARDEN_LDFLAGS = \
	-pie \
	-Wl,-z,relro \
	-Wl,-z,now
LIBS = -l:libcmt.a
LDFLAGS += -Wl,--build-id=none $(HARDEN_LDFLAGS) $(LIBS)

MACHINE_ENTRYPOINT = /home/dapp/honeypot
MACHINE_FLAGS = \
	--ram-image=linux.bin \
	--flash-drive=label:root,filename:rootfs.ext2 \
	--flash-drive=label:state,length:4096

# TODO: remove me
INCS += -I/home/bart/projects/cartesi/machine/guest-tools/sys-utils/libcmt/include

honeypot: honeypot.cpp honeypot-config.hpp
	$(CXX) $(CXXFLAGS) $(HARDEN_CXXFLAGS) -o $@ $< $(LDFLAGS)

rootfs.tar: Dockerfile honeypot.cpp honeypot-config.hpp
	docker buildx build --progress plain --output type=tar,dest=$@ .

rootfs.ext2: rootfs.tar
	xgenext2fs --block-size 4096 --faketime --readjustment +4096 --tarball $< $@

linux.bin:
	wget -O linux.bin https://github.com/cartesi/machine-linux-image/releases/download/v0.20.0/linux-6.5.13-ctsi-1-v0.20.0.bin

snapshot: rootfs.ext2 linux.bin
	rm -rf snapshot
	cartesi-machine $(MACHINE_FLAGS) --assert-rolling-template --final-hash --store=$@ -- $(MACHINE_ENTRYPOINT)

shell: rootfs.ext2 linux.bin
	cartesi-machine $(MACHINE_FLAGS) -v=.:/mnt -u=root -i -- /bin/bash

lint: honeypot.cpp honeypot-config.hpp
	clang-tidy $^ -- $(CXXFLAGS) $(INCS)

lint-lua:
	luacheck .

format: honeypot.cpp honeypot-config.hpp
	clang-format -i $^

format-lua:
	stylua --indent-type Spaces --collapse-simple-statement Always \
		*.lua \
		cartesi-testlib/encode-utils.lua

test: snapshot
	lua5.4 honeypot-tests.lua

stress-test: snapshot
	lua5.4 honeypot-stress-tests.lua

clean:
	rm -rf snapshot rootfs.ext2 rootfs.tar honeypot

distclean: clean
	rm -rf linux.bin

.PHONY: shell lint format format-lua test stress-test clean distclean
