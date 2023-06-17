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

.PHONY: lint test clean

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
	cartesi-machine \
        --assert-rolling-template \
        --ram-length=128Mi\
        --rollup \
		--flash-drive=label:root,filename:$< \
		--final-hash \
        --store=$@ \
        -- /home/dapp/honeypot

lint: honeypot.cpp
	clang-tidy honeypot.cpp -- $(CXXFLAGS) $(INCS)

test: snapshot
	lua5.4 honeypot-usual-tests.lua
	lua5.4 honeypot-edge-tests.lua

clean:
	rm -rf snapshot rootfs.ext2 rootfs.tar honeypot
