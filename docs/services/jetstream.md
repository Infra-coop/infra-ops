# Jetstream consumer

The Jetstream consumer keeps the [co/infra image CDN](https://github.com/co-infra/co-infra-img)
cache honest. It watches the AT Protocol firehose for accounts that go inactive and tells the
CDN to purge every cached image for that account. This is the account-level half of the CDN's
blob invalidation. The CDN itself handles single-blob deletions when it serves a stale entry.

It has no inbound connections. It only opens an outbound WebSocket to Jetstream and makes
outbound calls to the CDN, so it needs no DNS record and no Traefik route.

## Why Jetstream and not Tap or the raw firehose

We only need one event type going forward, account status changes, not repository content or
history. Jetstream is a lightweight JSON WebSocket that delivers exactly that with no CBOR
decoding and no sync machinery. Tap is for repository synchronization with backfill, which is
the wrong tool here, and the raw firehose would mean decoding binary frames we do not need.

## How it works

- Connects to Jetstream and asks for a collection nothing publishes to, which drops the commit
  firehose while still delivering account and identity events. The result is a trickle.
- On an `account` event with `active: false` (deleted, deactivated, or taken down), it calls
  the CDN's `POST /admin/purge` with the DID.
- Persists its `time_us` cursor to a volume, so a restart resumes without gaps. Reconnects
  with backoff.

## Configuration

`.env` values:

- `PURGE_URL`, the CDN purge endpoint, for example `https://img.infra.coop/admin/purge`.
- `PURGE_TOKEN`, a shared secret that must match the CDN Worker's `PURGE_TOKEN`.
- `JETSTREAM_URL`, the Jetstream endpoint. Defaults to a public one.

## Runbook

Follow what it is doing:

```bash
docker compose logs -f jetstream
```

It logs each purge with the DID and how many variants were removed. The cursor lives in the
`jetstream-data` volume. If you ever need it to re-scan from now rather than resume, remove
that volume and restart the service.
