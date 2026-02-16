#!/bin/bash
# Load encrypted secrets into environment
# Usage: source scripts/load-secrets.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SECRETS_DIR="$PROJECT_ROOT/secrets"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔐 Loading encrypted secrets...${NC}"

# Check if age is installed
if ! command -v age &> /dev/null; then
    echo -e "${RED}❌ Error: age is not installed${NC}"
    echo ""
    echo "Install age:"
    echo "  macOS:  brew install age"
    echo "  Linux:  sudo apt install age"
    echo ""
    return 1
fi

# Check if key file exists
if [ ! -f "$SECRETS_DIR/agent.key" ]; then
    echo -e "${RED}❌ Error: Private key not found${NC}"
    echo ""
    echo "Expected location: $SECRETS_DIR/agent.key"
    echo ""
    echo "Generate a key:"
    echo "  age-keygen -o $SECRETS_DIR/agent.key"
    echo ""
    return 1
fi

# Check if encrypted secrets exist
if [ ! -f "$SECRETS_DIR/secrets.env.age" ]; then
    echo -e "${YELLOW}⚠️  Warning: No encrypted secrets found${NC}"
    echo ""
    echo "Expected location: $SECRETS_DIR/secrets.env.age"
    echo ""
    echo "Create encrypted secrets:"
    echo "  1. Create secrets.env with your values"
    echo "  2. age -r \$(cat $SECRETS_DIR/agent.key.pub) -o $SECRETS_DIR/secrets.env.age secrets.env"
    echo "  3. shred -u secrets.env"
    echo ""
    return 1
fi

# Decrypt and load secrets into environment
# This never writes plaintext to disk!
while IFS= read -r line; do
    # Skip empty lines and comments
    if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
        continue
    fi
    
    # Export the variable
    export "$line"
done < <(age -d -i "$SECRETS_DIR/agent.key" "$SECRETS_DIR/secrets.env.age" 2>/dev/null)

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Secrets loaded successfully${NC}"
    
    # Show loaded (but not values!)
    echo ""
    echo "Loaded environment variables:"
    age -d -i "$SECRETS_DIR/agent.key" "$SECRETS_DIR/secrets.env.age" 2>/dev/null | grep -oE '^[A-Z_]+=' | sed 's/=$//' | while read var; do
        echo "  • $var"
    done
else
    echo -e "${RED}❌ Failed to decrypt secrets${NC}"
    echo ""
    echo "Possible causes:"
    echo "  - Wrong private key"
    echo "  - Corrupted encrypted file"
    echo "  - File encrypted with different key"
    echo ""
    return 1
fi
