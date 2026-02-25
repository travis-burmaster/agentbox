#!/usr/bin/env python3
"""
Test event publisher — simulate Kafka events locally.
Usage:
  python scripts/publish_event.py --topic marketing.leads --event lead.created \
    --data '{"lead_id":"test-001","name":"Travis B","company":"Northramp","email":"t@n.com"}'
"""
import argparse
import json
import os
from confluent_kafka import Producer

KAFKA_CONFIG = {
    "bootstrap.servers": os.environ.get("KAFKA_BOOTSTRAP_SERVERS", "localhost:9092"),
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--topic", required=True)
    parser.add_argument("--event", required=True)
    parser.add_argument("--key", default="test-key")
    parser.add_argument("--data", default="{}")
    args = parser.parse_args()

    p = Producer(KAFKA_CONFIG)

    payload = {
        "event": args.event,
        **json.loads(args.data),
    }

    p.produce(
        topic=args.topic,
        key=args.key.encode(),
        value=json.dumps(payload).encode(),
    )
    p.flush()
    print(f"✅ Published to {args.topic}: {json.dumps(payload, indent=2)}")


if __name__ == "__main__":
    main()
