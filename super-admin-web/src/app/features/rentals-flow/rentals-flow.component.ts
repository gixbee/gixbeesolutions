import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-rentals-flow',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="gx-full-screen-view d-flex flex-column flex-grow-1 w-100">
      <div class="d-flex justify-content-between align-items-center flex-wrap gap-2 mb-3">
        <div>
          <div class="gx-page-title mb-1">Rental booking flow</div>
          <div class="gx-page-sub mb-0">
            Target architecture: customer Flutter, Rust API, PostgreSQL, verified rental store.
            Nearby stores use city or GPS radius.
          </div>
        </div>
        <a
          href="/architecture/gixbee-rentals-booking-flow.html"
          target="_blank"
          rel="noopener"
          class="btn btn-outline-secondary btn-sm d-flex align-items-center gap-2">
          <i class="bi bi-box-arrow-up-right"></i>
          Open in new tab
        </a>
      </div>
      <iframe
        class="flex-grow-1 w-100"
        style="min-height: calc(100vh - 180px); border: 1px solid #e2e8f0; border-radius: 12px; background: #fff;"
        title="Gixbee Rentals booking flow"
        src="/architecture/gixbee-rentals-booking-flow.html">
      </iframe>
    </div>
  `,
})
export class RentalsFlowComponent {}
