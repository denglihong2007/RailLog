.bail on
.headers on
.mode column

PRAGMA foreign_keys = ON;
BEGIN IMMEDIATE;

-- Rebuild the primary association from the review owner and entity key.
-- Candidate order is deterministic and uses the first cloud trip by Id.
UPDATE EntityReviews
SET TripId = (
    SELECT trip.Id
    FROM TripRecords AS trip
    WHERE trip.UserId = EntityReviews.UserId
      AND trip.DeletedAt IS NULL
      AND (
          (
              lower(EntityReviews.EntityType) = 'station'
              AND (
                  lower(replace(trim(trip.FromStation), ' ', '')) =
                      lower(replace(trim(EntityReviews.EntityKey), ' ', ''))
                  OR lower(replace(trim(trip.ToStation), ' ', '')) =
                      lower(replace(trim(EntityReviews.EntityKey), ' ', ''))
              )
          )
          OR (
              lower(EntityReviews.EntityType) = 'train'
              AND lower(replace(trim(trip.TrainNumber), ' ', '')) =
                  lower(replace(trim(EntityReviews.EntityKey), ' ', ''))
          )
          OR (
              lower(EntityReviews.EntityType) = 'company'
              AND lower(replace(trim(coalesce(trip.CompanyName, '')), ' ', '')) =
                  lower(replace(trim(EntityReviews.EntityKey), ' ', ''))
          )
          OR (
              lower(EntityReviews.EntityType) = 'route'
              AND EXISTS (
                  SELECT 1
                  FROM json_each(trip.ViaRoutes) AS segment
                  WHERE lower(replace(trim(coalesce(
                            json_extract(segment.value, '$.routeName'),
                            json_extract(segment.value, '$.RouteName'),
                            ''
                        )), ' ', '')) =
                        lower(replace(trim(EntityReviews.EntityKey), ' ', ''))
              )
          )
          OR (
              lower(EntityReviews.EntityType) = 'rollingstock'
              AND (
                  upper(replace(coalesce(trip.RollingStock, ''), ' ', '')) =
                      upper(replace(trim(EntityReviews.EntityKey), ' ', ''))
                  OR (
                      substr(
                          upper(replace(coalesce(trip.RollingStock, ''), ' ', '')),
                          1,
                          length(replace(trim(EntityReviews.EntityKey), ' ', '')) + 1
                      ) =
                          upper(replace(trim(EntityReviews.EntityKey), ' ', '')) || '-'
                      AND substr(
                          upper(replace(coalesce(trip.RollingStock, ''), ' ', '')),
                          length(replace(trim(EntityReviews.EntityKey), ' ', '')) + 2,
                          1
                      ) GLOB '[0-9]'
                  )
              )
          )
      )
    ORDER BY trip.Id
    LIMIT 1
);

-- Transfer reviews need a second trip departing from the same station
-- within 24 hours after the selected primary trip arrives.
UPDATE EntityReviews
SET SecondTripId = CASE
    WHEN lower(ReviewType) <> 'transfer' THEN NULL
    ELSE (
        SELECT second_trip.Id
        FROM TripRecords AS primary_trip
        JOIN TripRecords AS second_trip
          ON second_trip.UserId = primary_trip.UserId
         AND second_trip.DeletedAt IS NULL
        WHERE primary_trip.Id = EntityReviews.TripId
          AND primary_trip.UserId = EntityReviews.UserId
          AND primary_trip.DeletedAt IS NULL
          AND primary_trip.ArrivalTime IS NOT NULL
          AND second_trip.Id <> primary_trip.Id
          AND lower(replace(trim(second_trip.FromStation), ' ', '')) =
              lower(replace(trim(EntityReviews.EntityKey), ' ', ''))
          AND julianday(second_trip.DepartureTime) >=
              julianday(primary_trip.ArrivalTime)
          AND julianday(second_trip.DepartureTime) <=
              julianday(primary_trip.ArrivalTime) + 1
        ORDER BY second_trip.Id
        LIMIT 1
    )
END;

COMMIT;

SELECT
    COUNT(*) AS total_reviews,
    SUM(CASE WHEN TripId IS NULL THEN 1 ELSE 0 END) AS without_trip,
    SUM(CASE WHEN TripId IS NOT NULL THEN 1 ELSE 0 END) AS with_trip,
    SUM(CASE WHEN SecondTripId IS NOT NULL THEN 1 ELSE 0 END) AS with_second_trip
FROM EntityReviews;

SELECT
    TripId,
    COUNT(*) AS review_count
FROM EntityReviews
GROUP BY TripId
ORDER BY TripId;

PRAGMA integrity_check;
