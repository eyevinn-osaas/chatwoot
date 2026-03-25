#!/bin/bash
set -eo pipefail

PORT=${PORT:-8080}

# Chatwoot Rails server runs on port 3000 internally but we proxy via PORT.
# OSC sets PORT; we update the FRONTEND_URL to reflect the OSC hostname.
export RAILS_ENV="${RAILS_ENV:-production}"
export NODE_ENV="${NODE_ENV:-production}"
export INSTALLATION_ENV="${INSTALLATION_ENV:-docker}"

# Map OSC_HOSTNAME to Chatwoot's frontend URL
if [ -n "$OSC_HOSTNAME" ]; then
    export FRONTEND_URL="${FRONTEND_URL:-https://${OSC_HOSTNAME}}"
fi

# Parse DATABASE_URL into individual Chatwoot postgres vars if provided
if [ -n "$DATABASE_URL" ]; then
    # DATABASE_URL format: postgres://user:password@host:port/dbname
    DB_REST="${DATABASE_URL#*://}"
    DB_USERINFO="${DB_REST%%@*}"
    DB_HOSTPATH="${DB_REST#*@}"
    DB_USER="${DB_USERINFO%%:*}"
    DB_PASS="${DB_USERINFO#*:}"
    DB_HOSTPORT="${DB_HOSTPATH%%/*}"
    DB_NAME="${DB_HOSTPATH#*/}"
    DB_HOST="${DB_HOSTPORT%%:*}"
    DB_PORT_PARSED="${DB_HOSTPORT#*:}"
    if [ "$DB_PORT_PARSED" = "$DB_HOST" ]; then
        DB_PORT_PARSED="5432"
    fi
    export POSTGRES_HOST="${POSTGRES_HOST:-$DB_HOST}"
    export POSTGRES_PORT="${POSTGRES_PORT:-$DB_PORT_PARSED}"
    export POSTGRES_USERNAME="${POSTGRES_USERNAME:-$DB_USER}"
    export POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$DB_PASS}"
    export POSTGRES_DATABASE="${POSTGRES_DATABASE:-$DB_NAME}"
fi

# Redis URL passthrough (Chatwoot reads REDIS_URL directly)
# REDIS_URL is already handled by Chatwoot natively

# Secret key base is required
if [ -z "$SECRET_KEY_BASE" ]; then
    echo "WARNING: SECRET_KEY_BASE is not set. Generating ephemeral secret (will change on restart)."
    export SECRET_KEY_BASE="$(cat /dev/urandom | tr -dc 'a-f0-9' | fold -w 128 | head -n 1)"
fi

# Remove stale PID file if present
rm -rf /app/tmp/pids/server.pid

# Run database migrations on startup if DB is available
if [ -n "$POSTGRES_HOST" ] || [ -n "$DATABASE_URL" ]; then
    echo "Running database migrations..."
    bundle exec rails db:chatwoot_prepare 2>&1 || echo "Migration warning - continuing..."
fi

# Chatwoot's Rails server binds to 3000; we tell OSC's proxy that $PORT is the external port.
# The internal CMD runs on 3000, OSC platform maps PORT externally.
export PORT=3000

exec "$@"
