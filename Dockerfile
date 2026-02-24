FROM elixir:1.19.5-slim AS build

RUN apt-get update && \
    apt-get install -y build-essential bash ca-certificates curl && \
    rm -rf /var/lib/apt/lists/*
WORKDIR /app

COPY mix.exs mix.lock ./
RUN mix deps.get && \
    mix deps.compile

COPY config config
COPY lib lib
COPY priv priv

RUN MIX_ENV=prod mix release

FROM debian:trixie-slim AS app
RUN apt-get update && apt-get install -y openssl ca-certificates

WORKDIR /app
COPY --from=build /app/_build/prod/rel/webserver ./
CMD ["bin/webserver", "start"]