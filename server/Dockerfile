FROM dart:stable AS build

WORKDIR /app

COPY server/pubspec.yaml server/pubspec.lock ./
RUN dart pub get

COPY server/ ./
RUN mkdir -p build
RUN dart compile exe bin/server.dart -o build/server

FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=build /app/build/server /app/server
COPY server/public /app/public

RUN useradd --create-home --shell /usr/sbin/nologin appuser \
    && mkdir -p /data \
    && chown -R appuser:appuser /app /data

USER appuser

ENV APP_PORT=8080
ENV DATA_DIR=/data
ENV PUBLIC_DIR=/app/public

EXPOSE 8080

CMD ["./server"]
