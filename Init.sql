IF NOT EXISTS (SELECT * FROM sys.databases WHERE name = '@DB_NAME')
BEGIN
    CREATE DATABASE [@DB_NAME]
    ON PRIMARY
    (
        NAME = N'@DB_FILE_NAME',
        FILENAME = N'/var/opt/mssql/data/@DB_FILE_NAME.mdf',
        SIZE = 256MB,
        FILEGROWTH = 128MB
    )
    LOG ON
    (
        NAME = N'@LOG_FILE_NAME',
        FILENAME = N'/var/opt/mssql/data/@LOG_FILE_NAME.ldf',
        SIZE = 256MB,
        FILEGROWTH = 128MB
    )
    COLLATE @MSSQL_COLLATION;
END

IF NOT EXISTS (SELECT 1 FROM sys.databases WHERE name = '@DB_NAME' AND is_read_committed_snapshot_on = 1)
BEGIN
    ALTER DATABASE [@DB_NAME] SET READ_COMMITTED_SNAPSHOT ON;
END

IF (ISNULL(DATABASEPROPERTYEX('@DB_NAME', 'IsChangeTrackingEnabled'), 0) = 0)
BEGIN
    ALTER DATABASE [@DB_NAME]
    SET CHANGE_TRACKING = ON  
    (AUTO_CLEANUP = ON, CHANGE_RETENTION = @DB_CHANGE_TRACKING_PERIOD_DAYS DAYS)
END
