# blog

A custom blog server built with Elixir. No Phoenix, no framework. Just Plug and Bandit, a hand-rolled template engine, and ETS for caching.

## Features

- **Custom Templating**: Nested partials and named slots with recursive parsing.
- **ETS Caching**: Concurrent template serving with automatic, event-driven invalidation.
- **SCSS Support**: Modular design system built with Dart Sass and hot-reloading.
- **LiveReload**: Instant browser style patching and page refreshes via SSE.
- **Front-Matter Content**: Metadata embedded in page files drives the blog index and `sitemap.xml` automatically.
- **Infrastructure**: Automated deployment to DigitalOcean via OpenTofu and Watchtower.

## Local Development

### Prerequisites

- Elixir 1.19+ & Erlang 27+
- System deps (used by `mix assets.build`):
  - `vips` and `vipsheader` (libvips)
  - `cwebp` (WebP tools)
- Sass (Dart Sass installed automatically via `mix sass.install`)

### Setup

1. Install dependencies:
   ```bash
   mix deps.get
   ```
2. Setup Sass binary:
   ```bash
   mix sass.install
   ```
3. Verify system deps:
   ```bash
   vips --version
   vipsheader --version
   cwebp -version
   ```
4. Start the server:
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

Metadata lives in each page file as front-matter — no separate JSON files to keep in sync.

### New blog post

```bash
mix webserver.new_post "My Post Title"
```

Creates `priv/templates/pages/my-post-title.html` pre-filled with front-matter and the `blog_post.html` template. Fill in `category`, `summary`, and write the content — the blog index and sitemap update automatically on the next request.

### Front-matter reference

```
---
title: My Post Title
date: 2026-02-25        # ISO 8601; shown as "Feb 25, 2026" on the index
category: Elixir
summary: One-line description shown on the blog index card.
noindex: true           # Omit from sitemap (e.g. admin pages)
---
```

A page is treated as a blog post (and appears on the index) when it has both `date` and `summary`. Pages without front-matter are still served but won't appear in the sitemap.
