# blog

A custom blog server built with Elixir. No Phoenix, no framework. Just Plug and Bandit, a hand-rolled template engine, and ETS for caching.

## Features

- **Custom Templating**: Nested partials and named slots with recursive parsing.
- **ETS Caching**: Concurrent template serving with automatic, event-driven invalidation.
- **SCSS Support**: Modular design system built with Dart Sass and hot-reloading.
- **LiveReload**: Instant browser style patching and page refreshes via SSE.
- **Page Registry**: Centralized `pages.json` for URL management and dynamic `sitemap.xml`.
- **Infrastructure**: Automated deployment to DigitalOcean via OpenTofu and Watchtower.

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

Run before pushing:
```bash
mix check
```
Runs formatting, Credo (linting), Dialyzer (types), and the test suite.

## Deployment

### Docker

Images are built by CI and pushed to GHCR on every merge to `main`.

Manual build:
```bash
docker build -t ghcr.io/frodi-karlsson/blog:latest .
```

### Infrastructure (OpenTofu)

The app runs on a DigitalOcean Droplet ($4/mo) using Docker Compose. Watchtower polls GHCR every 30 seconds and restarts the container when a new image is available.

1. Setup your secrets:
   ```bash
   cp tofu/terraform.tfvars.example tofu/terraform.tfvars
   # Fill in cloudflare_token, cloudflare_zone_id, and do_token
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
- Launching the app, an observability sidecar, and Watchtower.

## Content Management

### Blog Posts
1. Add a new `.html` file to `priv/templates/pages/`.
2. Add the post metadata to `priv/templates/blog.json`.
3. The index at `/` will update automatically.

### Pages
Manage all site pages in `priv/templates/pages.json`. Use `"noindex": true` to exclude pages (like admin tools) from the sitemap.
