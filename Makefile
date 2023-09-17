MACHINE_ENTRYPOINT := \
	cd /opt/cartesi/dapp;\
	PATH=/opt/cartesi/bin:/opt/cartesi/dapp:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
	RUST_LOG=warn \
	ROLLUP_HTTP_SERVER_URL=http://127.0.0.1:5004 \
	rollup-init lua dapp.lua

MACHINE_FLAGS := \
	--ram-length=128Mi \
	--flash-drive=label:root,filename:.sunodo/image.ext2 \
	--rollup --assert-rolling-template

all: rootfs image config
rootfs: .sunodo/image.ext2
image: .sunodo/image
config: .sunodo/image.config.lua

.sunodo/image.tar: Dockerfile *.lua luadeps/*.lua
	mkdir -p .sunodo
	docker buildx build --progress plain --output type=tar,dest=$@ .

.sunodo/image.ext2: .sunodo/image.tar
	genext2fs \
		--tarball $< \
		--block-size 4096 \
		--faketime \
		--readjustment +4096 \
		$@

.sunodo/image: .sunodo/image.ext2
	rm -rf $@
	cartesi-machine $(MACHINE_FLAGS) --final-hash --store=$@ -- "$(MACHINE_ENTRYPOINT)"

.sunodo/image.config.lua: .sunodo/image.ext2
	cartesi-machine $(MACHINE_FLAGS) --store-config=$@ --max-mcycle=0 -- "$(MACHINE_ENTRYPOINT)" || true

clean:
	rm -rf .sunodo

test: config
	lua5.4 tests/basic-tests.lua

shell: rootfs
	cartesi-machine $(MACHINE_FLAGS) -i -- /bin/bash

lint:
	luacheck .

quick-test:
	e2cp *.lua .sunodo/image.ext2:/opt/cartesi/dapp/
	lua5.4 tests/basic-tests.lua

live-dev:
	luamon -e lua -x "make quick-test"

run-node:
	sunodo build
	sunodo run

.PHONY: all rootfs image clean test shell lint

