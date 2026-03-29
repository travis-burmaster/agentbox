#!/usr/bin/env bash
# Seeds ./workspace/ from a gitagent repo using `gitagent export`.
# Run ONCE on the host before first `docker compose up`.
#
# Usage:
#   ./export-agent.sh                                        # use starter workspace
#   ./export-agent.sh https://github.com/org/agent-repo     # seed from gitagent repo

set -euo pipefail

REPO_URL="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$SCRIPT_DIR/workspace"

echo "AgentBox export-agent.sh"
echo "─────────────────────────────────────────────"

# Check gh CLI
if ! command -v gh &>/dev/null; then
    echo "WARNING: gh CLI not found. Install from https://cli.github.com/"
    echo "         Required only if seeding from a private gitagent repo."
elif ! gh auth status &>/dev/null 2>&1; then
    echo "WARNING: gh CLI not authenticated. Run: gh auth login"
    echo "         Required only if seeding from a private gitagent repo."
fi

# Check gitagent
if ! command -v gitagent &>/dev/null; then
    echo "WARNING: gitagent not found. Install with: npm install -g gitagent"
    echo "         Required only if seeding from a gitagent repo."
fi

if [ -n "$REPO_URL" ]; then
    if ! command -v gitagent &>/dev/null; then
        echo "ERROR: gitagent is required to export from a repo. Install: npm install -g gitagent"
        exit 1
    fi

    echo "Cloning $REPO_URL..."
    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT

    gh repo clone "$REPO_URL" "$TMPDIR" -- --depth=1 2>/dev/null \
        || git clone --depth=1 "$REPO_URL" "$TMPDIR"

    echo "Exporting agent to workspace/..."
    gitagent export --format openclaw --agent-dir "$TMPDIR" --out "$WORKSPACE_DIR/"

    echo ""
    echo "Workspace seeded from: $REPO_URL"
    echo "Contents:"
    ls -la "$WORKSPACE_DIR/"
else
    echo "No repo URL provided — starter workspace files are in place."
    echo "To seed from your gitagent repo:"
    echo "  ./export-agent.sh https://github.com/your-org/your-agent"
fi

echo ""
echo "Next steps:"
echo "  1. Edit secrets/secrets.env (set CLAUDE_OAUTH_TOKEN)"
echo "  2. docker compose up -d"
echo "  3. Open http://localhost:3000"
