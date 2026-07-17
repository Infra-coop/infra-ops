#!/usr/bin/env bash
# Generates the shared secrets for the CDN and prints where each goes. The
# imgproxy key and salt sign transform URLs, and the purge token authenticates
# the CDN's purge endpoint. Each value must match on both sides (this box's .env
# and the Worker's secrets) or the corresponding check fails.
set -euo pipefail

KEY=$(openssl rand -hex 32)
SALT=$(openssl rand -hex 32)
PURGE_TOKEN=$(openssl rand -hex 32)

cat <<EOF
Generated secrets (hex):

  IMGPROXY_KEY=$KEY
  IMGPROXY_SALT=$SALT
  PURGE_TOKEN=$PURGE_TOKEN

1) On the services host, put these in co-infra-ops/.env:

  IMGPROXY_KEY=$KEY
  IMGPROXY_SALT=$SALT
  PURGE_TOKEN=$PURGE_TOKEN

2) In the co-infra-img Worker, set the matching secrets:

  echo "$KEY"         | wrangler secret put IMGPROXY_KEY
  echo "$SALT"        | wrangler secret put IMGPROXY_SALT
  echo "$PURGE_TOKEN" | wrangler secret put PURGE_TOKEN

Keep these out of git. Rotating any value means updating both sides together.
EOF
