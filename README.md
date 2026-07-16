# infra-coop-ops

**Shared services host for the infra.coop cooperative.**

A single Docker VPS running a reverse proxy (Traefik) in front of the co-op's
lightweight, stateless backend services. Runs on an existing Docker host
(a DigitalOcean droplet); a `cloud-init` file reproduces the box from scratch when
needed. The first tenant is **imgproxy**, the transform engine behind
[img.infra.coop](../img-infra-coop).

```
        Hetzner VPS  (services.infra.coop)
        ┌───────────────────────────────────────────────────┐
 443 ──▶│ Traefik   (auto-TLS, routes by Host header)       │
        │   ├─ imgproxy.infra.coop → imgproxy  [CPU-capped] │
        │   ├─ (later) label.infra.coop → labeler           │
        │   └─ …                                            │
        └───────────────────────────────────────────────────┘
```

## Why a shared host

The co-op will run several services (image transform now; a labeler and other
lightweight/stateless services later). At bootstrap scale, one Docker host with a
reverse proxy is the cheapest correct thing: adding a service is a container plus a
couple of Traefik labels, not a new box.

**imgproxy is resource-capped** on this box so a transform spike can't starve
neighbors — it's the CPU-heavy, bursty tenant.

### Graduation path

Every service here is stateless (imgproxy's cache lives in Cloudflare R2, not on the
box). When one saturates the shared host, its container lifts to a dedicated droplet and
its subdomain repoints — **no code or data migration**. So starting shared costs nothing
later.

> **Not for the relay.** A real ATProto relay (firehose ingest, heavy bandwidth + disk +
> Postgres, stateful) is a different animal and gets its own box. This host is for the
> lightweight/stateless services.

## What runs here

| Service | Subdomain | Purpose | Repo |
|---------|-----------|---------|------|
| Traefik | — | TLS + host routing | this repo |
| imgproxy | `imgproxy.infra.coop` | image transform for the CDN | this repo · consumed by [img-infra-coop](../img-infra-coop) |

## GitOps: how deploys happen

**This repo is the source of truth for the box.** The host just reflects `main` — nobody
SSHes in to change things by hand. That keeps the production stack transparent and open:
anyone can propose a change, and a reviewed merge ships it.

```
fork / branch → PR ──▶ CI (compose validate)      ← no secrets; safe for anyone
                          │
                     maintainer review  (branch protection: required approval)
                          │
                     merge to main ──▶ Deploy      ← SSHes to box: git pull && compose up -d
```

- **`ci.yml`** runs on every PR, including from forks. It only validates — it never
  touches secrets — so opening a PR is safe for anyone.
- **`deploy.yml`** runs **only on push to `main`** (i.e. after a reviewed merge). GitHub
  never exposes deploy secrets to fork PRs, so "anyone can PR to prod" is true *and* safe:
  the gate is code review, not access to the box.

### The one SSH key

The repo is **public**, so the box clones/pulls over HTTPS with no key of its own. The
only key CI/CD needs is for **CI → box**: the deploy workflow SSHes into the droplet to
roll the stack.

| | CI → box deploy key |
|---|---|
| Why | deploy workflow SSHes in as `deploy` and runs `git pull && docker compose up -d` |
| Private half | GitHub Actions secret `DEPLOY_SSH_KEY` |
| Public half | the box's `~deploy/.ssh/authorized_keys` (installed by `host-setup.sh`) |
| Generated | anywhere, once |

Required GitHub Actions secrets: `DEPLOY_HOST` (box IP/hostname) and `DEPLOY_SSH_KEY`.
Enable branch protection on `main` with a required review + the required `CI` check — on a
public repo this review *is* the deploy gate.

## First-run runbook

One-time, by hand. Everything after this is GitOps.

1. **Deploy key** — generate the CI→box key; stash the private half for step 5:
   ```bash
   ssh-keygen -t ed25519 -C infra-ops-ci -f ci_deploy -N ""
   # ci_deploy.pub → the box (step 2) ;  ci_deploy → GH secret (step 5)
   ```
2. **Prep the host**, then point DNS `imgproxy.infra.coop` A record → box IP.
   - **Existing Docker host** (current target — a DigitalOcean droplet with Docker
     already installed): skip cloud-init and run the root-side prep, passing the deploy
     key's public half:
     ```bash
     scp scripts/host-setup.sh ci_deploy.pub root@<box>:/root/
     ssh root@<box> 'bash /root/host-setup.sh /root/ci_deploy.pub'
     ```
   - **Fresh box:** create it with `cloud-init.yaml` as user-data (deploy key's public
     half pasted into it); Docker, the `deploy` user, and a firewall come up with it.
3. **Signing keys** — generate the shared imgproxy key/salt (also prints the Worker secret
   commands): `./scripts/gen-keys.sh`.
4. **Clone + start**, as `deploy` (public repo → HTTPS, no key):
   ```bash
   git clone https://github.com/Infra-coop/infra-ops.git /opt/infra-coop && cd /opt/infra-coop
   cp .env.example .env     # fill ACME_EMAIL, IMGPROXY_DOMAIN, IMGPROXY_KEY, IMGPROXY_SALT
   docker compose up -d
   ```
5. **GitHub secrets + protection** — add `DEPLOY_HOST` (box IP) and `DEPLOY_SSH_KEY`
   (deploy key private half), then turn on `main` branch protection. From here, merges to
   `main` deploy automatically.

## Adding a service

1. Add a container to `compose.yaml` on the `edge` network with the four Traefik labels
   (`enable`, router `rule=Host(...)`, `entrypoints=websecure`, `tls.certresolver=le`,
   service `loadbalancer.server.port`).
2. Point its subdomain's DNS at the box.
3. PR it. Merge deploys it. No box surgery.

## Status

🚧 **Stack written, not yet deployed.** Traefik + imgproxy Compose stack, host prep
(`host-setup.sh` for the existing droplet; `cloud-init.yaml` for a fresh box), key-gen
helper, and GitOps CI/deploy workflows are in place; repo is **public** at
`github.com/Infra-coop/infra-ops` (box pulls over HTTPS). Target is an existing
DigitalOcean Docker droplet, ports 80/443 free. Next: run the first-run runbook on it.

## License

MIT
