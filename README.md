# About

Yet another Envoy benchmark framework.

Tests Envoy specifically against a TCP echo server.

# Architecture

This repository builds a DigitalOcean image containing all our dependencies using Packer, and provides a Terraform script to launch a machine that will perform perf tests.

In the image, Envoy 1.11.1 is compiled into a baseline binary.

We use `cpuset/cset` to pin envoy and the upstream to their own CPUs, disallowing all but kernel threads to run on these CPUs. This ensures a quiesced system. Hyperthreading is not enabled in any vCPUs in the images we use to build and work with. Unfortunately, because we're using a cloud machine, access to power settings via `tuned-adm` or similar will likely not work so we eschew setting this.  The image uses Intel Xeon processors.

[A custom load testing tool](https://github.com/AkshatM/bullseye) is used to send requests to our Envoy. We run them separately, not in parallel, to avoid network issues and to be able to chart the impact on CPU.

# Development and Usage

## Dependencies

You need Make, Packer and Terraform 0.12 installed. For Terraform, I strongly recommed using https://warrensbox.github.io/terraform-switcher/ to install your Terraform for you. For Packer, use https://github.com/robertpeteuil/packer-installer.

Add an `env.tfvars` file with the following content:

```
do_token = "<your DigitalOcean API token, retrieved from the website>"
user_ssh_key_name = "<name of the SSH key you've registered with DigitalOcean"
```

## Usage Instructions
Then, to build the image:

```
cd image
make pack
```

Once done, `cd` back into the parent directory and run:

```
make build
```

This will launch a machine for you. 

It is advised to wait about 5 minutes after machine creation for all of the perf tests to finish before SSHing in. 

Then `make connect` will SSH you in using the SSH key defined in `env.tfvars`. 
