#!/bin/bash

set -xe

chmod +x /root/helpers.sh

# generate dedicated CPU sets for certain tasks
cset set --cpu=5,6 --set=node --cpu_exclusive
cset set --cpu=1,2,3,4 --set=envoy --cpu_exclusive
cset set --cpu=7 --set=client --cpu_exclusive
cset set --cpu=0 --set=system

rates=(100)
concurrencies=(4)
durations=(10)
header_types=( $(seq 1 324) )
envoy_config_types=( $(seq 1 126) )

for rate in ${rates[*]}; do
    for concurrency in ${concurrencies[*]}; do
	for duration in ${durations[*]}; do
	    for header_type in ${header_types[*]}; do
	        for envoy_config_type in ${envoy_config_types[*]}; do
                    mkdir -p /root/results/${envoy_config_type}/${rate}/${concurrency}/${duration}/${header_type}
		done
                mkdir -p /root/results/none/${rate}/${concurrency}/${duration}/${header_type}
            done
        done
    done
done

# we use cpuset to run these processes, but cpuset is dumb and can't parse bash redirection operators
# as belonging to the root command, nor will it accept a string - only a filepath. So we create script files
# corresponding to it here.

function format_envoy_command() {
    # First argument is concurrency count for Envoy
    echo "/root/baseline_envoy --concurrency ${1} -c /root/envoy-${2}.yaml 2>&1 >/dev/null" > /root/run_envoy_baseline.sh
    chmod +x /root/run_envoy_baseline.sh
}

function format_node_command() {
    echo "forever start /root/tcp_server.js" > /root/run_node.sh
    chmod +x /root/run_node.sh
}

function format_test_result_collection() {
    # ping envoy in this case
    if [ "${4}" != "none" ]; then
        cat << EOF > /root/collect_results.sh
perf record -o /root/results/${4}/${1}/${2}/${3}/perf.data -p \$(pgrep -f "/root/baseline_envoy" | head -1) -C 3 -g -- sleep ${duration} &
generate_target "http://localhost:10000" ${5} | vegeta attack -format=json -duration=${3}s -rate=${1}/s > /root/results/${4}/${1}/${2}/${3}/${5}/vegeta.bin
curl http://localhost:7000/stats > /root/results/${4}/${1}/${2}/${3}/${5}envoy_metrics.log
pkill -INT -f "perf record"
EOF
    # otherwise don't ping Envoy, but the echo server directly
    else
        cat << EOF > /root/collect_results.sh
generate_target "http://localhost:8001" ${5} | vegeta attack -format=json -duration=${3}s -rate=${1}/s > /root/results/${4}/${1}/${2}/${3}/${5}/vegeta.bin
EOF
    fi
    
    chmod +x /root/collect_results.sh
}

function run_test() {

   # move all running threads to different CPUs
   cset proc --move --kthread --fromset=root --toset=system --force

   # start node
   format_node_command
   screen -dm bash -c 'cset proc --set=node --exec bash -- -c /root/run_node.sh'

   for concurrency in ${concurrencies[*]}; do
       for rate in ${rates[*]}; do
           for duration in ${durations[*]}; do
	       for header_type in ${header_types[*]}; do

	           # get numbers without Envoy
                   format_test_result_collection ${rate} ${concurrency} ${duration} "none" ${header_type}
                   cset proc --set=client --exec bash -- -c /root/collect_results.sh

	           # get numbers with Envoy - we run in a screen because cset doesn't handle & correctly
                   for config_type in ${envoy_config_types[*]}; do
                       
		       format_envoy_command ${concurrency} ${config_type}

	               screen -dm bash -c "cset proc --set=envoy --exec bash -- -c /root/run_envoy_baseline.sh"
		       # wait for Envoy to finish initializing 
	               sleep 10
	               
		       format_test_result_collection ${rate} ${concurrency} ${duration} ${config_type} ${header_type}
	               cset proc --set=client --exec bash -- -c /root/collect_results.sh && kill -9 $(pgrep -f "/root/baseline_envoy")
		   done
	       done
	   done
       done
   done
}

run_test
