# Egg Hunt

Local egg hunt prototype built as a small monolith: one Dart container serves the web UI, HTTP API, real-time WebSocket updates, and JSON persistence. A Caddy proxy in front of it provides local HTTPS for phones and computers on the same network.

## What It Includes

- Hide spot and riddle catalog
- Active game creation
- Existing player selection
- Player release after choosing the wrong player
- Egg discovery validation
- Real-time game synchronization over WebSocket
- JSON persistence on a Docker volume
- Web UI served from `/`
- Local HTTPS through Caddy

## Run With Docker Compose

The recommended local deployment path is the Docker Compose stack in this repository.

1. Copy the example environment file:

```bash
cp .env.example .env
```

2. Edit `.env` if needed, especially `PUBLIC_HOSTS`:

```text
PUBLIC_HOSTS=localhost,127.0.0.1,raspberrypi.local,192.168.1.100
```

Include every hostname or IP address that players will use to open the app.

3. Start the stack:

```bash
docker compose up --build -d
```

4. Open the app from a device on the same network:

```text
https://raspberrypi.local:8181
```

If `raspberrypi.local` does not resolve, use the Raspberry Pi IP address instead:

```text
https://<RASPBERRY_PI_IP>:8181
```

If you change `HTTPS_PORT`, use that port in the URL.

## Local HTTPS Certificate

Caddy is configured with `tls internal`, so it generates a local certificate authority and certificates for the hosts listed in `PUBLIC_HOSTS`.

Browsers will usually show a certificate warning until the Caddy local root certificate is trusted on each device. Export the root certificate with:

```bash
docker compose cp egg-hunt-proxy:/data/caddy/pki/authorities/local/root.crt ./caddy-local-root.crt
```

Then install `caddy-local-root.crt` as a trusted certificate authority on every phone or computer that should open the app without warnings.

## Stop The Stack

```bash
docker compose down
```

Game data is kept in the `egg_hunt_data` Docker volume.

## Configuration

Docker Compose reads these variables from `.env`:

- `HTTP_PORT`: HTTP proxy port, defaults to `8180`
- `HTTPS_PORT`: HTTPS proxy port, defaults to `8181`
- `PUBLIC_HOSTS`: comma-separated hostnames and IP addresses covered by the local Caddy certificate
- `ALLOWED_ORIGIN`: allowed CORS origin for the Dart server, defaults to `*`

## API

- `GET /health`
- `GET /api/catalog/hide-spots`
- `GET /api/games`
- `GET /api/games/active`
- `GET /api/games/{id}`
- `POST /api/games`
- `POST /api/games/{id}/join`
- `POST /api/games/{id}/leave`
- `POST /api/games/{id}/eggs/{eggId}/found`
- `POST /api/games/{id}/close`
- `GET /ws/games/{id}`

## Create A Game From The API

```bash
curl -k -X POST https://raspberrypi.local:8181/api/games \
  -H 'Content-Type: application/json' \
  -d '{
    "title": "Sunday Egg Hunt",
    "hostName": "Living room",
    "adminCode": "1234",
    "players": ["Zoe", "Louis"],
    "eggs": [
      {"playerName": "Zoe", "hideSpotId": "salon-canape"},
      {"playerName": "Louis", "hideSpotId": "jardin-pot"}
    ]
  }'
```

Use `-k` when the Caddy root certificate is not trusted by the machine running `curl`.

## Notes

The Dart backend itself serves plain HTTP inside the Docker network. HTTPS is provided by Caddy. Opening the Dart container directly with an `https://` URL will fail with a protocol error.

The repository may still contain older Flutter prototype code, but the browser-based Dart server in `server/` is the easiest path for a Raspberry Pi and local-network players.
