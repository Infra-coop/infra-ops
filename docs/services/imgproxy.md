# imgproxy

imgproxy is the image transform backend for the
[co/infra image CDN](https://github.com/co-infra/co-infra-img). The CDN fetches an original
image from a user's data server, then calls imgproxy to resize, crop, and reformat it.
Without imgproxy the CDN cannot transform images.

It runs at `imgproxy.infra.coop`. Only the CDN calls it, using signed URLs, so the endpoint
cannot be driven by anyone else.

## Configuration

imgproxy is a service in `compose.yaml`. It reads three values from `.env`:

- `IMGPROXY_DOMAIN` is the hostname Traefik routes to it, `imgproxy.infra.coop`.
- `IMGPROXY_KEY` and `IMGPROXY_SALT` are the signing keys. imgproxy only accepts URLs signed
  with them.

Generate the keys once:

```bash
./scripts/gen-keys.sh
```

Put the printed `IMGPROXY_KEY` and `IMGPROXY_SALT` in `.env`. The image CDN must use the same
two values, or every request fails its signature check. To rotate them, change both sides
together.

The container is capped on CPU and memory so a spike cannot starve the other services, and it
is limited to fetching over HTTPS.

## DNS

Add an A record for `imgproxy.infra.coop` to the box IP, proxied (orange cloud). The wildcard
origin certificate from the host setup already covers it, so there is no separate certificate.

## Runbook

Check imgproxy from the box:

```bash
docker compose exec imgproxy imgproxy health
```

Check it end to end, through Traefik and Cloudflare:

```bash
curl -sI https://imgproxy.infra.coop/health
```

A healthy response is `200`. If requests fail their signature check, confirm `IMGPROXY_KEY`
and `IMGPROXY_SALT` match the values the image CDN uses.
