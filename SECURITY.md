# 🔒 Security Architecture

AgentBox is designed with security as the primary concern. This document outlines the threat model, security features, and best practices.

## Threat Model

### Assets We Protect

1. **API Keys & Secrets** - LLM provider keys, messaging tokens, credentials
2. **Conversation Data** - Session transcripts may contain sensitive user information
3. **Host System** - Prevent agent from compromising the host machine
4. **Network** - Prevent unauthorized data exfiltration

### Threats We Defend Against

| Threat | Mitigation | Status |
|--------|------------|--------|
| **Secret exposure in git** | age encryption, .gitignore | ✅ Implemented |
| **Agent escaping container** | `cap_drop: ALL`, `no-new-privileges`, `read_only` | ✅ Implemented |
| **Privilege escalation** | Non-root user, `no-new-privileges:true` | ✅ Implemented |
| **Unauthorized API access** | Encrypted secrets, key rotation | ✅ Implemented |
| **Data exfiltration** | Firewall allowlists, localhost-only ports | ✅ Implemented |
| **Supply-chain compromise** | Pinned openclaw version + build-time npm audit | ✅ Implemented |
| **Resource exhaustion (DoS)** | CPU/memory limits in docker-compose | ✅ Implemented |
| **Session transcript leaks** | Audit logs, encryption at rest | 🚧 Planned (v0.2.0) |
| **Malicious tool execution** | Tool allowlists, sandboxing | 🚧 Planned (v0.2.0) |
| **Key compromise** | Key rotation, HSM support | 🚧 Planned (v0.3.0) |

### Out of Scope

- **LLM prompt injection attacks** - Inherent risk in LLM-based systems
- **Zero-day vulnerabilities in dependencies** - Mitigated by version pinning + audit gate
- **Physical access to host** - Assumed trusted physical security

## Security Layers

### Layer 1: VM Isolation

**Goal:** Prevent agent from accessing host filesystem or network.

**Implementation:**
- Agent runs in dedicated VM (Docker, Vagrant, UTM)
- No host filesystem mounts (except explicit read-only shares)
- Dedicated virtual network interface
- Resource limits (CPU, memory, disk)

**Example Docker Configuration:**

```yaml
# docker-compose.yml
version: '3.8'
services:
  agentbox:
    build: .
    security_opt:
      - no-new-privileges:true
      - apparmor=docker-default
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    read_only: true
    tmpfs:
      - /tmp:noexec,nosuid,size=100M
    volumes:
      - ./secrets:/agentbox/secrets:ro
      - agentbox-data:/agentbox/data
    networks:
      - agentbox-network
    ports:
      - "127.0.0.1:3000:3000"  # Only localhost binding!

networks:
  agentbox-network:
    driver: bridge
    internal: false  # Set to true for complete air-gap

volumes:
  agentbox-data:
```

### Layer 2: Encrypted Secrets

**Goal:** Prevent secrets from being exposed in version control or backups.

**Implementation:**
- All secrets encrypted with age (ChaCha20-Poly1305)
- Private key never stored in git
- Decryption only in-memory (never writes plaintext to disk)
- Regular key rotation (recommended: every 6 months)

**Encryption Flow:**

```
┌─────────────┐     age -r <pubkey>     ┌──────────────────┐
│ secrets.env │ ───────────────────────> │ secrets.env.age  │
│ (plaintext) │                          │ (encrypted)      │
└─────────────┘                          └──────────────────┘
      │                                            │
      │ shred -u                                   │ git commit
      ▼                                            ▼
   DELETED                                    SAFE TO COMMIT
```

**Key Storage Best Practices:**

1. **Primary key:** Password manager (1Password, Bitwarden)
2. **Backup #1:** Encrypted USB drive (physically separate location)
3. **Backup #2:** Printed QR code in safe/vault
4. **Advanced:** Shamir's Secret Sharing (split key into 5 shares, need 3 to reconstruct)

### Layer 3: Network Isolation

**Goal:** Prevent unauthorized network access and data exfiltration.

**Implementation:**

```bash
# Firewall rules (UFW example)
ufw default deny incoming
ufw default deny outgoing

# Allowlist only required endpoints
ufw allow out to api.anthropic.com port 443 proto tcp
ufw allow out to api.openai.com port 443 proto tcp
ufw allow out to api.telegram.org port 443 proto tcp

# DNS (CloudFlare DoH only)
ufw allow out to 1.1.1.1 port 443 proto tcp
ufw allow out to 1.0.0.1 port 443 proto tcp

# Block all other outbound traffic
ufw enable
```

**DNS-over-HTTPS (DoH):**

```bash
# /etc/systemd/resolved.conf
[Resolve]
DNS=1.1.1.1 1.0.0.1
DNSOverTLS=yes
```

**Monitoring:**

```bash
# Log all outbound connections
iptables -A OUTPUT -j LOG --log-prefix "OUTBOUND: "

# Monitor logs
tail -f /var/log/syslog | grep OUTBOUND
```

### Layer 4: Audit Logging

**Goal:** Immutable record of all agent actions for forensics and compliance.

**Implementation:**

```bash
# Auditd rules
-w /agentbox/data -p wa -k agentbox-data
-w /agentbox/secrets -p rwa -k agentbox-secrets
-w /usr/bin/age -p x -k agentbox-crypto
```

**Log Format:**

