"""
skill_router.py — The core middleware that wires identity, policy, rate limiting,
and OpenClaw together.

Users never call OpenClaw skills directly. They request ACTIONS through Slack.
SkillRouter is the single enforcement point:

    1. Resolve Slack user → Identity (with role)
    2. Check rate limit for that user/role
    3. Check policy: is this action allowed with these params?
    4. If denied at any step: return a human-readable denial message
    5. If allowed: forward sanitized params to OpenClaw, return response
"""

import logging
from dataclasses import dataclass, field
from typing import Any

from .identity_resolver import Identity, IdentityResolver
from .openclaw_client import OpenClawClient
from .policy_engine import PolicyEngine
from .rate_limiter import RateLimiter

logger = logging.getLogger(__name__)


@dataclass
class SkillResponse:
    """Response from the SkillRouter after dispatching an action."""

    allowed: bool
    response: str
    role: str
    reason: str = ""
    action: str = ""
    slack_user_id: str = ""


class SkillRouter:
    """
    Routes Slack action requests through the authorization pipeline to OpenClaw.

    Args:
        identity_resolver: Resolves Slack user IDs to roles.
        policy_engine: Checks action + param permissions per role.
        rate_limiter: Enforces per-user rate limits.
        openclaw_client: Sends approved requests to OpenClaw gateway.
        roles_config: Raw roles dict (from roles.yaml) for rate limiter lookups.
    """

    def __init__(
        self,
        identity_resolver: IdentityResolver,
        policy_engine: PolicyEngine,
        rate_limiter: RateLimiter,
        openclaw_client: OpenClawClient,
        roles_config: dict[str, Any],
    ) -> None:
        self._resolver = identity_resolver
        self._policy = policy_engine
        self._limiter = rate_limiter
        self._openclaw = openclaw_client
        self._roles_config = roles_config

    async def dispatch(
        self,
        slack_user_id: str,
        action: str,
        params: dict[str, Any],
    ) -> SkillResponse:
        """
        Dispatch an action request from a Slack user through the full authz pipeline.

        Steps:
            1. Resolve identity (Slack user → role)
            2. Check rate limit
            3. Check policy (allowed action + sanitize params)
            4. Forward to OpenClaw if approved
            5. Return SkillResponse (allowed/denied + message)

        Args:
            slack_user_id: The Slack member ID of the requesting user.
            action: The action name being requested (e.g. "search_web").
            params: Raw parameters from the Slack request body.

        Returns:
            SkillResponse with allowed status, human-readable response, and metadata.
        """
        logger.info(
            "dispatch: user=%s action=%s params_keys=%s",
            slack_user_id,
            action,
            list(params.keys()),
        )

        # ── Step 1: Resolve identity ─────────────────────────────────────────
        try:
            identity: Identity = await self._resolver.resolve(slack_user_id)
        except Exception as exc:  # noqa: BLE001
            logger.error("Identity resolution failed for %s: %s", slack_user_id, exc)
            return SkillResponse(
                allowed=False,
                response="⛔ Unable to verify your identity. Please contact an admin.",
                role="unknown",
                reason=str(exc),
                action=action,
                slack_user_id=slack_user_id,
            )

        # ── Step 2: Rate limit check ─────────────────────────────────────────
        if not self._limiter.check(slack_user_id, identity.role, self._roles_config):
            role_cfg = self._roles_config.get(identity.role, {})
            limit = role_cfg.get("rate_limit", 10)
            logger.warning(
                "Rate limit hit: user=%s role=%s action=%s", slack_user_id, identity.role, action
            )
            return SkillResponse(
                allowed=False,
                response=(
                    f"⏱️ Slow down — you've hit the rate limit for your role "
                    f"(*{identity.role}*: {limit} requests/min). Try again in a moment."
                ),
                role=identity.role,
                reason="Rate limit exceeded",
                action=action,
                slack_user_id=slack_user_id,
            )

        # ── Step 3: Policy check ─────────────────────────────────────────────
        policy_result = self._policy.check(identity, action, params)

        if not policy_result.allowed:
            logger.info(
                "Policy denied: user=%s role=%s action=%s reason=%s",
                slack_user_id,
                identity.role,
                action,
                policy_result.reason,
            )
            return SkillResponse(
                allowed=False,
                response=f"🚫 {policy_result.reason}",
                role=identity.role,
                reason=policy_result.reason,
                action=action,
                slack_user_id=slack_user_id,
            )

        # ── Step 4: Record request + forward to OpenClaw ─────────────────────
        self._limiter.record(slack_user_id)

        # Build the message to send to OpenClaw
        # Converts action + sanitized params to a natural language instruction
        openclaw_message = self._build_openclaw_message(action, policy_result.sanitized_params)

        try:
            openclaw_response = await self._openclaw.send_message(openclaw_message)
        except RuntimeError as exc:
            logger.error(
                "OpenClaw call failed: user=%s action=%s error=%s",
                slack_user_id,
                action,
                exc,
            )
            return SkillResponse(
                allowed=True,  # policy allowed, but execution failed
                response=f"⚠️ Action was approved but OpenClaw returned an error: {exc}",
                role=identity.role,
                reason="OpenClaw execution error",
                action=action,
                slack_user_id=slack_user_id,
            )

        logger.info(
            "dispatch complete: user=%s role=%s action=%s response_len=%d",
            slack_user_id,
            identity.role,
            action,
            len(openclaw_response),
        )
        return SkillResponse(
            allowed=True,
            response=openclaw_response,
            role=identity.role,
            reason=policy_result.reason,
            action=action,
            slack_user_id=slack_user_id,
        )

    def _build_openclaw_message(
        self,
        action: str,
        params: dict[str, Any],
    ) -> str:
        """
        Convert a structured action + sanitized params into a natural language
        message for the OpenClaw agent.

        Custom action → message mappings can be added here to give OpenClaw
        better context for each action type.

        Args:
            action: Action name (e.g. "search_web", "run_code").
            params: Sanitized parameters from the policy layer.

        Returns:
            A string message to send to the OpenClaw gateway.
        """
        # Action-specific templates for better OpenClaw context
        templates: dict[str, str] = {
            "search_web": "Search the web for: {query}",
            "read_file": "Read the file at path: {path}",
            "write_file": "Write to file at path: {path}\n\nContent:\n{content}",
            "run_code": "Run the following {language} code:\n```{language}\n{code}\n```",
            "run_analysis": "Run analysis: {description}",
            "get_status": "What is the current status of the agent and workspace?",
            "send_message": "Send this message to {target}: {content}",
            "fetch_url": "Fetch and summarize the content at this URL: {url}",
        }

        template = templates.get(action)
        if template:
            try:
                return template.format(**params)
            except KeyError:
                pass  # Fall through to generic format

        # Generic fallback: action name + params as key=value
        if params:
            param_str = "\n".join(f"  {k}: {v}" for k, v in params.items())
            return f"Action: {action}\nParameters:\n{param_str}"
        return f"Action: {action}"
