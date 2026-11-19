-- Missions with several spots (docs/missions.md, Spots): one mission, one cleanup, one receipt and one payment, at up to
-- 4 places and days. Spot 1 stays where it always was: the mission's place_name, lat, lng and plan_date, and the cleanup's
-- place_name, lat, lng and cleanup_date. Marcus said 'Yes, build it' on 2026-11-17, for mission #2 (two days, two nearby
-- places).
--   missions.spots     spots 2 to 4 of the mission, a JSON array [{place_name, lat, lng, date}] in spot order, NULL for a
--                      mission with one spot. Written by Sapu Earth for now (an UPDATE in the D1 console, docs/missions.md).
--   submissions.spots  the same for the cleanup of such a mission, copied from the mission by POST /api/submit, with the
--                      day the crew cleaned each spot.
--   uploads.spot       the spot a cleanup's before or after photo shows, 2 to 4; NULL for spot 1, for every photo of a
--                      mission with one spot, and for every video (a mission keeps one video before and one after).
-- The points of spots 2 to 4 are stored rounded to 3 decimals (about 100 m, the public precision), so they hold nothing
-- private: removing a mission and the 90-day trim leave them as they are.
-- Additive, and the code works without it (withSpots in functions/_lib/spots.js): every mission then has one spot. Run it
-- BEFORE the UPDATE that gives mission #2 its second spot, and before or after the code; before is better.
-- Apply with: sh scripts/remote-migrate.sh --apply (ops/production-rules.md). Pasted into the D1 console a second time it
-- fails with "duplicate column name": it is already in then.
ALTER TABLE missions ADD COLUMN spots TEXT;
ALTER TABLE submissions ADD COLUMN spots TEXT;
ALTER TABLE uploads ADD COLUMN spot INTEGER CHECK (spot BETWEEN 2 AND 4);
