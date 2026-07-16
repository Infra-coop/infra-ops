# infra-coop-ops

**Shared services host for the infra.coop cooperative.**

A single Docker VPS running a reverse proxy (Traefik) in front of the co-op's
lightweight, stateless backend services. Provisioned reproducibly from a
`cloud-init` file. The first tenant is **imgproxy**, the transform engine behind
[img.infra.coop](../img-infra-coop).

```
        Hetzner VPS  (services.infra.coop)
        ┌─────────────────────────────────────────────┐
 443 ──▶│ Traefik   (auto-TLS, routes by Host header)  │
        │   ├─ imgproxy.infra.coop → imgproxy  [CPU-capped]
        │   ├─ (later) label.infra.coop → labeler
        │   └─ …                                        │
        └─────────────────────────────────────────────┘
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

## Status

🚧 **Bootstrapping.** Repo scaffold only. The Traefik + imgproxy Compose stack and the
`cloud-init` provisioning file land on `dev`.

## License

MIT
