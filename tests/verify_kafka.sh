#!/usr/bin/env bash
set -euo pipefail

TOPIC=${1:-output_topic}
BROKER="kafka:9092"

echo "[tests] Creating topic $TOPIC (if not exists)..."
docker exec bb-kafka kafka-topics --create --if-not-exists --topic "$TOPIC" --bootstrap-server "$BROKER" --replication-factor 1 --partitions 1 >/dev/null 2>&1 || true

echo "[tests] Consuming 10 messages from $TOPIC..."
docker exec bb-kafka-tools kcat -b "$BROKER" -t "$TOPIC" -C -o beginning -e -q -c 10

echo "[tests] Done."

