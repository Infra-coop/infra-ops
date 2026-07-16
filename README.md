# co/infra services host

A single Docker machine that runs the co-op's backend services behind one reverse proxy. One
box, one proxy, many services. It is cheap to run and easy to extend, so a new shared service
slots in beside the existing ones instead of needing its own machine.

Today it runs one service, imgproxy, but it is built to hold more.

## How it works

**Traefik** is the reverse proxy. It listens on ports 80 and 443, terminates TLS, and routes
each request to a container based on the hostname. Adding a service means adding a container
with a few Traefik labels.

**TLS** runs through Cloudflare. The host sits behind Cloudflare's proxy, so Cloudflare
terminates the public TLS and forwards the request to the box. Traefik presents a Cloudflare
Origin Certificate for that last hop, and Cloudflare is set to Full (strict) so it verifies
the certificate. One wildcard origin certificate covers every service.

**Deploys** are GitOps. The box mirrors the `main` branch. A merge to `main` runs a GitHub
Actions workflow that connects to the box over SSH and runs `git pull` and
`docker compose up`. Nobody changes the box by hand.

## Services

Each service has its own doc for why it exists and how to run it.

| Service | Address | Role | Doc |
|---|---|---|---|
| imgproxy | `imgproxy.infra.coop` | Image transform backend for the image CDN | [docs/services/imgproxy.md](docs/services/imgproxy.md) |

## Files

- `compose.yaml` is the stack (Traefik and the services).
- `dynamic/tls.yml` is the Traefik config that loads the Cloudflare origin certificate.
- `cloud-init.yaml` provisions a fresh box (Docker, a firewall, and a deploy user).
- `scripts/host-setup.sh` preps an existing Docker box instead.
- `scripts/gen-keys.sh` generates imgproxy's signing keys.

## Adding a service

1. Add a container to `compose.yaml` on the `edge` network with the Traefik labels (enable, a
   router `rule=Host(...)`, `entrypoints=websecure`, `tls=true`, and the service port).
2. Point the subdomain DNS (proxied) at the box. The `*.infra.coop` origin certificate
   already covers it.
3. Write a short doc under `docs/services/` for what the service is and how to run it.
4. Open a PR. Merging deploys it.

## Setup

To stand up the host from scratch, see [docs/setup.md](docs/setup.md). To configure a
service, see its doc under `docs/services/`.

## License

Licensed under the GNU Affero General Public License, version 3 or later
(`AGPL-3.0-or-later`). See [LICENSE](LICENSE).
