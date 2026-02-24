# Webserver

A lightweight template server built with Elixir, Plug, and Bandit. Designed for performance and simplicity.

## Features

- **Custom Templating**: Nested partials and named slots with recursive parsing.
- **ETS Caching**: Concurrent template serving with automatic, event-driven invalidation.
- **SCSS Support**: Modular design system built with Dart Sass and hot-reloading.
- **LiveReload**: Instant browser style patching and page refreshes via SSE.
- **Page Registry**: Centralized `pages.json` for URL management and dynamic `sitemap.xml`.
- **Infrastructure**: Automated deployment to DigitalOcean via OpenTofu.

## Local Development

### Prerequisites

- Elixir 1.19+ & Erlang 27+
- Sass (installed automatically via `mix sass.install`)

### Setup

1. Install dependencies:
   ```bash
   mix deps.get
   ```
2. Setup Sass binary:
   ```bash
   mix sass.install
   ```
3. Start the server:
   ```bash
   iex -S mix
   ```
   Access the server at `http://localhost:4040`.

### Quality Checks

The project enforces strict standards. Before pushing, run:
```bash
mix check
```
This runs formatting, Credo (linting), Dialyzer (types), and the test suite.

## Deployment

### Docker

The project uses GHCR for hosting images. The CI pipeline builds and pushes the image on every change to `main`.

Manual build:
```bash
docker build -t ghcr.io/your-username/webserver:latest .
```

### Infrastructure (OpenTofu)

The application is deployed to a DigitalOcean Droplet ($4/mo) using Docker Compose.

1. Setup your secrets:
   ```bash
   cp tofu/terraform.tfvars.example tofu/terraform.tfvars
   # Fill in clouflare_token, cloudflare_zone_id, and do_token
   ```
2. Deploy:
   ```bash
   cd tofu
   tofu init
   tofu apply
   ```

The Tofu code handles:
- Provisioning the Droplet.
- Configuring Cloudflare DNS (proxied).
- Launching the app and an observability sidecar.

## Content Management

### Blog Posts
1. Add a new `.html` file to `priv/templates/pages/`.
2. Add the post metadata to `priv/templates/blog.json`.
3. The index at `/` will update automatically.

### Pages
Manage all site pages in `priv/templates/pages.json`. Use `"noindex": true` to exclude pages (like admin tools) from the sitemap.
