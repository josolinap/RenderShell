#!/bin/sh
# Web terminal launcher (ttyd + tmux).
#
# ttyd listens on loopback only; `tailscale serve` proxies it onto the tailnet
# (see supervisord.conf). Login is HTTP basic auth: user "root" + ROOT_PASSWORD.
# Each browser connection attaches to one shared tmux session, so a page
# reload, a dropped connection or a second device picks up where you left off.
# (A container restart or free-tier sleep still ends the session.)

export HOME=/root
export SHELL=/bin/bash
export TERM=xterm-256color
cd "$HOME" || exit 1

PORT="${TTYD_PORT:-4200}"

# Optional hardening: reject WebSocket connections from other origins.
# Off by default; set TTYD_CHECK_ORIGIN=1 and confirm the terminal still
# connects through `tailscale serve` before relying on it.
ORIGIN_FLAG=""
if [ "${TTYD_CHECK_ORIGIN:-0}" = "1" ]; then
    ORIGIN_FLAG="--check-origin"
fi

# shellcheck disable=SC2086  # ORIGIN_FLAG is intentionally unquoted (empty or one flag)
exec ttyd \
    --port "$PORT" \
    --interface lo \
    --writable \
    --credential "root:${ROOT_PASSWORD:-change-me}" \
    $ORIGIN_FLAG \
    -t titleFixed=render-shell \
    -t fontSize=15 \
    -t disableLeaveAlert=true \
    -t 'theme={"background":"#1e2327","foreground":"#d3c6aa","cursor":"#d3c6aa"}' \
    tmux new-session -A -s main 'cat /etc/motd; exec bash -l'
