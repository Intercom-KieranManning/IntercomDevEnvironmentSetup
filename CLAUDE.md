# Intercom — Project Overview

Full-stack video intercom system. Django REST API backend + React frontend + Python device client with WebRTC streaming.

## Repository Structure

```
Intercom/
├── APIServer/                   # Django REST API backend
│   ├── IntercomAPIServer/       # Settings, root URLs, ASGI/WSGI
│   ├── accounts/                # Custom User model (email-based), session endpoints
│   ├── authentication/          # Cognito OAuth, JWT middleware, device grant views
│   ├── client_devices/          # Device registration & OAuth device flow (RFC 8628)
│   ├── invites/                 # Invite code system (PENDING/ACCEPTED/REVOKED)
│   ├── live_stream/             # WebSocket consumers for device signaling
│   ├── api/                     # API versioning (v1) & OpenAPI schema
│   ├── manage.py
│   ├── pyproject.toml           # uv dependencies
│   ├── Dockerfile.dev           # Dev image (uv + Alpine)
│   ├── utility.sh               # Init script (migrations, superuser, device registration)
│   └── start.sh                 # Legacy startup script
├── Frontend/                    # Vite + React SPA
│   ├── src/
│   │   ├── main.tsx             # Entry point, routing, session auth gate
│   │   ├── pages/               # Route components (home, login, profile, devices, about)
│   │   ├── layout/              # Dashboard layout, header, side menu
│   │   ├── components/          # SignInForm, ProtectedRoute
│   │   └── utils/               # session, useSignalingSocket, useWebRTC
│   ├── Dockerfile.dev           # Dev image (Node 18 + npm)
│   └── vite.config.ts           # Dev server + proxy config
├── ClientPython/                # Python device client (camera + WebRTC)
│   ├── main.py                  # PiClient entry point
│   ├── intercomclient/          # Config, auth, camera, token store
│   ├── pyproject.toml           # uv dependencies (aiortc, opencv, websockets)
│   └── Dockerfile.dev           # Dev image (uv + bookworm-slim + OpenCV deps)
├── docker-compose.yml           # Root orchestration (all services)
├── .env                         # Environment variables (root level)
└── .envrc                       # Direnv config (loads .env)
```

## Tech Stack

| Layer | Technology |
|---|---|
| **Backend** | Python 3.13+, Django 5.2, PostgreSQL 15 |
| **API** | Django REST Framework, drf-spectacular (OpenAPI) |
| **Auth** | AWS Cognito OAuth2, django-oauth-toolkit (RFC 8628 device flow), PyJWT |
| **ASGI** | Daphne (HTTP + WebSockets via Django Channels) |
| **Frontend** | React 19, TypeScript, Vite 6, Material-UI 9, React Router 7 |
| **Device Client** | Python 3.14+, aiortc (WebRTC), OpenCV, websockets |
| **Package Mgmt** | uv (Python), npm (frontend) |
| **DevOps** | Docker Compose, GitHub Actions CI/CD |
| **Code Quality** | Ruff, MyPy, ESLint, pre-commit hooks, Conventional Commits |

## Docker Compose Services

| Service | Purpose | Depends On |
|---|---|---|
| `postgres_db` | PostgreSQL 15 database | — |
| `backend` | Django API via Daphne (port 8000) | `postgres_db` (healthy) |
| `utility` | Init: migrations, superuser, Cognito user, device registration. Runs indefinitely after init. | `backend` (healthy) |
| `frontend` | React dev server via Vite (port 8080) | `backend` (healthy) |
| `clientpython` | Device client (camera + WebRTC signaling) | `utility` (healthy) |

### Startup Order
```
postgres_db → backend → utility → frontend
                            → clientpython
```

### Key Configuration
- `utility` and `backend` services map `aws_access_key_id` / `aws_secret_access_key` (lowercase in `.env`) to uppercase `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` for boto3 compatibility
- `clientpython` mounts `/dev/video0` from the host for camera access
- Shared volumes: `pgdata`, `client_tokens`, `device_oauth_config`

## Local Development

```bash
# Start everything
cd /home/spoon/code/Intercom
docker compose up -d

# View logs
docker compose logs -f <service>

# Rebuild after code changes
docker compose up -d --build <service>

# Clean restart (removes volumes)
docker compose down -v && docker compose up -d
```

### Ports
- `8000` — Django backend (Daphne)
- `8080` — React frontend (Vite dev server)
- `5432` — PostgreSQL

