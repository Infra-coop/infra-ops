# Setting up the co/infra services host

A full setup from scratch. This covers the host and the global pieces (the box, the deploy
key, TLS, and automatic deploys). Per-service configuration lives in each service's doc under
`docs/services/`.

## What you need

- A machine with Docker installed. co/infra uses a DigitalOcean droplet, but any Docker host
  works. Ports 80 and 443 must be free.
- A domain on Cloudflare for the service hostnames. co/infra uses `infra.coop`.
- SSH access to the machine as root or a sudo user.

## How deploys reach the box

GitHub Actions connects to the box over SSH and runs `git pull` and `docker compose up` on
every merge to `main`. That needs one SSH key. Its private half is a GitHub Actions secret
named `DEPLOY_SSH_KEY`. Its public half goes in the deploy user's `authorized_keys` on the
box. The repo is public, so the box clones and pulls over HTTPS with no key of its own.

## Steps

1. Generate the deploy key on your own machine. Keep `ci_deploy` for step 6.

   ```bash
   ssh-keygen -t ed25519 -C co-infra-ops-ci -f ci_deploy -N ""
   ```

2. Prepare the host.

   - Existing Docker host: run the prep script, which creates a `deploy` user, installs the
     deploy key, and makes the stack directory.

     ```bash
     scp scripts/host-setup.sh ci_deploy.pub root@<box>:/root/
     ssh root@<box> 'bash /root/host-setup.sh /root/ci_deploy.pub'
     ```

   - Fresh box: create it with `cloud-init.yaml` as user-data, with `ci_deploy.pub` pasted
     into it. That installs Docker, a firewall, and the `deploy` user.

3. Set up TLS on Cloudflare. This is done once and covers every service.

   - Under SSL/TLS, Origin Server, create an Origin Certificate. The default covers
     `*.infra.coop` and `infra.coop`, which is enough for every service.
   - Set the SSL mode to Full (strict).

   On the box, as the `deploy` user, save the certificate and key.

   ```bash
   mkdir -p /opt/co-infra/certs
   # paste the Origin Certificate into certs/origin.crt
   # paste the Private Key into certs/origin.key
   chmod 600 /opt/co-infra/certs/origin.key
   ```

   Cloudflare terminates the public TLS. Traefik presents this origin certificate for the
   Cloudflare to origin hop. Each service adds its own DNS record, covered in its doc.

4. Clone the repo, as the `deploy` user.

   ```bash
   git clone https://github.com/co-infra/co-infra-ops.git /opt/co-infra && cd /opt/co-infra
   cp .env.example .env
   ```

5. Configure the services. For each service under `docs/services/`, follow its doc to fill
   the `.env` values it needs and add its DNS record. The image transform service is
   [imgproxy](services/imgproxy.md).

6. Start the stack. The certificate files from step 3 and the `.env` values from step 5 must
   be in place first.

   ```bash
   docker compose up -d
   ```

7. Turn on automatic deploys. Add two repository secrets on GitHub, `DEPLOY_HOST` (the box IP
   or hostname) and `DEPLOY_SSH_KEY` (the `ci_deploy` private half). Protect the `main` branch
   with a required CI check. From here, merging to `main` deploys.

## Notes

- The box's Docker daemon must accept the Docker API version Traefik uses. Recent Docker
  engines require a modern client, so `compose.yaml` pins a current Traefik image. If Traefik
  logs a Docker API version error and loads no routes, update the Traefik image.
- Keep `certs/origin.key` and `.env` out of git. Both are gitignored.
- To lock the box down further, restrict inbound 443 to Cloudflare's IP ranges so nobody can
  reach the origin directly.
