.PHONY: build up up-sr restart-flink submit produce verify verify-avro run down logs status clean schema-policy schema-get consume-avro

ROOT := $(abspath ..)
COMPOSE_FILE := $(ROOT)/build/docker-compose.yml
TOPIC ?= output_topic
MSG_COUNT ?= 50
SR_URL ?= http://schema-registry:8085

build:
	@echo "[make] Building artifacts and images"
	bash $(ROOT)/build/build.sh

up:
	@echo "[make] Starting docker-compose"
	docker compose -f $(COMPOSE_FILE) up -d

up-sr:
	@echo "[make] Starting Schema Registry"
	docker compose -f $(COMPOSE_FILE) up -d schema-registry

restart-flink:
	@echo "[make] Restarting Flink JM/TM"
	docker compose -f $(COMPOSE_FILE) restart flink-jobmanager flink-taskmanager

submit:
	@echo "[make] Submitting Flink job"
	docker start bb-flink-submit >/dev/null || true

produce:
	@echo "[make] Producing test messages to RabbitMQ"
	 docker compose -f $(COMPOSE_FILE) run -e MSG_COUNT=$(MSG_COUNT) --rm rabbit-producer

verify:
	@echo "[make] Verifying messages in Kafka topic=$(TOPIC)"
	 bash $(ROOT)/tests/verify_kafka.sh $(TOPIC) $(MSG_COUNT)

verify-avro:
	@echo "[make] Verifying Avro messages via Schema Registry topic=$(TOPIC) count=$(MSG_COUNT)"
	 docker compose -f $(COMPOSE_FILE) exec kafka-tools \
	   kcat -b kafka:9092 -C -t $(TOPIC) -o beginning -c $(MSG_COUNT) \
	   -s value=avro -r $(SR_URL) -f '%s\n'

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

.PHONY: test-load test-schema

test-load:
	@echo "[make] Load test: MSG_COUNT=$(MSG_COUNT), topic=$(TOPIC)"
	bash $(ROOT)/tests/load_test.sh $(MSG_COUNT) $(TOPIC)

test-schema:
	@echo "[make] Schema test: JSON, MSG_COUNT=$(MSG_COUNT), topic=$(TOPIC)"
	bash $(ROOT)/tests/schema_test.sh $(MSG_COUNT) $(TOPIC)

# Schema Registry helpers
schema-policy:
	@echo "[make] Setting global compatibility to BACKWARD"
	curl -s -X PUT -H 'Content-Type: application/json' \
	  --data '{"compatibility":"BACKWARD"}' \
	  http://localhost:8085/config | jq .

schema-get:
	@echo "[make] Get latest schema for subject $(TOPIC)-value"
	curl -s http://localhost:8085/subjects/$(TOPIC)-value/versions/latest | jq .

consume-avro:
	@echo "[make] Consuming Avro messages with SR URL=$(SR_URL)"
	 docker compose -f $(COMPOSE_FILE) exec kafka-tools \
	   kcat -b kafka:9092 -C -t $(TOPIC) -o beginning -c $(MSG_COUNT) \
	   -s value=avro -r $(SR_URL) -f '%s\n'

