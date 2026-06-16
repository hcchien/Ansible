ARG ELIXIR_IMAGE=hexpm/elixir:1.19.5-erlang-28.5.0.2-debian-bookworm-20260610-slim
ARG RUNNER_IMAGE=debian:bookworm-slim

FROM ${ELIXIR_IMAGE} AS build

ENV MIX_ENV=prod

WORKDIR /app

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      git \
    && rm -rf /var/lib/apt/lists/*

# hex.pm's CDN (builds.hex.pm / repo.hex.pm, Fastly) intermittently serves a
# cert chain whose intermediate has keyUsage[keyCertSign] + EKU[serverAuth],
# which OTP's :ssl correctly rejects as key_usage_mismatch (erlang/otp
# GHSA-qw6r-qh9v-638v). This is NOT OTP-version-fixable. So:
#  - install hex over git (system TLS, not OTP :ssl → unaffected),
#  - install rebar3 from its GitHub release via curl (system TLS),
#  - fetch deps with HEX_UNSAFE_HTTPS: this only relaxes TRANSPORT cert
#    verification to repo.hex.pm; package integrity is still enforced by the
#    cryptographic checksums pinned in mix.lock.
RUN mix archive.install github hexpm/hex branch latest --force
RUN curl -fsSL https://github.com/erlang/rebar3/releases/latest/download/rebar3 \
      -o /usr/local/bin/rebar3 \
    && chmod +x /usr/local/bin/rebar3 \
    && mix local.rebar rebar3 /usr/local/bin/rebar3 --force
ENV HEX_UNSAFE_HTTPS=1

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
