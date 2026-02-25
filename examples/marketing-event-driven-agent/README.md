# AgentBox Example: Marketing Agent — Event-Driven, Scale-to-Zero on GCP

An autonomous AI marketing agent that runs on **GCP Cloud Run** (scales to zero between events), restores its full memory from **Redis** on cold start, and is triggered by a **Kafka** event-driven loop.

This example shows how to extend AgentBox into a production-grade autonomous agent that survives container restarts with no memory loss.

---

## What It Does

The agent runs a marketing business end-to-end:

| Trigger | What Happens |
|---------|-------------|
| `lead.created` (Kafka) | Researches company → scores lead → drafts personalized email → sends outreach → logs to CRM |
| `lead.responded` (Kafka) | Reads full interaction history from Redis → crafts reply → escalates if high-value |
| `campaign.start` (Kafka) | Kicks off multi-step drip sequence (email → LinkedIn → follow-up) |
| `schedule.daily_report` (Cloud Scheduler) | Pulls BigQuery analytics → generates insights → emails report |
| `schedule.competitor_scan` (Cloud Scheduler) | Scans competitor web presence → summarizes changes → emails intel brief |
| `schedule.content_publish` | Generates and publishes LinkedIn posts / newsletters |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        EVENT SOURCES                                 │
│   CRM Webhooks    Cloud Scheduler (cron)    Human Commands (Telegram)│
│        │                   │                        │               │
└────────┼───────────────────┼────────────────────────┼───────────────┘
         │                   │                        │
         ▼                   ▼                        ▼
┌─────────────────────────────────────────────────────────────────────┐
│                  KAFKA (Confluent Cloud / GCP Pub/Sub)               │
│                                                                      │
│  marketing.leads        marketing.campaigns    marketing.schedule    │
│  marketing.commands     marketing.agent.results                      │
└──────────────────────────────┬──────────────────────────────────────┘
                               │ Consumer Group: agentbox-marketing
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│           CLOUD RUN — AgentBox Container  (min=0, max=10)            │
│                                                                      │
│   ① COLD START (~300ms)              ② PROCESS EVENT                 │
│      └─ Load memory from Redis          └─ Parse Kafka message       │
│      └─ Restore task queue              └─ Invoke Gemini 1.5 Pro    │
│      └─ Restore campaign states         └─ Execute tools             │
│      └─ Reconstruct LLM context         └─ Publish to output topic   │
│                                                                      │
│   ③ SHUTDOWN FLUSH (~100ms)                                           │
│      └─ Write memory → Redis                                         │
│      └─ Write task updates → Redis                                   │
│      └─ Write campaign state → Redis                                 │
└──────────────────────────────┬──────────────────────────────────────┘
                               │
        ┌──────────────────────┼──────────────────────┐
        ▼                      ▼                       ▼
┌──────────────┐   ┌──────────────────┐   ┌─────────────────────────┐
│ REDIS        │   │ VERTEX AI        │   │ DOWNSTREAM              │
│ (Memorystore)│   │ Gemini 1.5 Pro   │   │                         │
│              │   │                  │   │ • Gmail / SMTP          │
│ long_term    │   │ • LLM inference  │   │ • HubSpot CRM           │
│ tasks        │   │ • Tool calling   │   │ • LinkedIn API          │
│ campaigns    │   │ • Grounding      │   │ • BigQuery analytics    │
│ leads        │   └──────────────────┘   │ • Cloud Storage         │
│ content      │                          └─────────────────────────┘
└──────────────┘
```

---

## How Cold Start Memory Works

Every time the container wakes from zero, it runs a **boot sequence** before touching any Kafka message:

```python
async def boot_context(redis) -> dict:
    # All 4 loads happen in parallel — total ~200-400ms
    memory, tasks, campaign_ids, hot_leads = await asyncio.gather(
        redis.get("agent:memory:marketing"),       # Long-term memory
        redis.zrange("agent:tasks:pending", 0, 20), # Priority task queue
        redis.smembers("agent:campaigns:active"),   # Active campaign IDs
        redis.zrevrange("agent:leads:hot", 0, 9),   # Top 10 hot leads
    )
    # Load each campaign's full state in parallel
    campaign_states = await asyncio.gather(*[
        redis.hgetall(f"agent:campaign:{cid}:state")
        for cid in campaign_ids
    ])
    return { memory, tasks, campaign_states, hot_leads }
