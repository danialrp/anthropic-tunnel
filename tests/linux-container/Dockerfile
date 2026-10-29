FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv systemd-resolved iproute2 iputils-ping curl ca-certificates python3 sudo dnsutils nftables \
    && rm -rf /var/lib/apt/lists/* \
    && systemctl enable systemd-resolved \
    && useradd -m -s /bin/bash tester && echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-test
STOPSIGNAL SIGRTMIN+3
CMD ["/lib/systemd/systemd"]
