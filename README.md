# broker-bridge

RabbitMQ -> Apache Flink -> Apache Kafka local sandbox, fully Dockerized.

## Prerequisites
- Docker (Desktop with WSL2 integration, or Docker Engine + Compose Plugin)
- Internet access to pull images and Maven deps

## Topology
- RabbitMQ (rabbitmq:3.12-management)
- Kafka (confluentinc/cp-kafka) + Zookeeper
- Flink (jobmanager + taskmanager)
- Flink job: reads from RabbitMQ queue, writes to Kafka topic
- Test producer: sends sample messages to RabbitMQ
- Kafka tools: kcat for consumption checks

## Default config
- RabbitMQ: host `rabbitmq`, port `5672`, user `user`, pass `pass`, queue `input_queue`
- Kafka: bootstrap `kafka:9092`, topic `output_topic`
- Flink UI: http://localhost:8081
- RabbitMQ UI: http://localhost:15672 (user/pass)

## Quick start (Makefile)
From the `build/` directory:

```bash
cd build
# default 50 msgs end-to-end
make run

# run with a specific message count (end-to-end)
MSG_COUNT=200 make run
```
This will:
1. Build the Flink fat JAR and the Rabbit producer image
2. Start docker-compose services
3. Submit the Flink job
4. Produce sample messages into RabbitMQ
5. Verify all produced messages arrived to Kafka

## Step-by-step
```bash
cd build
make build        # build Flink job JAR (via Dockerized Maven) and producer image
make up           # start RabbitMQ, Kafka, Flink, tools
make submit       # submit Flink job
make produce      # send test messages into RabbitMQ
make verify       # consume all produced messages (default: MSG_COUNT=50)
```
Override topic for verification:
```bash
make verify TOPIC=my_topic
```

## Tear down
```bash
cd build
make down         # stop & remove containers and volumes
```

## Sources
- Flink job code: `flink-job/src/main/java/com/example/RabbitToKafkaJob.java`
- Build scripts: `build/build.sh`, `build/run.sh`, `build/Makefile`
- Compose: `build/docker-compose.yml`
- Test producer: `build/rabbit_producer.py`
- Kafka verify script: `tests/verify_kafka.sh`

## Notes
- Everything runs inside Docker; no local JVM/Maven required.
- If you change queue/topic/user/pass, update them in the compose or job env before running.
- The Flink job uses manual acknowledgements (basicConsume with autoAck=false + basicAck). Messages are removed from RabbitMQ only after being collected and forwarded to Kafka.

## Why Flink here instead of ad‑hoc code?
- Exactly‑once and checkpointing: built‑in state snapshots, backpressure handling, and recovery without duplicates, which is non‑trivial to implement correctly by hand.
- Fault tolerance and scaling: automatic recovery, parallelism, rescaling, and distributed execution out of the box.
- Connectors and ecosystem: production‑grade connectors (Kafka, filesystems, JDBC, etc.), metrics, and tooling (Flink UI).
- Stateful stream processing: windows, timers, keyed state, watermarking when requirements grow beyond simple piping.
- Operational maturity: proven semantics, backpressure, and monitoring simplify reliability and on‑call load.
