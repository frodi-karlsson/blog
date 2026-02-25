terraform {
  required_version = ">= 1.6.0"
  required_providers {
    digitalocean = {
      source  = "digitalocean/digitalocean"
      version = "~> 2.77"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

provider "digitalocean" {
  token = var.do_token
}

provider "cloudflare" {
  api_token = var.cloudflare_token
}

resource "digitalocean_ssh_key" "default" {
  name       = "webserver-blog-key"
  public_key = file(var.ssh_public_key_path)
}

resource "digitalocean_droplet" "blog" {
  image      = "ubuntu-24-04-x64"
  name       = "webserver-blog"
  region     = var.do_region
  size       = "s-1vcpu-512mb-10gb"
  ssh_keys   = [digitalocean_ssh_key.default.id]
  monitoring = true

  user_data = <<-EOF
    #!/bin/bash
    set -euo pipefail

    exec > /var/log/cloud-init-user-data.log 2>&1
    echo "=== Starting cloud-init at $(date) ==="

    apt-get update
    apt-get install -y docker.io docker-compose-v2 unattended-upgrades

    systemctl start docker
    systemctl enable docker

    echo "Docker installed, waiting for daemon..."
    sleep 5
    docker version

    mkdir -p /app
    cat <<EOC > /app/docker-compose.yml
    services:
      app:
        image: ghcr.io/frodi-karlsson/elixir-learning-server:${var.image_tag}
        restart: always
        ports:
          - "80:4040"
        environment:
          - PORT=4040
        logging:
          driver: "json-file"
          options:
            max-size: "10m"
            max-file: "3"
        labels:
          - "com.centurylinklabs.watchtower.scope=blog"

      watchtower:
        image: containrrr/watchtower:latest
        restart: always
        volumes:
          - /var/run/docker.sock:/var/run/docker.sock
        environment:
          - WATCHTOWER_POLL_INTERVAL=30
          - WATCHTOWER_CLEANUP=true
          - WATCHTOWER_SCOPE=blog
        labels:
          - "com.centurylinklabs.watchtower.scope=blog"

      observability:
        image: timberio/vector:0.34.1-distroless-static
        restart: always
        volumes:
          - /var/run/docker.sock:/var/run/docker.sock:ro
    EOC

    cd /app
    docker compose up -d

    echo "=== Cloud-init completed at $(date) ==="
  EOF
}

resource "cloudflare_dns_record" "blog" {
  zone_id = var.cloudflare_zone_id
  name    = "blog"
  content = digitalocean_droplet.blog.ipv4_address
  type    = "A"
  proxied = true
  ttl     = 1
}

resource "digitalocean_firewall" "blog" {
  name        = "webserver-blog-fw"
  droplet_ids = [digitalocean_droplet.blog.id]

  inbound_rule {
    protocol         = "tcp"
    port_range       = "22"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "tcp"
    port_range       = "80"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  inbound_rule {
    protocol         = "icmp"
    source_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "tcp"
    port_range            = "all"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "udp"
    port_range            = "all"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }

  outbound_rule {
    protocol              = "icmp"
    destination_addresses = ["0.0.0.0/0", "::/0"]
  }
}
