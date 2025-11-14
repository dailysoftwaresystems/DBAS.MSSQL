#!/bin/bash
set -e

PASS="${MSSQL_SA_PASSWORD:-${SA_PASSWORD:-}}"
if [ -z "$PASS" ]; then
  echo "ERROR: SA password is not set (MSSQL_SA_PASSWORD/SA_PASSWORD)."
  exit 1
fi

export ACCEPT_EULA="Y"
export SA_PASSWORD="$PASS"
export MSSQL_SA_PASSWORD="$PASS"

echo "Starting SQL Server ($DB_NAME)..."
start_all=$(date +%s)
/opt/mssql/bin/sqlservr &
SQL_PID=$!

echo "Waiting for SQL error log to be created..."
until [ -f /var/opt/mssql/log/errorlog ]; do
    sleep 2
done

echo "Waiting SQL to be ready for connections..."
until grep -q "SQL Server is now ready for client connection" /var/opt/mssql/log/errorlog; do 
    sleep 2
done

LOGIN_TIMEOUT=120
echo "Waiting for SQL Server to accept connections (timeout: $LOGIN_TIMEOUT seconds)..."
start_ts=$(date +%s)
until /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -C -Q "SELECT 1" -b &>/dev/null; do
    echo "$(date) - Waiting for SA login..."
    now=$(date +%s)
    if [ $((now - start_ts)) -gt "$LOGIN_TIMEOUT" ]; then
        echo "ERROR: Timed out waiting for SA login after ${LOGIN_TIMEOUT}s"
        echo "Last 10 lines of errorlog:"
        tail -n 200 /var/opt/mssql/log/errorlog || true
        exit 1
    fi
    sleep 5
done

echo "Waiting for all system databases to be online..."
until /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -C -Q "SELECT CASE WHEN COUNT(*) >= 4 THEN 1 ELSE 0 END FROM sys.databases WHERE name IN ('master','tempdb','model','msdb') AND state_desc='ONLINE';"  -b | grep -q 1; do
    sleep 5
done

echo "Checking if $DB_NAME database exists..."
if ! /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -C \
  -Q "SET NOCOUNT ON; SELECT name FROM sys.databases WHERE name = '$DB_NAME';" \
  -h -1 | tr -d '[:space:]' | grep -q "^$DB_NAME$"; then
    echo "Database $DB_NAME not found. Running initialization..."
    DB_FILE_NAME=$(echo "${DB_NAME}_data" | sed 's/[^a-zA-Z0-9]/_/g' | tr '[:upper:]' '[:lower:]')
    LOG_FILE_NAME=$(echo "${DB_NAME}_log" | sed 's/[^a-zA-Z0-9]/_/g' | tr '[:upper:]' '[:lower:]')

    sed -e "s/@DB_NAME/$DB_NAME/g" \
        -e "s/@DB_FILE_NAME/$DB_FILE_NAME/g" \
        -e "s/@LOG_FILE_NAME/$LOG_FILE_NAME/g" \
        -e "s/@MSSQL_COLLATION/$MSSQL_COLLATION/g" \
        -e "s/@DB_CHANGE_TRACKING_PERIOD_DAYS/$DB_CHANGE_TRACKING_PERIOD_DAYS/g" \
        /start-up/init.sql > /start-up/final_init.sql
    
    # Retry logic for SQL initialization
    MAX_RETRIES=3
    RETRY_COUNT=0
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "Attempt $RETRY_COUNT of $MAX_RETRIES: Running initialization script..."
        
        if INIT_OUTPUT=$(/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -C -i /start-up/final_init.sql -b 2>&1); then
            echo "$DB_NAME initialization completed successfully"
            break
        else
            echo "Attempt $RETRY_COUNT failed. SQL Error Output:"
            echo "$INIT_OUTPUT"
            
            if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
                echo "Retrying in 1 second..."
                sleep 1
            else
                echo "ERROR: Failed to execute init script after $MAX_RETRIES attempts"
                echo "Last 20 lines of SQL Server errorlog:"
                tail -n 20 /var/opt/mssql/log/errorlog || true
                exit 1
            fi
        fi
    done
fi

echo "Waiting for $DB_NAME db to be up..."
until /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -C -Q "SELECT CASE WHEN DB_ID('$DB_NAME') IS NOT NULL THEN 1 ELSE 0 END;" -b | grep -q 1; do
    sleep 5
done

now=$(date +%s)
echo "SQL Server is ready for application commands ($DB_NAME) (startup time: $((now - start_all)) seconds)"
wait $SQL_PID