```

This context is injected into the LLM system prompt — the agent wakes up knowing exactly where it left off.

---

## Redis Memory Schema

```
# Long-term agent memory (never evicted — noeviction policy)
agent:memory:marketing          JSON  { brand_voice, icp, lessons, decisions, competitors }

# Task queue (sorted set — score = priority × timestamp)
agent:tasks:pending             ZSET  priority-ordered task list
agent:tasks:completed           LIST  last 500 completed tasks
agent:tasks:failed              LIST  last 100 failed tasks (for review)

# Per-campaign state
agent:campaign:{id}:state       HASH  { status, stage, name, metrics, next_action }
agent:campaign:{id}:history     LIST  chronological action log
agent:campaigns:active          SET   set of active campaign IDs

# Per-lead memory
agent:lead:{id}:profile         HASH  { name, company, email, score, status, last_action }
agent:lead:{id}:history         LIST  interaction log (last 100 touchpoints)
agent:leads:hot                 ZSET  leads scored by engagement (high score = hot)

# Content library
agent:content:{id}              JSON  { type, body, platform, performance }
agent:content:approved          SET   IDs of approved/published content
```

---

## Kafka Topics

| Topic | Key | Trigger | Example Event |
|-------|-----|---------|--------------|
| `marketing.leads` | `lead_id` | CRM webhook | `lead.created`, `lead.responded` |
| `marketing.campaigns` | `campaign_id` | Campaign engine | `campaign.start`, `campaign.step_complete` |
| `marketing.schedule` | `task_type` | Cloud Scheduler | `daily_report`, `competitor_scan` |
| `marketing.commands` | — | Human (Telegram/API) | Free-form command text |
| `marketing.agent.results` | `run_id` | Agent output | Action log, next events |

---

## GCP Infrastructure

| Service | Purpose | Config |
|---------|---------|--------|
| **Cloud Run** | AgentBox container | min=0, max=10, concurrency=1, CPU boost on cold start |
| **Memorystore Redis** | Agent memory persistence | 2GB, STANDARD_HA, `noeviction` policy |
| **Confluent Cloud** | Kafka event bus | 3 partitions per topic, SASL/SSL |
| **Vertex AI** | Gemini 1.5 Pro inference + tool calling | us-central1 |
| **BigQuery** | Analytics/reporting data warehouse | `agentbox_marketing` dataset |
| **Cloud Storage** | Artifacts, reports, generated content | `agentbox-marketing-artifacts` |
| **Cloud Scheduler** | Cron → Kafka (daily report, weekly competitor scan) | UTC schedule |
| **Artifact Registry** | Container image storage | `agentbox/marketing` |
| **Secret Manager** | API keys, credentials | Kafka, SMTP, CRM tokens |
| **Cloud Build** | CI/CD pipeline | Trigger on `main` branch push |

---

## Scaling Model

```
Kafka message arrives
       │
       ▼
Kafka Pull Consumer (Cloud Run Kafka trigger or push connector)
       │
       ├── 0 instances running?
       │      └── Cold start (5-10s total)
       │             ├── Container pull + init: ~4s
       │             ├── Redis memory boot:    ~300ms
       │             └── Ready to process:     ✅
       │
       └── Instance already warm?
              └── Process immediately (<100ms)

After processing:
  └── Commit Kafka offset
  └── Flush memory to Redis (~100ms)
  └── Container idles → Cloud Run scales to 0 after 60s
```

**Key design decision:** `concurrency=1` — each Cloud Run instance handles exactly one Kafka event at a time. This keeps the memory model simple and prevents state corruption between concurrent events. Scale-out happens by launching more instances in parallel.

---

## Project Structure

```
examples/marketing-event-driven-agent/
├── README.md                     ← This file
├── Dockerfile                    ← Slim Python 3.12, non-root, Cloud Run optimized
├── docker-compose.yml            ← Local dev: Redis + Kafka + AgentBox
├── requirements.txt
│
├── agent/
│   ├── memory.py                 ← Redis memory manager (boot sequence + flush)
│   ├── kafka_consumer.py         ← Kafka consumer loop (Cloud Run entrypoint)
│   ├── marketing_agent.py        ← LLM agent + all marketing workflow handlers
│   └── tools.py                  ← Tool implementations (email, CRM, search, analytics)
│
├── infra/
│   └── main.tf                   ← Full Terraform (Cloud Run, Redis, IAM, Scheduler)
│
└── scripts/
    ├── deploy.sh                 ← Build + push container + deploy to Cloud Run
    └── publish_event.py          ← Test event publisher (local dev)
