#!/usr/bin/env bash
set -euo pipefail

COUNT=${1:-20}
TOPIC=${2:-output_topic}
BROKER="kafka:9092"

echo "[schema] Canceling old Flink jobs..."
docker compose -f "$(dirname "$0")/../build/docker-compose.yml" exec -T flink-jobmanager /opt/flink/bin/flink list -r 2>/dev/null | grep "RUNNING" | awk '{print $4}' | while read jobid; do
  echo "[schema] Canceling job $jobid"
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

echo "[schema] Resetting topic $TOPIC (before Flink job)..."
docker exec bb-kafka kafka-topics --delete --topic "$TOPIC" --bootstrap-server "$BROKER" >/dev/null 2>&1 || true
sleep 2
docker exec bb-kafka kafka-topics --create --if-not-exists --topic "$TOPIC" --bootstrap-server "$BROKER" --replication-factor 1 --partitions 1 >/dev/null
sleep 1

echo "[schema] Deleting old Schema Registry subjects for $TOPIC..."
curl -s -X DELETE "http://localhost:8085/subjects/$TOPIC-value" >/dev/null 2>&1 || true
curl -s -X DELETE "http://localhost:8085/subjects/$TOPIC-value?permanent=true" >/dev/null 2>&1 || true
sleep 1

echo "[schema] Submitting Flink job..."
docker start bb-flink-submit >/dev/null || true
sleep 10

echo "[schema] Purging RabbitMQ queue input_queue..."
docker exec bb-rabbitmq rabbitmqctl purge_queue input_queue >/dev/null

echo "[schema] Producing $COUNT JSON messages..."
docker compose -f "$(dirname "$0")/../build/docker-compose.yml" run --rm -e MSG_COUNT="$COUNT" -e MSG_FORMAT=json rabbit-producer >/dev/null

echo "[schema] Waiting for Flink to process messages (up to 30s)..."
MAX_WAIT=30
WAITED=0
RCV=0
while [ "$WAITED" -lt "$MAX_WAIT" ]; do
  sleep 1
  WAITED=$((WAITED + 1))
  RCV=$(docker exec bb-kafka-tools sh -c "timeout 3 kcat -b $BROKER -t $TOPIC -C -o beginning -c $COUNT -q 2>&1 | wc -l" || echo "0")
  RCV=$(echo "$RCV" | tr -d '\r')
  if [ "$RCV" -ge "$COUNT" ]; then
    break
  fi
done

if [ "$RCV" -lt "$COUNT" ]; then
  echo "[schema][ERROR] Expected $COUNT messages, got $RCV after ${WAITED}s" >&2
  exit 1
fi

echo "[schema] Verifying JSON structure in Kafka..."
# Read messages and check they look like JSON with keys id and payload
docker exec bb-kafka-tools sh -c "kcat -b $BROKER -t $TOPIC -C -o beginning -q -c $COUNT" | awk '
  BEGIN { ok=1; count=0 }
  {
    count++
    if ($0 !~ /^\{/ || index($0, "\"id\"") == 0 || index($0, "\"payload\"") == 0) { ok=0 }
  }
  END { 
    if (count < '$COUNT') { 
      print "[schema][ERROR] Expected '$COUNT' messages, got " count > "/dev/stderr"
      exit 1 
    }
    if (ok==0) { 
      print "[schema][ERROR] Invalid JSON structure detected" > "/dev/stderr"
      exit 1 
    }
  }
'

echo "[schema] OK"

