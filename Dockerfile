FROM debian:trixie-slim AS adder
ADD https://github.com/sass/dart-sass/releases/download/1.83.4/dart-sass-1.83.4-linux-x64.tar.gz /
RUN tar -xvzf /dart-sass-1.83.4-linux-x64.tar.gz

FROM elixir:1.19.5-slim AS build

RUN apt-get update && \
    apt-get install -y build-essential bash ca-certificates && \
    rm -rf /var/lib/apt/lists/*

COPY --from=adder /dart-sass /usr/local/bin/

WORKDIR /app

ENV MIX_ENV=prod

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod
RUN mix deps.compile

COPY config config
COPY assets assets
COPY lib lib
COPY priv priv

RUN mkdir -p priv/static/css && \
    mix sass.install && \
    mix sass default

RUN mix release

FROM debian:trixie-slim AS app

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
