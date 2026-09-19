CREATE EXTENSION IF NOT EXISTS pgcrypto;

DO $$ BEGIN
  CREATE TYPE "master_entries_type_enum" AS ENUM (
    'CATEGORY', 'SERVICE', 'ROLE', 'CONFIGURATION', 'BANNER', 'DEAL', 'PRO_TRADE', 'PRO_SUB_SKILL'
  );
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS master_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type "master_entries_type_enum" NOT NULL,
  label varchar NOT NULL,
  value varchar NOT NULL,
  icon varchar,
  category varchar,
  "cityId" uuid,
  "isActive" boolean NOT NULL DEFAULT true,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS cities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name varchar NOT NULL,
  state varchar NOT NULL,
  lat double precision NOT NULL,
  lng double precision NOT NULL,
  "isActive" boolean NOT NULL DEFAULT true,
  "createdAt" timestamptz NOT NULL DEFAULT now(),
  "updatedAt" timestamptz NOT NULL DEFAULT now()
);

-- Cities (only if empty)
INSERT INTO cities (name, state, lat, lng, "isActive")
SELECT * FROM (VALUES
  ('Kochi', 'Kerala', 9.9312, 76.2673, true),
  ('Thiruvananthapuram', 'Kerala', 8.5241, 76.9366, true),
  ('Kozhikode', 'Kerala', 11.2588, 75.7804, true),
  ('Bangalore', 'Karnataka', 12.9716, 77.5946, true),
  ('Chennai', 'Tamil Nadu', 13.0827, 80.2707, true),
  ('Mumbai', 'Maharashtra', 19.076, 72.8777, true),
  ('Coimbatore', 'Tamil Nadu', 11.0168, 76.9558, true)
) AS v(name, state, lat, lng, "isActive")
WHERE NOT EXISTS (SELECT 1 FROM cities LIMIT 1);

-- Default active trades
INSERT INTO master_entries (type, label, value, icon, "isActive")
SELECT 'PRO_TRADE', x.label, '', x.icon, true
FROM (VALUES
  ('Electrician', 'bolt_rounded'),
  ('Plumber', 'plumbing_rounded'),
  ('Driver', 'directions_car_rounded'),
  ('Cleaner', 'cleaning_services_rounded'),
  ('Nurse', 'medical_services_rounded'),
  ('Carpenter', 'handyman_rounded'),
  ('AC Technician', 'ac_unit_rounded')
) AS x(label, icon)
WHERE NOT EXISTS (SELECT 1 FROM master_entries e WHERE e.type = 'PRO_TRADE' AND e.label = x.label);

INSERT INTO master_entries (type, label, value, category, "isActive")
SELECT 'PRO_SUB_SKILL', x.label, x.label, x.category, true
FROM (VALUES
  ('Wiring & rewiring', 'Electrician'),
  ('Switch & socket repair', 'Electrician'),
  ('Fan installation', 'Electrician'),
  ('Light fitting', 'Electrician'),
  ('MCB / fuse box', 'Electrician'),
  ('Inverter & battery', 'Electrician'),
  ('Pipe leaking / dripping', 'Plumber'),
  ('Burst pipe emergency', 'Plumber'),
  ('Wall / ceiling leakage', 'Plumber'),
  ('Joint / fitting leak', 'Plumber'),
  ('Drain & blockage', 'Plumber'),
  ('Toilet repair', 'Plumber'),
  ('Tap & faucet', 'Plumber'),
  ('Water supply', 'Plumber'),
  ('Personal driver (hourly)', 'Driver'),
  ('Outstation trips', 'Driver'),
  ('Two-wheeler delivery', 'Driver'),
  ('Goods transport', 'Driver'),
  ('Airport pickup / drop', 'Driver'),
  ('Home deep cleaning', 'Cleaner'),
  ('Bathroom cleaning', 'Cleaner'),
  ('Kitchen cleaning', 'Cleaner'),
  ('Sofa & carpet', 'Cleaner'),
  ('Office cleaning', 'Cleaner'),
  ('Move-in / move-out', 'Cleaner'),
  ('Water tank cleaning', 'Cleaner'),
  ('Well cleaning', 'Cleaner'),
  ('Elderly care', 'Nurse'),
  ('Patient bedside care', 'Nurse'),
  ('Injection & dressing', 'Nurse'),
  ('Post-surgery care', 'Nurse'),
  ('Baby care', 'Nurse'),
  ('Furniture repair', 'Carpenter'),
  ('Door & window fitting', 'Carpenter'),
  ('Modular kitchen', 'Carpenter'),
  ('Bed & wardrobe', 'Carpenter'),
  ('Custom woodwork', 'Carpenter'),
  ('AC servicing', 'AC Technician'),
  ('Gas refill', 'AC Technician'),
  ('Installation / uninstall', 'AC Technician'),
  ('Cooling repair', 'AC Technician'),
  ('Water leakage fix', 'AC Technician')
) AS x(label, category)
WHERE NOT EXISTS (
  SELECT 1 FROM master_entries e
  WHERE e.type = 'PRO_SUB_SKILL' AND e.label = x.label AND e.category = x.category
);

