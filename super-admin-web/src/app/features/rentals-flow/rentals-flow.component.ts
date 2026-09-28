import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-rentals-flow',
  standalone: true,
  imports: [CommonModule],
  styles: [`
    .rf-legend { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 16px; }
    .rf-chip {
      display: inline-flex; align-items: center; gap: 8px;
      background: #fff; border: 1px solid var(--gx-card-border);
      border-radius: 999px; padding: 5px 12px; font-size: 12.5px; font-weight: 650;
    }
    .rf-dot { width: 10px; height: 10px; border-radius: 99px; flex-shrink: 0; }
    .rf-lanes { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 12px; }
    .rf-lane {
      border: 1px solid var(--gx-card-border); border-radius: var(--gx-radius);
      overflow: hidden; background: #fff; min-height: 100%;
    }
    .rf-lane h3 {
      margin: 0; padding: 12px 14px; font-size: 13px; font-weight: 800;
      display: flex; align-items: center; gap: 8px; background: #fff;
    }
    .rf-lane ul { list-style: none; margin: 0; padding: 12px; }
    .rf-lane li {
      background: #fff; border: 1px solid var(--gx-card-border); border-radius: 10px;
      padding: 8px 10px; margin-bottom: 7px; font-weight: 600; font-size: 13px;
    }
    .rf-lane li:last-child { margin-bottom: 0; }
    .rf-meta { display: block; font-weight: 500; color: var(--gx-text-muted); font-size: 11.5px; margin-top: 2px; }
    .rf-lane.customer { background: #eff6ff; border-color: #93c5fd; }
    .rf-lane.backend { background: #ecfdf5; border-color: #6ee7b7; }
    .rf-lane.db { background: #f5f3ff; border-color: #c4b5fd; }
    .rf-lane.store { background: #fff7ed; border-color: #fdba74; }
    .rf-lane.customer h3 { color: #2563eb; border-bottom: 1px solid #93c5fd; }
    .rf-lane.backend h3 { color: #059669; border-bottom: 1px solid #6ee7b7; }
    .rf-lane.db h3 { color: #7c3aed; border-bottom: 1px solid #c4b5fd; }
    .rf-lane.store h3 { color: #ea580c; border-bottom: 1px solid #fdba74; }
    .rf-flow { display: flex; flex-wrap: wrap; align-items: stretch; gap: 8px; }
    .rf-step {
      background: #fff; border: 1px solid var(--gx-card-border); border-radius: 12px;
      padding: 10px 12px; min-width: 124px; max-width: 180px; flex: 1;
    }
    .rf-step b { display: block; font-size: 12.5px; }
    .rf-step span { color: var(--gx-text-muted); font-size: 11.5px; }
    .rf-step.blue { border-top: 3px solid #2563eb; }
    .rf-step.orange { border-top: 3px solid #ea580c; }
    .rf-step.green { border-top: 3px solid #059669; }
    .rf-step.purple { border-top: 3px solid #7c3aed; }
    .rf-step.fail { border-top: 3px solid var(--gx-danger); }
    .rf-step.ok { border-top: 3px solid var(--gx-success); }
    .rf-chev { align-self: center; color: #94a3b8; font-size: 16px; font-weight: 700; }
    .rf-status { display: flex; flex-wrap: wrap; gap: 6px; align-items: center; }
    .rf-st {
      border-radius: 8px; padding: 7px 10px; font-size: 11px; font-weight: 800;
      letter-spacing: 0.02em; background: #f8fafc; border: 1px solid var(--gx-card-border);
    }
    .rf-st.main { background: #eff6ff; border-color: #93c5fd; color: #2563eb; }
    .rf-st.side { background: #fef2f2; border-color: #fecaca; color: var(--gx-danger); }
    .rf-to { color: #94a3b8; font-weight: 800; }
    .rf-pills { display: flex; flex-wrap: wrap; gap: 8px; }
    .rf-pill {
      background: #ecfdf5; color: #059669; border: 1px solid #6ee7b7;
      border-radius: 8px; padding: 6px 10px; font-weight: 700; font-size: 12px;
    }
    .rf-pill.db { background: #f5f3ff; color: #7c3aed; border-color: #c4b5fd; }
    .rf-rules { columns: 2; gap: 18px; margin: 0; padding-left: 18px; }
    .rf-rules li { break-inside: avoid; margin-bottom: 8px; color: #334155; }
    .rf-note { font-size: 12px; color: var(--gx-text-muted); margin: 10px 0 0; }
    @media (max-width: 980px) {
      .rf-lanes { grid-template-columns: 1fr; }
      .rf-rules { columns: 1; }
    }
  `],
  template: `
    <div class="gx-page-title">Rental booking flow</div>
    <div class="gx-page-sub">
      How Rentals works in the phone app: nearby store, hold, advance payment,
      store confirm, OTP handover and return. This is a process map, not a live list of bookings.
    </div>

    <div class="rf-legend">
      <span class="rf-chip"><span class="rf-dot" style="background:#2563eb"></span>Customer – Flutter App</span>
      <span class="rf-chip"><span class="rf-dot" style="background:#059669"></span>Gixbee Backend – Rust</span>
      <span class="rf-chip"><span class="rf-dot" style="background:#7c3aed"></span>PostgreSQL Database</span>
      <span class="rf-chip"><span class="rf-dot" style="background:#ea580c"></span>Verified Rental Store</span>
    </div>

    <div class="rf-lanes mb-4">
      <section class="rf-lane customer">
        <h3>1. Customer – Flutter</h3>
        <ul>
          <li>Home → Rentals</li>
          <li>Show nearby verified stores<span class="rf-meta">City match or 25 km GPS pin</span></li>
          <li>Select a rental store</li>
          <li>Browse items in that store</li>
          <li>Select item → date → time slot → quantity</li>
          <li>Check availability</li>
          <li>Pickup or Delivery</li>
          <li>Price breakdown<span class="rf-meta">Rent · min advance · deposit · delivery</span></li>
          <li>Pay minimum booking advance</li>
          <li>Track request, handover OTP, return, rate store</li>
        </ul>
      </section>
      <section class="rf-lane backend">
        <h3>2. Gixbee Backend – Rust</h3>
        <ul>
          <li>Location / Nearby Search</li>
          <li>Catalog + Availability</li>
          <li>Slot Booking → temporary hold</li>
          <li>Pricing Service</li>
          <li>Payment Service (Razorpay advance)</li>
          <li>Reservation + Notification</li>
          <li>OTP · Handover · Return</li>
          <li>Deposit + Settlement</li>
          <li>Rating Service</li>
        </ul>
      </section>
      <section class="rf-lane db">
        <h3>3. PostgreSQL</h3>
        <ul>
          <li>users</li>
          <li>rental_businesses<span class="rf-meta">Mapped to businesses type=RENTAL</span></li>
          <li>rental_items · photos · inventory</li>
          <li>rental_availability · rental_slots</li>
          <li>rental_bookings · booking_items</li>
          <li>rental_payments · rental_deposits</li>
          <li>rental_handover · rental_returns</li>
          <li>ratings</li>
        </ul>
      </section>
      <section class="rf-lane store">
        <h3>4. Verified Rental Store</h3>
        <ul>
          <li>Create store profile + location</li>
          <li>List items<span class="rf-meta">Name, photos, description, price, deposit, qty, slots, pickup/delivery</span></li>
          <li>Incoming request</li>
          <li>Confirm or Reject</li>
          <li>Handover OTP / deliver item</li>
          <li>Inspect return · damage if any</li>
          <li>Settlement · rate customer</li>
        </ul>
      </section>
    </div>

    <div class="card mb-3">
      <div class="card-header py-3"><h5 class="mb-0">Customer booking</h5></div>
      <div class="card-body">
        <div class="rf-flow">
          <div class="rf-step blue"><b>Home</b><span>Flutter</span></div>
          <div class="rf-chev">→</div>
          <div class="rf-step blue"><b>Rentals</b><span>Location on</span></div>
          <div class="rf-chev">→</div>
          <div class="rf-step blue"><b>Nearby stores</b><span>City or 25 km</span></div>
          <div class="rf-chev">→</div>
          <div class="rf-step orange"><b>Select store</b><span>Verified RENTAL</span></div>
          <div class="rf-chev">→</div>
          <div class="rf-step blue"><b>Browse items</b><span>That store only</span></div>
          <div class="rf-chev">→</div>
          <div class="rf-step blue"><b>Date + slot + qty</b><span>Availability check</span></div>
          <div class="rf-chev">→</div>
          <div class="rf-step blue"><b>Pickup / Delivery</b><span>Fee if delivery</span></div>
          <div class="rf-chev">→</div>
          <div class="rf-step green"><b>Temp hold slot</b><span>10 min lock</span></div>
          <div class="rf-chev">→</div>
          <div class="rf-step green"><b>Pay min advance</b><span>Razorpay</span></div>
        </div>
      </div>
    </div>

    <div class="row g-3 mb-3">
      <div class="col-md-6">
        <div class="card h-100">
          <div class="card-header py-3"><h5 class="mb-0">Payment failed / cancelled / timeout</h5></div>
          <div class="card-body">
            <div class="rf-flow">
              <div class="rf-step fail"><b>Release hold</b><span>TEMP_HOLD / PAYMENT_PENDING</span></div>
              <div class="rf-chev">→</div>
              <div class="rf-step"><b>AVAILABLE</b><span>Item/slot free again</span></div>
            </div>
          </div>
        </div>
      </div>
      <div class="col-md-6">
        <div class="card h-100">
          <div class="card-header py-3"><h5 class="mb-0">Payment successful</h5></div>
          <div class="card-body">
            <div class="rf-flow">
              <div class="rf-step ok"><b>Create request</b><span>Advance paid</span></div>
              <div class="rf-chev">→</div>
              <div class="rf-step green"><b>PENDING_OWNER_CONFIRMATION</b><span>Notify store</span></div>
            </div>
          </div>
        </div>
      </div>
    </div>

    <div class="card mb-3">
      <div class="card-header py-3"><h5 class="mb-0">Owner / rental store</h5></div>
      <div class="card-body">
        <div class="rf-flow">
          <div class="rf-step orange"><b>Verified business</b><span>Store profile + geo</span></div>
          <div class="rf-chev">→</div>
          <div class="rf-step orange"><b>List items</b><span>Price, deposit, qty, slots</span></div>
          <div class="rf-chev">→</div>
          <div class="rf-step orange"><b>View request</b><span>Incoming</span></div>
          <div class="rf-chev">→</div>
          <div class="rf-step ok"><b>Confirm</b><span>Permanently reserve</span></div>
          <div class="rf-chev">or</div>
          <div class="rf-step fail"><b>Reject</b><span>Refund advance · release slot</span></div>
        </div>
      </div>
    </div>

    <div class="card mb-3">
      <div class="card-header py-3"><h5 class="mb-0">Handover → active → return → settlement</h5></div>
      <div class="card-body">
        <div class="rf-flow">
          <div class="rf-step orange"><b>CONFIRMED</b><span>Pickup or delivery</span></div>
          <div class="rf-chev">→</div>
          <div class="rf-step green"><b>Handover OTP</b><span>Both parties ack</span></div>
          <div class="rf-chev">→</div>
          <div class="rf-step ok"><b>ACTIVE</b><span>Remind before due</span></div>
          <div class="rf-chev">→</div>
          <div class="rf-step orange"><b>Return check</b><span>Condition / damage</span></div>
          <div class="rf-chev">→</div>
          <div class="rf-step green"><b>Return OTP</b><span>RETURN_PENDING</span></div>
          <div class="rf-chev">→</div>
          <div class="rf-step purple"><b>Settlement</b><span>Rest + fees − deposit</span></div>
          <div class="rf-chev">→</div>
          <div class="rf-step"><b>COMPLETED</b><span>Mutual ratings</span></div>
        </div>
        <p class="rf-note">
          Settlement: remaining rental + delivery + late fee + damage − advance.
          Refund refundable deposit net of damage/penalty. Then customer rates store/item and store rates customer.
        </p>
      </div>
    </div>

    <div class="card mb-3">
      <div class="card-header py-3"><h5 class="mb-0">Rental status flow</h5></div>
      <div class="card-body">
        <div class="rf-status">
          <span class="rf-st">AVAILABLE</span><span class="rf-to">→</span>
          <span class="rf-st main">TEMP_HOLD</span><span class="rf-to">→</span>
          <span class="rf-st main">PAYMENT_PENDING</span><span class="rf-to">→</span>
          <span class="rf-st main">PENDING_OWNER_CONFIRMATION</span><span class="rf-to">→</span>
          <span class="rf-st main">CONFIRMED</span><span class="rf-to">→</span>
          <span class="rf-st main">ACTIVE</span><span class="rf-to">→</span>
          <span class="rf-st main">RETURN_PENDING</span><span class="rf-to">→</span>
          <span class="rf-st main">COMPLETED</span>
        </div>
        <p class="rf-note" style="font-weight:700;color:var(--gx-text)">Side branches</p>
        <div class="rf-status mt-2">
          <span class="rf-st">TEMP_HOLD / PAYMENT_PENDING</span><span class="rf-to">→</span>
          <span class="rf-st side">timeout or payment fail</span><span class="rf-to">→</span>
          <span class="rf-st">AVAILABLE</span>
        </div>
        <div class="rf-status mt-2">
          <span class="rf-st">PENDING_OWNER_CONFIRMATION</span><span class="rf-to">→</span>
          <span class="rf-st side">owner REJECTED</span><span class="rf-to">→</span>
          <span class="rf-st">refund advance</span><span class="rf-to">→</span>
          <span class="rf-st">AVAILABLE</span>
        </div>
        <div class="rf-status mt-2">
          <span class="rf-st">PENDING_OWNER_CONFIRMATION</span><span class="rf-to">→</span>
          <span class="rf-st side">customer CANCELLED</span><span class="rf-to">→</span>
          <span class="rf-st">refund policy</span><span class="rf-to">→</span>
          <span class="rf-st">AVAILABLE</span>
        </div>
      </div>
    </div>

    <div class="card mb-3">
      <div class="card-header py-3"><h5 class="mb-0">Backend services – Rust</h5></div>
      <div class="card-body">
        <div class="rf-pills">
          <span class="rf-pill">Rental Store Service</span>
          <span class="rf-pill">Catalog Service</span>
          <span class="rf-pill">Availability Service</span>
          <span class="rf-pill">Slot Booking Service</span>
          <span class="rf-pill">Reservation Service</span>
          <span class="rf-pill">Pricing Service</span>
          <span class="rf-pill">Payment Service</span>
          <span class="rf-pill">Deposit Service</span>
          <span class="rf-pill">OTP Service</span>
          <span class="rf-pill">Handover Service</span>
          <span class="rf-pill">Return Service</span>
          <span class="rf-pill">Settlement Service</span>
          <span class="rf-pill">Notification Service</span>
          <span class="rf-pill">Rating Service</span>
          <span class="rf-pill">Location / Nearby Search Service</span>
        </div>
        <p class="rf-note">Implemented as modules inside the Rust rentals API, not separate processes.</p>
      </div>
    </div>

    <div class="card mb-3">
      <div class="card-header py-3"><h5 class="mb-0">PostgreSQL tables</h5></div>
      <div class="card-body">
        <div class="rf-pills">
          <span class="rf-pill db">users</span>
          <span class="rf-pill db">rental_businesses</span>
          <span class="rf-pill db">rental_items</span>
          <span class="rf-pill db">rental_item_photos</span>
          <span class="rf-pill db">rental_item_inventory</span>
          <span class="rf-pill db">rental_availability</span>
          <span class="rf-pill db">rental_slots</span>
          <span class="rf-pill db">rental_bookings</span>
          <span class="rf-pill db">rental_booking_items</span>
          <span class="rf-pill db">rental_payments</span>
          <span class="rf-pill db">rental_deposits</span>
          <span class="rf-pill db">rental_handover</span>
          <span class="rf-pill db">rental_returns</span>
          <span class="rf-pill db">ratings</span>
        </div>
        <p class="rf-note">Stores persist as businesses (type = RENTAL). Photos and inventory stay on rental_items unless later split.</p>
      </div>
    </div>

    <div class="card mb-2">
      <div class="card-header py-3"><h5 class="mb-0">Key rules</h5></div>
      <div class="card-body">
        <ul class="rf-rules">
          <li>Customer books from a verified rental store.</li>
          <li>Rental items belong to a rental business/store.</li>
          <li>Nearby stores are shown based on city or 25 km GPS radius.</li>
          <li>A slot is temporarily locked before payment to prevent double booking.</li>
          <li>Minimum booking advance is required to submit the reservation.</li>
          <li>Owner must confirm the rental request.</li>
          <li>If owner rejects, booking advance is refunded.</li>
          <li>Only one confirmed booking can hold the same inventory for the same time slot (up to listed quantity).</li>
          <li>Handover requires customer/owner acknowledgement and OTP.</li>
          <li>Return requires acknowledgement from both parties.</li>
          <li>Security deposit is refunded after successful return, minus applicable damage or penalty charges.</li>
          <li>Payment status must be separate from rental booking status.</li>
        </ul>
      </div>
    </div>
  `,
})
export class RentalsFlowComponent {}
