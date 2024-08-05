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

# Database configuration
DB_USER=${POSTGRES_USER:=postgres}
DB_PASSWORD="${POSTGRES_PASSWORD:=password}"
DB_NAME="${POSTGRES_DB:=replic8}"
DB_PORT="${POSTGRES_PORT:=5433}"
DB_HOST="${POSTGRES_HOST:=localhost}"
DOCKER_DB_HOST="host.docker.internal"

# Allow to skip Docker if a dockerized Postgres database is already running
if [[ -z "${SKIP_DOCKER}" ]]
then
  docker-compose up -d
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

# Apply database migrations
sqlx database create
sqlx migrate run

CONNECTOR_NAME="replic8-postgres-connector"
REPLICATION_SLOT_NAME="replic8_slot"
KAFKA_BOOTSTRAP_SERVERS="kafka:29092"
KAFKA_TOPIC="schema-changes.replic8"
TABLE_INCLUDE_LIST="public.subscriptions"
CONNECTOR_HOST="localhost"
CONNECTOR_PORT=8083
CONNECTOR_URL="http://${CONNECTOR_HOST}:${CONNECTOR_PORT}/connectors"

# Create logical replication slot if it doesn't exist
if ! pg_recvlogical -h "${DB_HOST}" -U "${DB_USER}" -d "${DB_NAME}" -p "${DB_PORT}" --slot "${REPLICATION_SLOT_NAME}" --drop-slot > /dev/null 2>&1; then
  pg_recvlogical -h "${DB_HOST}" -U "${DB_USER}" -d "${DB_NAME}" -p "${DB_PORT}" --slot "${REPLICATION_SLOT_NAME}" --create-slot -P pgoutput
  >&2 echo "Replication slot ${REPLICATION_SLOT_NAME} created!"
else
  >&2 echo "Replication slot ${REPLICATION_SLOT_NAME} already exists!"
fi

function post_connector() {
  local attempts=0
  local max_attempts=5
  local success=false
  local sleep_duration=5

  while [ $attempts -lt $max_attempts ]; do
    # Perform the curl request
    curl -X POST -H 'Content-Type: application/json' --data '{
      "name": "'"${CONNECTOR_NAME}"'",
      "config": {
        "connector.class": "io.debezium.connector.postgresql.PostgresConnector",
        "plugin.name": "pgoutput",
        "tasks.max": "1",
        "topic.prefix": "postgres",
        "database.hostname": "'"${DOCKER_DB_HOST}"'",
        "database.port": "'"${DB_PORT}"'",
        "database.user": "'"${DB_USER}"'",
        "database.password": "'"${DB_PASSWORD}"'",
        "database.dbname": "'"${DB_NAME}"'",
        "database.server.name": "dbserver1",
        "slot.name": "'"${REPLICATION_SLOT_NAME}"'",
        "publication.name": "replic8_publication",
        "database.history.kafka.bootstrap.servers": "'"${KAFKA_BOOTSTRAP_SERVERS}"'",
        "database.history.kafka.topic": "'"${KAFKA_TOPIC}"'"
      }
    }' $CONNECTOR_URL && success=true && break

    # If curl fails, increment the attempts counter and sleep
    attempts=$((attempts + 1))
    echo "Attempt $attempts/$max_attempts failed. Retrying in $sleep_duration seconds..."
    sleep $sleep_duration
  done

  if [ $success = false ]; then
    echo "Failed to set up the Debezium connector after $max_attempts attempts."
    exit 1
  fi
}
#
# attempts=0
# max_attempts=10
# success=false

while [ $attempts -lt $max_attempts ]; do
  # Use nc to check if the connector service is up
  if nc -z "${CONNECTOR_HOST}" "${CONNECTOR_PORT}"; then
    echo "Connector is up. Running your logic..."
    # Set up Debezium PostgreSQL connector
    post_connector
    break
  else
    echo "Attempt $((attempts+1))/$max_attempts failed. Status code: $http_status. Retrying in 1 second..."
  fi

  # Increment the attempts counter
  attempts=$((attempts + 1))
  # Wait for 1 second before the next attempt
  sleep 1
done
