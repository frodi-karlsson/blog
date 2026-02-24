FROM elixir:1.19.5-slim AS build

RUN apt-get update && \
    apt-get install -y build-essential bash ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod && \
    mix deps.compile

COPY config config
COPY lib lib
COPY priv priv

RUN MIX_ENV=prod mix release

FROM debian:bookworm-slim AS app

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y openssl ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /app/_build/prod/rel/webserver ./

EXPOSE 4040
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD bash -c '</dev/tcp/localhost/4040' || exit 1

CMD ["bin/webserver", "start"]
