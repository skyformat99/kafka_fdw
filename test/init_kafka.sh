#!/bin/bash
: ${PG_PORT:=5432}
: ${KAFKA_PRODUCER:="/usr/local/bin/kafka-console-producer"}
: ${KAFKA_TOPICS:="/usr/local/bin/kafka-topics"}
: ${KAFKA_CONFIG:="/usr/local/bin/kafka-configs"}


topics=( contrib_regress4 contrib_regress contrib_regress_prod contrib_regress_prod_json contrib_regress_junk contrib_regress_json contrib_regress_json_junk )
partitions=( 4 1 4 4 1 1 1 )

declare -a toppart
index=0

for t in "${topics[@]}"; do
  toppart[$index]="--topic ${t} --partitions ${partitions[${index}]}"
  ((index++))
done

out_sql="SELECT i as int_val, 'It''s some text, that is for number '||i as text_val, ('2015-01-01'::date + (i || ' seconds')::interval)::date as date_val, ('2015-01-01'::date + (i || ' seconds')::interval)::timestamp as time_val FROM generate_series(1,1e6::int, 10) i ORDER BY i"
kafka_cmd="$KAFKA_PRODUCER --broker-list localhost:9092 --topic"
kafka_config_cmd="$KAFKA_CONFIG --zookeeper localhost:2181 --entity-type topics"

# delete topic if it might exist
topics+=(contrib_regress_retained)
for t in "${topics[@]}"; do $KAFKA_TOPICS --zookeeper localhost:2181 --delete --topic ${t} & done; wait


# create topics with partitions
for t in "${toppart[@]}"; do $KAFKA_TOPICS --zookeeper localhost:2181 --create ${t} --replication-factor 1 & done; wait

# write some test data to json topicc
psql -c "COPY(SELECT json_build_object('int_val',int_val, 'text_val',text_val, 'date_val',date_val, 'time_val', time_val ) FROM (${out_sql}) t) TO STDOUT (FORMAT TEXT);" -d postgres -p $PG_PORT -o "| ${kafka_cmd} contrib_regress_json" >/dev/null &

# write some test data to csv topicc
for t in contrib_regress contrib_regress4; do psql -c "COPY(${out_sql}) TO STDOUT (FORMAT CSV);" -d postgres -p $PG_PORT -o "| ${kafka_cmd} ${t}" >/dev/null & done; wait


$kafka_cmd contrib_regress_junk <<-EOF
91,"correct line",01-01-2015,Thu Jan 01 01:31:00 2015
131,"additional data",01-01-2015,Thu Jan 01 02:11:00 2015,aditional data
161,"additional data although null",01-01-2015,Thu Jan 01 02:41:00 2015,
301,"correct line although last line null",01-01-2015,
371,"invalidat date",invalid_date,Thu Jan 01 06:11:00 2015
401,"unterminated string","01-01-2015,Thu Jan 01 06:41:00 2015
421,"correct line",01-01-2015,Thu Jan 01 07:01:00 2015
999999999999999,"invalid number",01-01-2015,Thu Jan 01 07:11:00 2015
521,"correct line",01-01-2015,Thu Jan 01 08:41:00 2015
foo,"invalid number, invalid date and extra data",20-20-2015,Thu Jan 01 09:31:00 2015,extra data
"401,unterminated string,01-01-2015,Thu Jan 01 06:41:00 2015
EOF


$kafka_cmd contrib_regress_json_junk <<-EOF
{"int_val" : 999741, "text_val" : "correct line", "date_val" : "2015-01-12", "time_val" : "2015-01-12T13:42:21"}
{"int_val" : 999751, "text_val" : "additional data", "date_val" : "2015-01-12", "time_val" : "2015-01-12T13:42:31", "more_val": "to much data"}
{"int_val" : 999761, "text_val" : "additional data although null", "date_val" : "2015-01-12", "time_val" : "2015-01-12T13:42:41", "more_val": null}
{"int_val" : 999781, "text_val" : "invalidat date", "date_val" : "foob", "time_val" : "2015-01-12T13:43:01", "time_val": "2015-01-12T13:42:51"}
{"int_val" : 999791, "text_val" : "invalid json (unterminated quote)", "date_val" : "2015-01-12", "time_val : "2015-01-12T13:43:11"}
{"int_val" : 999801, "text_val" : "correct line", "date_val" : "2015-01-12", "time_val" : "2015-01-12T13:43:21"}
{"int_val" : 9998119999999999, "text_val" : "invalid number", "date_val" : "2015-01-12", "time_val" : "2015-01-12T13:43:31"}
{"int_val" : 999821, "text_val" : "correct line", "date_val" : "2015-01-12", "time_val" : "2015-01-12T13:43:41"}
{"int_val" : "9998119999999999",  "text_val" : "invalid number, invalid date and extra data", "date_val" : "2015-13-13", "time_val" : "2015-01-12T13:43:51", "foo": "just to much"}
{"int_val" : 999841, "text_val" : "empty time" , "date_val" : "2015-01-12", "time_val" : ""}
{"int_val" : 999851, "text_val" : "correct line null time", "date_val" : "2015-01-12", "time_val" : null}
{"int_val" : 999871, "invalid json no time" : "invalid json", "date_val" : "2015-01-12", "time_val" : }
EOF


$KAFKA_TOPICS --zookeeper localhost:2181 --create --topic contrib_regress_retained --partitions 1 --replication-factor 1 --config retention.ms=10 --config file.delete.delay.ms=10

$kafka_cmd contrib_regress_retained <<-EOF
1,"correct line",01-01-2015,Thu Jan 01 01:31:00 2015
2,"correct line",01-01-2015,Thu Jan 01 01:31:00 2015
3,"correct line",01-01-2015,Thu Jan 01 01:31:00 2015
EOF

# $kafka_config_cmd --alter --add-config retention.ms=100,file.delete.delay.ms=100 --entity-name contrib_regress_retained
sleep 3
$kafka_config_cmd --alter --delete-config retention.ms --entity-name contrib_regress_retained


$kafka_cmd contrib_regress_retained <<-EOF
4,"correct line",01-01-2015,Thu Jan 01 01:31:00 2015
5,"correct line",01-01-2015,Thu Jan 01 01:31:00 2015
6,"correct line",01-01-2015,Thu Jan 01 01:31:00 2015
EOF

kafka-console-consumer --bootstrap-server localhost:9092 --topic contrib_regress_retained --from-beginning --timeout-ms 100