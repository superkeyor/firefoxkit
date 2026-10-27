#!/usr/bin/env bash
# Start Xvfb (+ x11vnc + noVNC when ENABLE_VNC=true) in the background.
# Usage in the child's start.sh, before launching the app:  vnc-start
#   ENABLE_VNC=true   -> Xvfb + x11vnc + noVNC at http://<host>:6080/
#   VNC_PASSWORD=...  -> require a password (strongly advised if port is exposed)
#   ENABLE_WM=true    -> also start fluxbox (window manager: active window, title bars, taskbar)
# Otherwise only Xvfb is started, so non-headless firefox still works.

rm -f /tmp/.X99-lock "/tmp/.X11-unix/X${DISPLAY#:}"
Xvfb "$DISPLAY" -screen 0 "$SCREEN_GEOMETRY" -nolisten tcp &

# wait for the X socket (max ~5s)
for _ in $(seq 50); do
    [ -S "/tmp/.X11-unix/X${DISPLAY#:}" ] && break
    sleep 0.1
done

if [ ! -S "/tmp/.X11-unix/X${DISPLAY#:}" ]; then
    echo "vnc-start: Xvfb failed to start on $DISPLAY" >&2
    exit 1
fi

if [ "$ENABLE_WM" = "true" ]; then
    # fluxbox, not openbox: under openbox every Firefox window after the first stays black
    fluxbox >/dev/null 2>&1 &
fi

if [ "$ENABLE_VNC" = "true" ]; then
    if [ -n "$VNC_PASSWORD" ]; then
        x11vnc -storepasswd "$VNC_PASSWORD" /tmp/vncpass >/dev/null 2>&1
        AUTH="-rfbauth /tmp/vncpass"
    else
        AUTH="-nopw"
    fi
    # -localhost: raw VNC reachable only inside the container; web goes via websockify
    x11vnc -display "$DISPLAY" -forever -shared -localhost -rfbport 5900 $AUTH -quiet &
    websockify --web /usr/share/novnc 6080 localhost:5900 &
fi
