# n8n Integration Proposal

## Overview

This document outlines the changes required to add n8n (workflow automation tool) to the existing Docker Compose stack. The n8n service will use the existing PostgreSQL instance for data persistence, following the established project structure patterns.

## Architecture Changes

### New Service Structure

```
services/
├── postgres/
│   ├── Dockerfile
│   ├── postgres.conf
│   └── init-scripts/
│       ├── initdb-postgis.sh
│       ├── update-postgis.sh
│       └── 001-init-extensions.sql
└── n8n/                              # NEW
    └── init-scripts/                 # NEW
        └── 002-init-n8n-db.sql       # NEW
```

The n8n service follows a simpler structure than postgres since it uses the official n8n Docker image directly without customization.

## File Changes

### 1. Create New Directory Structure

```bash
mkdir -p services/n8n/init-scripts
```

### 2. Create `services/n8n/init-scripts/002-init-n8n-db.sql`

This initialization script creates a dedicated database and user for n8n within the existing PostgreSQL instance.

```sql
-- Create n8n database if it doesn't exist
SELECT 'CREATE DATABASE n8n'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'n8n')\gexec

-- Create n8n user if it doesn't exist
DO
$$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_user WHERE usename = 'n8n_user') THEN
        CREATE USER n8n_user WITH PASSWORD 'n8n_password_change_me';
    END IF;
END
$$;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n_user;

-- Connect to n8n database and grant schema permissions
\c n8n

GRANT ALL PRIVILEGES ON SCHEMA public TO n8n_user;
GRANT CREATE ON SCHEMA public TO n8n_user;

-- Grant default privileges for future tables
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO n8n_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO n8n_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO n8n_user;

-- Set owner of public schema to n8n_user
ALTER SCHEMA public OWNER TO n8n_user;
```

### 3. Update `services/postgres/Dockerfile`

Add the n8n initialization script to the postgres Dockerfile:

```dockerfile
FROM postgis/postgis:17-3.5

# Install build dependencies, build pgvector, then clean up
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        git \
        postgresql-server-dev-17 && \
    cd /tmp && \
    git clone --branch v0.8.0 https://github.com/pgvector/pgvector.git && \
    cd pgvector && \
    make && \
    make install && \
    cd / && \
    rm -rf /tmp/pgvector && \
    apt-get remove -y build-essential git postgresql-server-dev-17 && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ADD ./init-scripts/001-init-extensions.sql /docker-entrypoint-initdb.d/
ADD ./init-scripts/002-init-n8n-db.sql /docker-entrypoint-initdb.d/
```

**Alternative Approach (if you prefer not to modify Dockerfile):**

Uncomment line 13 in `compose.yml` and add the n8n init script to the postgres init-scripts directory. The volume mount will make it available to the container:

```yaml
volumes:
  - mystack-postgres-data:/var/lib/postgresql/data
  - ./services/postgres/init-scripts:/docker-entrypoint-initdb.d
```

Then copy the SQL file:
```bash
cp services/n8n/init-scripts/002-init-n8n-db.sql services/postgres/init-scripts/
```

### 4. Update `compose.yml`

Add the n8n service after the postgres service:

```yaml
services:
  postgres:
    platform: linux/amd64
    build:
      context: ./services/postgres
      dockerfile: Dockerfile
    container_name: postgres_db
    env_file: .env
    ports:
      - 5432:5432
    volumes:
      - mystack-postgres-data:/var/lib/postgresql/data
      # Uncomment below to use volume-based init scripts (see Alternative Approach)
      # - ./services/postgres/init-scripts:/docker-entrypoint-initdb.d
    networks:
      - mystack-network
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER}"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  n8n:
    image: docker.n8n.io/n8nio/n8n
    container_name: n8n
    env_file: .env
    environment:
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=${N8N_DB_NAME:-n8n}
      - DB_POSTGRESDB_USER=${N8N_DB_USER}
      - DB_POSTGRESDB_PASSWORD=${N8N_DB_PASSWORD}
      - N8N_HOST=${N8N_HOST:-localhost}
      - N8N_PORT=5678
      - N8N_PROTOCOL=${N8N_PROTOCOL:-http}
      - WEBHOOK_URL=${N8N_WEBHOOK_URL:-http://localhost:5678/}
      - GENERIC_TIMEZONE=${TIMEZONE:-America/New_York}
    ports:
      - "${N8N_PORT:-5678}:5678"
    volumes:
      - mystack-n8n-data:/home/node/.n8n
    networks:
      - mystack-network
    depends_on:
      postgres:
        condition: service_healthy
    restart: unless-stopped

volumes:
  mystack-postgres-data:
  mystack-n8n-data:

networks:
  mystack-network:
    driver: bridge
```

### 5. Update `.env` File

Add the following environment variables to your `.env` file:

