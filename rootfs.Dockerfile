################################
# honeypot builder
FROM --platform=linux/riscv64 riscv64/ubuntu:noble-20250127 as builder

# Install build essential
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential=12.10ubuntu1

# Install libcmt
ARG MACHINE_EMULATOR_TOOLS_VERSION=0.16.1
ADD https://github.com/cartesi/machine-guest-tools/releases/download/v${MACHINE_EMULATOR_TOOLS_VERSION}/libcmt-dev-v${MACHINE_EMULATOR_TOOLS_VERSION}.deb /tmp/
RUN dpkg -i /tmp/libcmt-dev-v${MACHINE_EMULATOR_TOOLS_VERSION}.deb

# Compile
WORKDIR /home/dapp
COPY Makefile .
COPY honeypot.cpp .
COPY honeypot-config.hpp .
ENV SOURCE_DATE_EPOCH=0
RUN make

################################
# rootfs builder
FROM --platform=linux/riscv64 riscv64/ubuntu:noble-20250127

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    busybox-static=1:1.36.1-6ubuntu3.1 && \
    rm -rf /var/lib/apt/lists/* /var/log/* /var/cache/*

# Install guest tools
ARG MACHINE_EMULATOR_TOOLS_VERSION=0.16.1
ADD https://github.com/cartesi/machine-emulator-tools/releases/download/v${MACHINE_EMULATOR_TOOLS_VERSION}/machine-emulator-tools-v${MACHINE_EMULATOR_TOOLS_VERSION}.deb /tmp/
RUN dpkg -i /tmp/machine-emulator-tools-v${MACHINE_EMULATOR_TOOLS_VERSION}.deb

# Give permission for dapp user to access /dev/pmem1
RUN mkdir -p /etc/cartesi-init.d && \
    echo "chown dapp:dapp /dev/pmem1" > /etc/cartesi-init.d/dapp-state && \
    chmod 755 /etc/cartesi-init.d/dapp-state

# Install honeypot
WORKDIR /home/dapp
COPY --from=builder /home/dapp/honeypot .
