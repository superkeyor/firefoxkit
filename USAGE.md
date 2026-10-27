# Using firefoxkit as a base image

Base = Debian trixie + Firefox (current release, from Mozilla's APT repo) + Xvfb + x11vnc + noVNC.
Sibling of `chromiumkit`, with the same layout and env vars; only the browser differs.
No Python/Miniforge/tini/cron/tzdata here; the app image gets those from `dockerapp_template`.
No geckodriver either: drive Firefox with an extension, or add WebDriver in the app image if you need it.

## 1. App Dockerfile

Take `dockerapp_template/Dockerfile` unchanged except the first lines:

```dockerfile
FROM superkeyor/firefoxkit:latest
ARG MINIFORGE_VERSION=26.9.4-0
```

(Replaces `FROM debian:trixie-...-slim`. Everything else stays, including its
`ENTRYPOINT ["tini", "--"]`.)

## 2. start.sh

Call `vnc-start` once, before launching the app:

```bash
#!/usr/bin/env bash

if [ "$ENABLE_CRON" = "true" ]; then
    cron
fi

# Starts the ONE Xvfb (:99, -nolisten tcp); plus x11vnc + noVNC if ENABLE_VNC=true.
# DISPLAY=:99 is already set in the image, so the app inherits it. Exits 1 if Xvfb fails.
vnc-start || exit 1

exec python main.py   # exec: app gets SIGTERM directly
```

Cron jobs do NOT inherit the container env. In `crontab`, set it per line or at the top:
`DISPLAY=:99`.

## 3. docker-compose.yml

```yaml
services:
    myapp:
        hostname: myapp                  # fixed: Firefox's profile lock embeds the hostname
        shm_size: 2gb                    # browsers crash on the default 64MB /dev/shm
        ports:
            - "127.0.0.1:6080:6080"      # noVNC; keep on localhost (or put behind a proxy)
        volumes:
            - ./ffprofile:/app/ffprofile # persistent profile (cookies, logins, extensions)
        environment:
            - ENABLE_VNC=true            # default false: Xvfb only, no VNC/noVNC
            - VNC_PASSWORD=${VNC_PASSWORD}   # empty = no password, anyone reaching 6080 controls the browser
            # - SCREEN_GEOMETRY=1920x1080x24
```

Open `http://localhost:6080/` (noVNC; click Connect, enter the password).
Put `ENABLE_VNC=true` in `docker-compose.override.yml` (dev) and leave it off in production
if you don't need to watch.

## 4. Env vars provided by the base

| Var | Default | Meaning |
|---|---|---|
| `DISPLAY` | `:99` | Display of the single Xvfb. Don't start another one. |
| `ENABLE_VNC` | `false` | `true` = also start x11vnc + noVNC on 6080 |
| `VNC_PASSWORD` | empty | Password for VNC |
| `SCREEN_GEOMETRY` | `1920x1080x24` | Xvfb screen `WxHxDepth` |

## 5. Running Firefox

Run it headed (no `--headless`) so it shows on the display. There is no window manager, so give
the window the screen size yourself:

```bash
firefox --no-remote --width 1920 --height 1080 -profile /app/ffprofile https://example.com
```

- `-profile DIR` (created if missing) keeps one explicit profile; `--no-remote` stops it from
  handing the URL to another running Firefox.
- Policies: put them in `/etc/firefox/policies/policies.json` in the app image. Useful ones for
  automation: `"SkipTermsOfUse": true` (otherwise a first-run Terms of Use dialog covers the page),
  `"DisableAppUpdate": true`, `"DisableTelemetry": true`, and `ExtensionSettings` to force-install a
  signed `.xpi` from `file:///...`. Verified: the Mozilla `.deb` reads `/etc/firefox/policies`.
- Prefs: put a `user.js` in the profile directory, e.g. `browser.translations.automaticallyPopup=false`,
  `browser.sessionstore.resume_from_crash=false`.
- Regular Firefox only installs **signed** extensions (AMO, including unlisted).
- Window manager: none is included. Add one only if you need an active window (e.g. OS-level input
  that checks `_NET_ACTIVE_WINDOW`). Use **fluxbox** (`apt-get install fluxbox`, start it with `fluxbox &`
  after `vnc-start`). Do not use **openbox**: under openbox every Firefox window after the first stays
  black on the display and in noVNC (pages still run). Verified on Firefox 158.

Tested on arm64 (OrbStack, Firefox 158.0.1): pages render on `:99` and in noVNC, CJK included, with
exactly one Xvfb.

## 6. Debugging

- `docker exec -it myapp pgrep -a "Xvfb|x11vnc|websockify|firefox"`
- `pkill firefox` to clear a stuck browser (procps is installed).
- Expected, harmless log lines: `Sandbox: CanCreateUserNamespace() clone() failure: EPERM` (Docker
  blocks user namespaces; Firefox runs with a reduced content sandbox, much like Chromium's
  `--no-sandbox`) and `Failed to create DBus proxy ... dbus-launch` (no D-Bus session in the container).
