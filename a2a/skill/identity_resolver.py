"""
identity_resolver.py — Resolves Slack user IDs to internal identities with roles.

Loading priority:
    1. SLACK_ROLE_MAP env var (JSON string) — highest priority, useful for secrets
    2. identity_map.yaml in this directory — human-friendly, commit-safe config
    3. Default role ("readonly") — fail-safe fallback
"""

import json
import logging
import os
from dataclasses import dataclass, field
from pathlib import Path

import yaml

logger = logging.getLogger(__name__)

_IDENTITY_MAP_PATH = Path(__file__).with_name("identity_map.yaml")


@dataclass
class Identity:
    """Resolved identity for a Slack user."""

    slack_user_id: str
    role: str  # admin | operator | readonly
    display_name: str = ""

    def __str__(self) -> str:
        return f"Identity(user={self.slack_user_id!r}, role={self.role!r})"


class IdentityResolver:
    """
    Resolves a Slack user_id to an Identity (with role).

    Args:
        role_map: dict mapping Slack user IDs to role names.
        default_role: Role assigned to any user not in role_map.
    """

    DEFAULT_ROLE = "readonly"

    def __init__(
        self,
        role_map: dict[str, str],
        default_role: str = DEFAULT_ROLE,
    ) -> None:
        self._role_map = role_map
        self._default_role = default_role

    async def resolve(self, slack_user_id: str) -> Identity:
        """
        Resolve a Slack user_id to an Identity.

        Unknown users receive the default_role (fail-safe).

        Args:
            slack_user_id: The Slack member ID (e.g. "U01ABC123").

        Returns:
            Identity with role set.
        """
        if not slack_user_id:
            logger.warning("resolve() called with empty slack_user_id — returning default role")
            return Identity(slack_user_id="", role=self._default_role)

        role = self._role_map.get(slack_user_id, self._default_role)
        logger.debug("Resolved %s → role=%s", slack_user_id, role)
        return Identity(slack_user_id=slack_user_id, role=role)

    @classmethod
    def from_env(cls, default_role: str = DEFAULT_ROLE) -> "IdentityResolver":
        """
        Build an IdentityResolver from environment or YAML config.

        Priority:
            1. SLACK_ROLE_MAP env var (JSON: {"U123": "admin", ...})
            2. identity_map.yaml in the skill directory
            3. Empty map (everyone gets default_role)

        Returns:
            Configured IdentityResolver instance.
        """
        # 1. Try env var first
        env_map_raw = os.environ.get("SLACK_ROLE_MAP", "").strip()
        if env_map_raw:
            try:
                env_map: dict[str, str] = json.loads(env_map_raw)
                logger.info(
                    "IdentityResolver: loaded %d entries from SLACK_ROLE_MAP env var",
                    len(env_map),
                )
                return cls(role_map=env_map, default_role=default_role)
            except json.JSONDecodeError as exc:
                logger.error("SLACK_ROLE_MAP is not valid JSON: %s", exc)

        # 2. Fall back to identity_map.yaml
        if _IDENTITY_MAP_PATH.exists():
            try:
                raw = yaml.safe_load(_IDENTITY_MAP_PATH.read_text(encoding="utf-8"))
                yaml_map: dict[str, str] = raw.get("identity_map", {})
                # "default" key is special — use it as default_role override
                resolved_default = yaml_map.pop("default", default_role)
                logger.info(
                    "IdentityResolver: loaded %d entries from %s (default_role=%s)",
                    len(yaml_map),
                    _IDENTITY_MAP_PATH.name,
                    resolved_default,
                )
                return cls(role_map=yaml_map, default_role=resolved_default)
            except Exception as exc:  # noqa: BLE001
                logger.error("Failed to parse %s: %s", _IDENTITY_MAP_PATH, exc)

        # 3. Empty map — everyone gets default_role
        logger.warning(
            "IdentityResolver: no role map found — all users get role=%s", default_role
        )
        return cls(role_map={}, default_role=default_role)
