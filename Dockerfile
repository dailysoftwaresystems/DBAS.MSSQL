FROM mcr.microsoft.com/mssql/server:2022-latest

USER root

COPY  Init.sql /start-up/init.sql
COPY  entrypoint.sh /start-up/entrypoint.sh

RUN chmod +x /start-up/entrypoint.sh

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl apt-transport-https gnupg2 && \
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

ARG DB_NAME
ARG DB_CHANGE_TRACKING_PERIOD_DAYS

# SQL Server configuration environment variables with fallback values
ENV MSSQL_COLLATION=${MSSQL_COLLATION:-"Latin1_General_100_CI_AS_SC_UTF8"}
ENV MSSQL_ENABLE_HADR=${MSSQL_ENABLE_HADR:-0}
ENV MSSQL_AGENT_ENABLED=${MSSQL_AGENT_ENABLED:-false}
ENV MSSQL_TELEMETRY_ENABLED=${MSSQL_TELEMETRY_ENABLED:-false}
ENV MSSQL_TEMPDB_FILE_SIZE=${MSSQL_TEMPDB_FILE_SIZE:-128}
ENV MSSQL_TEMPDB_FILE_GROWTH=${MSSQL_TEMPDB_FILE_GROWTH:-64}

ENV DB_NAME=${DB_NAME:-"DBAS"}
ENV DB_CHANGE_TRACKING_PERIOD_DAYS=${DB_CHANGE_TRACKING_PERIOD_DAYS:-"7"}

HEALTHCHECK --interval=5s --timeout=5s --retries=15 \
  CMD /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P ${MSSQL_SA_PASSWORD:-${SA_PASSWORD}} -C -Q "SELECT CASE WHEN DB_ID('${DB_NAME}') IS NOT NULL THEN 1 ELSE 0 END;" -b | grep -q 1

USER mssql
CMD ["/start-up/entrypoint.sh"]
