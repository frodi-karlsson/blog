variable "cloudflare_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_zone_id" {
  type = string
}

variable "do_token" {
  type      = string
  sensitive = true
}

variable "do_region" {
  type    = string
  default = "fra1"
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "ssh_allowed_cidrs" {
  type    = list(string)
  default = ["0.0.0.0/0", "::/0"]
}

variable "admin_username" {
  type      = string
  sensitive = true
}

variable "admin_password" {
  type      = string
  sensitive = true
}
