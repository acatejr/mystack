# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Docker Compose-based infrastructure stack for applications requiring PostgreSQL with geospatial and vector search capabilities. The stack is designed to provide a production-ready PostgreSQL database with PostGIS and pgvector extensions.

## Architecture

### Database Stack
- **PostgreSQL 17** with custom Docker image based on `postgis/postgis:17-3.5`
- **Extensions enabled**:
  - PostGIS (geospatial data support)
  - pgvector v0.8.0 (vector similarity search)
- **Initialization**: SQL scripts in `services/postgres/init-scripts/` run automatically on first container startup (numbered sequentially, e.g., `001-init-extensions.sql`)
- **Configuration**: Custom PostgreSQL settings in `services/postgres/postgres.conf` (not automatically loaded by default Docker image)

### Project Structure
```
.
├── compose.yml                     # Main Docker Compose configuration
├── .env                           # Environment variables (not in git)
├── .env.example                   # Template for environment variables
├── services/
│   └── postgres/
│       ├── Dockerfile             # Custom PostgreSQL image with pgvector
│       ├── postgres.conf          # PostgreSQL configuration
│       └── init-scripts/          # Database initialization scripts
│           └── 001-init-extensions.sql
└── volumes/                       # Volume mount point directory
```

## Development Commands

### Starting the Stack
```bash
docker compose up -d
```

### Stopping the Stack
```bash
docker compose down
```

### Removing Everything (including volumes)
```bash
docker compose down -v
```

### Rebuilding After Changes
```bash
docker compose up -d --build
```

### Viewing Logs
```bash
# All services
docker compose logs -f

# Specific service
docker compose logs -f postgres
```

### Database Access
```bash
# Connect to PostgreSQL
docker compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB

# Or with explicit credentials from .env
docker compose exec postgres psql -U postgres -d myapp_db
```

### Health Checks
```bash
# Check service status
docker compose ps

# Check PostgreSQL health
docker compose exec postgres pg_isready -U postgres
```

## Important Implementation Details

### PostgreSQL Configuration
- The `postgres.conf` file exists in `services/postgres/` but is NOT automatically applied by the current Dockerfile
- To use custom PostgreSQL configuration, the Dockerfile needs to be modified to copy and reference it, or it should be mounted as a volume in `compose.yml`
- Current settings in `postgres.conf` include performance tuning and logging configurations

### Adding New Init Scripts
- Place SQL scripts in `services/postgres/init-scripts/`
- Name them with numeric prefixes for execution order (e.g., `002-create-schema.sql`)
- Scripts run only on initial database creation, not on subsequent starts

### pgvector Extension
- Built from source (v0.8.0) during Docker image build
- Build dependencies are cleaned up after installation to reduce image size
- Enabled in `001-init-extensions.sql`

### Network Configuration
- Services communicate via `app-network` (bridge driver)
- PostgreSQL exposed on host port 5432
- Note: `compose.yml` has typo on line 26: `bridged` should be `bridge`

## Environment Variables

Required variables (see `.env.example`):
- `POSTGRES_DB`: Database name
- `POSTGRES_USER`: Database user
- `POSTGRES_PASSWORD`: Database password
- `COMPOSE_PROJECT_NAME`: Docker Compose project name

MongoDB variables exist in `.env.example` but no MongoDB service is currently defined in `compose.yml`.
