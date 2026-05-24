-- Migration 001: convert patient risk columns from BOOLEAN to VARCHAR(20)
--
-- The app has always shown graded risk levels ('none' / 'low' / 'medium' /
-- 'high') in the UI, but the database column was BOOLEAN. That broke the
-- "create patient" form with: "Input should be a valid boolean".
--
-- Run this once if you have existing patient data you want to keep:
--   docker compose exec -T database psql -U postgres -d $POSTGRES_DB \
--     < database/migrations/001_risk_levels_to_string.sql
--
-- If you don't care about existing data, just nuke the DB instead:
--   docker compose down -v
--   docker compose up -d
-- (The updated init.sql will recreate the tables with the right column type.)

BEGIN;

ALTER TABLE patient_profiles
    ALTER COLUMN fall_risk DROP DEFAULT,
    ALTER COLUMN fall_risk TYPE VARCHAR(20)
        USING CASE WHEN fall_risk THEN 'high' ELSE 'none' END,
    ALTER COLUMN fall_risk SET DEFAULT 'none',
    ALTER COLUMN fall_risk SET NOT NULL;

ALTER TABLE patient_profiles
    ALTER COLUMN seizure_risk DROP DEFAULT,
    ALTER COLUMN seizure_risk TYPE VARCHAR(20)
        USING CASE WHEN seizure_risk THEN 'high' ELSE 'none' END,
    ALTER COLUMN seizure_risk SET DEFAULT 'none',
    ALTER COLUMN seizure_risk SET NOT NULL;

COMMIT;
