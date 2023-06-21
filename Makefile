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
	-Wformat -Werror=format-security
INCS := -I/opt/riscv/kernel/work/linux-headers/include
LDFLAGS := -Wl,-O1,--sort-common,-z,relro,-z,now,--as-needed

RPC_PROTOCOL=jsonrpc
MACHINE_ENTRYPOINT := "/home/dapp/honeypot 2>/dev/null"
MACHINE_FLAGS := \
	--assert-rolling-template \
    --ram-length=128Mi\
    --rollup \
	--flash-drive=label:root,filename:rootfs.ext2 \
	--flash-drive=label:honeypot_dapp_state,length:4096

.PHONY: lint test stress-test clean format-lua

honeypot: honeypot.cpp
	$(CXX) $(CXXFLAGS) $(INCS) $(LDFLAGS) -o $@ $^

rootfs.tar: Dockerfile honeypot.cpp
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
