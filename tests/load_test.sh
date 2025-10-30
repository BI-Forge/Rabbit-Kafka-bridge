#!/usr/bin/env bash
set -euo pipefail

COUNT=${1:-10000}
TOPIC=${2:-output_topic}
BROKER="kafka:9092"

echo "[load] Resetting topic $TOPIC..."
docker exec bb-kafka kafka-topics --delete --topic "$TOPIC" --bootstrap-server "$BROKER" >/dev/null 2>&1 || true
sleep 1
docker exec bb-kafka kafka-topics --create --if-not-exists --topic "$TOPIC" --bootstrap-server "$BROKER" --replication-factor 1 --partitions 3 >/dev/null

echo "[load] Submitting Flink job (ensure running)..."
docker start bb-flink-submit >/dev/null || true
sleep 3

echo "[load] Producing $COUNT messages..."
docker compose -f "$(dirname "$0")/../build/docker-compose.yml" run --rm -e MSG_COUNT="$COUNT" rabbit-producer >/dev/null

echo "[load] Verifying consumption: expecting $COUNT messages"
OUT=$(docker exec bb-kafka-tools sh -lc "kcat -b $BROKER -t $TOPIC -C -o beginning -e -q | wc -l")
RCV=$(echo "$OUT" | tr -d '\r')
echo "[load] Received: $RCV"

if [ "$RCV" -lt "$COUNT" ]; then
  echo "[load][ERROR] Expected $COUNT, got $RCV" >&2
  exit 1
fi

echo "[load] OK"

