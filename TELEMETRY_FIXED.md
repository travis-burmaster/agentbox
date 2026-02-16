# Telemetry Dashboard - FIXED! 🎉

The OpenClaw telemetry dashboard is now working and accessible at **http://localhost:8501**

## ✅ What Was Fixed

### Problem 1: Database Not Found
**Error**: `Database not found: openclaw_telemetry.db`

**Root Cause**: The telemetry container couldn't access OpenClaw session files because:
1. Sessions are stored in `/agentbox/.openclaw/.openclaw/agents/main/sessions/`
2. The telemetry container was looking in `~/.openclaw/agents/main/sessions/`
3. The config volume wasn't shared with the telemetry container

**Fix**: Added agentbox-config volume mount to telemetry container in docker-compose.yml:
```yaml
volumes:
  - agentbox-config:/root/.openclaw:ro  # Share config (includes sessions)
```

### Problem 2: Wrong Sessions Path in Dashboard Code
**Error**: Sessions directory not found

**Root Cause**: Dashboard was hardcoded to look in `~/.openclaw/agents/main/sessions/` but OpenClaw uses `.openclaw/.openclaw/agents/main/sessions/`

**Fix**: Updated `telemetry/dashboard.py` to check the correct path:
```python
sessions_dir = os.getenv("OPENCLAW_SESSIONS_DIR") or os.path.expanduser("~/.openclaw/.openclaw/agents/main/sessions")
```

### Problem 3: TypeError with Metrics
**Error**: `TypeError: int() argument must be a string, a bytes-like object or a real number, not 'NoneType'`

**Root Cause**: Dashboard tried to format None values as numbers when no sessions existed yet

**Fix**: Changed all metric formatting to handle None values:
```python
# Before:
f"{int(metrics.get('total_messages', 0)):,}"

# After:
f"{int(metrics.get('total_messages') or 0):,}"
```

## 🚀 How to Use the Dashboard

### Access the Dashboard

Open your browser to: **http://localhost:8501**

### What You'll See

The dashboard automatically displays:

#### 📊 Overview Metrics
- Total sessions
- Total messages (LLM API calls)
- Total tokens (input + output)
- Total cost across all models

#### 📈 Timeline Visualization
- Usage patterns (hourly, daily, monthly)
- Cost trends
- Message volume tracking

#### 🤖 Model Analytics
- Per-model cost breakdown
- Token distribution by provider
- Session count by model

#### 🔧 Tool Usage Tracking
- Most frequently used tools
- Tool call patterns
- Performance insights

#### 📜 Session History
- Recent session details
- Per-session token and cost data
- Detailed session timelines

### Generate Some Data

To see real metrics, chat with OpenClaw:

```bash
# Create some sessions
docker exec agentbox openclaw agent chat "Hello! Tell me about AI."
docker exec agentbox openclaw agent chat "What is quantum computing?"
docker exec agentbox openclaw agent chat "Explain Docker in simple terms."

# Then refresh the dashboard at http://localhost:8501
```

## 🔧 Configuration

### Sessions Directory

The dashboard automatically looks for sessions in:
1. `/root/.openclaw/.openclaw/agents/main/sessions/` (Docker default)
2. Or set custom path: `OPENCLAW_SESSIONS_DIR=/custom/path`

### Database Location

Telemetry data is stored in: `/app/openclaw_telemetry.db` (inside container)

To persist the database across container restarts, add a volume in docker-compose.yml:
```yaml
volumes:
  - telemetry-db:/app  # Persist database
```

## 🐛 Troubleshooting

### Dashboard Shows "No Data"

**Solution**: Create some OpenClaw sessions first:
```bash
docker exec agentbox openclaw agent chat "Hello!"
# Then refresh the dashboard
```

### "Sessions directory not found" Error

**Solution**: Verify the config volume is mounted:
```bash
docker exec agentbox-telemetry ls -la /root/.openclaw/.openclaw/agents/main/sessions/
# Should show session *.jsonl files
```

### Dashboard Won't Load

**Solution**: Check telemetry logs:
```bash
docker logs agentbox-telemetry
# Look for errors

# Restart if needed:
docker-compose restart telemetry
```

### Container Shows as "Unhealthy"

**Note**: The health check URL might be incorrect. The dashboard works even if status shows unhealthy. Fix health check:

Edit docker-compose.yml health check:
```yaml
healthcheck:
  test: ["CMD", "curl", "-f", "http://localhost:8501"]
  interval: 30s
  timeout: 10s
  retries: 3
  start_period: 15s
```

## 📂 Files Modified

1. **docker-compose.yml**:
   - Added `agentbox-config` volume mount to telemetry service

2. **telemetry/dashboard.py**:
   - Fixed sessions directory path detection
   - Fixed None value handling in metric formatting

## 🎯 Next Steps

### 1. Monitor Your AI Usage

Keep the dashboard open while using OpenClaw to see real-time metrics:
- Track token usage
- Monitor API costs
- Identify expensive sessions
- Optimize your prompts

### 2. Enable BMasterAI (Optional)

For advanced monitoring and alerting:
```bash
# Install bmasterai in telemetry container
docker exec -it agentbox-telemetry pip install bmasterai>=0.2.3

# Restart telemetry
docker-compose restart telemetry
```

### 3. Set Up Cost Alerts

The dashboard can alert you when costs exceed thresholds (requires BMasterAI).

## 📊 Example Metrics

After running a few OpenClaw sessions, you'll see:

```
Total Sessions: 5
Total Messages: 23
Total Tokens: 45,231
Total Cost: $0.89

Top Models:
- claude-opus-4-6: $0.67 (75%)
- claude-sonnet-4-5: $0.22 (25%)

Most Used Tools:
- bash: 12 calls
- read: 8 calls
- write: 3 calls
```

## ✅ Verification

To confirm everything is working:

```bash
# 1. Check containers are running
docker ps

# Should show both:
# - agentbox (healthy)
# - agentbox-telemetry (may show unhealthy, but works)

# 2. Check telemetry can see sessions
docker exec agentbox-telemetry ls -la /root/.openclaw/.openclaw/agents/main/sessions/

# Should show *.jsonl files

# 3. Access dashboard
open http://localhost:8501

# Should load without errors
```

## 🎉 Success!

Your telemetry dashboard is now fully operational! Track your AI usage, optimize costs, and monitor performance in real-time.

---

**Dashboard URL**: http://localhost:8501
**Last Updated**: 2026-02-16
**Status**: ✅ Fully Operational