```

---

## Quick Start

### Local Development

```bash
# Clone and enter the example
git clone https://github.com/travis-burmaster/agentbox.git
cd agentbox/examples/marketing-event-driven-agent

# Copy env template
cp .env.example .env
# Edit .env: add GCP_PROJECT, LLM keys, SMTP credentials

# Start local stack (Redis + Kafka + AgentBox)
docker-compose up -d

# Watch the agent boot and wait for events
docker-compose logs -f agentbox

# In another terminal — simulate a new lead
python scripts/publish_event.py \
  --topic marketing.leads \
  --event lead.created \
  --key lead-001 \
  --data '{
    "lead_id": "lead-001",
    "name": "Jane Smith",
    "company": "Acme Corp",
    "email": "jane@acme.com",
    "title": "VP Engineering",
    "source": "linkedin",
    "message": "Saw your post about AI modernization — would love to connect."
  }'

# Watch the agent:
#   1. Research Acme Corp
#   2. Score the lead
#   3. Draft personalized outreach
#   4. Send email
#   5. Update CRM
#   6. Flush memory to Redis
```

### Deploy to GCP

```bash
# Prerequisites: gcloud auth, terraform init
export GCP_PROJECT=your-project-id
export GCP_REGION=us-central1

# Provision infrastructure
cd infra
terraform init
terraform apply \
  -var="project_id=$GCP_PROJECT" \
  -var="kafka_bootstrap=pkc-xxxxx.us-central1.gcp.confluent.cloud:9092" \
  -var="kafka_api_key=YOUR_KEY" \
  -var="kafka_api_secret=YOUR_SECRET" \
  -var="smtp2go_pass=YOUR_SMTP_PASS"

# Build and deploy container
cd ..
./scripts/deploy.sh
```

---

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `REDIS_URL` | ✅ | `redis://host:port` (Memorystore in prod) |
| `KAFKA_BOOTSTRAP_SERVERS` | ✅ | Confluent Cloud bootstrap servers |
| `KAFKA_API_KEY` | ✅ | Confluent Cloud API key |
| `KAFKA_API_SECRET` | ✅ | Confluent Cloud API secret |
| `GCP_PROJECT` | ✅ | GCP project ID for Vertex AI |
| `GCP_LOCATION` | — | Vertex AI region (default: `us-central1`) |
| `LLM_MODEL` | — | Gemini model (default: `gemini-1.5-pro`) |
| `SMTP2GO_PASS` | ✅ | SMTP2GO password for email sending |
| `MAX_EVENTS_PER_RUN` | — | Max events per container run (default: `10`) |
| `POLL_TIMEOUT_SECONDS` | — | Kafka poll timeout before idle exit (default: `30`) |

---

## Extending This Example

### Add a New Marketing Workflow

1. Add a new Kafka topic or event type
2. Add a handler in `marketing_agent.py`:
   ```python
   async def _handle_my_new_workflow(self, event, key, payload):
       prompt = "..."
       await self._execute_llm_task(prompt)
   ```
3. Register it in `handle_event()`
4. Add any new Redis keys to `memory.py`

### Add a New Tool

1. Implement the tool in `agent/tools.py`
2. Add a `FunctionDeclaration` in `_build_tools()`
3. Add dispatch case in `_dispatch_tool()`

### Swap the LLM

Replace Vertex AI Gemini with any LLM provider — just swap out `_execute_llm_task()`. The memory model and Kafka consumer are fully provider-agnostic.

---

## Key Design Principles

1. **Memory-first design** — Redis is the agent's brain. Cold start = reload Redis. Shutdown = flush to Redis. Never lose state.

2. **Scale-to-zero is the default** — Don't pay for idle compute. Events drive execution; silence means zero cost.

3. **One event, one instance** — `concurrency=1` keeps state simple. Parallelism = more instances, not more threads.

4. **Graceful shutdown** — `SIGTERM` handler ensures Redis flush happens before Cloud Run kills the container.

5. **Human-in-the-loop** — `alert_human()` tool lets the agent escalate to Telegram/email when it needs a decision.

---

## Related Examples

- [`a2a/`](../../a2a/) — A2A (Agent-to-Agent) protocol implementation for Cloud Run
- More examples coming — PRs welcome!

---

*Built with [AgentBox](https://github.com/travis-burmaster/agentbox) — self-hosted AI agent runtime.*
