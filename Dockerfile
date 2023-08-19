################################
# Stage 1 (compile)
FROM --platform=linux/riscv64 riscv64/ubuntu:22.04 as builder

# Install dependencies
RUN apt-get update
RUN apt-get install -y --no-install-recommends build-essential clang-tidy

# Install linux headers
COPY dep/linux-libc-dev.deb /root/linux-libc-dev.deb
RUN dpkg -i /root/linux-libc-dev.deb

# Compile
WORKDIR /home/dapp
COPY Makefile .
COPY honeypot.cpp .
RUN make lint
RUN make

################################
# Stage 2 (final rootfs)
FROM --platform=linux/riscv64 riscv64/ubuntu:22.04

# Install dependencies
RUN apt-get update
RUN apt-get install -y --no-install-recommends busybox-static=1:1.30.1-7ubuntu3
RUN rm -rf /var/lib/apt/lists/* /var/log/*

# Install init
RUN mkdir -p /opt/cartesi/bin
COPY --chmod=755 dep/init /opt/cartesi/bin/init

# Install honeypot
WORKDIR /home/dapp
COPY --from=builder /home/dapp/honeypot .
