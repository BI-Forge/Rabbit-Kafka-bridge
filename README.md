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
 - Schema Registry (optional, recommended): Confluent SR for schema management

## Default config
- RabbitMQ: host `rabbitmq`, port `5672`, user `user`, pass `pass`, queue `input_queue`
- Kafka: bootstrap `kafka:9092`, topic `output_topic`
- Flink UI: http://localhost:8081
- RabbitMQ UI: http://localhost:15672 (user/pass)

## Quick start (Makefile)
From the `build/` directory:

```bash
cd build
# default 50 msgs end-to-end (plain text verification)
make run

# end-to-end with Avro verification via Schema Registry
make run-avro

# run with a specific message count (end-to-end)
MSG_COUNT=200 make run
```
This will:
1. Build the Flink fat JAR and the Rabbit producer image
2. Start docker-compose services
3. Submit the Flink job
4. Produce sample messages into RabbitMQ
5. Verify delivery (plain text by default, or Avro with run-avro)

Enable Schema Registry (optional, recommended):
```bash
make up-sr            # start schema-registry
make restart-flink    # restart Flink to pick up SR env vars
```

> Note: `/subjects` will be empty until the first Avro record is written to Kafka.

## Step-by-step
```bash
cd build
make build        # build Flink job JAR (via Dockerized Maven) and producer image
make up           # start RabbitMQ, Kafka, Flink, tools
make up-sr        # start Schema Registry on http://localhost:8085
make submit       # submit Flink job
make produce      # send test messages into RabbitMQ
make verify       # consume all produced messages (default: MSG_COUNT=50)
make verify-avro  # consume Avro messages via Schema Registry
```
Override topic for verification:
```bash
make verify TOPIC=my_topic
make verify-avro TOPIC=my_topic
```

## Tests
Run from `build/`.

- Load test (produce N messages, verify all consumed):
```bash
make test-load MSG_COUNT=10000              # topic=output_topic by default
make test-load MSG_COUNT=50000 TOPIC=my_topic
```

- Schema test (JSON format end-to-end):
```bash
make test-schema MSG_COUNT=20               # produces JSON to RabbitMQ, verifies JSON in Kafka
```
Producer supports JSON via env:
```bash
make produce MSG_COUNT=20                   # text messages (default)
# or JSON into RabbitMQ
docker compose -f build/docker-compose.yml run --rm -e MSG_COUNT=20 -e MSG_FORMAT=json rabbit-producer
```

With Schema Registry enabled, the Flink job outputs Avro to Kafka using a stable schema.
To inspect messages:
```bash
# show topic metadata
docker compose -f build/docker-compose.yml exec kafka-tools kcat -b kafka:9092 -L -t output_topic

# decode Avro via SR
cd build
make verify-avro MSG_COUNT=10 TOPIC=output_topic

# list subjects and get latest schema
make schema-subjects
make schema-get TOPIC=output_topic

# set global compatibility policy (default suggestion: BACKWARD)
make schema-policy
```

### Schema Registry UI?
Confluent Schema Registry does not provide a built‑in web UI. Use its REST API on `http://localhost:8085`.

- Quick links in your browser:
  - `http://localhost:8085/subjects`
  - `http://localhost:8085/subjects/output_topic-value/versions`
  - `http://localhost:8085/config`

- CLI examples (already covered above):
  - List subjects: `make schema-subjects`
  - Get latest schema: `make schema-get TOPIC=output_topic`
  - Set compatibility: `make schema-policy`

If you need a graphical UI, consider running external tools (not included here) like Confluent Control Center or Redpanda Console which can connect to Schema Registry.

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
- When Schema Registry is up, the Flink pipeline serializes Kafka values as Avro in the sink and auto-registers schema in SR (subject `<topic>-value`).

## Why Flink here instead of ad‑hoc code?
- Exactly‑once and checkpointing: built‑in state snapshots, backpressure handling, and recovery without duplicates, which is non‑trivial to implement correctly by hand.
- Fault tolerance and scaling: automatic recovery, parallelism, rescaling, and distributed execution out of the box.
- Connectors and ecosystem: production‑grade connectors (Kafka, filesystems, JDBC, etc.), metrics, and tooling (Flink UI).
- Stateful stream processing: windows, timers, keyed state, watermarking when requirements grow beyond simple piping.
- Operational maturity: proven semantics, backpressure, and monitoring simplify reliability and on‑call load.

## Production deployment to Kubernetes (step-by-step)
This is a pragmatic checklist to run the same architecture (RabbitMQ -> Flink -> Kafka + Schema Registry) in production on Kubernetes.

1) Prerequisites
- A production-grade Kubernetes cluster (managed: GKE/EKS/AKS, or on-prem).
- kubectl and helm configured.
- Container registry (push your images): GHCR/ECR/GCR/ACR.
- StorageClass for persistent volumes, Ingress, certificates (e.g., cert-manager), and metrics stack (Prometheus/Grafana) recommended.

2) Create namespaces and baseline policies
```bash
kubectl create namespace data
kubectl create namespace streaming
kubectl create namespace tooling
# (optional) baseline NetworkPolicies and PodSecurity policies per org standards
```