-- Expanded trades (inactive until you have pros)
INSERT INTO master_entries (type, label, value, icon, "isActive")
SELECT 'PRO_TRADE', x.label, '', x.icon, false
FROM (VALUES
  ('Painter', 'format_paint_rounded'),
  ('Appliance Technician', 'local_laundry_service_rounded'),
  ('Pest Control', 'pest_control_rounded'),
  ('Beautician', 'spa_rounded'),
  ('Electronics Repair', 'devices_rounded'),
  ('Gardener', 'grass_rounded'),
  ('Renovation Pro', 'construction_rounded')
) AS x(label, icon)
WHERE NOT EXISTS (SELECT 1 FROM master_entries e WHERE e.type = 'PRO_TRADE' AND e.label = x.label);

INSERT INTO master_entries (type, label, value, category, "isActive")
SELECT 'PRO_SUB_SKILL', x.label, x.label, x.category, true
FROM (VALUES
  ('Interior painting', 'Painter'),
  ('Exterior painting', 'Painter'),
  ('Putty & primer', 'Painter'),
  ('Wood polish', 'Painter'),
  ('Waterproof coating', 'Painter'),
  ('Washing machine', 'Appliance Technician'),
  ('Fridge', 'Appliance Technician'),
  ('TV repair', 'Appliance Technician'),
  ('Microwave oven', 'Appliance Technician'),
  ('Gas stove', 'Appliance Technician'),
  ('Water purifier', 'Appliance Technician'),
  ('Cockroach control', 'Pest Control'),
  ('Termite treatment', 'Pest Control'),
  ('Rodent control', 'Pest Control'),
  ('Bed bugs', 'Pest Control'),
  ('Mosquito treatment', 'Pest Control'),
  ('Haircut & styling', 'Beautician'),
  ('Facial & cleanup', 'Beautician'),
  ('Mehendi', 'Beautician'),
  ('Bridal makeup', 'Beautician'),
  ('Waxing & threading', 'Beautician'),
  ('Mobile repair', 'Electronics Repair'),
  ('Laptop repair', 'Electronics Repair'),
  ('Desktop repair', 'Electronics Repair'),
  ('CCTV installation', 'Electronics Repair'),
  ('Tablet repair', 'Electronics Repair'),
  ('Grass cutting', 'Gardener'),
  ('Tree trimming', 'Gardener'),
  ('Garden maintenance', 'Gardener'),
  ('Landscaping', 'Gardener'),
  ('Tile work', 'Renovation Pro'),
  ('Waterproofing', 'Renovation Pro'),
  ('Aluminium fabrication', 'Renovation Pro'),
  ('False ceiling', 'Renovation Pro'),
  ('Truss & roofing work', 'Renovation Pro')
) AS x(label, category)
WHERE NOT EXISTS (
  SELECT 1 FROM master_entries e
  WHERE e.type = 'PRO_SUB_SKILL' AND e.label = x.label AND e.category = x.category
);

-- Runtime config keys
INSERT INTO master_entries (type, label, value, category, "isActive")
SELECT 'CONFIGURATION', x.label, x.value, x.note, true
FROM (VALUES
  ('go_live_daily_limit', '0', 'How many times a worker may go LIVE per day. 0 = unlimited.'),
  ('go_live_jobs_per_payment', '3', 'Completed jobs included per payment. 0 = plan OFF.'),
  ('go_live_period_fee', '49', 'Rs. charged to unlock the next batch of included jobs.'),
  ('instant_petrol_per_km', '10', 'Instant Help petrol charge in Rs. per one-way km.'),
  ('job_credit_per_accept', '15', 'Job credits deducted when a worker accepts a booking.')
) AS x(label, value, note)
WHERE NOT EXISTS (
  SELECT 1 FROM master_entries e WHERE e.type = 'CONFIGURATION' AND e.label = x.label
);
