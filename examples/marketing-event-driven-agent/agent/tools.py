"""
Tool Implementations — AgentBox Marketing

Wire up your real integrations here.
Each function maps 1:1 to a FunctionDeclaration in marketing_agent.py.
"""

import os
import smtplib
import httpx
import logging
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart

log = logging.getLogger(__name__)


async def send_email(to: str, subject: str, body: str, lead_id: str = "") -> dict:
    """Send email via SMTP2GO."""
    try:
        msg = MIMEMultipart("alternative")
        msg["Subject"] = subject
        msg["From"] = "bot@yourdomain.com"
        msg["To"] = to
        msg.attach(MIMEText(body, "html" if "<" in body else "plain"))

        with smtplib.SMTP("smtp.smtp2go.com", 587) as s:
            s.starttls()
            s.login("your.smtp.user", os.environ.get("SMTP2GO_PASS", ""))
            s.send_message(msg)

        log.info(f"Email sent to {to}: {subject}")
        return {"sent": True, "to": to, "subject": subject}
    except Exception as e:
        log.error(f"Email failed: {e}")
        return {"sent": False, "error": str(e)}


async def search_web(query: str) -> dict:
    """Search the web using Brave Search API."""
    api_key = os.environ.get("BRAVE_API_KEY", "")
    if not api_key:
        return {"results": [], "note": "BRAVE_API_KEY not set"}

    async with httpx.AsyncClient() as client:
        resp = await client.get(
            "https://api.search.brave.com/res/v1/web/search",
            params={"q": query, "count": 5},
            headers={"X-Subscription-Token": api_key},
            timeout=10,
        )
        data = resp.json()

    results = [
        {"title": r.get("title"), "url": r.get("url"), "snippet": r.get("description")}
        for r in data.get("web", {}).get("results", [])[:5]
    ]
    return {"query": query, "results": results}


async def update_crm(lead_id: str, updates: dict, note: str = "") -> dict:
    """Update a contact in HubSpot CRM."""
    api_key = os.environ.get("HUBSPOT_API_KEY", "")
    if not api_key:
        log.warning("HUBSPOT_API_KEY not set — CRM update skipped")
        return {"updated": False, "note": "HUBSPOT_API_KEY not set"}

    async with httpx.AsyncClient() as client:
        # Update contact properties
        resp = await client.patch(
            f"https://api.hubapi.com/crm/v3/objects/contacts/{lead_id}",
            json={"properties": updates},
            headers={"Authorization": f"Bearer {api_key}"},
            timeout=10,
        )

        if note:
            # Add engagement note
            await client.post(
                "https://api.hubapi.com/crm/v3/objects/notes",
                json={
                    "properties": {
                        "hs_note_body": note,
                        "hs_timestamp": str(int(__import__("time").time() * 1000)),
                    },
                    "associations": [
                        {"to": {"id": lead_id}, "types": [{"associationTypeId": 202}]}
                    ],
                },
                headers={"Authorization": f"Bearer {api_key}"},
                timeout=10,
            )

    return {"updated": resp.status_code == 200, "lead_id": lead_id}


async def publish_content(
    platform: str, body: str, title: str = "", schedule_at: str = "now"
) -> dict:
    """
    Publish content to LinkedIn, blog, or newsletter.
    Implement your platform-specific logic here.
    """
    log.info(f"Publishing to {platform}: {title or body[:60]}...")

    if platform == "linkedin":
        # LinkedIn API — UGC Posts endpoint
        token = os.environ.get("LINKEDIN_ACCESS_TOKEN", "")
        if not token:
            return {"published": False, "note": "LINKEDIN_ACCESS_TOKEN not set"}

        async with httpx.AsyncClient() as client:
            resp = await client.post(
                "https://api.linkedin.com/v2/ugcPosts",
                json={
                    "author": f"urn:li:organization:{os.environ.get('LINKEDIN_ORG_ID')}",
                    "lifecycleState": "PUBLISHED" if schedule_at == "now" else "DRAFT",
                    "specificContent": {
                        "com.linkedin.ugc.ShareContent": {
                            "shareCommentary": {"text": body},
                            "shareMediaCategory": "NONE",
                        }
                    },
                    "visibility": {"com.linkedin.ugc.MemberNetworkVisibility": "PUBLIC"},
                },
                headers={"Authorization": f"Bearer {token}"},
                timeout=10,
            )
        return {"published": resp.status_code in [200, 201], "platform": "linkedin"}

    elif platform == "newsletter":
        # Send newsletter via email broadcast
        return await send_email(
            to=os.environ.get("NEWSLETTER_LIST", ""),
            subject=title or "Newsletter",
            body=body,
        )

    return {"published": False, "note": f"Platform {platform} not configured"}


async def query_bigquery(metric: str, date_range: str = "7d", filters: dict = {}) -> dict:
    """Query BigQuery for marketing analytics."""
    from google.cloud import bigquery

    project = os.environ.get("GCP_PROJECT", "")
    if not project:
        return {"error": "GCP_PROJECT not set"}

    client = bigquery.Client(project=project)
    dataset = "agentbox_marketing"

    queries = {
        "open_rate": f"""
            SELECT AVG(opened) as open_rate, COUNT(*) as total_sent
            FROM `{project}.{dataset}.email_events`
            WHERE sent_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
        """,
        "reply_rate": f"""
            SELECT AVG(replied) as reply_rate, COUNT(*) as total_sent
            FROM `{project}.{dataset}.email_events`
            WHERE sent_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
        """,
        "meetings_booked": f"""
            SELECT COUNT(*) as meetings
            FROM `{project}.{dataset}.meetings`
            WHERE booked_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
        """,
        "new_leads": f"""
            SELECT COUNT(*) as new_leads, source
            FROM `{project}.{dataset}.leads`
            WHERE created_at >= TIMESTAMP_SUB(CURRENT_TIMESTAMP(), INTERVAL 1 DAY)
            GROUP BY source
        """,
    }

    sql = queries.get(metric, f"SELECT '{metric} not found' as error")

    try:
        results = client.query(sql).result()
        rows = [dict(row) for row in results]
        return {"metric": metric, "data": rows}
    except Exception as e:
        return {"metric": metric, "error": str(e)}


async def score_lead_with_ml(lead_data: dict) -> float:
    """
    Score a lead using Vertex AI or simple rule-based scoring.
    Returns 0-100 score.
    """
    score = 50.0  # Baseline

    # Company size signals (from research)
    company = lead_data.get("company", "").lower()
    title = lead_data.get("title", "").lower()
    message = lead_data.get("message", "").lower()

    # Title scoring
    if any(t in title for t in ["cto", "cio", "vp", "director", "head of"]):
        score += 20
    elif any(t in title for t in ["manager", "lead", "senior"]):
        score += 10

    # Intent signals in message
    intent_keywords = ["interested", "demo", "pricing", "timeline", "budget",
                       "evaluate", "looking for", "need", "help with"]
    if any(k in message for k in intent_keywords):
        score += 15

    # Source scoring
    source = lead_data.get("source", "")
    source_scores = {"linkedin": 10, "referral": 20, "website": 5, "cold": 0}
    score += source_scores.get(source, 0)

    return min(100.0, score)
