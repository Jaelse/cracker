packer {
  required_plugins {
    hcloud = {
      source  = "github.com/hetznercloud/hcloud"
      version = "~> 1"
    }
  }
}

variable "hcloud_token" {
  type      = string
  sensitive = true
}

variable "server_type" {
  type    = string
  default = "cpx22"
}

variable "location" {
  type    = string
  default = "hel1"
}

variable "ssh_key_names" {
  type    = list(string)
  default = []
}

locals {
  timestamp     = regex_replace(timestamp(), "[- TZ:]", "")
  snapshot_name = "ubuntu-24-openclaw-${local.timestamp}"
}

source "hcloud" "ubuntu24-openclaw" {
  token = var.hcloud_token

  image       = "ubuntu-24.04"
  server_type = var.server_type
  location    = var.location

  snapshot_name = local.snapshot_name
  snapshot_labels = {
    app     = "openclaw"
    managed = "packer"
  }

  ssh_keys     = var.ssh_key_names
  communicator = "ssh"
  ssh_username = "root"
  user_data    = file("cloud-init-openclaw.yaml")
}

build {
  sources = ["source.hcloud.ubuntu24-openclaw"]

  provisioner "shell" {
    inline           = ["cloud-init status --wait"]
    valid_exit_codes = [0, 2]
  }

  provisioner "file" {
    source      = "scripts/cleanup.sh"
    destination = "/tmp/cleanup.sh"
  }

  provisioner "shell" {
    script = "scripts/provision_openclaw.sh"
  }

  provisioner "file" {
    source      = "scripts/openclaw-start.sh"
    destination = "/tmp/openclaw-start.sh"
  }

  provisioner "shell" {
    script = "scripts/install_openclaw.sh"
  }
}
