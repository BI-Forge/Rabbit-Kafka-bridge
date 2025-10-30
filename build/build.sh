#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

echo "[build] Building Flink job jar via Docker Maven..."
docker run --rm \
  -v "$ROOT_DIR/flink-job":/app \
  -w /app \
  maven:3.9-eclipse-temurin-11 \
  mvn -B -DskipTests package

echo "[build] Building rabbit producer image..."
docker build -f "$ROOT_DIR/build/rabbit-producer.Dockerfile" -t bb/rabbit-producer:latest "$ROOT_DIR"

echo "[build] Done. Artifacts in flink-job/target"

