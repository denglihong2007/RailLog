.bail on
.headers on
.mode column

-- One-time repair of the TripRecords id space. Run with the API stopped, against
-- a database that has been backed up first.
--
-- Between the 2.4.0 release and the fix now in SyncTripsCoreAsync the server used
-- a blind "INSERT ... ON CONFLICT(UserId, ClientId) DO UPDATE". SQLite allocates
-- the AUTOINCREMENT rowid before it detects the uniqueness conflict, so every trip
-- a client re-uploaded burned an id even when nothing about it had changed. Ids
-- that should sit just above the trip count had reached 583403, and since
-- TripRecords.Id is the number the app shows as the trip number ("#583403") and
-- what /api/trips/{id} resolves, the visible numbers had drifted far from reality.
--
-- This renumbers Id to a dense 1..N. New ids keep the old ordering (ROW_NUMBER
-- over the old Id), so a trip created earlier still sorts before a later one and
-- IX_TripRecords_UserPublicDashboard (..., Id DESC) keeps meaning the same thing.
--
-- Everything that stores a trip id is remapped in the same transaction:
-- UserAchievements.TriggerTripId, EntityReviews.TripId, EntityReviews.SecondTripId.
--
-- Each user's UserSyncState.Version is then advanced and their rows are stamped
-- with the new value, so every client's next sync - with or without local edits -
-- returns that client's whole trip list. Clients keep a local ticket_id and open
-- the trip page with it (TripRecordDetailsPage.public(ticketId:)), so a client that
-- failed to re-pull would open the wrong trip.
--
-- TripRecords is rebuilt rather than updated in place: assigning INTEGER PRIMARY
-- KEY values row by row can land on a row the scan has not visited yet. Foreign
-- keys stay off for the rebuild and the remap finishes before COMMIT, so
-- PRAGMA foreign_key_check validates the committed result instead of the
-- intermediate state. legacy_alter_table stops the rename from rewriting the
-- UserAchievements.TriggerTripId foreign key clause out from under us.

PRAGMA foreign_keys = OFF;
PRAGMA legacy_alter_table = ON;

BEGIN IMMEDIATE;

-- Indexed on both sides: the rebuild joins on old_id and the remap lookups below
-- probe by old_id, so an unindexed map turns each of those into a full scan.
CREATE TEMP TABLE trip_id_map (
    old_id INTEGER NOT NULL PRIMARY KEY,
    new_id INTEGER NOT NULL
);
INSERT INTO trip_id_map (old_id, new_id)
SELECT Id, ROW_NUMBER() OVER (ORDER BY Id) FROM TripRecords;
CREATE UNIQUE INDEX trip_id_map_new_id ON trip_id_map (new_id);

CREATE TABLE TripRecords_rebuild (
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
    DeletedAt TEXT NULL, "ServerUpdatedAt" TEXT NULL, "SyncVersion" INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (UserId) REFERENCES AspNetUsers (Id) ON DELETE CASCADE,
    UNIQUE (UserId, ClientId)
);

INSERT INTO TripRecords_rebuild
    (Id, UserId, ClientId, CreatedAt, TrainNumber, TravelDate, RollingStock,
     CompanyName, FromStation, ToStation, DepartureTime, ArrivalTime, MileageKm,
     ViaRoutes, SeatType, SeatNumber, Price, Notes, IsRailTrip, UpdatedAt,
     DeletedAt, "ServerUpdatedAt", "SyncVersion")
SELECT
     map.new_id, trip.UserId, trip.ClientId, trip.CreatedAt, trip.TrainNumber,
     trip.TravelDate, trip.RollingStock, trip.CompanyName, trip.FromStation,
     trip.ToStation, trip.DepartureTime, trip.ArrivalTime, trip.MileageKm,
     trip.ViaRoutes, trip.SeatType, trip.SeatNumber, trip.Price, trip.Notes,
     trip.IsRailTrip, trip.UpdatedAt, trip.DeletedAt, trip."ServerUpdatedAt",
     trip."SyncVersion"
FROM TripRecords AS trip
JOIN trip_id_map AS map ON map.old_id = trip.Id;

DROP TABLE TripRecords;
ALTER TABLE TripRecords_rebuild RENAME TO TripRecords;

CREATE INDEX IX_TripRecords_UserId ON TripRecords (UserId);
CREATE UNIQUE INDEX IX_TripRecords_UserClient ON TripRecords (UserId, ClientId);
CREATE INDEX IX_TripRecords_UserServerUpdatedAt ON TripRecords (UserId, ServerUpdatedAt);
CREATE INDEX IX_TripRecords_UserSyncVersion ON TripRecords (UserId, SyncVersion);
CREATE INDEX IX_TripRecords_UserPublicDashboard
    ON TripRecords (UserId, DeletedAt, DepartureTime DESC, Id DESC);

-- Remap every stored trip id through the same mapping the table was rebuilt with.
UPDATE UserAchievements
SET TriggerTripId = (SELECT new_id FROM trip_id_map WHERE old_id = TriggerTripId);

UPDATE EntityReviews
SET TripId = (SELECT new_id FROM trip_id_map WHERE old_id = TripId)
WHERE TripId IS NOT NULL;

