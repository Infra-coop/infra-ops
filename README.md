# infra-coop-ops

**Shared services host for the infra.coop cooperative.**

A single Docker VPS running a reverse proxy (Traefik) in front of the co-op's
lightweight, stateless backend services. Provisioned reproducibly from a
`cloud-init` file. The first tenant is **imgproxy**, the transform engine behind
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

Required GitHub Actions secrets: `DEPLOY_HOST` (box IP/hostname) and `DEPLOY_SSH_KEY`
(private half of the `deploy` user's key). Enable branch protection on `main` with a
required review + required `CI` check.

## First-run runbook

One-time, by hand. Everything after this is GitOps.

1. **Create the box** with `cloud-init.yaml` as user-data (put the CI deploy key's
   **public** half in it first). Point DNS: `imgproxy.infra.coop` A record → box IP.
2. **Generate signing keys** and install them on both sides:
   ```bash
   ./scripts/gen-keys.sh   # prints IMGPROXY_KEY / IMGPROXY_SALT + the wrangler commands
   ```
3. **On the box**, as the `deploy` user:
   ```bash
   git clone <this-repo> /opt/infra-coop && cd /opt/infra-coop
   cp .env.example .env      # fill ACME_EMAIL, IMGPROXY_DOMAIN, IMGPROXY_KEY, IMGPROXY_SALT
   docker compose up -d
   ```
4. **Add the GitHub secrets** (`DEPLOY_HOST`, `DEPLOY_SSH_KEY`) and turn on branch
   protection. From here, merges to `main` deploy automatically.

## Adding a service

1. Add a container to `compose.yaml` on the `edge` network with the four Traefik labels
   (`enable`, router `rule=Host(...)`, `entrypoints=websecure`, `tls.certresolver=le`,
   service `loadbalancer.server.port`).
2. Point its subdomain's DNS at the box.
3. PR it. Merge deploys it. No box surgery.

## Status

🚧 **Stack written, not yet deployed.** Traefik + imgproxy Compose stack, `cloud-init`
provisioning, key-gen helper, and GitOps CI/deploy workflows are in place. Blocked on:
GitHub remotes for the repos, then a real box to run the first deploy against.

## License

MIT
