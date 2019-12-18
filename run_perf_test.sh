#!/bin/bash

set -xe

# generate dedicated CPU sets for certain tasks
cset set --cpu=5,6 --set=node --cpu_exclusive
cset set --cpu=1,2,3,4 --set=envoy --cpu_exclusive
cset set --cpu=7 --set=client --cpu_exclusive
cset set --cpu=0 --set=system

rates=(100)
concurrencies=(4)
durations=(10)
header_profiles=(00000000)
envoy_config_types=(0000000)
#readarray -t header_profiles < /root/header_profiles 
#readarray -t envoy_config_types < /root/envoy_configs

for rate in ${rates[*]}; do
    for concurrency in ${concurrencies[*]}; do
	for duration in ${durations[*]}; do
	    for header_profile in ${header_profiles[*]}; do
	        for config_type in ${envoy_config_types[*]}; do
                    mkdir -p /root/results/"${config_type}"/"${rate}"/"${concurrency}"/"${duration}"/"${header_profile}"
		done
                mkdir -p /root/results/none/"${rate}"/"${concurrency}"/"${duration}"/"${header_profile}"
            done
        done
    done
done

# we use cpuset to run these processes, but cpuset is dumb and can't parse bash redirection operators
# as belonging to the root command, nor will it accept a string - only a filepath. So we create script files
# corresponding to it here.

function format_envoy_command() {
    # First argument is concurrency count for Envoy
    concurrency=${1}
    config_type=${2}
    echo "/root/baseline_envoy --concurrency ${concurrency} -c /root/envoy-${config_type}.yaml 2>&1 >/dev/null" > /root/run_envoy_baseline.sh
    chmod +x /root/run_envoy_baseline.sh
}

function format_node_command() {
    rate=${1}
    concurrency=${2}
    duration=${3}
    config_type=${4}
    header_profile=${5}

    echo "forever start /root/tcp_server.js /root/results/${config_type}/${rate}/${concurrency}/${duration}/${header_profile}/request_duration.csv" > /root/run_node.sh
    chmod +x /root/run_node.sh
}

function format_test_result_collection() {
    rate=${1}
    concurrency=${2}
    duration=${3}
    config_type=${4}
    header_profile=${5}
    
    # ping envoy in this case
    if [ "${4}" != "none" ]; then
        cat << EOF > /root/collect_results.sh
perf record -o /root/results/${config_type}/${rate}/${concurrency}/${duration}/${header_profile}/perf.data -p \$(pgrep -f "/root/baseline_envoy" | head -1) -g -- sleep ${duration} &
/usr/bin/bullseye "http://localhost:10000" ${header_profile} ${rate} ${duration} 1>/root/results/${config_type}/${rate}/${concurrency}/${duration}/${header_profile}/vegeta_success.plot 2>/root/results/${config_type}/${rate}/${concurrency}/${duration}/${header_profile}/vegeta_errors.plot
curl http://localhost:7000/stats > /root/results/${config_type}/${rate}/${concurrency}/${duration}/${header_profile}/envoy_metrics.log
pkill -INT -f "perf record"
EOF
    # otherwise don't ping Envoy, but the echo server directly
    else
        cat << EOF > /root/collect_results.sh
bullseye "http://localhost:8001" ${header_profile} ${rate} ${duration} > /root/results/${config_type}/${rate}/${concurrency}/${duration}/${header_profile}/vegeta.bin
EOF
    fi
    
    chmod +x /root/collect_results.sh
}

function run_test() {

   # move all running threads to different CPUs
   cset proc --move --kthread --fromset=root --toset=system --force

   for concurrency in ${concurrencies[*]}; do
       for rate in ${rates[*]}; do
           for duration in ${durations[*]}; do
	       for header_profile in ${header_profiles[*]}; do

                   # start node as baseline
		   format_node_command "${rate}" "${concurrency}" "${duration}" "none" "${header_profile}"

		   while ! pgrep --full node ; do
		   	   screen -dm bash -c 'cset proc --set=node --exec bash -- -c /root/run_node.sh' 
			   sleep 10
		   done

	           # get numbers without Envoy
                   format_test_result_collection "${rate}" "${concurrency}" "${duration}" "none" "${header_profile}"
                   cset proc --set=client --exec bash -- -c /root/collect_results.sh
		   
		   # kill node
		   forever stopall

	           # get numbers with Envoy - we run in a screen because cset doesn't handle & correctly
                   for config_type in ${envoy_config_types[*]}; do

                       # start node
		       format_node_command "${rate}" "${concurrency}" "${duration}" "${config_type}" "${header_profile}"
		       while ! pgrep --full tcp_server.js ; do
		       	       screen -dm bash -c 'cset proc --set=node --exec bash -- -c /root/run_node.sh' 
			       sleep 10
		       done
                       
		       format_envoy_command "${concurrency}" "${config_type}"
		       while ! pgrep --full /root/baseline_envoy ; do
	                       screen -dm bash -c "cset proc --set=envoy --exec bash -- -c /root/run_envoy_baseline.sh"
			       sleep 10
		       done
	               
		       if pgrep --full /root/baseline_envoy && pgrep --full tcp_server.js; then
		       		format_test_result_collection "${rate}" "${concurrency}" "${duration}" "${config_type}" "${header_profile}"
	               		cset proc --set=client --exec bash -- -c /root/collect_results.sh && kill -9 "$(pgrep -f '/root/baseline_envoy')"

	       	       fi
		       forever stopall
		   done
	       done
	   done
       done
   done
}

run_test
