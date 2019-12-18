#!/bin/bash

set -x 
apt-get update

install_system_dependencies() {
    curl -sL https://deb.nodesource.com/setup_10.x | bash -
    apt-get install -y git python nodejs cpuset linux-tools-common linux-tools-generic linux-tools-$(uname -r) tuned jq
    npm install -g forever
}

install_client() {
    curl -L https://raw.githubusercontent.com/AkshatM/bullseye/master/bullseye > /usr/bin/bullseye
    chmod +x /usr/bin/bullseye
}

install_envoy_and_bazel_dependencies() {
    # install Docker so we can grab Envoy
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
}

cleanup_envoy_and_bazel_dependencies() {
    # remove and destroy Docker altogether
    apt-get purge -y docker-engine docker docker.io docker-ce
    apt-get autoremove -y
    rm -rf /var/lib/docker /etc/docker
}

download_and_build_envoy() {
   
   set -e
   install_envoy_and_bazel_dependencies

   # pull official containing a version of Envoy 1.11.1 with debug symbols still in the binary.
   # Though built in an alpine environment, I've tested this still works on Ubuntu. 
   docker pull envoyproxy/envoy-alpine-debug:v1.11.1
   docker run --rm --entrypoint cat envoyproxy/envoy-alpine-debug /usr/local/bin/envoy > /root/baseline_envoy
   chmod +x /root/baseline_envoy

   cleanup_envoy_and_bazel_dependencies
   set +e
   echo "Build finished!"
}

install_system_dependencies
install_client
download_and_build_envoy

sysctl -w net.ipv4.tcp_low_latency=1
tuned-adm profile network-latency
# kernel module for power management is not enabled on DigitalOceans machines
#for ((i=0; i < 4; i++)); do 
#	echo performance > /sys/devices/system/cpu/cpu${i}/cpufreq/scaling_governor
#done
