FROM postgres:latest

# Install dependencies and build wal2json
RUN apt-get update && apt-get install -y \
    build-essential \
    postgresql-server-dev-16 \
    postgresql-16-wal2json \
    git \
    vim \
    && rm -rf /var/lib/apt/lists/*

# RUN git clone https://github.com/eulerto/wal2json.git \
#     && cd wal2json \
#     && make && make install
# RUN tar -zxf wal2json-wal2json_2_6.tar.gz \
#     && cd wal2json-wal2json_2_6 \
#     && export PATH=/usr/lib/postgresql/16/bin:$PATH \
#     && make \
#     && make install

# Expose default PostgreSQL port
EXPOSE 5432

CMD ["postgres", "-c", "wal_level=logical", "-c", "max_replication_slots=10", "-c", "max_wal_senders=10"]