3) Deploy Kafka (and Zookeeper) or Kafka with KRaft
- Option A (operator): use Strimzi Operator for Kafka (recommended for prod lifecycle):
  - Install Strimzi: `helm repo add strimzi https://strimzi.io/charts/ && helm install strimzi-kafka strimzi/strimzi-kafka-operator -n data`
  - Apply a Kafka cluster CR (replicated brokers, persistent volumes, listeners for internal/external), and create topics `output_topic`.
- Option B (charts): use Bitnami Kafka + Zookeeper charts with persistent volumes and proper listeners.

4) Deploy Schema Registry
- Run `confluentinc/cp-schema-registry:7.5.x` as a Deployment with a Service in `data` namespace.
- Key envs:
  - `SCHEMA_REGISTRY_KAFKASTORE_BOOTSTRAP_SERVERS`: internal Kafka bootstrap (e.g., `PLAINTEXT://kafka:9092`).
  - `SCHEMA_REGISTRY_LISTENERS`: `http://0.0.0.0:8085`.
  - Expose as ClusterIP and optionally Ingress with TLS.
- Add readiness/liveness probes and resource requests/limits.

5) Deploy RabbitMQ
- Use Bitnami chart: `helm repo add bitnami https://charts.bitnami.com/bitnami` then
```bash
helm install rabbitmq bitnami/rabbitmq -n data \
  --set auth.username=user --set auth.password=pass \
  --set persistence.enabled=true --set replicaCount=2
```
- Create a durable queue `input_queue` (via chart values, init container, or post-install Job).

6) Build and push the Flink job image
- Build the shaded JAR as in this repo, then build a Docker image with it and push to your registry:
  - Image SHOULD include your JAR under `/opt/flink/usrlib/app.jar`.

7) Run Flink in K8s
- Recommended: Flink Kubernetes Operator (CRDs) for HA jobs with savepoints:
  - Install: `helm repo add flink-operator https://downloads.apache.org/flink/flink-kubernetes-operator-helm-charts/ && helm install flink-operator flink-operator/flink-kubernetes-operator -n streaming`
  - Create a `FlinkDeployment` (Job/Session) with:
    - Parallelism and resource limits set.
    - HA: set 2+ replicas for JobManager (where supported) and multiple TaskManagers.
    - Env vars: `RABBIT_HOST`, `RABBIT_PORT`, `RABBIT_USER`, `RABBIT_PASS`, `RABBIT_QUEUE`, `KAFKA_BOOTSTRAP`, `KAFKA_TOPIC`, `SCHEMA_REGISTRY_URL` (ClusterIP of SR).
    - Mount the JAR from the job image and set the entrypoint to the main class.
    - Enable checkpointing and configure savepoint upgrade mode.
- Alternative: Bitnami Flink chart (Session cluster) + Kubernetes Job to submit the JAR.

8) Secrets and configuration
- Store credentials in `Secret` objects (RabbitMQ, Kafka if SASL/TLS, Schema Registry if auth enabled).
- Use `ConfigMap` for non-secrets (topics, queue names, SR URL, compatibility policy).
- Reference envs via `envFrom` and `valueFrom`.

9) Networking and security
- Use internal Services (ClusterIP) for inter-service traffic; expose UIs via Ingress with authentication.
- Apply NetworkPolicies to restrict egress/ingress.
- If Kafka is TLS/SASL, configure Flink Kafka sink with truststores/JAAS via mounted secrets and `FLINK_OPTS` or config files.

10) Persistence and scaling
- Kafka/Zookeeper and RabbitMQ must use persistent volumes (adequate IOPS/throughput).
- Right-size partitions, replication factor, retention, and quotas.
- Horizontal scaling: increase Flink TaskManagers/parallelism; consider HPA on CPU/lag metrics.

11) Observability
- Expose metrics (Flink, Kafka, RabbitMQ, Schema Registry) to Prometheus; build Grafana dashboards.
- Centralized logs (ELK/Opensearch). Add app logs with message ids for traceability.
- Add a `kcat` toolbox pod in `tooling` for ad-hoc consumption and troubleshooting.

12) CI/CD and rollout
- Build images in CI, scan, sign, and push.
- Use GitOps (Argo CD/Flux) to sync Helm/CRDs across envs.
- Rolling upgrades of Flink jobs using savepoints; validate SR compatibility before rollout.

13) Backups and DR
- Backup Kafka/ZK (or KRaft metadata), RabbitMQ definitions, and SR subject registry (export via REST or storage snapshots).
- Test restore and cross-zone/region failover.

14) Production validation checklist
- Load test with expected peak (x1.5 headroom) and verify end-to-end latency/lag.
- Chaos tests: broker/node kills; verify recovery without message loss.
- Security review: secrets at rest, TLS in transit, RBAC least privilege.

References (suggested charts/operators)
- Kafka: Strimzi Operator, Bitnami Kafka
- RabbitMQ: Bitnami RabbitMQ
- Flink: Apache Flink K8s Operator
- Schema Registry: Confluent SR container (Deployment + Service)
