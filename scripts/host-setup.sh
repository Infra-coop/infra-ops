#!/usr/bin/env bash
# One-time root-side prep for deploying on an ALREADY-provisioned Docker host
# (e.g. an existing DigitalOcean droplet). Does what cloud-init would, MINUS
# installing Docker and MINUS touching the firewall — this box may run other
# services, so its network rules are left alone. Idempotent; safe to re-run.
#
# Usage:  sudo ./scripts/host-setup.sh path/to/ci_deploy.pub
#         (ci_deploy.pub = Keypair A PUBLIC half; CI SSHes in as `deploy`.)
set -euo pipefail

CI_PUBKEY="${1:?usage: sudo ./scripts/host-setup.sh <ci_deploy.pub>}"
DEPLOY_USER=deploy
STACK_DIR=/opt/infra-coop

[ -f "$CI_PUBKEY" ] || { echo "public key not found: $CI_PUBKEY" >&2; exit 1; }
command -v docker >/dev/null || { echo "docker not found — this script assumes Docker is already installed" >&2; exit 1; }

# deploy user with docker access
id -u "$DEPLOY_USER" >/dev/null 2>&1 || adduser --disabled-password --gecos "" "$DEPLOY_USER"
usermod -aG docker "$DEPLOY_USER"

# Keypair A public half -> authorized_keys (lets the deploy workflow SSH in)
install -d -m 700 -o "$DEPLOY_USER" -g "$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"
touch "/home/$DEPLOY_USER/.ssh/authorized_keys"
grep -qxF "$(cat "$CI_PUBKEY")" "/home/$DEPLOY_USER/.ssh/authorized_keys" \
  || cat "$CI_PUBKEY" >> "/home/$DEPLOY_USER/.ssh/authorized_keys"
chmod 600 "/home/$DEPLOY_USER/.ssh/authorized_keys"

# Trust github.com so the box's first `git clone` doesn't prompt (Keypair B,
# the box's read key, is generated separately as the deploy user).
ssh-keyscan github.com > "/home/$DEPLOY_USER/.ssh/known_hosts" 2>/dev/null
chown -R "$DEPLOY_USER:$DEPLOY_USER" "/home/$DEPLOY_USER/.ssh"

# Own compose project lives here, owned by deploy.
mkdir -p "$STACK_DIR"
chown "$DEPLOY_USER:$DEPLOY_USER" "$STACK_DIR"

cat <<EOF

Host prep done. Next, as the deploy user:

  sudo -iu $DEPLOY_USER
  ssh-keygen -t ed25519 -C infra-ops-box -f ~/.ssh/id_ed25519 -N ""   # Keypair B
  cat ~/.ssh/id_ed25519.pub    # add as a READ-ONLY Deploy key on the repo
  git clone git@github.com:Infra-coop/infra-ops.git $STACK_DIR && cd $STACK_DIR
  cp .env.example .env         # fill secrets (see scripts/gen-keys.sh)
  docker compose up -d

Firewall left untouched (shared box). Make sure 80/443 are reachable and locked
down as appropriate for this droplet.
EOF
