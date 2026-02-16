# AgentFork - Core Framework

This directory contains the core AgentBox framework code, forked from OpenClaw.

## What Goes Here

Place your forked OpenClaw source code in this directory:

```
agentfork/
├── package.json
├── src/
│   ├── agent/
│   ├── tools/
│   ├── runtime/
│   └── ...
├── bin/
│   └── agentbox
└── ...
```

## Building from Source

The Dockerfile will:
1. Copy this directory into the container
2. Run `npm install` to install dependencies
3. Run `npm run build` to compile TypeScript
4. Run `npm link` to make `agentbox` command available globally

## How to Fork OpenClaw

If you're starting fresh:

```bash
# Clone OpenClaw
git clone https://github.com/openclaw/openclaw.git temp-openclaw

# Copy to agentfork directory
cp -r temp-openclaw/* agentfork/

# Remove git history
rm -rf agentfork/.git

# Rename commands
cd agentfork
find . -type f -exec sed -i 's/openclaw/agentbox/g' {} +

# Update package.json
# Change "name": "openclaw" to "name": "agentbox"
# Update bin commands from "openclaw" to "agentbox"

# Clean up
cd ..
rm -rf temp-openclaw
```

## Required Changes

When forking OpenClaw, update these files:

### package.json
```json
{
  "name": "agentbox",
  "bin": {
    "agentbox": "./bin/agentbox"
  }
}
```

### bin/agentbox (rename from bin/openclaw)
```javascript
#!/usr/bin/env node
// Update all internal references from openclaw to agentbox
```

### Configuration paths
- Change `~/.openclaw` to `~/.agentbox`
- Update all environment variables from `OPENCLAW_*` to `AGENTBOX_*`

## Notes

- This is a fork, not a direct dependency, to maintain full control over security
- Keep attribution to OpenClaw in documentation
- Track upstream changes selectively (security patches, bug fixes)
- Don't automatically merge upstream - review all changes for security impact
