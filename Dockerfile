# syntax=docker.io/docker/dockerfile:1.4
FROM --platform=linux/riscv64 riscv64/ubuntu:22.04 as builder

RUN <<EOF
apt-get update
apt-get install -y --no-install-recommends build-essential
apt-get install -y --no-install-recommends clang-tidy
rm -rf /var/lib/apt/lists/*
EOF

COPY --from=sunodo/sdk:0.1.0 /opt/riscv /opt/riscv
WORKDIR /home/dapp
COPY . .
RUN make lint
RUN make

FROM --platform=linux/riscv64 riscv64/ubuntu:22.04

RUN <<EOF
apt-get update
apt-get install -y --no-install-recommends busybox-static=1:1.30.1-7ubuntu3
rm -rf /var/lib/apt/lists/*
EOF

COPY --from=sunodo/machine-emulator-tools:0.11.0-ubuntu22.04 / /
ENV PATH="/opt/cartesi/bin:${PATH}"

WORKDIR /home/dapp
COPY --from=builder /home/dapp/honeypot .

ENTRYPOINT ["/home/dapp/honeypot"]
