#!/bin/bash

set -xe

# we use cpuset to run these processes, but cpuset is dumb and can't parse bash redirection operators
# as belonging to the root command, nor will it accept a string - only a filepath. So we create these here.

function format_envoy_command() {
    # First argument is concurrency count
    echo "/root/baseline_envoy --concurrency ${1} -c /root/envoy.yaml 2>&1 >/dev/null" > /root/run_envoy_baseline.sh
    echo "/root/aslrfied_envoy --concurrency ${1} -c /root/envoy.yaml 2>&1 >/dev/null" > /root/run_envoy_aslrfied.sh
    chmod +x /root/run_envoy_baseline.sh
    chmod +x /root/run_envoy_aslrfied.sh
}

function format_node_command() {
    npm install -g forever
    echo "forever start /root/tcp_server.js" > /root/run_node.sh
    chmod +x /root/run_node.sh
}

cset set --cpu=2 --set=node --cpu_exclusive
cset set --cpu=3 --set=envoy --cpu_exclusive
cset set --cpu=0,1 --set=system

rates=(10 100 1000)
concurrencies=(1 2)
durations=(1 5 10 20 30 60 120 300) 

for rate in ${rates[*]}; do
    for concurrency in ${concurrencies[*]}; do
	for duration in ${durations[*]}; do
            mkdir -p /root/results/baseline/vegeta/${rate}/${concurrency}/${duration}
            mkdir -p /root/results/none/vegeta/${rate}/${concurrency}/${duration}
            mkdir -p /root/results/aslr/vegeta/${rate}/${concurrency}/${duration}
            mkdir -p /root/results/baseline/envoystats/${rate}/${concurrency}/${duration}
            mkdir -p /root/results/baseline/envoystats/${rate}/${concurrency}/${duration}
            mkdir -p /root/results/aslr/envoystats/${rate}/${concurrency}/${duration}
            mkdir -p /root/results/aslr/envoystats/${rate}/${concurrency}/${duration}
        done
    done
done

function format_test_result_collection() {
    # ping envoy in this case
    if [ "${4}" = "baseline" ] || [ "${4}" = "aslr" ]; then
        cat << EOF > /root/collect_results.sh
echo "GET http://localhost:10000/" | vegeta attack -duration=${3} -rate=${1} > /root/results/${4}/vegeta/${1}/${2}/${3}
curl http://localhost:7000/stats > /root/results/${4}/envoystats/${1}/${2}/${3}
perf stat
EOF
    else
        cat << EOF > /root/collect_results.sh
echo "GET http://localhost:8001/" | vegeta attack -duration=${3} -rate=${1} > /root/results/${4}/vegeta/${1}/${2}/${3}
EOF
    fi
    
    chmod +x /root/collect_results.sh
}


function run_test() {

   cset proc --move --kthread --fromset=root --toset=system --force

   format_node_command
   screen -dm bash -c 'cset proc --set=node --exec bash -- -c /root/run_node.sh'

   for concurrency in ${concurrencies[*]}; do
       for rate in ${rates[*]}; do
           for duration in ${durations[*]}; do
               format_test_result_collection ${rate} ${concurrency} ${duration} "none"

               cset proc --set=system --exec bash -- -c /root/collect_results.sh
               pkill -f aslrfied_envoy
           done

	   format_envoy_command ${concurrency}

	   for duration in ${durations[*]}; do
	       screen -dm bash -c 'cset proc --set=envoy --exec bash -- -c /root/run_envoy_baseline.sh'
	       sleep 10
	       screen -dm bash -c "perf stat record -o /root/results/baseline/envoystats/${rate}/${concurrency}/${duration}/perf.data -p $(pgrep /root/baseline_envoy)"
	       format_test_result_collection ${rate} ${concurrency} ${duration} "baseline"

               cset proc --set=system --exec bash -- -c /root/collect_results.sh
               pkill -f baseline_envoy
           done
           
           for duration in ${durations[*]}; do
               screen -dm bash -c 'cset proc --set=envoy --exec bash -- -c /root/run_envoy_aslrfied.sh'
	       sleep 10
	       screen -dm bash -c "perf stat record -o /root/results/aslr/envoystats/${rate}/${concurrency}/${duration}/perf.data -p $(pgrep /root/aslrfied_envoy)"
               format_test_result_collection ${rate} ${concurrency} ${duration} "aslr"

               cset proc --set=system --exec bash -- -c /root/collect_results.sh
               pkill -f aslrfied_envoy
           done
       done
   done
}

run_test
