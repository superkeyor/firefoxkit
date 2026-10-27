# =============================================================================
# Base Image: Debian + Firefox (Mozilla APT) + Xvfb + noVNC
# =============================================================================
# Sibling of chromiumkit with only the browser swapped. Only the Firefox/VNC pieces
# live here. Everything else (Miniforge, tini, tzdata, cron, TZ, python envs, WORKDIR,
# ENTRYPOINT) comes from the app image, i.e. from dockerapp_template, whose only change is:
#   FROM superkeyor/firefoxkit:latest
#   ARG MINIFORGE_VERSION=26.9.4-0
# and (the one addition elsewhere) a `vnc-start` line in the app's start.sh.
#
# https://hub.docker.com/_/debian/tags
# Use fixed versions (vs. latest) to avoid freq rebuild
FROM debian:trixie-20261020-slim

# Virtual display used by (non-headless) firefox; watch it via noVNC
ENV DISPLAY=:99
ENV ENABLE_VNC=false
ENV VNC_PASSWORD=
ENV SCREEN_GEOMETRY=1920x1080x24

# Firefox from Mozilla's own APT repo (amd64 + arm64, current release; Debian only ships ESR).
# https://support.mozilla.org/kb/install-firefox-linux#w_install-firefox-deb-package-for-debian-based-distributions
# The key fingerprint is the one Mozilla documents; the build fails if it ever differs.
ARG MOZILLA_REPO_FPR=35BAA0B33E9EB396F59CA838C0BA5CE6DC6315A3
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates curl gnupg && \
    install -d -m 0755 /etc/apt/keyrings && \
    curl -fsSL https://packages.mozilla.org/apt/repo-signing-key.gpg -o /etc/apt/keyrings/packages.mozilla.org.asc && \
    GNUPGHOME=$(mktemp -d) gpg --show-keys --with-colons /etc/apt/keyrings/packages.mozilla.org.asc | \
        awk -F: '$1=="fpr"{print $10; exit}' | grep -qx "$MOZILLA_REPO_FPR" && \
    echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" \
        > /etc/apt/sources.list.d/mozilla.list && \
    printf 'Package: *\nPin: origin packages.mozilla.org\nPin-Priority: 1000\n' > /etc/apt/preferences.d/mozilla && \
    apt-get purge -y --auto-remove gnupg && \
    rm -rf /var/lib/apt/lists/*

# procps: pkill for killing stuck firefox processes
# firefox: from Mozilla (see above); its package pulls the GTK/X11 libraries it needs
# xvfb xauth: virtual display; x11vnc + novnc + websockify: view it in a browser
# fonts-liberation fonts-dejavu-core fonts-noto-core fonts-noto-cjk: sane default fonts for rendering pages,
#   incl. Chinese/Japanese/Korean (a near-empty font list is also an easy bot fingerprint)
RUN export DEBIAN_FRONTEND=noninteractive && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        procps \
        firefox \
        xvfb \
        xauth \
        x11vnc \
        novnc \
        websockify \
        fonts-liberation \
        fonts-dejavu-core \
        fonts-noto-core \
        fonts-noto-cjk && \
    ln -sf /usr/share/novnc/vnc.html /usr/share/novnc/index.html && \
    rm -rf /var/lib/apt/lists/*

# Verify the Firefox binary; WebExtensions such as wbx need a recent release (>= 153)
RUN firefox --version && \
    [ "$(firefox --version | sed -E 's/[^0-9]*([0-9]+).*/\1/')" -ge 153 ]

# Call `vnc-start` from the app's start.sh (it no-ops unless ENABLE_VNC=true)
COPY vnc-start.sh /usr/local/bin/vnc-start
RUN chmod +x /usr/local/bin/vnc-start

# noVNC web UI (VNC itself, 5900, stays inside the container)
EXPOSE 6080
