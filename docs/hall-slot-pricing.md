Hall slot pricing
=================

Each slot in `slotOffers` stores its own enabled flag, booking window,
With/Without AC offer switches, GST-inclusive rents, discount switches and
percentages. Customer prices apply the selected discount once and round to
the nearest rupee; GST is included in the entered rent, as in the UI reference.
No additional tax is added by this preview.

AC fields are `acUsage` (full/partial), `acHours`, `acTiming` (flexible/fixed),
and `acFrom`/`acTo` for fixed schedules. Hours may be fractional. The booking
window is same-day, end strictly after start. AC hours must be positive and
at most the booking duration; equal hours are saved as full. Fixed schedules
must lie inside the booking window and exactly match included hours.

The PostgreSQL schema in `scripts/azure_hall_migrations.sql` already stores
package revisions in a JSONB `package` column. These fields require no DDL or
historical revision rewrite. Old packages default to full-window flexible AC;
missing discount switches retain the historical percentage behavior. Disabled
slots are retained by the editor for later re-enabling. Full-day windows may
overlap morning/evening offers because they are alternative booking products;
the existing calendar availability rules prevent conflicting bookings.
