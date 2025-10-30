package com.example;

import org.apache.flink.api.common.eventtime.WatermarkStrategy;
import org.apache.flink.api.common.serialization.SimpleStringSchema;
import org.apache.flink.connector.kafka.sink.KafkaRecordSerializationSchema;
import org.apache.flink.connector.kafka.sink.KafkaSink;
import org.apache.flink.streaming.api.datastream.DataStream;
import org.apache.flink.streaming.api.environment.StreamExecutionEnvironment;
import org.apache.flink.streaming.api.functions.source.RichSourceFunction;
import com.rabbitmq.client.Channel;
import com.rabbitmq.client.Connection;
import com.rabbitmq.client.ConnectionFactory;
import com.rabbitmq.client.GetResponse;

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

        StreamExecutionEnvironment env = StreamExecutionEnvironment.getExecutionEnvironment();

        DataStream<String> input = env.addSource(new RabbitMQSimpleSource(
                rabbitHost, rabbitPort, rabbitUser, rabbitPass, rabbitQueue
        )).name("rabbitmq-source").setParallelism(1);

        KafkaSink<String> kafkaSink = KafkaSink.<String>builder()
                .setBootstrapServers(kafkaBootstrap)
                .setRecordSerializer(KafkaRecordSerializationSchema.builder()
                        .setTopic(kafkaTopic)
                        .setValueSerializationSchema(new SimpleStringSchema())
                        .build())
                .build();

        input.sinkTo(kafkaSink).name("kafka-sink");

        env.execute("RabbitMQ to Kafka bridge");
    }

    private static String env(String key, String def) {
        String v = System.getenv(key);
        return v == null || v.isEmpty() ? def : v;
    }

    /** Simple RabbitMQ polling source for small demo/testing flows. */
    public static class RabbitMQSimpleSource extends RichSourceFunction<String> {
        private final String host;
        private final int port;
        private final String user;
        private final String pass;
        private final String queue;
        private volatile boolean running = true;
        private transient Connection connection;
        private transient Channel channel;

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

            while (running) {
                GetResponse resp = channel.basicGet(queue, true);
                if (resp != null) {
                    String body = new String(resp.getBody());
                    synchronized (ctx.getCheckpointLock()) {
                        ctx.collect(body);
                    }
                } else {
                    Thread.sleep(50);
                }
            }
        }

        @Override
        public void cancel() {
            running = false;
            try { if (channel != null && channel.isOpen()) channel.close(); } catch (Exception ignored) {}
            try { if (connection != null && connection.isOpen()) connection.close(); } catch (Exception ignored) {}
        }
    }
}


