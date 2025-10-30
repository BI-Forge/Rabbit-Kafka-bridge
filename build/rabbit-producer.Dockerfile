FROM python:3.11-slim

RUN pip install --no-cache-dir pika==1.3.2

WORKDIR /app
COPY build/rabbit_producer.py /app/producer.py

ENV RABBIT_HOST=rabbitmq \
    RABBIT_PORT=5672 \
    RABBIT_USER=user \
    RABBIT_PASS=pass \
    RABBIT_QUEUE=input_queue \
    MSG_COUNT=50

CMD ["python", "/app/producer.py"]

