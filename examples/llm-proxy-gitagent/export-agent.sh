#!/usr/bin/env bash
# Seeds ./workspace/ from an agent repo (openclaw workspace format).
# Run ONCE on the host before first `docker compose up`.
# No gitagent dependency — clones the repo and copies workspace files directly.
#
# Supported repo layouts:
#   - Flat (SOUL.md, RULES.md / AGENTS.md, agent.yaml at root)
#   - workspace/ subdirectory
#
# Usage:
#   ./export-agent.sh                                        # use starter workspace
#   ./export-agent.sh https://github.com/org/agent-repo     # seed from repo

set -euo pipefail

REPO_URL="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$SCRIPT_DIR/workspace"

echo "AgentBox export-agent.sh"
echo "─────────────────────────────────────────────"

if [ -z "$REPO_URL" ]; then
    echo "No repo URL provided — starter workspace files are in place."
    echo "To seed from your agent repo:"
    echo "  ./export-agent.sh https://github.com/your-org/your-agent"
    echo ""
    echo "Next steps:"
    echo "  1. Edit secrets/secrets.env (set CLAUDE_OAUTH_TOKEN)"
    echo "  2. docker compose up -d"
    echo "  3. Open http://localhost:3000"
    exit 0
fi

# Check git (required)
if ! command -v git &>/dev/null; then
    echo "ERROR: git is required. Install git and try again."
    exit 1
fi

# Clone the repo (use gh if available for private repos, fall back to git)
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "Cloning $REPO_URL..."
if command -v gh &>/dev/null && gh auth status &>/dev/null 2>&1; then
    gh repo clone "$REPO_URL" "$TMPDIR" -- --depth=1
else
    git clone --depth=1 "$REPO_URL" "$TMPDIR"
fi

# Detect workspace layout:
# - If repo has a workspace/ subdirectory, use that
# - Otherwise treat the repo root as the workspace
if [ -d "$TMPDIR/workspace" ] && [ -n "$(ls "$TMPDIR/workspace/")" ]; then
    SRC="$TMPDIR/workspace"
    echo "Found workspace/ subdirectory — using that."
else
    SRC="$TMPDIR"
    echo "Using repo root as workspace."
fi

# Copy all files (excluding .git) into ./workspace/
echo "Seeding workspace/..."
rsync -a --exclude='.git' --exclude='.gitignore' "$SRC/" "$WORKSPACE_DIR/"

# Preserve workspace .gitignore (ours, not the agent repo's)
echo "# gitagent runtime state — not committed" > "$WORKSPACE_DIR/.gitignore"
echo ".gitagent/" >> "$WORKSPACE_DIR/.gitignore"

echo ""
echo "Workspace seeded from: $REPO_URL"
echo "Contents:"
ls -la "$WORKSPACE_DIR/"

echo ""
echo "Next steps:"
echo "  1. Edit secrets/secrets.env (set CLAUDE_OAUTH_TOKEN)"
echo "  2. docker compose up -d"
echo "  3. Open http://localhost:3000"
