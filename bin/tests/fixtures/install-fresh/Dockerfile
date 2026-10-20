# Fresh Ubuntu with systemd as PID 1 and a lingering user, for bin/tests/install-fresh.sh.
ARG BASE=ubuntu:24.04
FROM ${BASE}
ENV DEBIAN_FRONTEND=noninteractive container=docker
RUN apt-get update && apt-get install -y --no-install-recommends \
      systemd systemd-sysv dbus dbus-user-session python3 jq git procps iproute2 ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && (userdel -r ubuntu 2>/dev/null || true)
ARG CU
RUN useradd -m -s /bin/bash "$CU" && mkdir -p /var/lib/systemd/linger && touch "/var/lib/systemd/linger/$CU"
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
