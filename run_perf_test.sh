#!/bin/bash

set -xe

mkdir /root/results

cset set --cpu=2 --set=node --cpu_exclusive
cset set --cpu=3 --set=envoy --cpu_exclusive
cset set --cpu=0,1 --set=system
cset proc --move --kthread --fromset=root --toset=system --force

screen -dm bash -c 'cset proc --set=node --exec bash -- -c /root/run_node.sh'

# run first batch of tests
durations=(1 5 10 20 30 60) 
for duration in ${durations[*]}; do
    screen -dm bash -c 'cset proc --set=envoy --exec bash -- -c /root/run_envoy.sh'
    sleep 10
    echo "GET http://localhost:10000/" | vegeta attack -duration=${duration}s -rate=1 > /root/results/results_1rps_${duration}s_1concurrency_baseline_vegeta.log
    curl http://localhost:7000/stats > /root/results/results_1rps_${duration}s_1concurrency_baseline_envoystats.log
    pkill -f baseline_envoy
done
