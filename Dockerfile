# syntax=docker.io/docker/dockerfile:1.4
FROM --platform=linux/riscv64 riscv64/ubuntu:22.04 as builder

RUN <<EOF
apt-get update
apt-get install -y --no-install-recommends \
  build-essential=12.9ubuntu3 \
  lua5.4=5.4.4-1 \
  liblua5.4-dev=5.4.4-1 \
  luarocks=3.8.0+dfsg1-1
rm -rf /var/lib/apt/lists/* /var/log/*
EOF

RUN <<EOF
luarocks install --lua-version=5.4 luasocket 3.1.0-1
luarocks install --lua-version=5.4 lua-cjson 2.1.0.10-1
EOF

FROM --platform=linux/riscv64 riscv64/ubuntu:22.04

LABEL io.sunodo.sdk_version=0.2.0
LABEL io.cartesi.rollups.ram_size=128Mi

ARG MACHINE_EMULATOR_TOOLS_VERSION=0.12.0
RUN <<EOF
apt-get update
apt-get install -y --no-install-recommends \
  busybox-static=1:1.30.1-7ubuntu3 \
  lua5.4=5.4.4-1
rm -rf /var/lib/apt/lists/* /var/log/*
EOF

COPY --from=builder /usr/local/lib/lua /usr/local/lib/lua
COPY --from=builder /usr/local/share/lua /usr/local/share/lua

ADD https://github.com/cartesi/machine-emulator-tools/releases/download/v${MACHINE_EMULATOR_TOOLS_VERSION}/machine-emulator-tools-v${MACHINE_EMULATOR_TOOLS_VERSION}.deb /tmp/machine-emulator-tools.deb
RUN <<EOF
dpkg -i /tmp/machine-emulator-tools.deb
rm -f /tmp/machine-emulator-tools.deb
EOF

WORKDIR /opt/cartesi/dapp
COPY . .

ENV PATH="/opt/cartesi/bin:/opt/cartesi/dapp:${PATH}"
ENV ROLLUP_HTTP_SERVER_URL="http://127.0.0.1:5004"
ENV RUST_LOG=warn
ENTRYPOINT ["rollup-init"]
CMD ["lua", "dapp.lua"]
