#!/usr/bin/env bash
# Nexra Panel "old panel" notice page — one-line installer.
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/MHBehzadian/nexra-notice/main/install.sh) [domain] [port]
#
# Defaults: domain dash.nexradns.site, port 8000.
# Serves the notice over HTTPS on <port> and on 443, for every path, so any
# old bookmark (/dashboard, /dashboard/#/login, ...) lands on it.
set -euo pipefail

DOMAIN="${1:-dash.nexradns.site}"
PORT="${2:-8000}"
REPO="https://github.com/MHBehzadian/nexra-notice.git"
DIR="/opt/nexra-notice"
WEBROOT="/var/www/certbot"
CONF="/etc/nginx/sites-available/nexra-notice"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || die "run as root"
command -v apt-get >/dev/null || die "only Debian/Ubuntu is supported"

say "Installing packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq nginx certbot git curl >/dev/null

say "Fetching site into $DIR"
if [ -d "$DIR/.git" ]; then
    git -C "$DIR" fetch -q origin main
    git -C "$DIR" reset -q --hard origin/main
else
    rm -rf "$DIR"
    git clone -q --depth 1 "$REPO" "$DIR"
fi

port_owner() { ss -ltnpH "sport = :$1" 2>/dev/null | grep -v nginx || true; }

for p in 80 "$PORT"; do
    owner=$(port_owner "$p")
    [ -z "$owner" ] || die "port $p is already used by another program:
$owner"
done

# 443 is a bonus, not a requirement: on a server where something else
# (xray, another site) already owns it, serve on $PORT only.
USE_443=1
if [ "$PORT" = "443" ] || [ -n "$(port_owner 443)" ]; then
    USE_443=0
    [ "$PORT" = "443" ] || echo "  port 443 is in use by another program, leaving it alone (serving on $PORT only)"
fi

say "Checking DNS"
ip=$(curl -4 -fsS --max-time 8 https://api.ipify.org || true)
resolved=$(getent ahostsv4 "$DOMAIN" | awk 'NR==1{print $1}' || true)
if [ -n "$ip" ] && [ "$resolved" != "$ip" ]; then
    echo "  $DOMAIN -> ${resolved:-nothing}, this server is $ip"
    echo "  Point an A record for $DOMAIN at $ip (DNS only, not proxied) first."
    die "DNS does not point here"
fi

say "Getting certificate for $DOMAIN"
mkdir -p "$WEBROOT"
rm -f /etc/nginx/sites-enabled/default
cat >"$CONF" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ { root $WEBROOT; }
    location / { return 301 https://\$host:$PORT\$request_uri; }
}
EOF
ln -sf "$CONF" /etc/nginx/sites-enabled/nexra-notice
nginx -t -q && systemctl reload nginx || systemctl restart nginx

if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    certbot certonly --webroot -w "$WEBROOT" -d "$DOMAIN" \
        --non-interactive --agree-tos --register-unsafely-without-email \
        --deploy-hook "systemctl reload nginx"
fi

say "Writing nginx config"
listen_443=""
if [ "$USE_443" = 1 ]; then
    listen_443="    listen 443 ssl;
    listen [::]:443 ssl;"
fi
cat >>"$CONF" <<EOF

server {
    listen $PORT ssl;
    listen [::]:$PORT ssl;
$listen_443
    http2 on;
    server_name $DOMAIN;

    ssl_certificate     /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    # Plain http:// sent to the TLS port: bounce to https on the same port.
    error_page 497 =301 https://\$host:\$server_port\$request_uri;

    root $DIR/site;

    location /assets/ {
        expires 7d;
        try_files \$uri =404;
    }

    location / {
        add_header Cache-Control "no-store";
        try_files /index.html =404;
    }
}
EOF

# Older nginx (< 1.25.1) has no "http2 on"; drop it there.
nginx -t -q 2>/dev/null || sed -i '/http2 on;/d' "$CONF"
nginx -t -q
systemctl enable -q nginx
systemctl reload nginx

if command -v ufw >/dev/null && ufw status | grep -q active; then
    ufw allow 80/tcp >/dev/null
    ufw allow 443/tcp >/dev/null
    ufw allow "$PORT"/tcp >/dev/null
fi

say "Done"
echo "  https://$DOMAIN:$PORT/dashboard"
[ "$USE_443" = 1 ] && echo "  https://$DOMAIN/"
exit 0
