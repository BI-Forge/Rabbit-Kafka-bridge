#!/usr/bin/env bash
set -euo pipefail

COUNT=${1:-10000}
TOPIC=${2:-output_topic}
BROKER="kafka:9092"

echo "[load] Canceling old Flink jobs..."
docker compose -f "$(dirname "$0")/../build/docker-compose.yml" exec -T flink-jobmanager /opt/flink/bin/flink list -r 2>/dev/null | grep "RUNNING" | awk '{print $4}' | while read jobid; do
  echo "[load] Canceling job $jobid"
  docker compose -f "$(dirname "$0")/../build/docker-compose.yml" exec -T flink-jobmanager /opt/flink/bin/flink cancel "$jobid" >/dev/null 2>&1 || true
done
# Wait for jobs to fully cancel (max 30s)
MAX_WAIT=30
WAITED=0
while [ "$WAITED" -lt "$MAX_WAIT" ]; do
  RUNNING=$(docker compose -f "$(dirname "$0")/../build/docker-compose.yml" exec -T flink-jobmanager /opt/flink/bin/flink list -r 2>/dev/null | grep -c "RUNNING" || echo "0")
  if [ "$RUNNING" -eq "0" ]; then
    break
  fi
  sleep 1
  WAITED=$((WAITED + 1))
done
sleep 2

echo "[load] Resetting topic $TOPIC (before Flink job)..."
docker exec bb-kafka kafka-topics --delete --topic "$TOPIC" --bootstrap-server "$BROKER" >/dev/null 2>&1 || true
sleep 2
docker exec bb-kafka kafka-topics --create --if-not-exists --topic "$TOPIC" --bootstrap-server "$BROKER" --replication-factor 1 --partitions 3 >/dev/null
sleep 1

echo "[load] Deleting old Schema Registry subjects for $TOPIC..."
curl -s -X DELETE "http://localhost:8085/subjects/$TOPIC-value" >/dev/null 2>&1 || true
curl -s -X DELETE "http://localhost:8085/subjects/$TOPIC-value?permanent=true" >/dev/null 2>&1 || true
sleep 1

echo "[load] Submitting Flink job..."
docker start bb-flink-submit >/dev/null || true
sleep 10

echo "[load] Producing $COUNT messages..."
docker compose -f "$(dirname "$0")/../build/docker-compose.yml" run --rm -e MSG_COUNT="$COUNT" rabbit-producer >/dev/null

echo "[load] Waiting for Flink to process messages (up to 60s)..."
MAX_WAIT=60
WAITED=0
RCV=0
while [ "$WAITED" -lt "$MAX_WAIT" ]; do
  sleep 2
  WAITED=$((WAITED + 2))
  RCV=$(docker exec bb-kafka-tools sh -c "timeout 5 kcat -b $BROKER -t $TOPIC -C -o beginning -c $COUNT -q 2>&1 | wc -l" || echo "0")
  RCV=$(echo "$RCV" | tr -d '\r')
  echo "[load] Progress: $RCV/$COUNT messages (waited ${WAITED}s)"
  if [ "$RCV" -ge "$COUNT" ]; then
    break
  fi
done

echo "[load] Final count: $RCV messages received"

if [ "$RCV" -lt "$COUNT" ]; then
  echo "[load][ERROR] Expected $COUNT, got $RCV after ${WAITED}s" >&2
  exit 1
fi

echo "[load] OK"