```bash
# PostgreSQL (existing)
POSTGRES_DB=myapp_db
POSTGRES_USER=postgres
POSTGRES_PASSWORD=your_secure_password
COMPOSE_PROJECT_NAME=mystack

# n8n Configuration (NEW)
N8N_DB_NAME=n8n
N8N_DB_USER=n8n_user
N8N_DB_PASSWORD=n8n_password_change_me

# n8n Web Interface (NEW)
N8N_HOST=localhost
N8N_PORT=5678
N8N_PROTOCOL=http
N8N_WEBHOOK_URL=http://localhost:5678/

# Optional: Timezone (NEW)
TIMEZONE=America/New_York

# Optional: n8n Basic Auth (Recommended for security) (NEW)
# N8N_BASIC_AUTH_ACTIVE=true
# N8N_BASIC_AUTH_USER=admin
# N8N_BASIC_AUTH_PASSWORD=your_secure_password

# Optional: n8n Encryption Key (Recommended for production) (NEW)
# N8N_ENCRYPTION_KEY=your_random_encryption_key
```

### 6. Update `.env.example`

Add the same n8n variables to `.env.example` as a template for other developers:

```bash
# PostgreSQL
POSTGRES_DB=myapp_db
POSTGRES_USER=postgres
POSTGRES_PASSWORD=changeme
COMPOSE_PROJECT_NAME=mystack

# MongoDB (placeholder for future use)
MONGODB_ROOT_USERNAME=root
MONGODB_ROOT_PASSWORD=changeme
MONGODB_USERNAME=user
MONGODB_PASSWORD=changeme
MONGODB_DATABASE=myapp_db

# n8n Configuration
N8N_DB_NAME=n8n
N8N_DB_USER=n8n_user
N8N_DB_PASSWORD=changeme

# n8n Web Interface
N8N_HOST=localhost
N8N_PORT=5678
N8N_PROTOCOL=http
N8N_WEBHOOK_URL=http://localhost:5678/

# Optional: Timezone
TIMEZONE=America/New_York

# Optional: n8n Basic Auth (Recommended for security)
# N8N_BASIC_AUTH_ACTIVE=true
# N8N_BASIC_AUTH_USER=admin
# N8N_BASIC_AUTH_PASSWORD=changeme

# Optional: n8n Encryption Key (Recommended for production)
# N8N_ENCRYPTION_KEY=generate_random_key_here
```

## Implementation Steps

### Step 1: Create Directory Structure
```bash
mkdir -p services/n8n/init-scripts
```

### Step 2: Create Database Initialization Script
Create `services/n8n/init-scripts/002-init-n8n-db.sql` with the SQL content provided above.

### Step 3: Update PostgreSQL Configuration
Choose one approach:
- **Approach A**: Update `services/postgres/Dockerfile` to include the new init script
- **Approach B**: Uncomment the volume mount in `compose.yml` and copy the script to postgres init-scripts

### Step 4: Update Environment Variables
Add all n8n-related environment variables to your `.env` file. Make sure to change default passwords!

### Step 5: Update Docker Compose
Update `compose.yml` with the n8n service configuration.

### Step 6: Rebuild and Start Services

If you're adding n8n to an existing setup:
```bash
# Stop services
docker compose down

# Rebuild postgres (if using Approach A)
docker compose build postgres

# Start services
docker compose up -d
```

If you're starting fresh (will initialize database from scratch):
```bash
# Remove volumes to reinitialize database
docker compose down -v

# Start services
docker compose up -d
```

### Step 7: Verify Installation

```bash
# Check service status
docker compose ps

# Check n8n logs
docker compose logs -f n8n

# Access n8n web interface
# Open browser to http://localhost:5678
```

## Database Schema

The n8n service will use a separate database named `n8n` within the PostgreSQL instance:

```
PostgreSQL Instance
├── myapp_db (your existing database)
│   ├── postgis extension
│   ├── pgvector extension
│   └── your application tables
└── n8n (new database for n8n)
    ├── n8n_user (dedicated user)
    └── n8n tables (auto-created by n8n)
```

## Security Considerations

1. **Change Default Passwords**: Update all passwords in `.env` from default values
2. **Enable Basic Auth**: Uncomment and configure `N8N_BASIC_AUTH_*` variables for web interface protection
3. **Encryption Key**: Generate and set `N8N_ENCRYPTION_KEY` for credential encryption
4. **Network Isolation**: n8n and postgres communicate via internal Docker network
5. **Database User**: n8n uses a dedicated non-root database user with limited privileges

## Port Configuration

- **PostgreSQL**: 5432 (exposed to host)
- **n8n Web Interface**: 5678 (exposed to host)

## Volume Persistence

Two volumes ensure data persistence:
- `mystack-postgres-data`: PostgreSQL data (including n8n database)
- `mystack-n8n-data`: n8n workflows, credentials, and settings

## Testing the Integration

