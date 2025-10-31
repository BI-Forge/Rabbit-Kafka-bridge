package com.example;

import org.apache.flink.api.common.serialization.SerializationSchema;
import org.apache.flink.connector.kafka.sink.KafkaRecordSerializationSchema;
import org.apache.flink.connector.kafka.sink.KafkaSink;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.functions.source.RichSourceFunction;
import org.apache.flink.api.common.functions.MapFunction;
import org.apache.flink.api.common.functions.RichMapFunction;
import org.apache.flink.configuration.Configuration;
import com.rabbitmq.client.Channel;
import com.rabbitmq.client.Connection;
import com.rabbitmq.client.ConnectionFactory;
import com.rabbitmq.client.GetResponse;

import org.apache.kafka.common.serialization.ByteArraySerializer;
import org.apache.avro.Schema;
import org.apache.avro.generic.GenericData;
import org.apache.avro.generic.GenericRecord;
import io.confluent.kafka.serializers.KafkaAvroSerializer;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

/** Reads strings from RabbitMQ queue and forwards to Kafka topic. */
public class RabbitToKafkaJob {

    public static void main(String[] args) throws Exception {
        final String rabbitHost = env("RABBIT_HOST", "rabbitmq");
        final int rabbitPort = Integer.parseInt(env("RABBIT_PORT", "5672"));
        final String rabbitUser = env("RABBIT_USER", "user");
        final String rabbitPass = env("RABBIT_PASS", "pass");
        final String rabbitQueue = env("RABBIT_QUEUE", "input_queue");

        final String kafkaBootstrap = env("KAFKA_BOOTSTRAP", "kafka:9092");
        final String kafkaTopic = env("KAFKA_TOPIC", "output_topic");
        final String schemaRegistryUrl = env("SCHEMA_REGISTRY_URL", "http://schema-registry:8085");

        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

        DataStream<String> input = env.addSource(new RabbitMQSimpleSource(
                rabbitHost, rabbitPort, rabbitUser, rabbitPass, rabbitQueue
        )).name("rabbitmq-source").setParallelism(1);

        // Avro schema definition
        final String schemaString = "{\n"
                + "  \"type\": \"record\",\n"
                + "  \"name\": \"Message\",\n"
                + "  \"namespace\": \"com.example\",\n"
                + "  \"fields\": [\n"
                + "    {\"name\": \"id\", \"type\": \"int\"},\n"
                + "    {\"name\": \"payload\", \"type\": \"string\"},\n"
                + "    {\"name\": \"ts\", \"type\": \"long\"}\n"
                + "  ]\n"
                + "}";
        final String avroSchemaString = schemaString;

        java.util.Properties producerProps = new java.util.Properties();
        producerProps.put("key.serializer", ByteArraySerializer.class.getName());
        producerProps.put("value.serializer", KafkaAvroSerializer.class.getName());
        producerProps.put("schema.registry.url", schemaRegistryUrl);

        KafkaSink<String> kafkaSink = KafkaSink.<String>builder()
                .setBootstrapServers(kafkaBootstrap)
                .setKafkaProducerConfig(producerProps)
                .setRecordSerializer(KafkaRecordSerializationSchema.builder()
                        .setTopic(kafkaTopic)
                        .setValueSerializationSchema(new AvroValueSerializationSchema(schemaRegistryUrl, kafkaTopic, avroSchemaString))
                        .build())
                .build();

        input.sinkTo(kafkaSink).name("kafka-sink");

        env.execute("RabbitMQ to Kafka bridge");
    }

    private static String env(String key, String def) {
        String v = System.getenv(key);
        return v == null || v.isEmpty() ? def : v;
    }

    /** Simple RabbitMQ source using manual acknowledgements. */
    public static class RabbitMQSimpleSource extends RichSourceFunction<String> {
        private final String host;
        private final int port;
        private final String user;
        private final String pass;
        private final String queue;
        private volatile boolean running = true;
        private transient Connection connection;
        private transient Channel channel;
        private transient String consumerTag;

