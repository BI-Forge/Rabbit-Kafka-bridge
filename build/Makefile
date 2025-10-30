.PHONY: build up submit produce verify run down logs status clean

ROOT := $(abspath ..)
COMPOSE_FILE := $(ROOT)/build/docker-compose.yml
TOPIC ?= output_topic

build:
	@echo "[make] Building artifacts and images"
	bash $(ROOT)/build/build.sh

up:
	@echo "[make] Starting docker-compose"
	docker compose -f $(COMPOSE_FILE) up -d

submit:
	@echo "[make] Submitting Flink job"
	docker start bb-flink-submit >/dev/null || true

produce:
	@echo "[make] Producing test messages to RabbitMQ"
	docker compose -f $(COMPOSE_FILE) run --rm rabbit-producer

verify:
	@echo "[make] Verifying messages in Kafka topic=$(TOPIC)"
	bash $(ROOT)/tests/verify_kafka.sh $(TOPIC)

run: build up submit produce verify

down:
	@echo "[make] Stopping and removing containers and volumes"
	docker compose -f $(COMPOSE_FILE) down -v

logs:
	@echo "[make] Tailing docker-compose logs (Ctrl+C to stop)"
	docker compose -f $(COMPOSE_FILE) logs -f

status:
	@echo "[make] docker-compose status"
	docker compose -f $(COMPOSE_FILE) ps

clean: down
	@echo "[make] Clean complete"

