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