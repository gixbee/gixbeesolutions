-- Decoration catalogues use the same table as photography and catering.
-- The original check allowed only those two and rejected every decoration save.
-- The first name keeps its mixed case; an unquoted name is folded to lowercase.
ALTER TABLE event_service_catalogues
  DROP CONSTRAINT IF EXISTS "event_service_catalogues_serviceType_check";
ALTER TABLE event_service_catalogues
  DROP CONSTRAINT IF EXISTS event_service_catalogues_servicetype_check;

ALTER TABLE event_service_catalogues
  ADD CONSTRAINT event_service_catalogues_servicetype_check
  CHECK ("serviceType" IN ('PHOTOGRAPHY', 'CATERING', 'DECORATION'));
