variable "do_token" {
	description = "Your DigitalOcean API token. Get this from the DigitalOcean website."
}

variable "user_ssh_key_name" {
	description = "Registered name of the SSH key attached to your Digitalocean account."
}

provider "digitalocean" {
	token = "${var.do_token}"
}

data "digitalocean_ssh_key" "user" {
        name = "${var.user_ssh_key_name}"
}

# Create a web server
resource "digitalocean_droplet" "benchmark_machine" {
	image  = "ubuntu-18-04-x64"
	name   = "benchmark-instance-1"
	region = "blr1"
	size   = "s-2vcpu-2gb"
        ssh_keys = ["${data.digitalocean_ssh_key.user.id}"]
        user_data = "${file('bootstrap.sh')}"
}
