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

READY_MARKER="${DBAS_READY_MARKER:-/dev/shm/dbas-ready}"
LOGIN_TIMEOUT="${LOGIN_TIMEOUT:-300}"
DB_READY_TIMEOUT="${DB_READY_TIMEOUT:-180}"

# DBAS_READY_MARKER points at /dev/shm, a tmpfs Docker mounts fresh on every
# container start, so it cannot be inherited from a previous run. Clearing it
# anyway costs nothing and keeps the guarantee if the marker is ever pointed at a
# path that does persist.
rm -f "$READY_MARKER"

# Elapsed time must come from a monotonic source. `date +%s` is wall clock and
# jumps when the host suspends/resumes or NTP corrects the VM clock -- observed
# on Docker Desktop as a 22s backward step mid-startup, which would make an
# elapsed-time check go negative and never time out. /proc/uptime is monotonic.
now_secs() {
    awk '{print int($1)}' /proc/uptime
}

# Drop readiness the moment shutdown starts, so dependents stop being pointed at a
# server that is going away, then let sqlservr checkpoint before this script
# exits -- once it returns, tini exits and the container is torn down, so exiting
# early would cut the shutdown short and force crash recovery on the next start.
#
# sqlservr is a grandchild (launch_sqlservr.sh starts it), so it cannot be
# signalled via $! and is addressed by name instead.
SHUTDOWN_TIMEOUT="${SHUTDOWN_TIMEOUT:-55}"
term_handler() {
    echo "Shutdown signal received, stopping SQL Server ($DB_NAME)..."
    rm -f "$READY_MARKER"
    pkill -TERM -x sqlservr 2>/dev/null || true

    waited=0
    while pgrep -x sqlservr >/dev/null 2>&1; do
        if [ "$waited" -ge "$SHUTDOWN_TIMEOUT" ]; then
            echo "WARNING: SQL Server still running after ${SHUTDOWN_TIMEOUT}s, exiting anyway"
            break
        fi
        waited=$((waited + 1))
        sleep 1
    done

    echo "SQL Server stopped after ${waited}s."
    exit 0
}
trap term_handler SIGTERM SIGINT

# -b sets a non-zero exit code on error, so callers can test readiness by exit
# status alone. Piping sqlcmd into grep would mask its exit code and match stray
# digits in the "(N rows affected)" footer.
sqlcmd_q() {
    /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$SA_PASSWORD" -C -b -h -1 -W "$@"
}

echo "Starting SQL Server ($DB_NAME)..."
start_all=$(now_secs)

# The base image's launcher, invoked the same way its own ENTRYPOINT would: it
# runs permissions_check.sh and init_custom_setup.sh, starts sqlservr, then runs
# run_custom_setup.sh. Calling it from here (rather than being called by it) is
# what lets this script own shutdown -- see the ENTRYPOINT note in the Dockerfile.
/opt/mssql/bin/launch_sqlservr.sh /opt/mssql/bin/sqlservr &
LAUNCHER_PID=$!

echo "Waiting for SQL error log to be created..."
until [ -f /var/opt/mssql/log/errorlog ]; do
    sleep 2
done

echo "Waiting SQL to be ready for connections..."
until grep -q "SQL Server is now ready for client connection" /var/opt/mssql/log/errorlog; do 
    sleep 2
done

# Changing MSSQL_COLLATION rebuilds the system databases, during which sa logins
# fail for as long as the rebuild takes. On a loaded host that can run well past
# two minutes, so this wait has to be generous.
echo "Waiting for SQL Server to accept connections (timeout: $LOGIN_TIMEOUT seconds)..."
start_ts=$(now_secs)
until sqlcmd_q -Q "SELECT 1" &>/dev/null; do
    echo "$(date) - Waiting for SA login..."
    now=$(now_secs)
    if [ $((now - start_ts)) -gt "$LOGIN_TIMEOUT" ]; then
        echo "ERROR: Timed out waiting for SA login after ${LOGIN_TIMEOUT}s"
        echo "Last 200 lines of errorlog:"
        tail -n 200 /var/opt/mssql/log/errorlog || true
        exit 1
    fi
    sleep 5
done

echo "Waiting for all system databases to be online (timeout: $DB_READY_TIMEOUT seconds)..."
start_ts=$(now_secs)
until sqlcmd_q -Q "SET NOCOUNT ON; IF (SELECT COUNT(*) FROM sys.databases WHERE name IN ('master','tempdb','model','msdb') AND state_desc = 'ONLINE') < 4 RAISERROR('system databases not online', 16, 1);" &>/dev/null; do
    now=$(now_secs)
    if [ $((now - start_ts)) -gt "$DB_READY_TIMEOUT" ]; then
        echo "ERROR: Timed out waiting for system databases after ${DB_READY_TIMEOUT}s"
        tail -n 200 /var/opt/mssql/log/errorlog || true
        exit 1
    fi
    sleep 5
done

DB_FILE_NAME=$(echo "${DB_NAME}_data" | sed 's/[^a-zA-Z0-9]/_/g' | tr '[:upper:]' '[:lower:]')
LOG_FILE_NAME=$(echo "${DB_NAME}_log" | sed 's/[^a-zA-Z0-9]/_/g' | tr '[:upper:]' '[:lower:]')

sed -e "s/@DB_NAME/$DB_NAME/g" \
    -e "s/@DB_FILE_NAME/$DB_FILE_NAME/g" \
    -e "s/@LOG_FILE_NAME/$LOG_FILE_NAME/g" \
    -e "s/@MSSQL_COLLATION/$MSSQL_COLLATION/g" \
    -e "s/@DB_CHANGE_TRACKING_PERIOD_DAYS/$DB_CHANGE_TRACKING_PERIOD_DAYS/g" \
    /start-up/init.sql > /start-up/final_init.sql

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

# Connecting with -d is the same thing dependent services do, so this gate proves
# the database is genuinely openable rather than merely present in sys.databases.
echo "Waiting for $DB_NAME to accept connections (timeout: $DB_READY_TIMEOUT seconds)..."
start_ts=$(now_secs)
until sqlcmd_q -d "$DB_NAME" -Q "SELECT 1" &>/dev/null; do
    now=$(now_secs)
    if [ $((now - start_ts)) -gt "$DB_READY_TIMEOUT" ]; then
        echo "ERROR: Timed out waiting for $DB_NAME to accept connections after ${DB_READY_TIMEOUT}s"
        tail -n 200 /var/opt/mssql/log/errorlog || true
        exit 1
    fi
    sleep 5
done

touch "$READY_MARKER"

now=$(now_secs)
echo "SQL Server is ready for application commands ($DB_NAME) (startup time: $((now - start_all)) seconds)"

# `wait` is interruptible, so a SIGTERM arriving here runs term_handler rather
# than being deferred until SQL Server exits on its own.
wait "$LAUNCHER_PID"
