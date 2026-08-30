[CmdletBinding()]
param([string]$DumpPath)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DatabaseTools.Common.ps1')

$layout = Get-BayshoreLayout
$settings = Get-DatabaseSettings $layout.ServerRoot
if (-not $DumpPath) { $DumpPath = Select-DatabaseDump $layout 'Select a Bayshore dump to merge into the current save' }
$DumpPath = (Resolve-Path -LiteralPath $DumpPath).Path
Test-DatabaseDump $layout $DumpPath

Confirm-DestructiveAction 'MERGE' `
    "This imports previously unseen card IDs from '$DumpPath'. Existing cards and destination-wide event/ranking data remain unchanged. A safety backup will be created first."

Stop-BayshoreApplication $layout
Ensure-PostgresRunning $layout $settings
$safetyBackup = New-DatabaseBackup $layout $settings 'before-merge'

$createdb = Find-PostgresTool $layout.ServerRoot 'createdb'
$dropdb = Find-PostgresTool $layout.ServerRoot 'dropdb'
$pgRestore = Find-PostgresTool $layout.ServerRoot 'pg_restore'
$pgDump = Find-PostgresTool $layout.ServerRoot 'pg_dump'
$psql = Find-PostgresTool $layout.ServerRoot 'psql'
$temporaryDatabase = 'bayshore_merge_{0}_{1}' -f $PID, (Get-Date -Format 'yyyyMMddHHmmss')
$temporarySql = Join-Path ([IO.Path]::GetTempPath()) "$temporaryDatabase.sql"
$createdTemporaryDatabase = $false

try {
    Invoke-WithDatabasePassword $settings {
        & $createdb -h $settings.HostName -p $settings.Port -U $settings.User -T template0 $temporaryDatabase
    }
    if ($LASTEXITCODE -ne 0) { throw 'Could not create the isolated merge database.' }
    $createdTemporaryDatabase = $true

    Invoke-WithDatabasePassword $settings {
        & $pgRestore -h $settings.HostName -p $settings.Port -U $settings.User -d $temporaryDatabase `
            --no-owner --no-privileges --single-transaction --exit-on-error $DumpPath
    }
    if ($LASTEXITCODE -ne 0) { throw 'Could not restore the incoming dump into the isolated merge database.' }

    $migrationSql = 'SELECT COALESCE(string_agg(migration_name, '','' ORDER BY migration_name), '''') FROM "_prisma_migrations" WHERE finished_at IS NOT NULL AND rolled_back_at IS NULL;'
    $currentMigrations = Invoke-PsqlScalar $layout $settings $settings.Database $migrationSql
    $incomingMigrations = Invoke-PsqlScalar $layout $settings $temporaryDatabase $migrationSql
    if ($currentMigrations -ne $incomingMigrations) {
        throw 'The dump and current server use different Bayshore database migrations. Use matching server versions before merging.'
    }

    $maxSql = @'
SELECT GREATEST(
  COALESCE((SELECT max(id) FROM "User"), 0),
  COALESCE((SELECT max(id) FROM "ScratchSheet"), 0),
  COALESCE((SELECT max(id) FROM "ScratchSquare"), 0),
  COALESCE((SELECT max("userItemId") FROM "UserItem"), 0),
  COALESCE((SELECT max("carId") FROM "Car"), 0),
  COALESCE((SELECT max("dbId") FROM "CarGTWing"), 0),
  COALESCE((SELECT max("dbId") FROM "CarItem"), 0),
  COALESCE((SELECT max("dbId") FROM "CarSettings"), 0),
  COALESCE((SELECT max("dbId") FROM "CarState"), 0),
  COALESCE((SELECT max("dbId") FROM "CarPathandTuning"), 0),
  COALESCE((SELECT max("dbId") FROM "TimeAttackRecord"), 0),
  COALESCE((SELECT max("dbId") FROM "GhostTrail"), 0)
);
'@
    $currentMaximum = [long](Invoke-PsqlScalar $layout $settings $settings.Database $maxSql)
    $incomingMaximum = [long](Invoke-PsqlScalar $layout $settings $temporaryDatabase $maxSql)
    $offset = $currentMaximum + 1
    if (($incomingMaximum + $offset) -ge [int]::MaxValue) {
        throw 'The database IDs are too large to remap safely within PostgreSQL integer columns.'
    }

    $hostSql = ConvertTo-SqlLiteral $settings.HostName
    $databaseSql = ConvertTo-SqlLiteral $settings.Database
    $userSql = ConvertTo-SqlLiteral $settings.User
    $passwordSql = ConvertTo-SqlLiteral $settings.Password
    $prepareSql = @"
BEGIN;
CREATE EXTENSION IF NOT EXISTS postgres_fdw;
DROP SCHEMA IF EXISTS bayshore_current_lookup CASCADE;
DROP SERVER IF EXISTS bayshore_current_server CASCADE;
CREATE SERVER bayshore_current_server FOREIGN DATA WRAPPER postgres_fdw
  OPTIONS (host '$hostSql', port '$($settings.Port)', dbname '$databaseSql');
CREATE USER MAPPING FOR CURRENT_USER SERVER bayshore_current_server
  OPTIONS (user '$userSql', password '$passwordSql');
CREATE SCHEMA bayshore_current_lookup;
IMPORT FOREIGN SCHEMA public LIMIT TO ("User")
  FROM SERVER bayshore_current_server INTO bayshore_current_lookup;

CREATE TEMP TABLE merge_keep_users AS
SELECT source_user.id
FROM public."User" AS source_user
WHERE NOT EXISTS (
  SELECT 1 FROM bayshore_current_lookup."User" AS destination_user
  WHERE destination_user."chipId" = source_user."chipId"
);
CREATE TEMP TABLE merge_keep_cars AS
SELECT car."carId" FROM public."Car" AS car
JOIN merge_keep_users AS kept ON kept.id = car."userId";

SET LOCAL session_replication_role = replica;
DELETE FROM "ScratchSquare" WHERE "sheetId" NOT IN (
  SELECT id FROM "ScratchSheet" WHERE "userId" IN (SELECT id FROM merge_keep_users)
);
DELETE FROM "ScratchSheet" WHERE "userId" NOT IN (SELECT id FROM merge_keep_users);
DELETE FROM "UserItem" WHERE "userId" NOT IN (SELECT id FROM merge_keep_users);
DELETE FROM "CarItem" WHERE "carId" NOT IN (SELECT "carId" FROM merge_keep_cars);
DELETE FROM "CarPathandTuning" WHERE "carId" NOT IN (SELECT "carId" FROM merge_keep_cars);
DELETE FROM "TimeAttackRecord" WHERE "carId" NOT IN (SELECT "carId" FROM merge_keep_cars);
DELETE FROM "GhostTrail" WHERE "carId" NOT IN (SELECT "carId" FROM merge_keep_cars);
DELETE FROM "Car" WHERE "carId" NOT IN (SELECT "carId" FROM merge_keep_cars);
DELETE FROM "CarSettings" WHERE "dbId" NOT IN (SELECT "carSettingsDbId" FROM "Car");
DELETE FROM "CarGTWing" WHERE "dbId" NOT IN (SELECT "carGTWingDbId" FROM "Car");
DELETE FROM "CarState" WHERE "dbId" NOT IN (SELECT "carStateDbId" FROM "Car");
DELETE FROM "User" WHERE id NOT IN (SELECT id FROM merge_keep_users);

UPDATE "User" SET
  id = id + $offset,
  "carOrder" = ARRAY(
    SELECT value + $offset FROM unnest(COALESCE("carOrder", ARRAY[]::integer[])) AS value
  );
UPDATE "ScratchSheet" SET id = id + $offset, "userId" = "userId" + $offset;
UPDATE "ScratchSquare" SET id = id + $offset, "sheetId" = "sheetId" + $offset;
UPDATE "UserItem" SET "userItemId" = "userItemId" + $offset, "userId" = "userId" + $offset;
UPDATE "CarSettings" SET "dbId" = "dbId" + $offset;
UPDATE "CarGTWing" SET "dbId" = "dbId" + $offset;
UPDATE "CarState" SET "dbId" = "dbId" + $offset;
UPDATE "Car" SET
  "carId" = "carId" + $offset,
  "userId" = "userId" + $offset,
  "carSettingsDbId" = "carSettingsDbId" + $offset,
  "carGTWingDbId" = "carGTWingDbId" + $offset,
  "carStateDbId" = "carStateDbId" + $offset,
  "lastPlayedPlaceId" = NULL;
UPDATE "CarItem" SET "dbId" = "dbId" + $offset, "carId" = "carId" + $offset;
UPDATE "CarPathandTuning" SET "dbId" = "dbId" + $offset, "carId" = "carId" + $offset;
UPDATE "TimeAttackRecord" SET "dbId" = "dbId" + $offset, "carId" = "carId" + $offset;
UPDATE "GhostTrail" SET "dbId" = "dbId" + $offset, "carId" = "carId" + $offset;
COMMIT;
"@

    Invoke-WithDatabasePassword $settings {
        $prepareSql | & $psql -X -q -v ON_ERROR_STOP=1 -h $settings.HostName -p $settings.Port `
            -U $settings.User -d $temporaryDatabase
    }
    if ($LASTEXITCODE -ne 0) { throw 'The isolated merge preparation failed.' }

    $importUsers = [int](Invoke-PsqlScalar $layout $settings $temporaryDatabase 'SELECT count(*) FROM "User";')
    $importCars = [int](Invoke-PsqlScalar $layout $settings $temporaryDatabase 'SELECT count(*) FROM "Car";')
    if ($importUsers -eq 0) {
        Write-Host 'No new card IDs were found. The current database was not changed.' -ForegroundColor Yellow
        Write-Host "Safety backup: $safetyBackup"
        return
    }

    $tableArguments = @(
        '--table=public.\"User\"',
        '--table=public.\"ScratchSheet\"',
        '--table=public.\"ScratchSquare\"',
        '--table=public.\"UserItem\"',
        '--table=public.\"CarSettings\"',
        '--table=public.\"CarGTWing\"',
        '--table=public.\"CarState\"',
        '--table=public.\"Car\"',
        '--table=public.\"CarItem\"',
        '--table=public.\"CarPathandTuning\"',
        '--table=public.\"TimeAttackRecord\"',
        '--table=public.\"GhostTrail\"'
    )
    Invoke-WithDatabasePassword $settings {
        & $pgDump -h $settings.HostName -p $settings.Port -U $settings.User -d $temporaryDatabase `
            --data-only --no-owner --no-privileges --file=$temporarySql @tableArguments
    }
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $temporarySql)) {
        throw 'Could not create the isolated player-data import stream.'
    }

    Invoke-WithDatabasePassword $settings {
        & $psql -X -q -v ON_ERROR_STOP=1 --single-transaction -h $settings.HostName -p $settings.Port `
            -U $settings.User -d $settings.Database -f $temporarySql
    }
    if ($LASTEXITCODE -ne 0) {
        throw "Merge import failed. The original data is safe in '$safetyBackup'."
    }

    Write-Host "Merge completed: imported $importUsers new player(s) and $importCars car(s)." -ForegroundColor Green
    Write-Host 'Existing cards and destination-wide crowns/events/rival history were unchanged.'
    Write-Host "Rollback backup: $safetyBackup"
}
finally {
    if (Test-Path -LiteralPath $temporarySql) {
        Remove-Item -LiteralPath $temporarySql -Force -ErrorAction SilentlyContinue
    }
    if ($createdTemporaryDatabase) {
        Invoke-WithDatabasePassword $settings {
            & $dropdb -h $settings.HostName -p $settings.Port -U $settings.User --force $temporaryDatabase *> $null
        }
    }
}
