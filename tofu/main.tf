terraform {
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
  image    = "ubuntu-22-04-x64"
  name     = "webserver-blog"
  region   = var.do_region
  size     = "s-1vcpu-512mb-10gb"
  ssh_keys = [digitalocean_ssh_key.default.id]

  user_data = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y docker.io docker-compose
    systemctl start docker
    systemctl enable docker

    mkdir -p /app
    cat <<EOC > /app/docker-compose.yml
    version: '3.8'
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

      observability:
        image: timberio/vector:0.34.1-distroless-static
        restart: always
        volumes:
          - /var/run/docker.sock:/var/run/docker.sock:ro
    EOC

    cd /app
    docker-compose up -d
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
