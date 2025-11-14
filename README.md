# 🗄️ DBAS.MSSQL

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](VERSION)
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

```yaml
version: '3.8'
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
    healthcheck:
      test: ["CMD-SHELL", "/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P $$MSSQL_SA_PASSWORD -C -Q 'SELECT 1' -b"]
      interval: 30s
      timeout: 10s
      retries: 3

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

The container includes a health check that verifies:
- SQL Server is responding
- DBAS database is accessible
- All connections are working

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

- [SQL Server 2022 Documentation](https://docs.microsoft.com/en-us/sql/sql-server/)
- [Docker for SQL Server](https://docs.microsoft.com/en-us/sql/linux/sql-server-linux-docker-container-deployment)
- [SQL Server Change Tracking](https://docs.microsoft.com/en-us/sql/relational-databases/track-changes/about-change-tracking-sql-server)

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

**Built with ❤️ for the DBAS project**
