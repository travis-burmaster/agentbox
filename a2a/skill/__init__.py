"""
a2a.skill — Slack Authorization Layer for OpenClaw

Provides identity resolution, policy enforcement, rate limiting, and skill routing
between Slack and the OpenClaw runtime. Users request actions; this layer decides
what they can touch and with what parameters.

Flow:
    Slack user → identity_resolver → policy_engine → rate_limiter → skill_router → OpenClaw
"""

from .identity_resolver import Identity, IdentityResolver
from .policy_engine import PolicyEngine, PolicyResult
from .rate_limiter import RateLimiter
from .openclaw_client import OpenClawClient
from .skill_router import SkillRouter, SkillResponse
from .middleware import get_skill_router

__all__ = [
    "Identity",
    "IdentityResolver",
    "PolicyEngine",
    "PolicyResult",
    "RateLimiter",
    "OpenClawClient",
    "SkillRouter",
    "SkillResponse",
    "get_skill_router",
]
