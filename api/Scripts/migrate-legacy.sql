-- Run after attaching the legacy database as `legacy`, for example:
-- sqlite3 raillog.db "ATTACH DATABASE 'C:/path/to/legacy.db' AS legacy;" ".read Scripts/migrate-legacy.sql"

.bail on

PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;

CREATE TABLE AspNetUsers (
    Id TEXT NOT NULL PRIMARY KEY,
    DisplayName TEXT NOT NULL,
    AvatarUrl TEXT NULL,
    Email TEXT NOT NULL,
    PasswordHash TEXT NOT NULL,
    Bio TEXT NULL,
    ShowEmailOnProfile INTEGER NOT NULL DEFAULT 0,
    CreatedAt TEXT NOT NULL
);

CREATE TABLE AuthTokens (
    TokenHash TEXT NOT NULL PRIMARY KEY,
    UserId TEXT NOT NULL,
    ExpiresAt TEXT NOT NULL,
    FOREIGN KEY (UserId) REFERENCES AspNetUsers (Id) ON DELETE CASCADE
);

CREATE TABLE EmailVerificationCodes (
    Id TEXT NOT NULL PRIMARY KEY,
    Email TEXT NOT NULL,
    Purpose TEXT NOT NULL,
    CodeHash TEXT NOT NULL,
    CreatedAt TEXT NOT NULL,
    ExpiresAt TEXT NOT NULL,
    AttemptCount INTEGER NOT NULL DEFAULT 0,
    ConsumedAt TEXT NULL
);

CREATE TABLE TripRecords (
    Id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    UserId TEXT NOT NULL,
    ClientId TEXT NOT NULL,
    CreatedAt TEXT NOT NULL,
    TrainNumber TEXT NOT NULL,
    TravelDate TEXT NOT NULL,
    RollingStock TEXT NULL,
    CompanyName TEXT NULL,
    FromStation TEXT NOT NULL,
    ToStation TEXT NOT NULL,
    DepartureTime TEXT NULL,
    ArrivalTime TEXT NULL,
    MileageKm REAL NOT NULL,
    ViaRoutes TEXT NOT NULL,
    SeatType TEXT NULL,
    SeatNumber TEXT NULL,
    Price REAL NOT NULL,
    Notes TEXT NULL,
    IsRailTrip INTEGER NOT NULL DEFAULT 1,
    UpdatedAt TEXT NOT NULL,
    DeletedAt TEXT NULL,
    FOREIGN KEY (UserId) REFERENCES AspNetUsers (Id) ON DELETE CASCADE,
    UNIQUE (UserId, ClientId)
);

INSERT INTO AspNetUsers
    (Id, DisplayName, AvatarUrl, Email, PasswordHash, Bio, ShowEmailOnProfile, CreatedAt)
SELECT
    user.Id,
    trim(user.DisplayName),
    nullif(trim(user.AvatarUrl), ''),
    trim(user.Email),
    user.PasswordHash,
    nullif(trim(user.Bio), ''),
    user.ShowEmailOnProfile,
    coalesce(
        (SELECT strftime('%Y-%m-%dT%H:%M:%fZ', min(trip.CreatedAt))
         FROM legacy.TripRecords AS trip
         WHERE trip.UserId = user.Id),
        strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
    )
FROM legacy.AspNetUsers AS user;

INSERT INTO TripRecords
    (Id, UserId, ClientId, CreatedAt, TrainNumber, TravelDate, RollingStock,
     CompanyName, FromStation, ToStation, DepartureTime, ArrivalTime, MileageKm,
     ViaRoutes, SeatType, SeatNumber, Price, Notes, IsRailTrip, UpdatedAt, DeletedAt)
SELECT
    trip.Id,
    trip.UserId,
    'legacy-' || printf('%016x', trip.Id),
    strftime('%Y-%m-%dT%H:%M:%fZ', trip.CreatedAt),
    trip.TrainNumber,
    strftime(
        '%Y-%m-%dT%H:%M:%fZ',
        trip.TravelDate || ' ' || coalesce(trip.DepartureTime, '00:00:00'),
        '-0 hours'
    ),
    nullif(trim(trip.RollingStock), ''),
    NULL,
    trip.FromStation,
    trip.ToStation,
    CASE WHEN trip.DepartureTime IS NULL THEN NULL ELSE
        strftime(
            '%Y-%m-%dT%H:%M:%fZ',
            trip.TravelDate || ' ' || trip.DepartureTime,
            '-0 hours'
        )
    END,
    CASE WHEN trip.ArrivalTime IS NULL THEN NULL ELSE
        strftime(
            '%Y-%m-%dT%H:%M:%fZ',
            trip.TravelDate || ' ' || trip.ArrivalTime,
            CASE WHEN trip.ArrivalTime < trip.DepartureTime THEN '+1 day' ELSE '+0 days' END,
            '-0 hours'
        )
    END,
    CAST(trip.MileageKm AS REAL),
    coalesce((
        SELECT json_group_array(json_object(
            'routeName', json_extract(segment.value, '$.RouteName'),
            'fromStation', json_extract(segment.value, '$.FromStation'),
            'toStation', json_extract(segment.value, '$.ToStation'),
            'mileageKm', CAST(json_extract(segment.value, '$.MileageKm') AS REAL)
        ))
        FROM json_each(trip.ViaRoutes) AS segment
    ), '[]'),
    nullif(trim(trip.SeatType), ''),
    nullif(trim(trip.SeatNumber), ''),
    CAST(trip.Price AS REAL),
    nullif(trim(trip.Notes), ''),
    1,
    strftime('%Y-%m-%dT%H:%M:%fZ', trip.CreatedAt),
    NULL
FROM legacy.TripRecords AS trip;

CREATE UNIQUE INDEX IX_AspNetUsers_Email
    ON AspNetUsers (Email COLLATE NOCASE);
CREATE UNIQUE INDEX IX_AspNetUsers_DisplayName
    ON AspNetUsers (DisplayName COLLATE NOCASE);
CREATE INDEX IX_AuthTokens_UserId ON AuthTokens (UserId);
CREATE INDEX IX_EmailVerificationCodes_Lookup
    ON EmailVerificationCodes (Email, Purpose, CreatedAt DESC);
CREATE INDEX IX_TripRecords_UserId ON TripRecords (UserId);
CREATE UNIQUE INDEX IX_TripRecords_UserClient
    ON TripRecords (UserId, ClientId);

COMMIT;
PRAGMA foreign_key_check;
PRAGMA integrity_check;