## Environment Variables (`.env`)

| Variable | Purpose |
|---|---|
| `COGNITO_DOMAIN`, `COGNITO_REGION`, `COGNITO_APP_CLIENT_ID` | AWS Cognito OAuth |
| `COGNITO_CLIENT_SECRET`, `COGNITO_USER_POOL_ID` | Cognito server-side |
| `DJANGO_SECRET_KEY` | Django security |
| `DJANGO_SUPERUSER_EMAIL`, `DJANGO_SUPERUSER_PASSWORD` | Auto-created superuser (password must meet Cognito policy: uppercase + lowercase + number + symbol) |
| `POSTGRES_HOST`, `POSTGRES_DB`, `POSTGRES_PASSWORD`, `POSTGRES_USER` | Database |
| `DJANGO_DEBUG`, `DJANGO_ALLOWED_HOSTS` | Runtime config |
| `SITE_URL`, `FRONTEND_URL` | CORS/redirects |
| `aws_access_key_id`, `aws_secret_access_key` | AWS credentials for Cognito operations |
| `DJANGO_LOCAL_DEV_USER` | Default device owner email |

## Authentication Architecture

### Two-tier auth:
1. **Session-based (browser SPA):** Django session cookies. Public routes are whitelisted in `JwtBearerAuthenticationMiddleware`.
2. **JWT Bearer Tokens (devices):** OAuth2 device flow tokens validated via `django-oauth-toolkit`. DRF uses `OAuth2Authentication`.

### WebSocket Auth:
- **Device clients:** Bearer token in `Authorization` header, validated against `oauth2_provider.AccessToken`
- **Browser viewers:** Session cookie via `AuthMiddlewareStack`

### OAuth2 Device Flow (RFC 8628):
1. `POST /oauth/device-authorization/` — creates `DeviceGrant` + `ClientDevice`
2. Device polls `POST /oauth/token/` with `device_code`
3. Utility auto-approves the grant and exchanges for tokens
4. Tokens written to shared volume (`client_tokens`)

## WebRTC Streaming Flow

1. **Device client** connects to `/ws/live_stream/<device_id>/` with Bearer token
2. **Viewer (React)** connects to same WebSocket via session auth
3. Viewer creates RTCPeerConnection with `recvonly` video transceiver
4. Viewer sends SDP offer → device receives it
5. Device captures camera frames via OpenCV → adds track → sends SDP answer
6. ICE candidates exchanged bidirectionally via signaling server
7. Video stream flows device → peer connection → viewer `<video>` element

## Key API Endpoints

| Endpoint | Auth | Description |
|---|---|---|
| `GET /api/v1/users/session/` | Public | Check auth state |
| `POST /api/v1/users/logout/` | Required | Logout |
| `GET /api/v1/devices/` | Required | List user's devices |
| `POST /api/v1/invites/validate/` | Public | Validate invite code |
| `POST /api/v1/invites/` | Admin | Create invite |
| `GET /api/v1/invites/` | Required | List invites |
| `POST /api/v1/invites/{id}/revoke/` | Admin | Revoke invite |
| `POST /oauth/device-authorization/` | Public | Initiate device flow |
| `POST /oauth/token/` | Public | Poll for tokens |
| `GET /api/v1/docs/` | — | Swagger UI |
| `GET /api/v1/schema/` | — | OpenAPI spec |
| `WS /ws/live_stream/<device_id>/` | Token/Session | WebRTC signaling |

## Django Management Commands

| Command | Purpose |
|---|---|
| `migrate` | Run database migrations |
| `createsuperuser --noinput` | Create Django superuser from env vars |
| `create_local_invite` | Generate a local dev invite token |
| `create_cognito_user` | Create superuser in AWS Cognito (idempotent — sets password even if user exists) |
| `register_device` | Full OAuth device flow: initiate → approve → exchange tokens → write to shared volume |
| `auto_approve_devices` | Poll and auto-approve pending devices (continuous loop) |

## Deployment

1. Push to `master` triggers GitHub Actions
2. Docker image built (multi-stage: Node → Python → Alpine) and pushed to `docker.kmanning.ie:5000`
3. Self-hosted runner pulls and runs `docker compose -f infra/docker-compose.yml -f infra/docker-compose.prod.yml up -d`
4. Daphne serves on port 8000 (HTTP + WebSocket)
