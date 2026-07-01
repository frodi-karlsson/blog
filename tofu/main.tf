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
  size       = "s-1vcpu-1gb"
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
      proxy:
        image: traefik:v3.7.6
        restart: always
        ports:
          - "80:80"
        volumes:
          - /var/run/docker.sock:/var/run/docker.sock:ro
        environment:
          - DOCKER_API_VERSION=1.44
        command:
          - --providers.docker=true
          - --providers.docker.exposedbydefault=false
          - --entrypoints.web.address=:80
        logging:
          driver: "json-file"
          options:
            max-size: "10m"
            max-file: "3"

      app:
        image: ghcr.io/frodi-karlsson/blog:${var.image_tag}
        restart: always
        expose:
          - "4040"
        environment:
          - PORT=4040
          - ADMIN_USERNAME=${var.admin_username}
          - ADMIN_PASSWORD=${var.admin_password}
        stop_grace_period: 20s
        deploy:
          replicas: 2
        healthcheck:
          test: ["CMD", "wget", "-q", "-O", "/dev/null", "http://127.0.0.1:4040/health"]
          interval: 10s
          timeout: 3s
          retries: 3
          start_period: 30s
        labels:
          - "com.centurylinklabs.watchtower.scope=blog"
          - "traefik.enable=true"
          - "traefik.http.routers.blog.entrypoints=web"
          - "traefik.http.routers.blog.rule=PathPrefix(\`/\`)"
          - "traefik.http.services.blog.loadbalancer.server.port=4040"
        logging:
          driver: "json-file"
          options:
            max-size: "10m"
            max-file: "3"

      watchtower:
        image: containrrr/watchtower:1.7.1
        restart: always
        volumes:
          - /var/run/docker.sock:/var/run/docker.sock
        environment:
          - DOCKER_API_VERSION=1.44
          - WATCHTOWER_POLL_INTERVAL=30
          - WATCHTOWER_CLEANUP=true
          - WATCHTOWER_SCOPE=blog
          - WATCHTOWER_ROLLING_RESTART=true
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
    source_addresses = var.ssh_allowed_cidrs
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
