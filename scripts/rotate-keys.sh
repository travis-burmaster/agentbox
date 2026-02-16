#!/bin/bash
# Rotate encryption keys
# This script generates a new key pair and re-encrypts all secrets

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SECRETS_DIR="$PROJECT_ROOT/secrets"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}🔄 Key Rotation Process${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if age is installed
if ! command -v age &> /dev/null; then
    echo -e "${RED}❌ Error: age is not installed${NC}"
    exit 1
fi

# Check if old key exists
if [ ! -f "$SECRETS_DIR/agent.key" ]; then
    echo -e "${RED}❌ Error: No existing key found${NC}"
    echo "Nothing to rotate. Run this to create initial key:"
    echo "  age-keygen -o $SECRETS_DIR/agent.key"
    exit 1
fi

# Backup old key
BACKUP_DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$SECRETS_DIR/backups"
mkdir -p "$BACKUP_DIR"

echo "📦 Backing up old key..."
cp "$SECRETS_DIR/agent.key" "$BACKUP_DIR/agent.key.$BACKUP_DATE"
cp "$SECRETS_DIR/agent.key.pub" "$BACKUP_DIR/agent.key.pub.$BACKUP_DATE"
echo -e "${GREEN}✅ Old key backed up to: $BACKUP_DIR${NC}"
echo ""

# Generate new key
echo "🔑 Generating new key pair..."
age-keygen -o "$SECRETS_DIR/agent.key.new"
age-keygen -y "$SECRETS_DIR/agent.key.new" > "$SECRETS_DIR/agent.key.pub.new"

NEW_PUBLIC_KEY=$(cat "$SECRETS_DIR/agent.key.pub.new")
echo -e "${GREEN}✅ New public key: $NEW_PUBLIC_KEY${NC}"
echo ""

# Decrypt with old key, re-encrypt with new key
if [ -f "$SECRETS_DIR/secrets.env.age" ]; then
    echo "🔄 Re-encrypting secrets..."
    
    # Decrypt with old key and re-encrypt with new key (never writes plaintext to disk!)
    age -d -i "$SECRETS_DIR/agent.key" "$SECRETS_DIR/secrets.env.age" | \
        age -r "$NEW_PUBLIC_KEY" -o "$SECRETS_DIR/secrets.env.age.new"
    
    # Backup old encrypted file
    cp "$SECRETS_DIR/secrets.env.age" "$BACKUP_DIR/secrets.env.age.$BACKUP_DATE"
    
    # Replace with new encrypted file
    mv "$SECRETS_DIR/secrets.env.age.new" "$SECRETS_DIR/secrets.env.age"
    
    echo -e "${GREEN}✅ Secrets re-encrypted${NC}"
else
    echo -e "${YELLOW}⚠️  No secrets file found (skipping re-encryption)${NC}"
fi
echo ""

# Replace old keys with new keys
mv "$SECRETS_DIR/agent.key.new" "$SECRETS_DIR/agent.key"
mv "$SECRETS_DIR/agent.key.pub.new" "$SECRETS_DIR/agent.key.pub"

chmod 600 "$SECRETS_DIR/agent.key"
chmod 644 "$SECRETS_DIR/agent.key.pub"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ Key rotation complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "📋 Summary:"
echo "  • Old key backed up: $BACKUP_DIR/agent.key.$BACKUP_DATE"
echo "  • New public key: $NEW_PUBLIC_KEY"
echo "  • Secrets re-encrypted: secrets.env.age"
echo ""
echo "⚠️  Important next steps:"
echo "  1. Test decryption: age -d -i secrets/agent.key secrets/secrets.env.age"
echo "  2. Backup new key to secure location (password manager, encrypted USB, etc.)"
echo "  3. Update any systems using the old public key"
echo "  4. Keep old key backup for 30 days (in case of emergency)"
echo ""
