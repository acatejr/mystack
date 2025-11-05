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