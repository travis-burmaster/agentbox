"""
Marketing Agent — AgentBox

The core LLM agent. Restored from Redis on cold start.
Handles: lead nurturing, campaign execution, content creation,
         analytics reporting, competitive intelligence.
"""

import os
import json
import time
import logging
from typing import Any
import vertexai
from vertexai.generative_models import GenerativeModel, Tool, FunctionDeclaration

from agent.memory import AgentMemory
from agent.tools import (
    send_email, search_web, update_crm, publish_content,
    query_bigquery, score_lead_with_ml
)

log = logging.getLogger(__name__)


class MarketingAgent:
    def __init__(self, memory: AgentMemory, boot_context: dict,
                 llm_project: str, llm_location: str = "us-central1"):
        self.memory = memory
        self.ctx = boot_context
        self._dirty_memory = {}  # Changes to flush on exit

        # Init Vertex AI
        vertexai.init(project=llm_project, location=llm_location)
        self.model = GenerativeModel(
            model_name=os.environ.get("LLM_MODEL", "gemini-1.5-pro"),
            tools=[self._build_tools()],
            system_instruction=self._build_system_prompt(),
        )

    def _build_system_prompt(self) -> str:
        mem = self.ctx["memory"]
        campaigns_summary = "\n".join([
            f"  - {cid}: {state.get('name','?')} [{state.get('status','?')}] "
            f"stage {state.get('stage','?')}"
            for cid, state in self.ctx["active_campaigns"].items()
        ]) or "  None active."

        tasks_summary = "\n".join([
            f"  - [{t.get('priority','normal')}] {t.get('type','?')}: {t.get('description','?')}"
            for t in self.ctx["pending_tasks"][:5]
        ]) or "  No pending tasks."

        return f"""You are AgentBox Marketing — an autonomous AI marketing agent for Northramp.

## Your Memory (restored from last session)
Brand Voice: {mem.get('brand_voice', 'Professional and results-focused')}
ICP: {json.dumps(mem.get('icp', {}), indent=2)}

## Active Campaigns
{campaigns_summary}

## Pending Tasks (top 5)
{tasks_summary}

## Hot Leads
{', '.join(self.ctx.get('hot_leads', [])) or 'None'}

## Your Role
You run Northramp's marketing business autonomously:
1. Nurture leads with personalized, research-backed outreach
2. Execute multi-step campaigns (email sequences, LinkedIn, content)
3. Create blog posts, newsletters, LinkedIn content
4. Generate analytics reports
5. Monitor competitors and surface intelligence

## Rules
- Always research a company before reaching out
- Never send generic outreach — personalize to their specific pain points
- Log all actions to memory for continuity
- If a lead responds, prioritize immediately
- Track campaign performance and iterate
- Escalate to human (send Telegram alert) if: budget decision needed, 
  negative response, or you're unsure of approach
"""

    def _build_tools(self) -> Tool:
        return Tool(function_declarations=[
            FunctionDeclaration(
                name="send_email",
                description="Send an email to a lead or contact",
                parameters={
                    "type": "object",
                    "properties": {
                        "to": {"type": "string"},
                        "subject": {"type": "string"},
                        "body": {"type": "string"},
                        "lead_id": {"type": "string"},
                    },
                    "required": ["to", "subject", "body"],
                },
            ),
            FunctionDeclaration(
                name="search_web",
                description="Search the web for information about a company or person",
                parameters={
                    "type": "object",
                    "properties": {
                        "query": {"type": "string"},
                    },
                    "required": ["query"],
                },
            ),
            FunctionDeclaration(
                name="update_crm",
                description="Update a lead or deal in HubSpot CRM",
                parameters={
                    "type": "object",
                    "properties": {
                        "lead_id": {"type": "string"},
                        "updates": {"type": "object"},
                        "note": {"type": "string"},
                    },
                    "required": ["lead_id", "updates"],
                },
            ),
            FunctionDeclaration(
                name="publish_content",
                description="Publish content to LinkedIn, blog, or email newsletter",
                parameters={
                    "type": "object",
                    "properties": {
                        "platform": {"type": "string", "enum": ["linkedin", "blog", "newsletter"]},
                        "title": {"type": "string"},
                        "body": {"type": "string"},
                        "schedule_at": {"type": "string", "description": "ISO8601 or 'now'"},
                    },
                    "required": ["platform", "body"],
                },
            ),
            FunctionDeclaration(
                name="query_analytics",
                description="Query BigQuery for campaign or lead analytics",
                parameters={
                    "type": "object",
                    "properties": {
                        "metric": {"type": "string"},
                        "date_range": {"type": "string"},
                        "filters": {"type": "object"},
                    },
                    "required": ["metric"],
                },
            ),
            FunctionDeclaration(
                name="alert_human",
                description="Send an alert to Travis via Telegram for decisions requiring human input",
                parameters={
                    "type": "object",
                    "properties": {
                        "message": {"type": "string"},
                        "urgency": {"type": "string", "enum": ["info", "action_needed", "urgent"]},
                    },
                    "required": ["message"],
                },
            ),
        ])

    # ─── EVENT HANDLERS ────────────────────────────────────────────────────────

    async def handle_event(self, topic: str, key: str | None, payload: dict):
        """Route Kafka event to the appropriate handler."""
        event = payload.get("event", "")

        handlers = {
            "marketing.leads": self._handle_lead_event,
            "marketing.campaigns": self._handle_campaign_event,
            "marketing.schedule": self._handle_schedule_event,
            "marketing.commands": self._handle_command_event,
        }

        handler = handlers.get(topic)
        if handler:
            await handler(event, key, payload)
        else:
            log.warning(f"No handler for topic: {topic}")

    async def _handle_lead_event(self, event: str, lead_id: str, payload: dict):
        lead_data = payload.get("data", {})

        if event == "lead.created":
            log.info(f"New lead: {lead_id} — {lead_data.get('name')} @ {lead_data.get('company')}")
            await self._nurture_new_lead(lead_id, lead_data)

        elif event == "lead.responded":
            log.info(f"Lead responded: {lead_id}")
            await self._handle_lead_response(lead_id, lead_data)

        elif event == "lead.updated":
            await self._reassess_lead(lead_id, lead_data)

    async def _handle_campaign_event(self, event: str, campaign_id: str, payload: dict):
        if event == "campaign.start":
            await self._start_campaign(campaign_id, payload.get("data", {}))
        elif event == "campaign.step_complete":
            await self._advance_campaign(campaign_id, payload.get("step", 1))

    async def _handle_schedule_event(self, event: str, key: str, payload: dict):
        task = payload.get("task")
        if task == "daily_report":
            await self._generate_daily_report()
        elif task == "content_publish":
            await self._create_and_publish_content(payload.get("params", {}))
        elif task == "lead_score_update":
            await self._update_lead_scores()
        elif task == "competitor_scan":
            await self._competitive_intelligence_scan()

    async def _handle_command_event(self, event: str, key: str, payload: dict):
        """Human override commands."""
        command = payload.get("command")
        log.info(f"Human command received: {command}")
        # Execute directly, log result, alert back
        await self._execute_llm_task(
            task_description=f"Human command: {command}",
            context=payload.get("context", {}),
        )

    # ─── CORE MARKETING WORKFLOWS ──────────────────────────────────────────────

    async def _nurture_new_lead(self, lead_id: str, lead_data: dict):
        """Research → Score → Draft personalized outreach → Send → Log."""
        prompt = f"""
New lead received. Execute the lead nurturing workflow:

Lead Info:
- Name: {lead_data.get('name')}
- Company: {lead_data.get('company')}
- Title: {lead_data.get('title', 'Unknown')}
- Email: {lead_data.get('email')}
- Source: {lead_data.get('source')}
- Message: {lead_data.get('message', 'None')}

Steps:
1. search_web to research {lead_data.get('company')} — find their tech stack, recent news, pain points
2. Determine lead score (0-100) based on ICP match
3. Draft a personalized outreach email (NOT generic — reference specific company details)
4. send_email to {lead_data.get('email')} with the personalized message
5. update_crm with lead score, notes, and next follow-up date
6. If lead score > 80, alert_human with summary

Brand voice: {self.ctx['memory'].get('brand_voice')}
"""
        await self._execute_llm_task(prompt)

        # Update lead memory
        await self.memory.save_lead(lead_id, {
            "name": lead_data.get("name", ""),
            "company": lead_data.get("company", ""),
            "email": lead_data.get("email", ""),
            "status": "contacted",
            "last_action": "initial_outreach",
            "last_action_ts": str(time.time()),
        })
        await self.memory.log_lead_interaction(lead_id, "initial_outreach_sent")

    async def _handle_lead_response(self, lead_id: str, lead_data: dict):
        """Lead responded — highest priority. Pull history + craft reply."""
        lead = await self.memory.load_lead(lead_id)

        prompt = f"""
🔥 PRIORITY: A lead has responded to our outreach.

Lead History: {json.dumps(lead['history'][:10], indent=2)}
Lead Profile: {json.dumps(lead['profile'], indent=2)}
Their Response: {lead_data.get('message')}

Steps:
1. Analyze their response — are they interested? Objecting? Ready to schedule?
2. Draft a thoughtful, personalized reply that moves them toward a discovery call
3. send_email with the reply
4. update_crm — update status and next steps
5. alert_human with summary and suggested next step
"""
        await self._execute_llm_task(prompt)
        await self.memory.log_lead_interaction(lead_id, "response_handled",
                                                lead_data.get("message", "")[:200])

    async def _generate_daily_report(self):
        """Pull analytics, generate insights, email report."""
        prompt = """
Generate the daily marketing performance report:

1. query_analytics for: open_rate, reply_rate, meetings_booked (last 24h vs 7d avg)
2. query_analytics for: top performing campaigns (by reply rate)
3. query_analytics for: new leads today and their sources
4. Identify top 3 insights and 1 recommended action
5. send_email to travis@burmaster.com with formatted HTML report
   Subject: "Marketing Daily Report — {date}"
"""
        await self._execute_llm_task(prompt)

    async def _competitive_intelligence_scan(self):
        """Weekly competitor scan."""
        mem = self.ctx["memory"]
        competitors = mem.get("competitors", ["Booz Allen Hamilton", "Deloitte Federal",
                                              "ICF", "Leidos"])
        prompt = f"""
Weekly competitive intelligence scan for Northramp:

Competitors to scan: {', '.join(competitors)}

For each competitor:
1. search_web for recent news, contract wins, leadership changes
2. Note any positioning changes or new service offerings
3. Identify opportunities where Northramp can differentiate

Then:
4. Write a 1-page competitive brief
5. send_email to travis@burmaster.com with the brief
6. Update memory with key learnings
"""
        await self._execute_llm_task(prompt)
        await self.memory.append_memory("competitive_scans", {"ts": time.time()})

    # ─── LLM EXECUTION ────────────────────────────────────────────────────────

    async def _execute_llm_task(self, task_description: str, context: dict = {}):
        """Core LLM execution loop with tool calling."""
        chat = self.model.start_chat()
        response = await chat.send_message_async(task_description)

        # Tool calling loop
        max_iterations = 10
        iteration = 0
        while response.candidates[0].finish_reason.name == "TOOL_CALLS" and iteration < max_iterations:
            tool_results = []
            for part in response.candidates[0].content.parts:
                if part.function_call:
                    result = await self._dispatch_tool(
                        part.function_call.name,
                        dict(part.function_call.args)
                    )
                    tool_results.append({
                        "function_response": {
                            "name": part.function_call.name,
                            "response": result,
                        }
                    })

            response = await chat.send_message_async(tool_results)
            iteration += 1

        final_text = response.text if hasattr(response, 'text') else ""
        log.info(f"LLM task complete: {final_text[:200]}")
        return final_text

    async def _dispatch_tool(self, name: str, args: dict) -> dict:
        """Execute a tool call and return results."""
        log.info(f"Tool call: {name}({list(args.keys())})")
        try:
            if name == "send_email":
                return await send_email(**args)
            elif name == "search_web":
                return await search_web(**args)
            elif name == "update_crm":
                return await update_crm(**args)
            elif name == "publish_content":
                return await publish_content(**args)
            elif name == "query_analytics":
                return await query_bigquery(**args)
            elif name == "alert_human":
                return await self._alert_human(args["message"], args.get("urgency", "info"))
            else:
                return {"error": f"Unknown tool: {name}"}
        except Exception as e:
            log.error(f"Tool {name} failed: {e}")
            return {"error": str(e)}

    async def _alert_human(self, message: str, urgency: str = "info") -> dict:
        """Send Telegram alert to Travis."""
        import smtplib
        from email.mime.text import MIMEText
        emoji = {"info": "ℹ️", "action_needed": "⚠️", "urgent": "🚨"}.get(urgency, "ℹ️")
        # Use SMTP2GO to email → Travis's notification chain
        msg = MIMEText(f"{emoji} AgentBox Marketing Alert\n\n{message}")
        msg["Subject"] = f"AgentBox: {urgency.replace('_',' ').title()} — Action Needed"
        msg["From"] = "bot@burmaster.com"
        msg["To"] = "travis@burmaster.com"
        with smtplib.SMTP("smtp.smtp2go.com", 587) as s:
            s.starttls()
            s.login("bot.burmaster", os.environ.get("SMTP2GO_PASS", ""))
            s.send_message(msg)
        return {"sent": True}

    # ─── MEMORY FLUSH ─────────────────────────────────────────────────────────

    async def flush_memory(self):
        """Called on shutdown — persist all dirty state to Redis."""
        mem = self.ctx["memory"]
        # Record shutdown time for next session context
        mem["last_session_end"] = time.time()
        await self.memory.save_long_term(mem)
        log.info("Long-term memory flushed to Redis.")
