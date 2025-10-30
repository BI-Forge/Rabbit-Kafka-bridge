#!/usr/bin/env bash
set -euo pipefail

COUNT=${1:-20}
TOPIC=${2:-output_topic}
BROKER="kafka:9092"

echo "[schema] Resetting topic $TOPIC..."
docker exec bb-kafka kafka-topics --delete --topic "$TOPIC" --bootstrap-server "$BROKER" >/dev/null 2>&1 || true
sleep 1
docker exec bb-kafka kafka-topics --create --if-not-exists --topic "$TOPIC" --bootstrap-server "$BROKER" --replication-factor 1 --partitions 1 >/dev/null

echo "[schema] Ensure Flink job is running..."
docker start bb-flink-submit >/dev/null || true
sleep 3

echo "[schema] Purging RabbitMQ queue input_queue..."
docker exec bb-rabbitmq rabbitmqctl purge_queue input_queue >/dev/null

echo "[schema] Producing $COUNT JSON messages..."
docker compose -f "$(dirname "$0")/../build/docker-compose.yml" run --rm -e MSG_COUNT="$COUNT" -e MSG_FORMAT=json rabbit-producer >/dev/null

echo "[schema] Verifying JSON structure in Kafka..."
# Read messages and check they look like JSON with keys id and payload
docker exec bb-kafka-tools sh -lc "kcat -b $BROKER -t $TOPIC -C -o beginning -e -q -c $COUNT" | awk '
  BEGIN { ok=1 }
  {
    if ($0 !~ /^\{/ || index($0, "\"id\"") == 0 || index($0, "\"payload\"") == 0) { ok=0 }
    print $0
  }
  END { if (ok==0) { exit 1 } }
'

echo "[schema] OK"

