FROM alpine:3.20 AS tailscale-builder
ARG TS_VERSION=1.86.2
RUN apk add --no-cache curl ca-certificates
WORKDIR /tmp
RUN curl -fsSL "https://pkgs.tailscale.com/stable/tailscale_${TS_VERSION}_amd64.tgz" | \
    tar -xz --strip-components=1

# ---------- Runtime stage ----------
FROM alpine:3.20

# Core packages. ttyd (web terminal) and tmux come from Alpine's stable repos.
RUN apk add --no-cache \
        ca-certificates \
        tini \
        supervisor \
        python3 \
        shadow \
        curl \
        git \
        vim \
        nano \
        openssh-client \
        openssh-keygen \
        tmux \
        ttyd \
        htop \
        bash \
        coreutils \
        findutils \
        grep \
        tar \
        gzip \
        unzip \
        wget

# Install File Browser (lightweight web file manager, ~15MB binary)
RUN curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash && \
    filebrowser config init --database /etc/filebrowser.db && \
    filebrowser config set --database /etc/filebrowser.db \
        --address 0.0.0.0 \
        --port 5800 \
        --root /root && \
    filebrowser users add --database /etc/filebrowser.db \
        admin "${FILEBROWSER_PASSWORD:-admin}" \
        --perm.admin 2>/dev/null || true

# Copy tailscale binaries from builder
COPY --from=tailscale-builder /tmp/tailscaled /usr/local/bin/tailscaled
COPY --from=tailscale-builder /tmp/tailscale   /usr/local/bin/tailscale

# Supervisor config
COPY supervisord.conf /etc/supervisor/conf.d/services.conf

# Web terminal launcher (ttyd + tmux)
COPY start-terminal.sh /usr/local/bin/start-terminal.sh
COPY tmux.conf /etc/tmux.conf
RUN chmod +x /usr/local/bin/start-terminal.sh

# Entrypoint
COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

# Set up root password (override at runtime with ROOT_PASSWORD env var)
ENV ROOT_PASSWORD=change-me
ENV FILEBROWSER_PASSWORD=admin
RUN echo "root:${ROOT_PASSWORD}" | chpasswd

# Use bash as root's login shell and set a friendly hostname
RUN sed -i 's|^root:x:0:0:root:/root:/bin/.*|root:x:0:0:root:/root:/bin/bash|' /etc/passwd && \
    echo "render-shell" > /etc/hostname

# Workspace + status page
RUN mkdir -p /var/run/tailscale /workspace

RUN printf '%s\n' \
  '<!DOCTYPE html>' \
  '<html><head><title>Render Shell</title>' \
  '<style>body{font-family:system-ui,sans-serif;max-width:700px;margin:50px auto;padding:0 20px;color:#333}' \
  '.card{background:#f5f5f5;padding:20px;border-radius:8px;margin:15px 0}' \
  'a{color:#1976d2;text-decoration:none;font-weight:500}' \
  'a:hover{text-decoration:underline}code{background:#e0e0e0;padding:2px 6px;border-radius:3px}</style></head>' \
  '<body><h1>Render Shell + File Browser</h1>' \
  '<div class="card"><h3>Web Terminal (ttyd)</h3>' \
  '<p>HTTPS via Tailscale Serve: <code>https://render-exit-node.curl-trench.ts.net/</code></p></div>' \
  '<div class="card"><h3>File Browser (GUI)</h3>' \
  '<p>HTTPS via Tailscale Serve: <code>https://render-exit-node.curl-trench.ts.net:5800/</code></p>' \
  '<p>Login: <code>admin</code> / password from <code>FILEBROWSER_PASSWORD</code> env var</p></div>' \
  '<div class="card"><h3>Tailscale Exit Node</h3><p>Active and available for your tailnet.</p></div>' \
  '</body></html>' > /workspace/index.html

WORKDIR /workspace

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD tailscale status >/dev/null 2>&1 || exit 1

EXPOSE 8080 4200 5800

ENTRYPOINT ["/sbin/tini", "--", "/docker-entrypoint.sh"]
