#!/usr/bin/env bash
set -x
set -eo pipefail

if ! [ -x "$(command -v psql)" ]; then
  echo >&2 "Error: psql is not installed."
  exit 1
fi

if ! [ -x "$(command -v sqlx)" ]; then
  echo >&2 "Error: sqlx is not installed."
  exit 1
fi

DB_USER=${POSTGRES_USER:=postgres}
DB_PASSWORD="${POSTGRES_PASSWORD:=password}"
DB_NAME="${POSTGRES_DB:=replic8}"
DB_PORT="${POSTGRES_PORT:=5433}"
DB_HOST="${POSTGRES_HOST:=localhost}"

# Allow to skip Docker if a dockerized Postgres database is already running”
if [[ -z "${SKIP_DOCKER}" ]]
then
  docker build -t replic8-db .
  docker run \
	  -e POSTGRES_USER=${DB_USER} \
	  -e POSTGRES_PASSWORD=${DB_PASSWORD} \
	  -e POSTGRES_DB=${DB_NAME} \
	  -p "${DB_PORT}":5432 \
          -v pgdata:/var/lib/postgresql/data \
	  -d replic8-db
fi

# Keep pinging Postgres until it's ready to accept commands
export PGPASSWORD="${DB_PASSWORD}"
until psql -h "${DB_HOST}" -U "${DB_USER}" -p "${DB_PORT}" -d "postgres" -c '\q'; do
  >&2 echo "Postgres is still unavailable - sleeping"
  sleep 1
done

>&2 echo "Postgres is up and running on port ${DB_PORT}!"

DATABASE_URL=postgres://${DB_USER}:${DB_PASSWORD}@${DB_HOST}:${DB_PORT}/${DB_NAME}

export DATABASE_URL
sqlx database create
sqlx migrate run

# Set wal_level to logical for logical replication
# psql -h "${DB_HOST}" -U "${DB_USER}" -p "${DB_PORT}" -d "${DB_NAME}" -c "ALTER SYSTEM SET wal_level = logical;"
# psql -h "${DB_HOST}" -U "${DB_USER}" -p "${DB_PORT}" -d "${DB_NAME}" -c "SELECT pg_reload_conf();"

# Create logical replication slot
# pg_recvlogical -h "${DB_HOST}" -U "${DB_USER}" -d "${DB_NAME}" -p "${DB_PORT}" --slot test_slot --create-slot -P wal2json

# Start logical replication
# pg_recvlogical -h "${DB_HOST}" -U "${DB_USER}" -d "${DB_NAME}" -p "${DB_PORT}" --slot test_slot --start -o pretty-print=1 -o add-msg-prefixes=wal2json -f -
