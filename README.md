# BackHaulBid local infrastructure

Docker Compose for running the BackHaulBid API, data stores, service discovery, bidding and web portal in a local development environment.

## Requirements

- Docker Desktop with Docker Compose v2.
- The sibling `backhaulbid-core-services`, `backhaulbid-node-services` and `backhaulbid-web-portal` repositories in the workspace layout used by `docker-compose.yml`.

## Configure

Compose reads `.env` from this repository directory. If it does not exist, copy `.env.example` and fill the required local values:

```powershell
Copy-Item .env.example .env
```

Keep `.env` private and out of Git. Do not copy mobile app variables into this file: the Expo app has its own `.env` under `fe/backhaulbid-driver-app`.

The Compose file includes an `ngrok` service and requires non-empty `NGROK_DOMAIN` and `NGROK_AUTHTOKEN` values while resolving Compose configuration. The current `.env.example` does not define these entries: add non-empty local placeholders to `.env` when you are not starting ngrok, and use valid account values only when starting the tunnel. The command below selects the local API and web services without selecting ngrok.

## Start the local API and web app

Run from this repository directory:

```powershell
docker compose up --build -d api-gateway web-portal notification-service
docker compose ps
```

Compose starts the selected services and their dependencies, including PostgreSQL, MongoDB, Redis, RabbitMQ, Eureka, identity, fleet, wallet, contract, media and bidding services. The main local entry points are:

| Service | Address |
| --- | --- |
| API Gateway | `http://localhost:8080` |
| Web portal | `http://localhost:3000` |
| Eureka dashboard | `http://localhost:8761` |
| PostgreSQL | `localhost:5432` |
| MongoDB | `localhost:27017` |
| Redis | `localhost:6379` |
| RabbitMQ | `localhost:5672` |

The app on a physical phone must use the computer's Wi-Fi IPv4 address, for example `http://192.168.1.25:8080`, in the app's `EXPO_PUBLIC_API_BASE_URL`. The phone and computer must be on the same network, and the gateway port must be reachable from the phone.

Follow service logs with:

```powershell
docker compose logs -f api-gateway identity-service bidding-service web-portal
```

## NFC eKYC in local development

Identity-service has NFC eKYC disabled by default. Enable it only in the local environment and configure the evidence encryption key before submitting evidence. `NFC_LOCAL_AUTOMATIC` defaults to `DISABLED`; the `COMPLETED_ONLY` and `CAPTURE_COMPLETE` modes require the Spring `local` profile and are development acceptance rules, not independent official identity verification. See the NFC eKYC section in the core-services README.

## Stop the stack

```powershell
docker compose down
```

This keeps the database volumes. `docker compose down -v` deletes the PostgreSQL, MongoDB, Redis and RabbitMQ data volumes; use it only when intentionally discarding local data.