```json
{
  "timestamp": "2026-02-15T18:00:00Z",
  "event": "secret_decrypt",
  "user": "agentbox",
  "file": "/agentbox/secrets/secrets.env.age",
  "result": "success"
}
```

**Log Shipping:**

- Local logs: `/var/log/audit/audit.log`
- Remote syslog: Ship to centralized logging server
- Immutable: Append-only, tamper-evident (optional: sign with GPG)

### Layer 5: Application Security

**Goal:** Prevent agent from executing unauthorized actions.

**Tool Allowlists (OpenClaw):**

```json
{
  "tools": {
    "exec": {
      "allow": ["ls", "cat", "grep", "python3"],
      "deny": ["rm", "dd", "curl", "wget"]
    },
    "write": {
      "allowPaths": ["/agentbox/workspace/**"],
      "denyPaths": ["/etc/**", "/root/**"]
    }
  }
}
```

## Dependency Version Pinning

**Threat:** A future version of OpenClaw (or any dependency) could introduce a vulnerability,
backdoor, or breaking behavioral change — either through a compromise of the upstream
project or an unintentional bug.

**Mitigation:** AgentBox pins OpenClaw to a **specific, known-good version** in both the
`Dockerfile` and `docker-compose.yml`. The pinned version is an explicit `ARG` with a
documented default — changing it requires a deliberate code change with a git trail.

### Build-time Audit Gate

The Dockerfile runs `npm audit --audit-level=high` immediately after installing OpenClaw.
If any high or critical CVEs are detected in the installed package tree, **the build fails**.
This means:
- Vulnerable images cannot be deployed accidentally.
- CI/CD pipelines will alert on newly disclosed CVEs even without a code change.

### Upgrading Safely

See [UPGRADE.md](./UPGRADE.md) for the full upgrade process, including:
- How to review the changelog and audit the new version before building
- How to test locally and roll back if needed
- Recommended image scanning tools (Trivy, Grype)

**Policy:** Never use `@latest` or `*` for OpenClaw in production. A pinned version
means security is opt-in, not opt-out.

---

## Compliance & Standards

### HIPAA Readiness

- ✅ Encryption at rest (age encryption)
- ✅ Encryption in transit (TLS for API calls)
- ✅ Audit logging (all access logged)
- ✅ Access controls (VM isolation)
- 🚧 BAA with LLM provider (user responsibility)

### PCI DSS Considerations

- ✅ Network segmentation (VM isolation)
- ✅ Strong cryptography (ChaCha20-Poly1305)
- ✅ Audit trails (immutable logs)
- ⚠️ Key management (manual rotation, no HSM yet)

### SOC 2 Type II

- ✅ Security (encryption, firewall, audit logs)
- ✅ Availability (VM snapshots, auto-restart)
- 🚧 Processing Integrity (checksums, signatures)
- 🚧 Confidentiality (DLP, egress monitoring)
- 🚧 Privacy (PII detection, redaction)

## Incident Response

### Key Compromise

If you suspect your encryption key has been compromised:

```bash
# 1. Immediately rotate keys
./scripts/rotate-keys.sh

# 2. Revoke old key (add to .revoked)
echo "age1old-key-here" >> secrets/.revoked

# 3. Re-encrypt all historical backups
for file in backups/*.age; do
    age -d -i old.key "$file" | age -r $(cat new.key.pub) -o "$file.new"
done

# 4. Audit all access logs
grep "secret_decrypt" /var/log/audit/audit.log > incident_$(date +%Y%m%d).log

# 5. Notify stakeholders (if enterprise)
```

### Data Breach

If conversation data was exposed:

```bash
# 1. Stop the agent
docker stop agentbox

# 2. Take VM snapshot for forensics
docker commit agentbox agentbox-incident-$(date +%Y%m%d)

# 3. Review audit logs
zgrep "session_access" /var/log/audit/*.gz | grep -v "user:agentbox"

# 4. Determine blast radius
# - Which sessions were accessed?
# - What data was in those sessions?
# - Was data exfiltrated?

# 5. Containment
# - Rotate all API keys
# - Reset messaging bot tokens
# - Revoke network access

# 6. Recovery
# - Restore from last known good snapshot
# - Apply security patches
# - Restart with hardened config
```

## Security Checklist

### Initial Setup

- [ ] Generate strong encryption key (`age-keygen`)
- [ ] Backup key to 3+ secure locations
- [ ] Test decryption works
- [ ] Configure firewall allowlists
- [ ] Enable audit logging
- [ ] Test VM snapshot/restore
- [ ] Review tool allowlists

### Monthly

- [ ] Review audit logs for anomalies
- [ ] Update dependencies (`docker pull`, `npm update`)
- [ ] Test backup restoration
- [ ] Check firewall rules still appropriate

### Every 6 Months

- [ ] Rotate encryption keys
- [ ] Review and update threat model
- [ ] Penetration test (if enterprise)
- [ ] Compliance audit (if required)

## Reporting Security Issues

**Do NOT create public GitHub issues for security vulnerabilities.**

Instead:
1. Use GitHub Security Advisories (private disclosure)
2. Or email: travis@burmaster.com

We aim to respond within 48 hours and patch critical issues within 7 days.

## References

- [age encryption spec](https://age-encryption.org/v1)
- [NIST Cryptographic Standards](https://csrc.nist.gov/projects/cryptographic-standards-and-guidelines)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)

---

**Last Updated:** 2026-02-16  
**Version:** 0.1.0-alpha
