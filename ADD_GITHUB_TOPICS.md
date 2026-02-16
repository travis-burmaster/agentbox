# Adding GitHub Topics to AgentBox

This guide shows how to add discoverability topics/tags to the agentbox repository.

## Option 1: Via GitHub Web Interface (Easiest)

1. Go to https://github.com/travis-burmaster/agentbox
2. Click on the ⚙️ gear icon next to "About" (top right of repository)
3. In the "Topics" field, add these tags (separated by spaces or commas):

```
ai-agents docker security self-hosted openclaw llm ai-automation devops privacy encryption
```

4. Click "Save changes"

**Result:** Topics will appear under the repository name and make it discoverable in GitHub search/explore.

---

## Option 2: Via GitHub CLI (Automated)

If you have `gh` CLI installed and authenticated as travis-burmaster:

```bash
cd agentbox

gh repo edit travis-burmaster/agentbox \
  --add-topic ai-agents \
  --add-topic docker \
  --add-topic security \
  --add-topic self-hosted \
  --add-topic openclaw \
  --add-topic llm \
  --add-topic ai-automation \
  --add-topic devops \
  --add-topic privacy \
  --add-topic encryption
```

---

## Option 3: Via GitHub API (Programmatic)

Using `curl` with a GitHub Personal Access Token:

```bash
# Set your GitHub token
export GITHUB_TOKEN="ghp_your_token_here"

# Add topics
curl -X PUT \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  https://api.github.com/repos/travis-burmaster/agentbox/topics \
  -d '{
    "names": [
      "ai-agents",
      "docker",
      "security",
      "self-hosted",
      "openclaw",
      "llm",
      "ai-automation",
      "devops",
      "privacy",
      "encryption"
    ]
  }'
```

---

## Recommended Topics Explained

| Topic | Why It Matters |
|-------|----------------|
| **ai-agents** | Primary category - shows up in AI agent searches |
| **docker** | Deployment method - attracts DevOps audience |
| **security** | Key differentiator - security-first approach |
| **self-hosted** | Privacy/control audience - vs cloud AI |
| **openclaw** | Attribution & findability by OpenClaw users |
| **llm** | Large language model integration |
| **ai-automation** | Use case - automated workflows |
| **devops** | Target audience - DevOps engineers |
| **privacy** | Key value prop - data sovereignty |
| **encryption** | Technical feature - encrypted secrets |

---

## Verification

After adding topics, verify they appear:

1. Visit https://github.com/travis-burmaster/agentbox
2. Topics should appear as blue tags under the repository name
3. Click any topic to see other repos with the same tag

---

## Additional Discovery Tips

### Add a Description

In the same "About" settings, add:

```
Security-first AI agent framework with VM isolation, encrypted secrets, and audit logging. Built on OpenClaw.
```

### Add a Website (Optional)

If you have a project page or docs site, add it to the "Website" field.

### Enable Features

Consider enabling:
- ✅ Issues (for bug reports)
- ✅ Discussions (for community Q&A)
- ✅ Wikis (for detailed docs)

---

**Once topics are added, the repository will be much more discoverable on GitHub!**
