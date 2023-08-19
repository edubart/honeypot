CONFIG_ERC20_PORTAL_ADDRESS     := "{0x43,0x40,0xac,0x4F,0xcd,0xFC,0x5e,0xF8,0xd3,0x49,0x30,0xC9,0x6B,0xBa,0xc2,0xAf,0x13,0x01,0xDF,0x40}"
CONFIG_ERC20_WITHDRAWAL_ADDRESS := "{0x70,0x99,0x79,0x70,0xC5,0x18,0x12,0xdc,0x3A,0x01,0x0C,0x7d,0x01,0xb5,0x0e,0x0d,0x17,0xdc,0x79,0xC8}"
CONFIG_ERC20_CONTRACT_ADDRESS   := "{0xc6,0xe7,0xDF,0x5E,0x7b,0x4f,0x2A,0x27,0x89,0x06,0x86,0x2b,0x61,0x20,0x58,0x50,0x34,0x4D,0x4e,0x7d}"
CONFIG_STATE_BLOCK_DEVICE       := "/dev/mtdblock1"

CXX := g++
CXXFLAGS := \
	-std=c++17 \
	-O1 \
	-fno-exceptions \
	-fno-rtti \
	-fno-strict-aliasing \
	-fno-strict-overflow \
	-fstack-protector-strong \
	-D_FORTIFY_SOURCE=2 \
	-D_GLIBCXX_ASSERTIONS \
	-Wall \
	-Wextra \
	-Werror \
	-Wformat -Werror=format-security \
	-DCONFIG_ERC20_PORTAL_ADDRESS=$(CONFIG_ERC20_PORTAL_ADDRESS) \
	-DCONFIG_ERC20_WITHDRAWAL_ADDRESS=$(CONFIG_ERC20_WITHDRAWAL_ADDRESS) \
	-DCONFIG_ERC20_CONTRACT_ADDRESS=$(CONFIG_ERC20_CONTRACT_ADDRESS) \
	-DCONFIG_STATE_BLOCK_DEVICE='$(CONFIG_STATE_BLOCK_DEVICE)'
LDFLAGS := -Wl,-O1,--sort-common,-z,relro,-z,now,--as-needed

RPC_PROTOCOL=jsonrpc
MACHINE_ENTRYPOINT := /home/dapp/honeypot
MACHINE_FLAGS := \
	--assert-rolling-template \
	--ram-length=64Mi\
	--rollup \
	--flash-drive=label:root,filename:rootfs.ext2 \
	--flash-drive=label:honeypot_dapp_state,length:4096

.PHONY: lint test stress-test clean format-lua

honeypot: honeypot.cpp
	$(CXX) $(CXXFLAGS) $(LDFLAGS) -o $@ $<

rootfs.tar: Dockerfile honeypot.cpp dep
	docker buildx build --progress plain --output type=tar,dest=$@ .

rootfs.ext2: rootfs.tar
	genext2fs \
		--tarball $< \
		--block-size 4096 \
		--faketime \
		--readjustment +4096 \
		$@

snapshot: rootfs.ext2
	rm -rf snapshot
	cartesi-machine $(MACHINE_FLAGS) --final-hash --store=$@ -- $(MACHINE_ENTRYPOINT)

shell: rootfs.ext2
	cartesi-machine $(MACHINE_FLAGS) -i -- /bin/bash

lint: honeypot.cpp
	clang-tidy honeypot.cpp -- $(CXXFLAGS) $(INCS)

test: snapshot
	lua5.4 honeypot-usual-tests.lua $(RPC_PROTOCOL)
	lua5.4 honeypot-edge-tests.lua $(RPC_PROTOCOL)

stress-test: snapshot
	lua5.4 honeypot-stress-tests.lua

clean:
	rm -rf snapshot rootfs.ext2 rootfs.tar honeypot

format-lua:
	stylua --indent-type Spaces --collapse-simple-statement Always \
		*.lua \
		cartesi-testlib/encode-utils.lua \
		cartesi-testlib/rolling-machine.lua

dep:
	mkdir -p dep

downloads: dep
	cat dependencies | tr -s ' ' | cut -d ' ' -f2,3 | xargs -n2 wget -c -O
	cat dependencies | tr -s ' ' | cut -d ' ' -f1,2 | sha1sum -c

depclean:
	rm -rf dep
