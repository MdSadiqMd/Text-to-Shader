FROM elixir:1.15-alpine AS builder

ENV MIX_ENV=prod

RUN apk add --no-cache build-base git

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

COPY mix.exs mix.lock ./

RUN mix deps.get --only $MIX_ENV

COPY lib ./lib

RUN mix compile && \
    mix release

FROM alpine:3.18

RUN apk add --no-cache bash openssl libstdc++ libgcc

WORKDIR /app

COPY --from=builder /app/_build/prod/rel/text_to_shader ./

ENV PORT=4000
EXPOSE $PORT

ENTRYPOINT ["/app/bin/text_to_shader"]
CMD ["start"]