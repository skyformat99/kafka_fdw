CREATE SERVER kafka_server
FOREIGN DATA WRAPPER kafka_fdw
OPTIONS (brokers 'localhost:9092');

CREATE USER MAPPING FOR PUBLIC SERVER kafka_server;
