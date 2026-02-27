FROM elixir:1.19.5-slim AS build

RUN apt-get update && \
    apt-get install -y build-essential bash ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

COPY config config
COPY assets assets
COPY lib lib
COPY priv/templates priv/templates

RUN mkdir -p priv/static/css && \
    mix sass.install && \
    mix sass default && \
    mix assets.build

RUN mix compile --warnings-as-errors

RUN mix release

FROM debian:trixie-slim AS app

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y openssl ca-certificates wget && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

RUN groupadd -r webserver && useradd -r -g webserver webserver

WORKDIR /app
COPY --from=build --chown=webserver:webserver /app/_build/prod/rel/webserver ./

USER webserver

EXPOSE 4040

HEALTHCHECK --interval=60s --timeout=3s --start-period=30s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:4040/health || exit 1

CMD ["bin/webserver", "start"]