UPDATE EntityReviews
SET SecondTripId = (SELECT new_id FROM trip_id_map WHERE old_id = SecondTripId)
WHERE SecondTripId IS NOT NULL;

-- DROP TABLE removed the old sequence row; put it back at the new high-water mark
-- so the next trip inserted continues from 33724 instead of starting over.
DELETE FROM sqlite_sequence WHERE name = 'TripRecords';
INSERT INTO sqlite_sequence (name, seq)
SELECT 'TripRecords', MAX(new_id) FROM trip_id_map;

-- Hand every client a reason to re-pull its full trip list. The client stores the
-- serverVersion it last saw, so rows stamped with the bumped per-user version fall
-- inside "SyncVersion > sinceVersion AND SyncVersion <= serverVersion" on the next
-- sync whether or not that client has local edits to upload.
UPDATE UserSyncState SET Version = Version + 1;
UPDATE TripRecords
SET SyncVersion = (SELECT Version FROM UserSyncState WHERE UserId = TripRecords.UserId)
WHERE UserId IN (SELECT UserId FROM UserSyncState);

-- A bad remap must roll the whole transaction back rather than commit quietly, so
-- every invariant is asserted as a CHECK that fails the script (.bail on) on
-- violation. A failed script leaves the transaction uncommitted, and an abandoned
-- transaction is rolled back when sqlite3 exits.
CREATE TEMP TABLE verification (ok INTEGER NOT NULL CHECK (ok = 1));

INSERT INTO verification (ok)
SELECT CASE WHEN (SELECT COUNT(*) FROM TripRecords) =
                 (SELECT COUNT(*) FROM trip_id_map)
            THEN 1 ELSE 0 END;

-- Dense and 1-based: the highest id equals the row count.
INSERT INTO verification (ok)
SELECT CASE WHEN (SELECT MAX(Id) FROM TripRecords) =
                 (SELECT COUNT(*) FROM TripRecords)
            THEN 1 ELSE 0 END;

-- The mapping itself is a bijection onto 1..N: old_id is the primary key and
-- new_id carries a unique index, so density here means every id was handed out
-- exactly once. Whether each id landed on the right trip is checked separately,
-- against the pre-migration backup.
INSERT INTO verification (ok)
SELECT CASE WHEN (SELECT COUNT(*) FROM trip_id_map) =
                 (SELECT MAX(new_id) FROM trip_id_map)
            THEN 1 ELSE 0 END;

INSERT INTO verification (ok)
SELECT CASE WHEN (SELECT seq FROM sqlite_sequence WHERE name = 'TripRecords') =
                 (SELECT MAX(new_id) FROM trip_id_map)
            THEN 1 ELSE 0 END;

INSERT INTO verification (ok)
SELECT CASE WHEN (SELECT COUNT(*) FROM pragma_foreign_key_check) = 0
            THEN 1 ELSE 0 END;

INSERT INTO verification (ok)
SELECT CASE WHEN (
           SELECT COUNT(*) FROM UserAchievements
           WHERE TriggerTripId NOT IN (SELECT Id FROM TripRecords)
       ) = 0
       AND (
           SELECT COUNT(*) FROM EntityReviews
           WHERE TripId IS NOT NULL AND TripId NOT IN (SELECT Id FROM TripRecords)
       ) = 0
       AND (
           SELECT COUNT(*) FROM EntityReviews
           WHERE SecondTripId IS NOT NULL
             AND SecondTripId NOT IN (SELECT Id FROM TripRecords)
       ) = 0
            THEN 1 ELSE 0 END;

COMMIT;

PRAGMA foreign_keys = ON;
PRAGMA legacy_alter_table = OFF;

SELECT
    COUNT(*) AS trips,
    MIN(Id) AS min_id,
    MAX(Id) AS max_id,
    (SELECT seq FROM sqlite_sequence WHERE name = 'TripRecords') AS sequence,
    (SELECT COUNT(DISTINCT UserId) FROM TripRecords) AS owners
FROM TripRecords;

SELECT
    COUNT(*) AS achievements,
    MIN(TriggerTripId) AS min_trigger_id,
    MAX(TriggerTripId) AS max_trigger_id
FROM UserAchievements;

SELECT
    COUNT(*) AS reviews,
    SUM(CASE WHEN TripId IS NOT NULL THEN 1 ELSE 0 END) AS with_trip,
    SUM(CASE WHEN SecondTripId IS NOT NULL THEN 1 ELSE 0 END) AS with_second_trip
FROM EntityReviews;

-- Every owner must now be stamped with their bumped version, otherwise that
-- client's next sync returns nothing and it keeps its stale ticket_ids.
SELECT
    COUNT(*) AS owners_not_stamped
FROM TripRecords AS trip
WHERE trip.SyncVersion <> (
    SELECT Version FROM UserSyncState WHERE UserId = trip.UserId
);

-- Spot check: the ten trips that had the largest ids must still be the ten
-- largest, and their owners unchanged.
SELECT Id, UserId, ClientId, TrainNumber, TravelDate, SyncVersion
FROM TripRecords
ORDER BY Id DESC
LIMIT 10;

PRAGMA foreign_key_check;
PRAGMA integrity_check;
