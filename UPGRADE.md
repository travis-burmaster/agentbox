# 🔐 Upgrading OpenClaw in AgentBox

AgentBox pins OpenClaw to a **specific, tested version**. This is a deliberate security measure:

- A supply-chain compromise or vulnerability in a future OpenClaw release
  will **not** automatically enter your running containers.
- Every version bump is a conscious, auditable act with a git trail.

---

## Before You Upgrade

1. **Check the OpenClaw changelog**
   ```
   https://github.com/openclaw/openclaw/releases
   ```

2. **Check for known vulnerabilities in the new version**
   ```bash
   # Scan the target version before building
   npm install --prefix /tmp/oc-audit openclaw@NEW_VERSION --no-fund
   npm audit --prefix /tmp/oc-audit --audit-level=moderate
   rm -rf /tmp/oc-audit
   ```

3. **Review breaking changes** — OpenClaw config schemas can change between releases.
   Compare your `config/openclaw.json` against the new version's defaults.

---

## How to Upgrade

### 1. Update the pinned version

Edit **`Dockerfile`** and **`docker-compose.yml`** — change `OPENCLAW_VERSION`:

```bash
# In Dockerfile:
ARG OPENCLAW_VERSION=2026.X.Y   # ← new version

# In docker-compose.yml:
OPENCLAW_VERSION: ${OPENCLAW_VERSION:-2026.X.Y}   # ← new version
```

### 2. Build and test locally

```bash
# Build with the new version
OPENCLAW_VERSION=2026.X.Y docker compose build --no-cache

# The build will automatically run npm audit.
# A high/critical vulnerability FAILS the build — do not bypass this.

# Run the new image locally
docker compose up -d

# Verify the version and basic function
docker exec agentbox openclaw --version
docker exec agentbox openclaw doctor
```

### 3. Commit and push

```bash
git add Dockerfile docker-compose.yml
git commit -m "chore: bump openclaw to 2026.X.Y

- Reviewed changelog: <link>
- npm audit: clean
- Tested locally: yes"
git push origin main
```

---

## Emergency Rollback

If a newly deployed version causes issues:

```bash
# Roll back to the previous image (if you tagged it)
docker tag agentbox:latest agentbox:backup-$(date +%Y%m%d)

# Or rebuild from the last known-good git commit
git checkout <previous-commit> -- Dockerfile docker-compose.yml
docker compose build --no-cache
docker compose up -d
```

---

## Checking the Currently Pinned Version

```bash
# From the image label
docker inspect agentbox:latest | grep -i openclaw_version

# From inside the container
docker exec agentbox openclaw --version
docker exec agentbox printenv OPENCLAW_VERSION
```

---

## Automated Security Scanning (Recommended)

For production deployments, add Trivy or Grype to your CI/CD pipeline:

```bash
# Scan built image for vulnerabilities
trivy image --exit-code 1 --severity HIGH,CRITICAL agentbox:latest

# Or with Grype
grype agentbox:latest --fail-on high
```

---

> **Policy:** Never use `@latest` or `*` for the openclaw version in production.  
> A pinned version means security is opt-in, not opt-out.
