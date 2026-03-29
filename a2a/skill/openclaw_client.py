"""
openclaw_client.py — Thin async HTTP client for the OpenClaw gateway.

Sends approved, sanitized action requests to the OpenClaw gateway and returns
the response text. Handles auth headers and basic error surfacing.

Environment variables:
    OPENCLAW_GATEWAY_URL    Gateway base URL (default: http://localhost:3000)
    OPENCLAW_GATEWAY_TOKEN  Bearer token if gateway requires auth (optional)
"""

import logging
import os
from typing import Any

import aiohttp

logger = logging.getLogger(__name__)

_DEFAULT_GATEWAY_URL = "http://localhost:3000"
_TIMEOUT_SECONDS = 120


class OpenClawClient:
    """
    Async HTTP client for the OpenClaw gateway.

    Args:
        gateway_url: Base URL of the OpenClaw gateway.
        gateway_token: Optional bearer token for authenticated gateways.
    """

    def __init__(
        self,
        gateway_url: str = _DEFAULT_GATEWAY_URL,
        gateway_token: str = "",
    ) -> None:
        self._gateway_url = gateway_url.rstrip("/")
        self._gateway_token = gateway_token

    def _headers(self) -> dict[str, str]:
        """Build request headers, including auth if token is set."""
        headers = {"Content-Type": "application/json"}
        if self._gateway_token:
            headers["Authorization"] = f"Bearer {self._gateway_token}"
        return headers

    async def send_message(
        self,
        message: str,
        session: str = "main",
        timeout: float = _TIMEOUT_SECONDS,
    ) -> str:
        """
        Send a message to OpenClaw and return the agent's response text.

        This posts to the gateway's message endpoint (OpenClaw REST API).
        The message is treated as a user turn in the specified session.

        Args:
            message: The text to send as a user message.
            session: OpenClaw session name (default: "main").
            timeout: Request timeout in seconds.

        Returns:
            Response text from the agent.

        Raises:
            RuntimeError: On HTTP errors or network failures.
        """
        url = f"{self._gateway_url}/api/sessions/{session}/messages"
        payload = {"message": message}

        logger.debug("OpenClawClient.send_message → %s | session=%s", url, session)

        try:
            async with aiohttp.ClientSession(
                timeout=aiohttp.ClientTimeout(total=timeout)
            ) as http:
                async with http.post(
                    url,
                    json=payload,
                    headers=self._headers(),
                ) as resp:
                    if resp.status >= 400:
                        body = await resp.text()
                        raise RuntimeError(
                            f"OpenClaw gateway returned HTTP {resp.status}: {body[:200]}"
                        )
                    data: dict[str, Any] = await resp.json()
                    # Gateway returns {"reply": "...", "text": "..."} or similar
                    return (
                        data.get("reply")
                        or data.get("text")
                        or data.get("message")
                        or str(data)
                    )
        except aiohttp.ClientConnectionError as exc:
            raise RuntimeError(
                f"Cannot reach OpenClaw gateway at {self._gateway_url}: {exc}"
            ) from exc
        except aiohttp.ClientTimeoutError as exc:
            raise RuntimeError(
                f"OpenClaw gateway timed out after {timeout}s: {exc}"
            ) from exc

    async def health(self) -> bool:
        """
        Check if the OpenClaw gateway is reachable.

        Returns:
            True if the gateway responds to a health check, False otherwise.
        """
        url = f"{self._gateway_url}/health"
        try:
            async with aiohttp.ClientSession(
                timeout=aiohttp.ClientTimeout(total=5)
            ) as http:
                async with http.get(url, headers=self._headers()) as resp:
                    ok = resp.status < 400
                    logger.debug("OpenClaw health check → %s (%s)", url, resp.status)
                    return ok
        except Exception:  # noqa: BLE001
            logger.debug("OpenClaw health check failed for %s", url)
            return False

    @classmethod
    def from_env(cls) -> "OpenClawClient":
        """
        Build an OpenClawClient from environment variables.

        Reads:
            OPENCLAW_GATEWAY_URL   (default: http://localhost:3000)
            OPENCLAW_GATEWAY_TOKEN (default: empty = no auth)

        Returns:
            Configured OpenClawClient.
        """
        url = os.environ.get("OPENCLAW_GATEWAY_URL", _DEFAULT_GATEWAY_URL)
        token = os.environ.get("OPENCLAW_GATEWAY_TOKEN", "")
        logger.info("OpenClawClient: gateway=%s auth=%s", url, "yes" if token else "no")
        return cls(gateway_url=url, gateway_token=token)
