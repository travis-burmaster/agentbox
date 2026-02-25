"""
Redis Memory Manager — AgentBox Marketing

Handles all agent memory persistence:
- Long-term memory (survives restarts — equivalent to MEMORY.md)
- Task queue (prioritized, scored)
- Campaign state (per-campaign hash)
- Lead profiles
"""

import json
import time
import asyncio
from typing import Any, Optional
import redis.asyncio as aioredis


AGENT_ID = "marketing"


class AgentMemory:
    def __init__(self, redis_url: str):
        self.redis = aioredis.from_url(redis_url, decode_responses=True)
        self.agent_id = AGENT_ID

    # ─── LONG-TERM MEMORY ──────────────────────────────────────────────────────

    async def load_long_term(self) -> dict:
        """Load agent's long-term memory. Called on every cold start."""
        raw = await self.redis.get(f"agent:memory:{self.agent_id}")
        if not raw:
            return self._default_memory()
        return json.loads(raw)

    async def save_long_term(self, memory: dict):
        """Persist long-term memory. Called on shutdown flush."""
        memory["last_updated"] = time.time()
        await self.redis.set(
            f"agent:memory:{self.agent_id}",
            json.dumps(memory),
        )

    async def append_memory(self, key: str, value: Any):
        """Append a single insight/decision to long-term memory."""
        memory = await self.load_long_term()
        if key not in memory:
            memory[key] = []
        if isinstance(memory[key], list):
            memory[key].append({"value": value, "ts": time.time()})
            memory[key] = memory[key][-100:]  # Keep last 100 entries per key
        else:
            memory[key] = value
        await self.save_long_term(memory)

    def _default_memory(self) -> dict:
        return {
            "brand_voice": "Professional, consultative, results-focused. Northramp tone.",
            "personas": [],
            "lessons": [],
            "decisions": [],
            "icp": {  # Ideal Customer Profile
                "company_size": "50-500 employees",
                "industries": ["healthcare", "federal", "fintech"],
                "roles": ["CTO", "VP Engineering", "Director IT"],
                "pain_points": ["cloud migration", "AI adoption", "compliance"],
            },
            "last_updated": None,
        }

    # ─── TASK QUEUE ────────────────────────────────────────────────────────────

    async def enqueue_task(self, task: dict, priority: float = 1.0):
        """Add task to priority queue. Lower score = higher priority."""
        score = priority * time.time()
        await self.redis.zadd(
            "agent:tasks:pending",
            {json.dumps(task): score}
        )

    async def dequeue_tasks(self, limit: int = 10) -> list[dict]:
        """Pull highest-priority pending tasks."""
        raw = await self.redis.zrange("agent:tasks:pending", 0, limit - 1)
        return [json.loads(t) for t in raw]

    async def complete_task(self, task: dict, result: str):
        """Mark task as complete, move to completed list."""
        task_str = json.dumps(task)
        await self.redis.zrem("agent:tasks:pending", task_str)
        entry = json.dumps({"task": task, "result": result, "completed_at": time.time()})
        await self.redis.lpush("agent:tasks:completed", entry)
        await self.redis.ltrim("agent:tasks:completed", 0, 499)  # Keep last 500

    async def fail_task(self, task: dict, error: str):
        """Mark task as failed for review."""
        task_str = json.dumps(task)
        await self.redis.zrem("agent:tasks:pending", task_str)
        entry = json.dumps({"task": task, "error": error, "failed_at": time.time()})
        await self.redis.lpush("agent:tasks:failed", entry)
        await self.redis.ltrim("agent:tasks:failed", 0, 99)

    # ─── CAMPAIGN STATE ────────────────────────────────────────────────────────

    async def get_active_campaigns(self) -> list[str]:
        return list(await self.redis.smembers("agent:campaigns:active"))

    async def load_campaign(self, campaign_id: str) -> dict:
        state = await self.redis.hgetall(f"agent:campaign:{campaign_id}:state")
        return state

    async def save_campaign(self, campaign_id: str, state: dict):
        await self.redis.hset(f"agent:campaign:{campaign_id}:state", mapping=state)
        await self.redis.sadd("agent:campaigns:active", campaign_id)

    async def log_campaign_action(self, campaign_id: str, action: str):
        entry = json.dumps({"action": action, "ts": time.time()})
        await self.redis.lpush(f"agent:campaign:{campaign_id}:history", entry)
        await self.redis.ltrim(f"agent:campaign:{campaign_id}:history", 0, 199)

    async def complete_campaign(self, campaign_id: str):
        await self.redis.hset(f"agent:campaign:{campaign_id}:state", "status", "completed")
        await self.redis.srem("agent:campaigns:active", campaign_id)

    # ─── LEAD MEMORY ───────────────────────────────────────────────────────────

    async def load_lead(self, lead_id: str) -> dict:
        profile = await self.redis.hgetall(f"agent:lead:{lead_id}:profile")
        history_raw = await self.redis.lrange(f"agent:lead:{lead_id}:history", 0, 49)
        history = [json.loads(h) for h in history_raw]
        return {"profile": profile, "history": history}

    async def save_lead(self, lead_id: str, profile: dict):
        await self.redis.hset(f"agent:lead:{lead_id}:profile", mapping=profile)

    async def log_lead_interaction(self, lead_id: str, action: str, notes: str = ""):
        entry = json.dumps({"action": action, "notes": notes, "ts": time.time()})
        await self.redis.lpush(f"agent:lead:{lead_id}:history", entry)
        await self.redis.ltrim(f"agent:lead:{lead_id}:history", 0, 99)

    async def score_lead(self, lead_id: str, score: float):
        await self.redis.zadd("agent:leads:hot", {lead_id: score})

    async def get_hot_leads(self, limit: int = 20) -> list[str]:
        return list(await self.redis.zrevrange("agent:leads:hot", 0, limit - 1))

    # ─── BOOT SEQUENCE ─────────────────────────────────────────────────────────

    async def boot_context(self) -> dict:
        """
        Full memory reconstruction on cold start.
        Returns everything the agent needs to resume where it left off.
        Target: <400ms
        """
        memory, tasks, campaign_ids, hot_leads = await asyncio.gather(
            self.load_long_term(),
            self.dequeue_tasks(limit=20),
            self.get_active_campaigns(),
            self.get_hot_leads(limit=10),
        )

        # Load campaign states in parallel
        campaign_states = {}
        if campaign_ids:
            states = await asyncio.gather(
                *[self.load_campaign(cid) for cid in campaign_ids]
            )
            campaign_states = dict(zip(campaign_ids, states))

        return {
            "memory": memory,
            "pending_tasks": tasks,
            "active_campaigns": campaign_states,
            "hot_leads": hot_leads,
            "boot_ts": time.time(),
        }

    async def close(self):
        await self.redis.aclose()
