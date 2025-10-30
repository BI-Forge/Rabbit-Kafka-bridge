import os
import sys
import time
import pika


def main():
    host = os.getenv("RABBIT_HOST", "rabbitmq")
    port = int(os.getenv("RABBIT_PORT", "5672"))
    user = os.getenv("RABBIT_USER", "user")
    password = os.getenv("RABBIT_PASS", "pass")
    queue = os.getenv("RABBIT_QUEUE", "input_queue")
    count = int(os.getenv("MSG_COUNT", "50"))

    credentials = pika.PlainCredentials(user, password)
    params = pika.ConnectionParameters(host=host, port=port, virtual_host="/", credentials=credentials)

    # Retry until RabbitMQ is ready
    for attempt in range(30):
        try:
            connection = pika.BlockingConnection(params)
            break
        except Exception:
            time.sleep(1)
    else:
        print("Failed to connect to RabbitMQ", file=sys.stderr)
        sys.exit(1)

    channel = connection.channel()
    channel.queue_declare(queue=queue, durable=True)

    for i in range(count):
        body = f"test-message-{i}"
        channel.basic_publish(exchange="", routing_key=queue, body=body.encode("utf-8"))
        print(f"[producer] sent {body}")
        time.sleep(0.05)

    connection.close()


if __name__ == "__main__":
    main()

