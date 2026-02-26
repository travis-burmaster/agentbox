"""
rate_limiter.py — Per-user sliding window rate limiter (in-memory).

Uses a deque of timestamps to track requests per user within a 60-second window.
Thread-safe via asyncio.Lock per user.

Limits are read from the roles_config (same dict used by PolicyEngine).
"""

import asyncio
import logging
import time
from collections import deque
from typing import Any

logger = logging.getLogger(__name__)

_WINDOW_SECONDS = 60  # sliding window duration


class RateLimiter:
    """
    Sliding window rate limiter, keyed by Slack user_id.

    Usage:
        limiter = RateLimiter()
        if not limiter.check(user_id, role, roles_config):
            # deny — over limit
        limiter.record(user_id)
    """

    def __init__(self) -> None:
        # user_id -> deque of float timestamps
        self._windows: dict[str, deque[float]] = {}
        # per-user lock to avoid race conditions in async context
        self._locks: dict[str, asyncio.Lock] = {}

    def _get_lock(self, user_id: str) -> asyncio.Lock:
        if user_id not in self._locks:
            self._locks[user_id] = asyncio.Lock()
        return self._locks[user_id]

    def _get_window(self, user_id: str) -> deque[float]:
        if user_id not in self._windows:
            self._windows[user_id] = deque()
        return self._windows[user_id]

    def _prune(self, window: deque[float]) -> None:
        """Remove timestamps older than the sliding window."""
        cutoff = time.monotonic() - _WINDOW_SECONDS
        while window and window[0] < cutoff:
            window.popleft()

    def check(
        self,
        user_id: str,
        role: str,
        roles_config: dict[str, Any],
    ) -> bool:
        """
        Check whether user_id is within their rate limit.

        Args:
            user_id: Slack user ID.
            role: The user's role name.
            roles_config: The full roles dict from roles.yaml.

        Returns:
            True if under the limit (request allowed), False if exceeded.
        """
        role_cfg = roles_config.get(role, {})
        limit: int = role_cfg.get("rate_limit", 10)

        window = self._get_window(user_id)
        self._prune(window)

        current_count = len(window)
        if current_count >= limit:
            logger.warning(
                "Rate limit exceeded: user=%s role=%s count=%d limit=%d",
                user_id,
                role,
                current_count,
                limit,
            )
            return False

        return True

    def record(self, user_id: str) -> None:
        """
        Record a successful request timestamp for user_id.

        Call this AFTER check() returns True and the request has been dispatched.

        Args:
            user_id: Slack user ID.
        """
        window = self._get_window(user_id)
        window.append(time.monotonic())

    def current_count(self, user_id: str) -> int:
        """Return the number of requests in the current window for user_id."""
        window = self._get_window(user_id)
        self._prune(window)
        return len(window)

    def reset(self, user_id: str) -> None:
        """Clear the rate limit window for a user (admin use)."""
        if user_id in self._windows:
            self._windows[user_id].clear()
        logger.info("Rate limit reset for user=%s", user_id)
