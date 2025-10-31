-- Flink SQL examples for querying Kafka topics with Avro/Schema Registry
-- Usage: make flink-sql, then copy-paste these commands

-- 1. Create table from Kafka topic with Avro format (Schema Registry)
CREATE TABLE output_topic_table (
    id INT,
    payload STRING,
    ts BIGINT
) WITH (
    'connector' = 'kafka',
    'topic' = 'output_topic',
    'properties.bootstrap.servers' = 'kafka:9092',
    'properties.group.id' = 'flink-sql-consumer',
    'scan.startup.mode' = 'earliest-offset',
    'format' = 'avro-confluent',
    'avro-confluent.schema-registry.url' = 'http://schema-registry:8085',
    'avro-confluent.schema-registry.subject' = 'output_topic-value'
);

-- 2. Query all messages
SELECT * FROM output_topic_table;

-- 3. Query with LIMIT
SELECT id, payload, ts 
FROM output_topic_table 
LIMIT 10;

-- 4. Filter messages
SELECT id, payload, ts
FROM output_topic_table
WHERE id > 5
LIMIT 20;

-- 5. Count messages
SELECT COUNT(*) as total_messages
FROM output_topic_table;

-- 6. Group by and aggregate
SELECT 
    SUBSTRING(payload, 1, 10) as prefix,
    COUNT(*) as count,
    MAX(ts) as latest_ts
FROM output_topic_table
GROUP BY SUBSTRING(payload, 1, 10);

-- 7. Window aggregations (if timestamps are event time)
-- Note: Requires watermark strategy for event time
SELECT 
    TUMBLE_START(ts, INTERVAL '1' MINUTE) as window_start,
    COUNT(*) as message_count
FROM output_topic_table
GROUP BY TUMBLE(ts, INTERVAL '1' MINUTE);

-- 8. Create a view for reuse
CREATE TEMPORARY VIEW filtered_messages AS
SELECT id, payload, ts
FROM output_topic_table
WHERE id % 2 = 0;

SELECT * FROM filtered_messages LIMIT 10;

-- 9. Show all tables
SHOW TABLES;

-- 10. Describe table structure
DESCRIBE output_topic_table;

-- 11. Drop table
-- DROP TABLE output_topic_table;

