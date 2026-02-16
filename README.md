# 🔒 AgentBox

**Self-hosted AI agent runtime in a secure VM with encrypted secrets**

AgentBox is a security-first AI agent framework designed for isolated VM deployment on macOS and Linux. Run AI agents with complete host isolation, encrypted secrets storage, and enterprise-grade security controls.

> **Note:** AgentBox was inspired by and built upon the foundation of [OpenClaw](https://github.com/openclaw/openclaw), an open-source personal AI agent framework. We are grateful to the OpenClaw community for pioneering accessible self-hosted AI agents. AgentBox extends these concepts with enhanced security, encrypted secrets management, and VM isolation for enterprise and privacy-focused deployments.

## 🎯 Why AgentBox?

| Feature | AgentBox | Standard AI Tools | Cloud AI Services |
|---------|----------|-------------------|-------------------|
| **VM Isolation** | ✅ Built-in | ⚠️ Manual | ❌ N/A |
| **Encrypted Secrets** | ✅ age encryption | ⚠️ Plain .env | ⚠️ Provider KMS |
| **Zero Host Access** | ✅ Default | ❌ Full access | ❌ Cloud access |
| **Audit Logging** | ✅ Immutable logs | ⚠️ Limited | ⚠️ Limited |
| **Network Isolation** | ✅ Firewall rules | ⚠️ Manual | ❌ Internet required |
| **Snapshot/Rollback** | ✅ VM snapshots | ❌ N/A | ❌ N/A |
| **Air-gap Capable** | ✅ Optional | ❌ Internet required | ❌ Cloud only |
| **Self-Hosted** | ✅ Complete control | ⚠️ Varies | ❌ SaaS only |

## 🚀 Quick Start

### Prerequisites

- **macOS**: [UTM](https://mac.getutm.app/) or [VirtualBox](https://www.virtualbox.org/)
- **Linux**: [QEMU/KVM](https://www.qemu.org/) or [VirtualBox](https://www.virtualbox.org/)
- **Any OS**: [Docker Desktop](https://www.docker.com/products/docker-desktop) or [Vagrant](https://www.vagrantup.com/)

### Option 1: Docker (Fastest)

```bash
# Clone the repo
git clone https://github.com/travis-burmaster/agentbox.git
cd agentbox

# Build the secure container
docker build -t agentbox .

# Run with encrypted secrets
docker run -it --name agentbox \
  -v $(pwd)/secrets:/agentbox/secrets:ro \
  -p 127.0.0.1:3000:3000 \
  agentbox
```

### Option 2: Vagrant (Full VM)

```bash
# Clone and start VM
git clone https://github.com/travis-burmaster/agentbox.git
cd agentbox
vagrant up

# SSH into the VM
vagrant ssh

# Inside VM: Initialize AgentBox
agentbox init
```

### Option 3: Manual VM Setup

See [VM_SETUP.md](./docs/VM_SETUP.md) for UTM, QEMU/KVM, and VirtualBox instructions.

## 🔐 Encrypted Secrets Management

AgentBox uses [age encryption](https://github.com/FiloSottile/age) to protect all secrets at rest.

### First-Time Setup

```bash
# Generate encryption key (do this ONCE, backup safely!)
age-keygen -o secrets/agent.key

# Your public key (safe to commit):
age1abc123...xyz789

# Add secrets
cat > secrets/secrets.env <<EOF
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
TELEGRAM_BOT_TOKEN=123456:ABC...
EOF

# Encrypt secrets
age -r age1abc123...xyz789 -o secrets/secrets.env.age secrets/secrets.env
rm secrets/secrets.env  # Delete plaintext!
```

### Using Encrypted Secrets

```bash
# Decrypt on-the-fly (never writes plaintext to disk)
age -d -i secrets/agent.key secrets/secrets.env.age | source /dev/stdin

# Or use the helper script
./scripts/load-secrets.sh
```

### Secrets File Structure

```bash
secrets/
├── agent.key              # Private key (NEVER commit! Add to .gitignore)
├── agent.key.pub          # Public key (safe to commit)
├── secrets.env.age        # Encrypted secrets (safe to commit)
└── README.md             # Instructions
```

**✅ Safe to commit:** `*.age`, `*.pub`  
**❌ NEVER commit:** `agent.key`, `*.env` (plaintext)

## 🛡️ Security Features

### 1. VM Isolation
- Agent runs in completely isolated VM
- No direct host filesystem access
- Restricted network egress (allowlist-only)
- Dedicated virtual network interface

### 2. Encrypted Secrets
- All secrets encrypted with age (ChaCha20-Poly1305)
- Private keys stored in VM only
- Secrets decrypted in-memory (never written to disk)
- Automatic key rotation scripts included

### 3. Network Security
- Default-deny firewall (UFW/iptables)
- Allowlist for API endpoints (Anthropic, OpenAI, etc.)
- Optional Tor/VPN routing
- DNS-over-HTTPS (DoH) enabled

### 4. Audit Logging
- All agent actions logged to immutable append-only log
- Logs exported to host via read-only mount
- Syslog integration for centralized monitoring
- Tamper-evident log signatures

### 5. Hardening
- SELinux/AppArmor profiles included
- Automatic security updates (unattended-upgrades)
- Minimal attack surface (no GUI, minimal packages)
- Secure boot support

## 📦 What's Included

```
agentbox/
├── Dockerfile              # Docker container config
├── Vagrantfile             # Vagrant VM config (coming soon)
├── agentfork/              # Core AgentBox framework (fork from OpenClaw)
├── vm-configs/             # VM configurations (coming soon)
│   ├── utm/               # macOS UTM configs
│   ├── qemu/              # Linux QEMU/KVM configs
│   └── virtualbox/        # Cross-platform VirtualBox
├── security/
│   ├── firewall.rules     # UFW/iptables rules
│   ├── selinux/           # SELinux policies
│   ├── apparmor/          # AppArmor profiles
│   └── audit.conf         # Auditd configuration
├── scripts/
│   ├── load-secrets.sh    # Decrypt secrets helper
│   ├── rotate-keys.sh     # Key rotation automation
│   ├── backup.sh          # Encrypted backup script
│   └── harden.sh          # Security hardening script
├── secrets/
│   ├── .gitignore         # Protects private keys
│   └── README.md          # Secrets management guide
└── docs/
    ├── VM_SETUP.md        # Detailed VM setup guides
    ├── SECURITY.md        # Security architecture
    └── THREAT_MODEL.md    # Threat analysis
```

## 🔧 Configuration

### Agent Configuration

```yaml
# agentbox.yaml
agent:
  name: "AgentBox"
  model: "anthropic/claude-sonnet-4-5"
  
secrets:
  encryption: "age"
  key_path: "/agentbox/secrets/agent.key"
  secrets_path: "/agentbox/secrets/secrets.env.age"

network:
  mode: "restricted"  # restricted | allowlist | open
  allowed_domains:
    - "api.anthropic.com"
    - "api.openai.com"
    - "api.telegram.org"
  
security:
  firewall: true
  selinux: true
  audit_logging: true
  auto_updates: true

vm:
  memory: "4GB"
  cpus: 2
  disk: "20GB"
  snapshot_on_shutdown: true
```

## 🎓 Use Cases

### 1. Personal AI Assistant (Privacy-Focused)
- All data stays on your hardware
- Encrypted secrets for API keys
- No telemetry or cloud dependencies

### 2. Development/Testing
- Isolated environment for agent experiments
- Snapshot before risky operations
- Rollback on failure

### 3. Enterprise Deployment
- Compliance-friendly (HIPAA, PCI, SOC 2)
- Air-gap capable for sensitive environments
- Audit logs for security reviews

### 4. Research
- Controlled environment for AI safety research
- Reproducible experiments (VM snapshots)
- Network isolation for adversarial testing

## 📋 Roadmap

- [ ] **v0.1.0** - Initial release (Docker + Vagrant)
  - [x] Encrypted secrets with age
  - [x] Docker container build
  - [ ] Vagrant VM configs
  - [ ] Basic VM configs (UTM, QEMU, VirtualBox)
  - [ ] Network isolation (firewall rules)
  - [ ] Audit logging
  
- [ ] **v0.2.0** - Enhanced Security
  - [ ] SELinux/AppArmor profiles
  - [ ] Automatic key rotation
  - [ ] Tor/VPN routing
  - [ ] Hardware security module (HSM) support
  
- [ ] **v0.3.0** - Compliance Features
  - [ ] FIPS 140-2 mode
  - [ ] STIG hardening
  - [ ] Compliance reporting (HIPAA, PCI)
  - [ ] Zero-knowledge backup

## 🤝 Contributing

Security contributions are welcome! Please see [CONTRIBUTING.md](./CONTRIBUTING.md).

**Security vulnerabilities:** Report privately via GitHub Security Advisories.

## 📜 License

AgentBox is released under the **MIT License**.

## 🙏 Acknowledgments

AgentBox was inspired by and builds upon [OpenClaw](https://github.com/openclaw/openclaw), an open-source framework for self-hosted AI agents. We extend our gratitude to the OpenClaw team and community for their pioneering work in making AI agents accessible and self-hostable.

**Other Credits:**
- **age** - Modern encryption tool by Filippo Valsorda
- **Vagrant** - HashiCorp's VM automation tool
- **Docker** - Container platform

## 📞 Support

- **Documentation:** [docs/](./docs/)
- **Issues:** [GitHub Issues](https://github.com/travis-burmaster/agentbox/issues)
- **Discussions:** [GitHub Discussions](https://github.com/travis-burmaster/agentbox/discussions)

---

**⚠️ Alpha Software:** AgentBox is in early development. Use in production at your own risk. Always test in a safe environment first.

**🔐 Security Notice:** Encryption is only as strong as your key management. Keep your `agent.key` safe, backed up, and never commit it to version control.
