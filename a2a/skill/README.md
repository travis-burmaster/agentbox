# a2a/skill — Slack Authorization Layer

An authorization middleware that sits between Slack and the OpenClaw runtime.
Users request **actions**. This layer decides what they can do, with what parameters.

---

## Architecture

```
Slack User
    │
    │  POST /slack/action
    │  {"slack_user_id": "U123", "action": "search_web", "params": {...}}
    ▼
┌─────────────────────────────────────────────────┐
│               server.py (FastAPI)               │
│            /slack/action endpoint               │
└────────────────────┬────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│              IdentityResolver                   │
│  Slack user_id → Identity(role="operator")      │
│  Source: SLACK_ROLE_MAP env var or              │
│          identity_map.yaml                      │
└────────────────────┬────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│                RateLimiter                      │
│  Sliding window (60s) per user                  │
│  Limits from roles.yaml (rate_limit field)      │
└────────────────────┬────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────┐
│               PolicyEngine                      │
│  Is action in allowed_actions for this role?    │
│  Is action in denied_actions? (deny wins)       │
│  Apply parameter_constraints (clamp/strip)      │
│  Source: roles.yaml                             │
└────────────────────┬────────────────────────────┘
                     │
             ┌───────┴───────┐
             │               │
           DENY           ALLOW
             │               │
             ▼               ▼
       🚫 Return       ┌──────────────────────────┐
       denial msg      │      OpenClawClient       │
       to Slack        │ POST to OpenClaw gateway  │
                       │ (sanitized params only)   │
                       └──────────┬───────────────┘
                                  │
                                  ▼
                         Response text
                         back to Slack
```

---

## Quick Start

### 1. Map Slack User IDs to Roles

**Option A: environment variable** (recommended for production)

```bash
export SLACK_ROLE_MAP='{"U01TRAVIS": "admin", "U02ENG": "operator"}'
```

**Option B: identity_map.yaml** (easier for development)

```yaml
# a2a/skill/identity_map.yaml
identity_map:
  U01TRAVIS: admin
  U02ENG: operator
  default: readonly    # fallback for unlisted users
```

To find your Slack user ID:
- In Slack: click your name → View Profile → ⋮ More → Copy member ID
- Via API: `GET https://slack.com/api/users.list` (requires `users:read` scope)
- Via bot: have your bot log `event.user` from any incoming event

### 2. Configure roles.yaml

Roles, allowed actions, and parameter constraints live in `a2a/skill/roles.yaml`.

```yaml
roles:
  admin:
    allowed_actions: ["*"]        # full access
    rate_limit: 100

  operator:
    allowed_actions:
      - search_web
      - run_code
      - read_file
    denied_actions:
      - exec_shell               # explicit deny wins over allowed_actions
    parameter_constraints:
      run_code:
        max_timeout_seconds: 30  # clamp execution time
    rate_limit: 30

  readonly:
    allowed_actions:
      - search_web
      - get_status
    rate_limit: 10
```

### 3. Set OpenClaw gateway config

```bash
export OPENCLAW_GATEWAY_URL=http://localhost:3000    # default
export OPENCLAW_GATEWAY_TOKEN=your-token-here        # optional
```

### 4. Call the endpoint

From your Slack bot (Bolt, Socket Mode, etc.):

```python
import httpx

async def handle_slack_action(slack_user_id: str, action: str, params: dict):
    async with httpx.AsyncClient() as client:
        resp = await client.post(
            "http://your-agentbox-host/slack/action",
            json={
                "slack_user_id": slack_user_id,
                "action": action,
                "params": params,
            },
        )
    result = resp.json()
    if result["allowed"]:
        await say(result["response"])
    else:
        await say(f"Sorry, that's not allowed: {result['reason']}")
```

---

## Adding a New Action

1. Add the action name to the appropriate role's `allowed_actions` in `roles.yaml`
2. Optionally add `parameter_constraints` for that action
3. Add a message template in `SkillRouter._build_openclaw_message()` for better OpenClaw context

Example — adding `summarize_document`:

```yaml
# roles.yaml
operator:
  allowed_actions:
    - summarize_document  # add here
  parameter_constraints:
    summarize_document:
      max_size_bytes: 524288  # 512KB max input
```

```python
# skill_router.py — _build_openclaw_message()
templates = {
    ...
    "summarize_document": "Summarize this document:\n{content}",
}
```

---

## Adding a New Role

1. Add a new entry under `roles:` in `roles.yaml`
2. Map Slack user IDs to the new role in `identity_map.yaml` or `SLACK_ROLE_MAP`

```yaml
# roles.yaml
roles:
  analyst:
    allowed_actions:
      - search_web
      - run_analysis
      - read_file
      - fetch_url
    rate_limit: 20
```

---

## Environment Variables

| Variable | Required | Default | Description |
|---|---|---|---|
| `SLACK_ROLE_MAP` | No | — | JSON string: `{"U123": "admin", "U456": "operator"}` |
| `OPENCLAW_GATEWAY_URL` | No | `http://localhost:3000` | OpenClaw gateway base URL |
| `OPENCLAW_GATEWAY_TOKEN` | No | — | Bearer token for gateway auth |

---

## Module Reference

| Module | Responsibility |
|---|---|
| `identity_resolver.py` | Resolves Slack user IDs → Identity with role |
| `policy_engine.py` | Checks action permissions, sanitizes params |
| `rate_limiter.py` | Sliding-window rate limiting per user |
| `openclaw_client.py` | Async HTTP client for OpenClaw gateway |
| `skill_router.py` | Orchestrates the full pipeline |
| `middleware.py` | FastAPI dependency injection (singleton SkillRouter) |
| `roles.yaml` | Role definitions, allowed actions, constraints |
| `identity_map.yaml` | Slack user ID → role mappings |

---

## Security Design Decisions

- **Deny by default**: unknown roles, unknown actions, and missing config all result in denial
- **Identity map fallback**: unmapped Slack users get `readonly` (not `admin`)
- **Explicit deny wins**: `denied_actions` overrides `allowed_actions` for defense in depth
- **Param sanitization**: dangerous param values are stripped/clamped before reaching OpenClaw
- **No secrets in YAML**: tokens go in env vars, user IDs in YAML (not sensitive)
- **Rate limiting**: prevents abuse even for authorized users