        public RabbitMQSimpleSource(String host, int port, String user, String pass, String queue) {
            this.host = host;
            this.port = port;
            this.user = user;
            this.pass = pass;
            this.queue = queue;
        }

        @Override
        public void run(SourceContext<String> ctx) throws Exception {
            ConnectionFactory factory = new ConnectionFactory();
            factory.setHost(host);
            factory.setPort(port);
            factory.setUsername(user);
            factory.setPassword(pass);
            factory.setVirtualHost("/");

            connection = factory.newConnection();
            channel = connection.createChannel();
            channel.queueDeclare(queue, true, false, false, null);
            channel.basicQos(50);

            com.rabbitmq.client.DeliverCallback deliver = (consumerTag, delivery) -> {
                if (!running) return;
                String body = new String(delivery.getBody());
                try {
                    synchronized (ctx.getCheckpointLock()) {
                        ctx.collect(body);
                    }
                    channel.basicAck(delivery.getEnvelope().getDeliveryTag(), false);
                    System.out.println("[RabbitMQ] Processed message: " + body.substring(0, Math.min(50, body.length())));
                } catch (Exception e) {
                    System.err.println("[RabbitMQ] ERROR processing message: " + e.getMessage());
                    e.printStackTrace();
                }
            };

            com.rabbitmq.client.CancelCallback cancelCb = ct -> { };

            consumerTag = channel.basicConsume(queue, false, deliver, cancelCb);

            while (running) {
                Thread.sleep(200);
            }
        }

        @Override
        public void cancel() {
            running = false;
            try { if (channel != null && channel.isOpen() && consumerTag != null) channel.basicCancel(consumerTag); } catch (Exception ignored) {}
            try { if (channel != null && channel.isOpen()) channel.close(); } catch (Exception ignored) {}
            try { if (connection != null && connection.isOpen()) connection.close(); } catch (Exception ignored) {}
        }
    }

    // removed intermediate GenericRecord mapping to avoid Kryo serialization issues

    /** SerializationSchema that delegates to Confluent KafkaAvroSerializer. */
    public static class AvroValueSerializationSchema implements SerializationSchema<String> {
        private final String registryUrl;
        private final String topic;
        private final String schemaString;
        private transient KafkaAvroSerializer serializer;
        private transient Schema schema;
        private transient ObjectMapper mapper;

        public AvroValueSerializationSchema(String registryUrl, String topic, String schemaString) {
            this.registryUrl = registryUrl;
            this.topic = topic;
            this.schemaString = schemaString;
        }

        @Override
        public void open(InitializationContext context) {
            java.util.Map<String, Object> props = new java.util.HashMap<>();
            props.put("schema.registry.url", registryUrl);
            serializer = new KafkaAvroSerializer();
            serializer.configure(props, false);
            schema = new Schema.Parser().parse(schemaString);
            mapper = new ObjectMapper();
        }

        @Override
        public byte[] serialize(String value) {
            System.out.println("[AvroSerializer] Serializing message: " + value.substring(0, Math.min(50, value.length())));
            Integer id = 0;
            String payload = value;
            Long ts = System.currentTimeMillis();
            try {
                JsonNode node = mapper.readTree(value);
                if (node.has("id")) id = node.get("id").asInt();
                if (node.has("payload")) payload = node.get("payload").asText();
                if (node.has("ts")) ts = node.get("ts").asLong();
            } catch (Exception ignored) { }

            GenericRecord record = new GenericData.Record(schema);
            record.put("id", id);
            record.put("payload", payload);
            record.put("ts", ts);
            try {
                byte[] result = serializer.serialize(topic, record);
                System.out.println("[AvroSerializer] Successfully serialized message to " + result.length + " bytes");
                return result;
            } catch (Exception e) {
                System.err.println("[AvroSerializer] ERROR serializing Avro record for topic " + topic + ": " + e.getMessage());
                e.printStackTrace();
                throw new RuntimeException("Failed to serialize Avro record", e);
            }
        }
    }
}


