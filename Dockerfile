FROM mcr.microsoft.com/mssql/server:2025-latest

USER root

COPY  Init.sql /start-up/init.sql
COPY  entrypoint.sh /start-up/entrypoint.sh

RUN chmod +x /start-up/entrypoint.sh

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl apt-transport-https gnupg2 tini && \
    curl -sSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft.gpg && \
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/22.04/prod jammy main" > /etc/apt/sources.list.d/mssql-release.list && \
    apt-get update && \
    ACCEPT_EULA=Y apt-get install -y mssql-tools18 unixodbc-dev && \
    ln -s /opt/mssql-tools18/bin/sqlcmd /usr/local/bin/sqlcmd && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/opt/mssql/data \
    /var/opt/mssql/log \
    /var/opt/mssql/backups \
    /var/opt/mssql/data/tempdb \
    /start-up && \
    chown -R mssql:mssql /var/opt/mssql /start-up

ARG MSSQL_COLLATION
ARG MSSQL_ENABLE_HADR
ARG MSSQL_AGENT_ENABLED
ARG MSSQL_TELEMETRY_ENABLED
ARG MSSQL_TEMPDB_FILE_SIZE
ARG MSSQL_TEMPDB_FILE_GROWTH
ARG MSSQL_MEMORY_LIMIT_MB

ARG DB_NAME
ARG DB_CHANGE_TRACKING_PERIOD_DAYS

# SQL Server configuration environment variables with fallback values
ENV MSSQL_COLLATION=${MSSQL_COLLATION:-"Latin1_General_100_CI_AS_SC_UTF8"}
ENV MSSQL_ENABLE_HADR=${MSSQL_ENABLE_HADR:-0}
ENV MSSQL_AGENT_ENABLED=${MSSQL_AGENT_ENABLED:-false}
ENV MSSQL_TELEMETRY_ENABLED=${MSSQL_TELEMETRY_ENABLED:-false}
ENV MSSQL_TEMPDB_FILE_SIZE=${MSSQL_TEMPDB_FILE_SIZE:-128}
ENV MSSQL_TEMPDB_FILE_GROWTH=${MSSQL_TEMPDB_FILE_GROWTH:-64}
ENV MSSQL_MEMORY_LIMIT_MB=${MSSQL_MEMORY_LIMIT_MB:-2048}

ENV DB_NAME=${DB_NAME:-"DBAS"}
ENV DB_CHANGE_TRACKING_PERIOD_DAYS=${DB_CHANGE_TRACKING_PERIOD_DAYS:-"7"}

# Written by entrypoint.sh only after startup has fully completed.
#
# This must NOT live in the container's writable layer (/tmp, /var, ...), which
# survives `docker restart` and `compose stop`/`start` -- a marker left by a
# previous run would then be present before this run has finished starting.
# /dev/shm is a tmpfs that Docker mounts fresh on every container start, so the
# marker cannot outlive the run that wrote it.
ENV DBAS_READY_MARKER=/dev/shm/dbas-ready

# Healthy means: startup finished AND the server accepts a connection to DB_NAME
# right now. Connecting with -d proves the database is online and openable -- a
# query against master would still succeed while DB_NAME is missing or recovering.
# -b makes sqlcmd exit non-zero on failure; no pipe, so no exit status is masked.
#
# The start period must outlast the entrypoint's own login wait, otherwise a slow
# boot is reported unhealthy while it is still legitimately starting.
HEALTHCHECK --start-period=360s --start-interval=5s --interval=30s --timeout=10s --retries=3 \
  CMD test -f "${DBAS_READY_MARKER}" && \
      /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa \
        -P "${MSSQL_SA_PASSWORD:-${SA_PASSWORD}}" -C -d "${DB_NAME}" -b \
        -Q "SET NOCOUNT ON; SELECT 1" > /dev/null

USER mssql

# The base image's ENTRYPOINT (launch_sqlservr.sh) runs its argument as a
# background child and installs no signal trap, so SIGTERM from `docker stop`
# reaches PID 1 and stops there: neither this entrypoint nor sqlservr sees it and
# Docker resorts to SIGKILL, cutting SQL Server off without a checkpoint.
#
# So the chain is inverted -- entrypoint.sh runs launch_sqlservr.sh rather than
# the reverse. entrypoint.sh can then trap SIGTERM and, crucially, hold the
# container open until sqlservr has finished shutting down. Signalling the
# process group instead would not work: launch_sqlservr.sh is plain bash with no
# trap, so it dies immediately and tears the container down mid-checkpoint.
# launch_sqlservr.sh still runs the vendor setup (permissions_check,
# init_custom_setup, run_custom_setup) exactly as before.
#
# tini stays PID 1 to reap orphaned children and forward signals to entrypoint.sh.
ENTRYPOINT ["/usr/bin/tini", "--", "/start-up/entrypoint.sh"]
CMD []
