FROM --platform=linux/riscv64 riscv64/ubuntu:22.04 as builder

RUN <<EOF
apt-get update
apt-get install -y --no-install-recommends build-essential
EOF

RUN <<EOF
apt-get install -y --no-install-recommends luarocks lua5.4-dev lua5.4
luarocks install --lua-version=5.4 lunix
EOF

FROM --platform=linux/riscv64 riscv64/ubuntu:22.04

RUN <<EOF
apt-get update
apt-get install -y --no-install-recommends busybox-static=1:1.30.1-7ubuntu3 lua5.4
rm -rf /var/lib/apt/lists/*
EOF

COPY --from=sunodo/machine-emulator-tools:0.11.0-ubuntu22.04 / /
ENV PATH="/opt/cartesi/bin:${PATH}"

WORKDIR /home/dapp
COPY ./cartesi-testlib/bint.lua /usr/local/lib/lua/5.4/bint.lua
COPY --from=builder /usr/local/lib/lua/5.4/unix.so /usr/local/lib/lua/5.4/unix.so
COPY --chmod=755 honeypot.lua /home/dapp/honeypot

ENTRYPOINT ["/home/dapp/honeypot]
