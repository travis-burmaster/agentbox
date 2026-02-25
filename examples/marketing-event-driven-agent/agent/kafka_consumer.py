"""
Kafka Consumer — AgentBox Marketing

Listens to marketing event topics and dispatches to the agent.
Designed for Cloud Run: starts, processes N events, exits cleanly.
"""

import os
import json
import asyncio
import logging
import signal
from confluent_kafka import Consumer, KafkaError, KafkaException
from agent.marketing_agent import MarketingAgent
from agent.memory import AgentMemory

log = logging.getLogger(__name__)


KAFKA_CONFIG = {
    "bootstrap.servers": os.environ["KAFKA_BOOTSTRAP_SERVERS"],
    "security.protocol": "SASL_SSL",
    "sasl.mechanisms": "PLAIN",
    "sasl.username": os.environ["KAFKA_API_KEY"],
    "sasl.password": os.environ["KAFKA_API_SECRET"],
    "group.id": "agentbox-marketing",
    "auto.offset.reset": "earliest",
    "enable.auto.commit": False,
    "max.poll.interval.ms": 300000,  # 5 min max per message
}

TOPICS = [
    "marketing.leads",
    "marketing.campaigns",
    "marketing.schedule",
    "marketing.commands",
]

# On Cloud Run: process this many events then exit cleanly (next trigger restarts)
MAX_EVENTS_PER_RUN = int(os.environ.get("MAX_EVENTS_PER_RUN", "10"))
POLL_TIMEOUT_SECONDS = int(os.environ.get("POLL_TIMEOUT_SECONDS", "30"))


class AgentBoxConsumer:
    def __init__(self):
        self.consumer = Consumer(KAFKA_CONFIG)
        self.memory = AgentMemory(os.environ["REDIS_URL"])
        self.agent: MarketingAgent | None = None
        self.running = True
        self._events_processed = 0

        # Graceful shutdown on SIGTERM (Cloud Run sends this before kill)
        signal.signal(signal.SIGTERM, self._handle_shutdown)
        signal.signal(signal.SIGINT, self._handle_shutdown)

    def _handle_shutdown(self, signum, frame):
        log.info("Shutdown signal received. Flushing memory before exit...")
        self.running = False

    async def start(self):
        log.info("AgentBox Marketing starting up...")

        # ── COLD START BOOT ──────────────────────────────────────────────────
        log.info("Booting agent memory from Redis...")
        context = await self.memory.boot_context()
        log.info(
            f"Memory loaded: {len(context['pending_tasks'])} tasks, "
            f"{len(context['active_campaigns'])} campaigns, "
            f"{len(context['hot_leads'])} hot leads"
        )

        # Initialize the agent with restored context
        self.agent = MarketingAgent(
            memory=self.memory,
            boot_context=context,
            llm_project=os.environ["GCP_PROJECT"],
            llm_location=os.environ.get("GCP_LOCATION", "us-central1"),
        )

        # ── SUBSCRIBE TO TOPICS ──────────────────────────────────────────────
        self.consumer.subscribe(TOPICS)
        log.info(f"Subscribed to topics: {TOPICS}")

        # ── EVENT LOOP ───────────────────────────────────────────────────────
        try:
            await self._consume_loop()
        finally:
            await self._shutdown_flush()
            self.consumer.close()
            await self.memory.close()
            log.info("AgentBox Marketing shutdown complete.")

    async def _consume_loop(self):
        while self.running and self._events_processed < MAX_EVENTS_PER_RUN:
            msg = self.consumer.poll(timeout=POLL_TIMEOUT_SECONDS)

            if msg is None:
                log.info("No messages in poll window — idle exit.")
                break

            if msg.error():
                if msg.error().code() == KafkaError._PARTITION_EOF:
                    log.debug("Partition EOF — caught up.")
                    break
                raise KafkaException(msg.error())

            # ── PROCESS EVENT ────────────────────────────────────────────────
            topic = msg.topic()
            key = msg.key().decode("utf-8") if msg.key() else None
            value = json.loads(msg.value().decode("utf-8"))

            log.info(f"Processing event: topic={topic} key={key} event={value.get('event')}")

            try:
                await self.agent.handle_event(topic=topic, key=key, payload=value)
                self.consumer.commit(message=msg)
                self._events_processed += 1
                log.info(f"Event processed and committed. ({self._events_processed}/{MAX_EVENTS_PER_RUN})")
            except Exception as e:
                log.error(f"Event processing failed: {e}", exc_info=True)
                # Don't commit — message will be retried on next run
                # Write to dead letter via Redis for visibility
                await self.memory.fail_task(
                    {"topic": topic, "key": key, "event": value.get("event")},
                    str(e)
                )

    async def _shutdown_flush(self):
        """Flush all memory to Redis before container exits."""
        if self.agent:
            log.info("Flushing agent memory to Redis...")
            await self.agent.flush_memory()
            log.info("Memory flush complete.")


async def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s"
    )
    consumer = AgentBoxConsumer()
    await consumer.start()


if __name__ == "__main__":
    asyncio.run(main())
