# Cross-compilacion de mkxp-z para Trimui Smart Pro (aarch64, glibc 2.31 < 2.34)
FROM debian:bullseye-slim
ENV DEBIAN_FRONTEND=noninteractive

# Bullseye esta archivado: apuntar apt a archive.debian.org
RUN rm -f /etc/apt/sources.list.d/* \
 && printf 'deb http://archive.debian.org/debian bullseye main\ndeb http://archive.debian.org/debian-security bullseye-security main\n' > /etc/apt/sources.list \
 && printf 'Acquire::Check-Valid-Until "false";\nAcquire::Retries "5";\n' > /etc/apt/apt.conf.d/99archive

RUN dpkg --add-architecture arm64 && apt-get update && apt-get install -y --no-install-recommends \
    build-essential gcc-aarch64-linux-gnu g++-aarch64-linux-gnu binutils-aarch64-linux-gnu \
    make file git curl ca-certificates pkg-config cmake ninja-build \
    python3 python3-pip python3-setuptools bison flex autoconf automake libtool xxd unzip xz-utils patch \
    ruby qemu-user-static \
    libsdl2-dev:arm64 libasound2-dev:arm64 \
 && rm -rf /var/lib/apt/lists/*

# mkxp-z exige meson >= 1.4 (bullseye trae 0.56)
RUN pip3 install --no-cache-dir "meson>=1.4,<2"

WORKDIR /work
CMD ["bash"]
