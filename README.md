# 🗄️ DBAS.MSSQL

[![Version](https://img.shields.io/badge/version-1.1.0-blue.svg)](VERSION)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![SQL Server](https://img.shields.io/badge/SQL%20Server-2022-red.svg)](https://hub.docker.com/r/microsoft/mssql-server)
[![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=flat&logo=docker&logoColor=white)](Dockerfile)

An optimized Microsoft SQL Server 2022 Docker image for the DBAS project, featuring reliable startup and automated database configuration.

## ✨ Features

- **🚀 Smart Startup**: Robust waiting system that ensures SQL Server is fully ready before releasing connections
- **🔧 Auto Configuration**: Automatic creation and configuration of the DBAS database
- **🏥 Health Check**: Continuous monitoring of database health
- **⚡ Performance**: Optimized configurations for TempDB and other performance settings
- **🔒 Security**: Secure configurations by default
- **📊 Change Tracking**: Native support for SQL Server Change Tracking

## 🚀 Quick Start

### Docker Run

```bash
docker run -d \
  --name dbas-mssql \
  -e "MSSQL_SA_PASSWORD=YourSecurePassword123!" \
  -p 1433:1433 \
  -v mssql_data:/var/opt/mssql \
  dailysoftwaresystems/dbas_mssql:latest
```

### Docker Compose

The image ships its own health check — do not override it. `healthy` means SQL
Server is accepting connections to `DB_NAME`, so dependent services can gate on
it directly:

```yaml
services:
  dbas-mssql:
    image: your-registry/dbas-mssql:latest
    environment:
      - MSSQL_SA_PASSWORD=YourSecurePassword123!
      - DB_NAME=DBAS
    ports:
      - "1433:1433"
    volumes:
      - dbas_data:/var/opt/mssql
    # SQL Server is sent SIGTERM and given time to checkpoint. Docker's default
    # grace period is 10s; raise it if your database takes longer to close.
    stop_grace_period: 60s

  your-app:
    image: your-app:latest
    depends_on:
      dbas-mssql:
        condition: service_healthy

volumes:
  dbas_data:
```

## ⚙️ Environment Variables

### Required

| Variable | Description |
|----------|-------------|
| `ACCEPT_EULA` | Must be `Y` to accept SQL Server license |
| `MSSQL_SA_PASSWORD` or `SA_PASSWORD` | SA user password (minimum 8 characters) |

### Optional

| Variable | Default | Description |
|----------|---------|-------------|
| `DB_NAME` | `DBAS` | Database name to be created |
| `MSSQL_COLLATION` | `Latin1_General_100_CI_AS_SC_UTF8` | SQL Server collation |
| `DB_CHANGE_TRACKING_PERIOD_DAYS` | `7` | Change Tracking retention period |
| `MSSQL_ENABLE_HADR` | `0` | Enable High Availability |
| `MSSQL_AGENT_ENABLED` | `false` | Enable SQL Server Agent |
| `MSSQL_TELEMETRY_ENABLED` | `false` | Enable telemetry |
| `MSSQL_TEMPDB_FILE_SIZE` | `128` | TempDB initial size (MB) |
| `MSSQL_TEMPDB_FILE_GROWTH` | `64` | TempDB growth (MB) |
| `MSSQL_MEMORY_LIMIT_MB` | `2048` | Max memory SQL Server may use (MB) |
| `LOGIN_TIMEOUT` | `300` | Seconds to wait for the `sa` login during startup |
| `DB_READY_TIMEOUT` | `180` | Seconds to wait for databases to come online |
| `SHUTDOWN_TIMEOUT` | `55` | Seconds to wait for SQL Server to stop before giving up |

### Collation and tempdb

`MSSQL_COLLATION` sets the **server** collation. This matters because `tempdb`
takes its collation from the server, so setting it is what makes `DBAS` and
`tempdb` match — required for joining temp tables against `DBAS` tables without
`Cannot resolve collation conflict` errors. There is no lighter-weight way to
align `tempdb`: it inherits from `model`, and `model` is a system database that
`ALTER DATABASE ... COLLATE` refuses to change.

Applying it rebuilds the system databases. That happens **once**, when the data
directory is first initialised — it is skipped on every later start, including
restarts and reuse of an existing volume.

> ⚠️ **Do not move this image to the `2025` base.** On `2025-latest` that rebuild
> crashes `sqlservr` with a SQLPAL assert (`NtumWaiter.cpp`), leaving the
> container hung or dead. Measured on the unmodified Microsoft images with only
> `MSSQL_COLLATION` set: **2025-latest succeeded 1 of 4 starts, 2022-latest 4 of
> 4.** This image is pinned to `2022-latest` for that reason. If you must move to
> 2025, pre-initialise `/var/opt/mssql` once and ship/mount it, so the rebuild
> never runs at container start.

`LOGIN_TIMEOUT` and `DB_READY_TIMEOUT` bound the startup waits. If you raise
them, raise the `HEALTHCHECK --start-period` in the Dockerfile to match, so a
slow boot is not reported unhealthy while it is still legitimately starting.

## 🏗️ Building

```bash
# Clone the repository
git clone <your-repository>/DBAS.MSSQL.git
cd DBAS.MSSQL

# Build the image
docker build -t dbas-mssql:latest .

# Build with custom arguments
docker build \
  --build-arg DB_NAME=MyDB \
  --build-arg MSSQL_COLLATION=SQL_Latin1_General_CP1_CI_AS \
  -t dbas-mssql:custom .
```

## 🔍 Monitoring

### Health Check

The container reports `healthy` only when **both** hold:

1. `entrypoint.sh` finished its full startup sequence, including `Init.sql`
2. `sqlcmd` can open a connection to `DB_NAME` *at that moment*

Connecting with `-d "$DB_NAME"` is the same thing a dependent service does, so
`healthy` is a safe gate for `depends_on: condition: service_healthy`. A query
against `master` would not be — it succeeds while `DB_NAME` is still missing or
recovering.

Readiness is signalled by a marker file (`DBAS_READY_MARKER`, default
`/dev/shm/dbas-ready`). `/dev/shm` is a tmpfs that Docker mounts fresh on every
container start, so the marker cannot outlive the run that wrote it. Putting it
under `/tmp` or any other path in the writable layer would be wrong: those
survive `docker restart` and `compose stop`/`start`, so a marker from a previous
run would still be there while the container was starting up again.

### Logs

```bash
# View container logs
docker logs dbas-mssql

# Follow logs in real-time
docker logs -f dbas-mssql

# SQL Server logs inside container
docker exec dbas-mssql tail -f /var/opt/mssql/log/errorlog
```

## 🗂️ Project Structure

```
.
├── Dockerfile              # Docker image definition
├── entrypoint.sh          # Smart startup script
├── Init.sql               # DBAS database creation script
├── LICENSE                # MIT License
├── README.md             # This documentation
└── VERSION               # Current version
```

## 🤝 Contributing

1. Fork the project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📋 Requirements

- Docker 20.10+
- Minimum 2GB RAM available
- Case-sensitive file system support (for Linux containers)

## ⚠️ Important Notes

- **SA Password**: Must be at least 8 characters, including uppercase, lowercase, numbers, and symbols
- **Production**: Always use persistent volumes for `/var/opt/mssql`
- **Networking**: SQL Server runs on default port 1433
- **Licensing**: This project is under MIT license, but SQL Server has its own licensing terms

## 📖 Additional Documentation

- [SQL Server Documentation](https://docs.microsoft.com/en-us/sql/sql-server/)
- [Docker for SQL Server](https://docs.microsoft.com/en-us/sql/linux/sql-server-linux-docker-container-deployment)
- [SQL Server Change Tracking](https://docs.microsoft.com/en-us/sql/relational-databases/track-changes/about-change-tracking-sql-server)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Built with ❤️ for the DBAS project**