After deployment, verify the connection:

```bash
# Connect to PostgreSQL and check n8n database
docker compose exec postgres psql -U postgres -c "\l" | grep n8n

# Verify n8n user exists
docker compose exec postgres psql -U postgres -c "\du" | grep n8n_user

# Test n8n database connection
docker compose exec postgres psql -U n8n_user -d n8n -c "SELECT version();"

# Check n8n logs for successful database connection
docker compose logs n8n | grep -i "database"
```

## Troubleshooting

### Issue: n8n can't connect to database
- Verify environment variables in `.env` match the init script
- Check postgres logs: `docker compose logs postgres`
- Ensure postgres health check passes: `docker compose ps`

### Issue: Database initialization didn't run
- If using existing volumes, init scripts only run on first creation
- Solution: `docker compose down -v` to remove volumes and recreate

### Issue: Permission denied errors in n8n logs
- Verify the `002-init-n8n-db.sql` script ran successfully
- Check user privileges: `docker compose exec postgres psql -U postgres -d n8n -c "\du"`

## Additional Configuration Options

### Enable Webhook Authentication
```bash
N8N_SKIP_WEBHOOK_DEREGISTRATION_SHUTDOWN=true
```

### Configure External URL (for production)
```bash
N8N_HOST=n8n.yourdomain.com
N8N_PROTOCOL=https
N8N_WEBHOOK_URL=https://n8n.yourdomain.com/
```

### Enable Execution Data Logging
```bash
EXECUTIONS_DATA_SAVE_ON_ERROR=all
EXECUTIONS_DATA_SAVE_ON_SUCCESS=all
EXECUTIONS_DATA_SAVE_MANUAL_EXECUTIONS=true
```

## Updating CLAUDE.md

Consider adding the following section to `CLAUDE.md`:

```markdown
### n8n Service
- **n8n** workflow automation platform using the official Docker image
- **Database**: Uses dedicated `n8n` database within the shared PostgreSQL instance
- **Initialization**: SQL script in `services/n8n/init-scripts/002-init-n8n-db.sql` creates database and user
- **Web Interface**: Accessible on port 5678
- **Data Persistence**: Workflows and credentials stored in `mystack-n8n-data` volume
```

## Summary

This integration adds n8n to your stack with:
- ✅ Reuse of existing PostgreSQL instance
- ✅ Separate database and user for n8n
- ✅ Consistent folder structure following project patterns
- ✅ Persistent data storage
- ✅ Health check dependencies
- ✅ Security best practices (dedicated user, optional basic auth)
- ✅ Environment-based configuration

The n8n service will be accessible at `http://localhost:5678` after deployment.

---

## Quick Reference

### What's Included

**Complete folder structure** following your existing pattern (`services/n8n/init-scripts/`)

**PostgreSQL initialization script** that creates a dedicated `n8n` database and user in your existing postgres instance

**Updated `compose.yml`** with n8n service configuration

**All required environment variables** for `.env` and `.env.example`

**Two implementation approaches:**
- Modify Dockerfile to add init script
- Use volume mount for init scripts

**Security best practices:**
- Dedicated database user with limited privileges
- Optional basic authentication
- Encryption key configuration

### Architecture Overview

**Database Setup:**
- n8n uses your existing PostgreSQL instance with a separate database named `n8n`
- Dedicated `n8n_user` with limited privileges following security best practices
- Automatic database initialization on first startup

**Access:**
- Web interface accessible at `http://localhost:5678`
- Data persisted in named volume `mystack-n8n-data`

**Network:**
- n8n and postgres communicate via internal Docker network `mystack-network`
- Health check dependencies ensure postgres is ready before n8n starts

### Implementation Checklist

- [ ] Create directory: `services/n8n/init-scripts/`
- [ ] Create file: `services/n8n/init-scripts/002-init-n8n-db.sql`
- [ ] Choose implementation approach (Dockerfile or volume mount)
- [ ] Update `compose.yml` with n8n service
- [ ] Add n8n environment variables to `.env`
- [ ] Update `.env.example` with n8n variables
- [ ] Change default passwords in `.env`
- [ ] Rebuild and start services
- [ ] Verify database and user creation
- [ ] Access n8n web interface
- [ ] (Optional) Enable basic authentication
- [ ] (Optional) Configure encryption key

### Key Files Modified/Created

```
Modified:
- compose.yml (add n8n service, add volume)
- services/postgres/Dockerfile (add init script) OR uncomment volume mount
- .env (add n8n variables)
- .env.example (add n8n variables)

Created:
- services/n8n/init-scripts/002-init-n8n-db.sql
- n8n-proposed.md (this file)
```

### Default Access

After deployment:
- **n8n Web UI**: http://localhost:5678
- **Database**: `n8n` database in existing PostgreSQL instance
- **User**: `n8n_user`

Remember to change all default passwords before deploying!
