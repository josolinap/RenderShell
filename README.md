# render_tailscaled + ttyd

A Render free-tier web service that combines:
- **Tailscale exit node** — routes your traffic through Render's IP
- **ttyd web terminal** — browser-based root shell (xterm.js + tmux), accessible via your Tailnet
- **HTTP status page** — placeholder page on the public Render URL

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  Render Free Web Service (HTTPS)                    │
│                                                     │
│  ┌──────────────────────────────────────────────┐   │
│  │  supervisord (PID 1 via tini)                │   │
│  │                                              │   │
│  │  ┌─ tailscaled (userspace networking) ──┐    │   │
│  │  │  ↳ registers as exit node via authkey│    │   │
│  │  └──────────────────────────────────────┘    │   │
│  │                                              │   │
│  │  ┌─ ttyd + tmux (127.0.0.1:4200) ───────┐    │   │
│  │  │  ↳ web terminal (Tailnet-only)       │    │   │
│  │  └──────────────────────────────────────┘    │   │
│  │                                              │   │
│  │  ┌─ python http.server (port 8080) ─────┐    │   │
│  │  │  ↳ status page (Render public URL)   │    │   │
│  │  └──────────────────────────────────────┘    │   │
│  └──────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
         ↑                          ↑
         │ public HTTPS              │ Tailnet only
         │ (https://...onrender.com) │ (http://render-exit-node:4200)
```

## Setup

### 1. Generate a Tailscale authkey

Go to https://login.tailscale.com/admin/settings/keys and generate:
- **Reusable**: yes (so it survives restarts)
- **Ephemeral**: no (so the node persists)
- **Tags**: optional (e.g. `tag:exit-node`)

Copy the key — it looks like `tskey-auth-XXXXXXXX-YYYYYYYYYYYYYYYY`.

### 2. Deploy to Render

1. Push this repo to GitHub
2. On Render: **New → Web Service → connect repo**
3. **Environment**: Docker
4. **Instance Type**: Free
5. **Environment Variables**:

| Key | Value | Purpose |
|---|---|---|
| `TAILSCALE_AUTHKEY` | `tskey-auth-XXXX-YYYY` | Auto-registers the node on your Tailnet |
| `ROOT_PASSWORD` | `your-strong-password` | Password for the web terminal login |
| `TAILSCALE_HOSTNAME` | `render-shell` | (optional) Custom hostname on your Tailnet |

### 3. Approve the exit node

After the first deploy:
1. Go to https://login.tailscale.com/admin/machines
2. Find the new node (`render-shell` or similar)
3. Click the `⚠` icon next to "Exit node" and approve it

### 4. Use the exit node

On any device on your Tailnet:
```bash
# Use the exit node for all traffic
tailscale up --exit-node=render-shell

# Or use it for specific traffic
tailscale up --exit-node=render-shell --exit-node-allow-lan-access=true
```

### 5. Access the web terminal

The ttyd terminal is **only accessible via your Tailnet** (not the public Render URL):

```
http://render-shell.<your-tailnet>.ts.net:4200
```

Or find the IP:
```bash
tailscale status | grep render-shell
# → 100.x.x.x  render-shell  ...
```

Then open `http://100.x.x.x:4200` in your browser. Your browser will ask for a login (HTTP basic auth): use `root` + your `ROOT_PASSWORD`.

## What's exposed where

| Port | Where | What |
|---|---|---|
| 8080 | Public Render URL (`https://...onrender.com`) | Status page (HTML) |
| 4200 | Tailnet only (`http://render-shell:4200`) | ttyd web terminal |
| — | Tailscale | Exit node routing |

The web terminal is **not** on the public Render URL — only the status page is. This is intentional: the terminal should be private.

## Environment variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `TAILSCALE_AUTHKEY` | ✅ yes | — | Tailscale authkey for auto-registration |
| `ROOT_PASSWORD` | ✅ yes | `change-me` | Password for the web terminal login (user `root`) |
| `TTYD_CHECK_ORIGIN` | no | `0` | Set to `1` to reject cross-origin WebSocket connections (test that the terminal still connects first) |
| `TAILSCALE_HOSTNAME` | no | `render-exit-node` | Hostname on your Tailnet |
| `TS_VERSION` | no | `1.86.2` | Tailscale version (build arg) |

## Free tier limitations

- **512MB RAM, 0.1 CPU** — enough for the web terminal + light dev work
- **Sleeps after 15 min inactivity** — terminal sessions die on sleep; the Tailscale exit node also drops
- **750 instance-hours/month** (~31 days) — enough for 24/7 for one month
- **No persistent disk** — files in `/root` are lost on restart

## Customization

### Auto-login (no password prompt)

Edit `start-terminal.sh` and delete the `--credential` line (and its trailing `\`).

⚠ Anyone on your Tailnet gets a root shell without a password.

### Terminal theme and font

Edit the `-t` (client option) lines in `start-terminal.sh`, for example:
```
-t fontSize=16
-t 'theme={"background":"#000000","foreground":"#ffffff"}'
```
Any xterm.js option can be set this way; see the
[ttyd client options](https://github.com/tsl0922/ttyd/wiki/Client-Options).

### Persistent terminal sessions (tmux)

The terminal attaches to a shared tmux session named `main`, so reloading the
page, a flaky connection or opening a second device reconnects to the same
shell. Mouse-wheel scrolling works through tmux (`/etc/tmux.conf`, copied from
`tmux.conf`). The session still ends when the container restarts or sleeps.

### Keep container awake (prevents sleep)

Add a self-ping cron job in the Dockerfile:
```dockerfile
RUN echo '*/10 * * * * wget -q -O- http://localhost:8080 >/dev/null' > /etc/crontabs/root
RUN apk add --no-cache dcron
# Add to supervisord.conf: [program:cron] command=crond -f
```
⚠ Burns your 750 free hours faster.

## Troubleshooting

**"tailscale up" fails in logs**
- Check that `TAILSCALE_AUTHKEY` is set correctly in Render env vars
- Check that the authkey hasn't expired (reusable keys last 90 days)
- Check Render logs for the exact error

**Web terminal not reachable at `http://render-shell:4200`**
- Verify the node is online: `tailscale status | grep render-shell`
- Userspace networking doesn't expose ports to the Tailnet directly — you may need to use `tailscale serve` or `tailscale funnel` to expose 4200

**Exit node not routing traffic**
- Approve the exit node in https://login.tailscale.com/admin/machines
- On the client: `tailscale up --exit-node=render-shell`
- Check: `curl https://api.ipify.org` should show Render's IP, not yours

**Container sleeps and drops the exit node**
- This is expected on free tier (15 min inactivity)
- Either upgrade to paid tier, or add a self-ping (see above)
