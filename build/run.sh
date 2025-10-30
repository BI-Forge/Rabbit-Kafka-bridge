#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT_DIR/build"

./build.sh

echo "[run] Starting docker-compose..."
docker compose up -d

echo "[run] Waiting for services to be ready..."
sleep 8

echo "[run] Submitting Flink job..."
docker start bb-flink-submit >/dev/null

echo "[run] Producing test messages to RabbitMQ..."
docker compose run --rm rabbit-producer

echo "[run] Verifying messages in Kafka..."
"$ROOT_DIR/tests/verify_kafka.sh" output_topic || true

echo "[run] Done. Use Flink UI at http://localhost:8081 and RabbitMQ UI at http://localhost:15672"

