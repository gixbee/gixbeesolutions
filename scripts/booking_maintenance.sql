CREATE TABLE IF NOT EXISTS booking_maintenance (
    id boolean PRIMARY KEY DEFAULT true CHECK (id),
    "nextRunAt" timestamptz NOT NULL DEFAULT NOW()
);
INSERT INTO booking_maintenance (id) VALUES (true) ON CONFLICT DO NOTHING;

CREATE INDEX IF NOT EXISTS booking_offers_expiry ON booking_offer_recipients (expires_at);
CREATE INDEX IF NOT EXISTS booking_deadlines_processed ON booking_deadlines ("processedAt")
    WHERE "processedAt" IS NOT NULL;
CREATE INDEX IF NOT EXISTS outbox_processed_booking ON outbox_events ("processedAt")
    WHERE status='processed' AND type IN ('booking.broadcast_created','booking.accepted','booking.cancelled',
        'booking.completed','booking.payment_confirmed','booking.gps_progress','marketplace.notify');

CREATE OR REPLACE FUNCTION enqueue_booking_deadline_events() RETURNS trigger
LANGUAGE plpgsql SET search_path = pg_catalog, public AS $$
BEGIN
    IF NEW.status='REQUESTED' AND NEW.type='INSTANT' THEN
        INSERT INTO booking_deadlines ("bookingId",kind,sequence,"dueAt")
        SELECT NEW.id,'TIMEOUT',n,NEW."createdAt"+n*INTERVAL '90 seconds'
        FROM (VALUES (1),(2)) AS steps(n)
        ON CONFLICT ("bookingId",kind,sequence) DO NOTHING;
    ELSIF NEW.status='ACCEPTED' AND NEW."acceptedAt" IS NOT NULL THEN
        INSERT INTO booking_deadlines ("bookingId",kind,sequence,"dueAt")
        VALUES (NEW.id,'REMINDER',1,(NEW."acceptedAt" AT TIME ZONE 'UTC')+INTERVAL '7 minutes')
        ON CONFLICT ("bookingId",kind,sequence) DO NOTHING;

        IF NEW."workerNoProgressAt" IS NULL AND NEW."gpsStrikes"<3 THEN
            INSERT INTO booking_deadlines ("bookingId",kind,sequence,"dueAt")
            VALUES (NEW.id,'GPS',NEW."gpsStrikes"+1,CASE WHEN NEW."gpsStrikes"=0
                THEN (NEW."acceptedAt" AT TIME ZONE 'UTC')+INTERVAL '10 minutes'
                ELSE NOW()+INTERVAL '3 minutes' END)
            ON CONFLICT ("bookingId",kind,sequence) DO NOTHING;
        END IF;
    END IF;
    RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS booking_deadline_events ON bookings;
CREATE TRIGGER booking_deadline_events
    AFTER INSERT OR UPDATE OF status, "acceptedAt", "gpsStrikes", "workerNoProgressAt"
    ON bookings FOR EACH ROW EXECUTE FUNCTION enqueue_booking_deadline_events();
