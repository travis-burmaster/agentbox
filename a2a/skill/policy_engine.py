"""
policy_engine.py — Policy enforcement layer.

Given an Identity and a requested action + params, decides:
    - Is this action allowed for this role?
    - Are the parameters within role constraints?
    - Returns a sanitized copy of params (stripping/clamping violations).

Design principle: deny by default. Unknown roles and unknown actions are denied.
"""

import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

import yaml

logger = logging.getLogger(__name__)

_ROLES_PATH = Path(__file__).with_name("roles.yaml")


@dataclass
class PolicyResult:
    """Result of a policy check."""

    allowed: bool
    reason: str
    sanitized_params: dict[str, Any] = field(default_factory=dict)
    role: str = ""


class PolicyEngine:
    """
    Checks whether an identity may perform an action with given params.

    Args:
        roles_config: Parsed content of roles.yaml (the "roles" dict).
    """

    def __init__(self, roles_config: dict[str, Any]) -> None:
        self._roles = roles_config

    def check(
        self,
        identity: Any,  # Identity dataclass
        action: str,
        params: dict[str, Any],
    ) -> PolicyResult:
        """
        Evaluate whether identity may perform action with params.

        Args:
            identity: Resolved Identity (slack_user_id, role).
            action: Action name requested (e.g. "search_web", "run_code").
            params: Raw parameters from the Slack request.

        Returns:
            PolicyResult with allowed, reason, sanitized_params, and role.
        """
        role_name = identity.role
        role_cfg = self._roles.get(role_name)

        if role_cfg is None:
            logger.warning(
                "Unknown role %r for user %s — denying", role_name, identity.slack_user_id
            )
            return PolicyResult(
                allowed=False,
                reason=f"Unknown role '{role_name}'. Contact an admin.",
                role=role_name,
            )

        # 1. Check explicit denials first (overrides allowed_actions)
        denied: list[str] = role_cfg.get("denied_actions", [])
        if action in denied:
            logger.info(
                "DENIED (explicit deny): user=%s role=%s action=%s",
                identity.slack_user_id,
                role_name,
                action,
            )
            return PolicyResult(
                allowed=False,
                reason=f"Action '{action}' is explicitly denied for role '{role_name}'.",
                role=role_name,
            )

        # 2. Check allowed_actions
        allowed_actions: list[str] = role_cfg.get("allowed_actions", [])
        if "*" not in allowed_actions and action not in allowed_actions:
            logger.info(
                "DENIED (not in allowed_actions): user=%s role=%s action=%s",
                identity.slack_user_id,
                role_name,
                action,
            )
            return PolicyResult(
                allowed=False,
                reason=(
                    f"Action '{action}' is not permitted for role '{role_name}'. "
                    f"Allowed actions: {', '.join(allowed_actions) or 'none'}."
                ),
                role=role_name,
            )

        # 3. Apply parameter constraints — returns sanitized params
        constraints: dict[str, Any] = role_cfg.get("parameter_constraints", {})
        try:
            sanitized = self._apply_parameter_constraints(constraints, action, params)
        except ValueError as exc:
            return PolicyResult(
                allowed=False,
                reason=str(exc),
                role=role_name,
            )

        logger.info(
            "ALLOWED: user=%s role=%s action=%s", identity.slack_user_id, role_name, action
        )
        return PolicyResult(
            allowed=True,
            reason=f"Action '{action}' permitted for role '{role_name}'.",
            sanitized_params=sanitized,
            role=role_name,
        )

    def _apply_parameter_constraints(
        self,
        constraints: dict[str, Any],
        action: str,
        params: dict[str, Any],
    ) -> dict[str, Any]:
        """
        Apply per-action parameter constraints to params.

        Modifies a copy of params — strips blocked values, clamps numeric limits.
        Raises ValueError if a hard constraint is violated.

        Args:
            constraints: The parameter_constraints dict for this role.
            action: Action name.
            params: Raw params from the request.

        Returns:
            Sanitized copy of params.
        """
        import copy
        sanitized = copy.deepcopy(params)
        action_constraints = constraints.get(action, {})

        if not action_constraints:
            return sanitized

        # max_timeout_seconds — clamp if exceeded
        if "max_timeout_seconds" in action_constraints:
            max_t = action_constraints["max_timeout_seconds"]
            if "timeout_seconds" in sanitized and sanitized["timeout_seconds"] > max_t:
                logger.debug(
                    "Clamping timeout_seconds from %s to %s for action=%s",
                    sanitized["timeout_seconds"],
                    max_t,
                    action,
                )
                sanitized["timeout_seconds"] = max_t

        # allowed_languages — enforce whitelist
        if "allowed_languages" in action_constraints:
            lang = sanitized.get("language", "")
            if lang and lang not in action_constraints["allowed_languages"]:
                raise ValueError(
                    f"Language '{lang}' is not permitted. "
                    f"Allowed: {', '.join(action_constraints['allowed_languages'])}."
                )

        # max_size_bytes — check content size
        if "max_size_bytes" in action_constraints:
            content = sanitized.get("content", "")
            if isinstance(content, str) and len(content.encode()) > action_constraints["max_size_bytes"]:
                raise ValueError(
                    f"Content exceeds maximum size of "
                    f"{action_constraints['max_size_bytes']} bytes for action '{action}'."
                )

        # blocked_paths — prevent reading sensitive paths
        if "blocked_paths" in action_constraints:
            path = sanitized.get("path", "")
            for blocked in action_constraints["blocked_paths"]:
                if blocked in str(path):
                    raise ValueError(
                        f"Access to path '{path}' is not permitted for your role."
                    )

        # blocked_patterns — prevent SSRF / internal network access
        if "blocked_patterns" in action_constraints:
            url = sanitized.get("url", "")
            for pattern in action_constraints["blocked_patterns"]:
                if pattern in str(url):
                    raise ValueError(
                        f"URL '{url}' contains a blocked pattern '{pattern}'."
                    )

        return sanitized

    @classmethod
    def from_yaml(cls, path: Path = _ROLES_PATH) -> "PolicyEngine":
        """
        Load a PolicyEngine from roles.yaml.

        Args:
            path: Path to the roles YAML file.

        Returns:
            Configured PolicyEngine.

        Raises:
            FileNotFoundError: If the roles file doesn't exist.
            ValueError: If the YAML is malformed.
        """
        if not path.exists():
            raise FileNotFoundError(f"Roles config not found: {path}")
        raw = yaml.safe_load(path.read_text(encoding="utf-8"))
        roles = raw.get("roles", {})
        if not roles:
            raise ValueError(f"No roles defined in {path}")
        logger.info("PolicyEngine: loaded %d roles from %s", len(roles), path.name)
        return cls(roles_config=roles)
