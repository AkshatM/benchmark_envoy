#!/bin/bash

taskset -c 2 'node /root/tcp_server.js' &

# run first batch of tests
durations=(1 5 10 20 30 60) 
for duration in ${durations[*]}; do
    taskset -c 3 '/root/baseline_envoy --concurrency 1 -c /root/envoy.yaml' &
    sleep 60
    echo "GET http://localhost:10000/" | vegeta attack -duration=${duration}s -rate=1 | tee /root/results_1rps_${duration}s_1concurrency_baseline_vegeta.log
    curl http://localhost:7000/stats > /root/results/results_1rps_${duration}s_1concurrency_baseline_envoystats.log
    pkill -f baseline_envoy
done
