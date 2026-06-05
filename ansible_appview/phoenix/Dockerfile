ARG ELIXIR_IMAGE=hexpm/elixir:1.16.3-erlang-26.2.5.12-debian-bookworm-20260202-slim
ARG RUNNER_IMAGE=debian:bookworm-slim

FROM ${ELIXIR_IMAGE} AS build

ENV MIX_ENV=prod

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      git \
    && rm -rf /var/lib/apt/lists/*

RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config ./config

RUN mix deps.get --only prod
RUN mix deps.compile

COPY lib ./lib
COPY priv ./priv

RUN mix compile
RUN mix release

FROM ${RUNNER_IMAGE}

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      ca-certificates \
      libstdc++6 \
      libncurses6 \
      openssl \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8 \
    MIX_ENV=prod \
    PORT=8080

WORKDIR /app

RUN addgroup --system app \
    && adduser --system --ingroup app --home /app app

COPY --from=build --chown=app:app /app/_build/prod/rel/ansible_appview ./

USER app

EXPOSE 8080

CMD ["/app/bin/ansible_appview", "start"]
