"""
middleware.py — FastAPI dependency injection for the Slack authorization layer.

Provides a singleton SkillRouter built from environment variables and YAML config.
Use get_skill_router() as a FastAPI dependency in route handlers.

Example:
    from a2a.skill.middleware import get_skill_router

    @app.post("/slack/action")
    async def slack_action(request: Request):
        body = await request.json()
        router = get_skill_router()
        result = await router.dispatch(
            slack_user_id=body.get("slack_user_id", ""),
            action=body.get("action", ""),
            params=body.get("params", {}),
        )
        return {"allowed": result.allowed, "response": result.response, "role": result.role}
"""

import logging
from pathlib import Path
from typing import Optional

from .identity_resolver import IdentityResolver
from .openclaw_client import OpenClawClient
from .policy_engine import PolicyEngine
from .rate_limiter import RateLimiter
from .skill_router import SkillRouter

import yaml

logger = logging.getLogger(__name__)

_ROLES_PATH = Path(__file__).with_name("roles.yaml")

# Module-level singleton — built once, reused across requests
_router_instance: Optional[SkillRouter] = None


def get_skill_router() -> SkillRouter:
    """
    Build (or return cached) SkillRouter from environment + YAML config.

    This function is safe to call on every request — it returns a cached instance
    after the first call, so there's no repeated I/O overhead.

    Configuration sources (in priority order):
        - SLACK_ROLE_MAP env var: JSON string mapping Slack user IDs to roles
        - identity_map.yaml: YAML file in the skill directory
        - roles.yaml: Role definitions and parameter constraints
        - OPENCLAW_GATEWAY_URL: Base URL for the OpenClaw gateway
        - OPENCLAW_GATEWAY_TOKEN: Bearer token for authenticated gateways

    Returns:
        Configured SkillRouter singleton.
    """
    global _router_instance

    if _router_instance is not None:
        return _router_instance

    logger.info("Building SkillRouter from config...")

    # Load roles config (shared between PolicyEngine and RateLimiter)
    raw = yaml.safe_load(_ROLES_PATH.read_text(encoding="utf-8"))
    roles_config: dict = raw.get("roles", {})

    identity_resolver = IdentityResolver.from_env()
    policy_engine = PolicyEngine(roles_config=roles_config)
    rate_limiter = RateLimiter()
    openclaw_client = OpenClawClient.from_env()

    _router_instance = SkillRouter(
        identity_resolver=identity_resolver,
        policy_engine=policy_engine,
        rate_limiter=rate_limiter,
        openclaw_client=openclaw_client,
        roles_config=roles_config,
    )

    logger.info("SkillRouter ready.")
    return _router_instance


def reset_skill_router() -> None:
    """
    Reset the cached SkillRouter instance.

    Call this in tests or after config changes to force a rebuild on the next
    call to get_skill_router().
    """
    global _router_instance
    _router_instance = None
    logger.info("SkillRouter cache cleared.")
