#!/usr/bin/env bash
# Generates the shared imgproxy signed-URL key + salt, and prints the commands
# to install them on both sides (this box's .env and the Worker's secrets).
# The same two hex values MUST live in both places or every signature mismatches.
set -euo pipefail

KEY=$(openssl rand -hex 32)
SALT=$(openssl rand -hex 32)

cat <<EOF
Generated imgproxy signing material (hex):

  IMGPROXY_KEY=$KEY
  IMGPROXY_SALT=$SALT

1) On the services host — put these in co-infra-ops/.env:

  IMGPROXY_KEY=$KEY
  IMGPROXY_SALT=$SALT

2) In the co-infra-img Worker — set the matching secrets:

  echo "$KEY"  | wrangler secret put IMGPROXY_KEY
  echo "$SALT" | wrangler secret put IMGPROXY_SALT

Keep these out of git. Rotating them means updating BOTH sides together.
EOF
