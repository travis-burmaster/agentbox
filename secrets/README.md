# 🔐 Encrypted Secrets Management

AgentBox uses [age](https://github.com/FiloSottile/age) for secure, modern encryption of all sensitive data.

## Why age?

- ✅ **Simple**: One command to encrypt, one to decrypt
- ✅ **Secure**: ChaCha20-Poly1305 + X25519 (modern cryptography)
- ✅ **Fast**: Native Golang implementation
- ✅ **Git-friendly**: Small encrypted files safe to commit
- ✅ **No dependencies**: Single static binary

## Setup (First Time Only)

### 1. Install age

**macOS:**
```bash
brew install age
```

**Linux:**
```bash
# Debian/Ubuntu
sudo apt install age

# Or download binary
wget https://github.com/FiloSottile/age/releases/download/v1.1.1/age-v1.1.1-linux-amd64.tar.gz
tar xzf age-v1.1.1-linux-amd64.tar.gz
sudo mv age/age* /usr/local/bin/
```

### 2. Generate Your Key Pair

```bash
# Generate keys (do this ONCE!)
age-keygen -o agent.key

# Output shows your public key:
# Public key: age1abc123def456ghi789jkl012mno345pqr678stu901vwx234yz567

# Save your public key
age-keygen -y agent.key > agent.key.pub
```

**⚠️ CRITICAL:** 
- Backup `agent.key` to a secure location (password manager, encrypted USB, etc.)
- If you lose this file, you **cannot decrypt your secrets**
- Never commit `agent.key` to git (it's in .gitignore)

### 3. Create Your Secrets File

```bash
# Create plaintext secrets (temporary)
cat > secrets.env <<EOF
# API Keys
ANTHROPIC_API_KEY=sk-ant-api03-...
OPENAI_API_KEY=sk-proj-...

# Messaging
TELEGRAM_BOT_TOKEN=123456789:ABCdefGHIjklMNOpqrSTUvwxYZ

# Email
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=bot@example.com
SMTP_PASS=your-app-password

# Database (if needed)
DATABASE_URL=postgresql://user:pass@localhost/agentbox

# Custom secrets
MY_SECRET_KEY=...
EOF
```

### 4. Encrypt Your Secrets

```bash
# Read your public key
PUBLIC_KEY=$(cat agent.key.pub)

# Encrypt secrets
age -r $PUBLIC_KEY -o secrets.env.age secrets.env

# Delete plaintext immediately!
shred -u secrets.env  # Linux
# OR
rm -P secrets.env     # macOS
```

### 5. Verify Encryption

```bash
# Try to decrypt (should show your secrets)
age -d -i agent.key secrets.env.age

# If it works, you're good! ✅
```

## Daily Usage

### Load Secrets (Recommended Method)

```bash
# From agentbox root directory:
source scripts/load-secrets.sh

# This decrypts secrets.env.age and loads into environment
# Secrets are NEVER written to disk in plaintext
```

### Manual Decryption

```bash
# Decrypt and load into shell
age -d -i secrets/agent.key secrets/secrets.env.age | source /dev/stdin

# Or decrypt to stdout for piping
age -d -i secrets/agent.key secrets/secrets.env.age
```

### Add New Secrets

```bash
# Decrypt to temporary file
age -d -i agent.key secrets.env.age > temp.env

# Edit the file
nano temp.env

# Re-encrypt
age -r $(cat agent.key.pub) -o secrets.env.age temp.env

# Delete temporary file
shred -u temp.env
```

## File Structure

```
secrets/
├── agent.key              # 🔴 PRIVATE KEY - Never commit!
├── agent.key.pub          # ✅ Public key - Safe to commit
├── secrets.env.age        # ✅ Encrypted secrets - Safe to commit
└── README.md              # This file
```

## Security Best Practices

### ✅ DO:
- Backup `agent.key` to multiple secure locations
- Use a password manager to store the key
- Rotate keys every 6-12 months (see `scripts/rotate-keys.sh`)
- Commit `*.age` and `*.pub` files to git
- Use unique keys per environment (dev, staging, prod)

### ❌ DON'T:
- Never commit `agent.key` to git
- Never share `agent.key` via email/Slack/etc.
- Never store plaintext secrets in files
- Never reuse the same key across projects
- Never store key in the VM if host is compromised

## Key Rotation

Rotate keys every 6-12 months or immediately if compromised:

```bash
# Run the rotation script
./scripts/rotate-keys.sh

# This will:
# 1. Generate new key pair
# 2. Re-encrypt all secrets with new key
# 3. Backup old key (for emergency decryption)
# 4. Update configs to use new key
```

## Backup Strategy

### Option 1: Encrypted USB Drive

```bash
# Copy to encrypted USB
cp agent.key /Volumes/EncryptedUSB/agentbox-key-backup-$(date +%Y%m%d).key
```

### Option 2: Password Manager

```bash
# Export as base64 for easy paste into 1Password/Bitwarden
cat agent.key | base64

# To restore:
echo "base64-string-here" | base64 -d > agent.key
chmod 600 agent.key
```

### Option 3: Split Key (Advanced)

Use Shamir's Secret Sharing to split the key:

```bash
# Install ssss
brew install ssss  # macOS
sudo apt install ssss  # Linux

# Split key into 5 shares (need any 3 to reconstruct)
cat agent.key | ssss-split -t 3 -n 5

# Give shares to trusted people/locations
# To reconstruct: ssss-combine -t 3
```

## Troubleshooting

### "age: error: incorrect identity file passphrase"
The key file is corrupted or wrong. Check backup.

### "age: error: no identity matched any of the recipients"
You're using the wrong key to decrypt. Ensure `agent.key` matches the public key used to encrypt.

### "Permission denied"
Fix permissions:
```bash
chmod 600 agent.key
chmod 644 agent.key.pub secrets.env.age
```

### Forgot which public key was used?
```bash
# Extract recipient from encrypted file
age -decrypt secrets.env.age 2>&1 | grep -oE 'age1[a-z0-9]+'
```

## Alternative: GPG

If you prefer GPG over age:

```bash
# Generate GPG key
gpg --gen-key

# Encrypt
gpg -e -r your-email@example.com secrets.env

# Decrypt
gpg -d secrets.env.gpg
```

AgentBox defaults to age for simplicity, but GPG works too.

## Questions?

- **age documentation:** https://github.com/FiloSottile/age
- **age specification:** https://age-encryption.org/v1
- **File issues:** https://github.com/ellucas-creator/agentbox/issues
