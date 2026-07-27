import { Component, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { DomSanitizer, SafeResourceUrl } from '@angular/platform-browser';

@Component({
  selector: 'app-infrastructure',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="d-flex justify-content-between align-items-center flex-wrap gap-2 mb-4">
      <div>
        <div class="gx-page-title mb-1">Infrastructure Monitoring</div>
        <div class="text-secondary small d-flex align-items-center gap-2">
          <span>Live container resources & real-time log streaming</span>
          <span class="badge bg-secondary-subtle text-secondary border border-secondary-subtle">
            <i class="bi bi-shield-lock me-1"></i>Protected by Basic Auth (user: admin)
          </span>
        </div>
      </div>
      <div class="d-flex gap-2">
        <a [href]="rawBeszelUrl" target="_blank" class="btn btn-outline-secondary btn-sm d-flex align-items-center gap-2">
          <i class="bi bi-cpu"></i>
          <span>Open Beszel Hub</span>
          <i class="bi bi-box-arrow-up-right small"></i>
        </a>
        <a href="/infra/dozzle/" target="_blank" class="btn btn-outline-secondary btn-sm d-flex align-items-center gap-2">
          <i class="bi bi-terminal"></i>
          <span>Open Dozzle Logs</span>
          <i class="bi bi-box-arrow-up-right small"></i>
        </a>
      </div>
    </div>

    <!-- Navigation Tabs -->
    <ul class="nav nav-tabs gx-nav-tabs mb-3" role="tablist">
      <li class="nav-item" role="presentation">
        <button
          class="nav-link d-flex align-items-center gap-2"
          [class.active]="activeTab === 'beszel'"
          (click)="activeTab = 'beszel'"
          type="button"
          role="tab"
        >
          <i class="bi bi-activity"></i>
          <span>Resource Metrics (Beszel)</span>
        </button>
      </li>
      <li class="nav-item" role="presentation">
        <button
          class="nav-link d-flex align-items-center gap-2"
          [class.active]="activeTab === 'dozzle'"
          (click)="activeTab = 'dozzle'"
          type="button"
          role="tab"
        >
          <i class="bi bi-terminal-split"></i>
          <span>Live Container Logs (Dozzle)</span>
        </button>
      </li>
    </ul>

    <!-- Tab Content / IFrames -->
    <div class="card gx-card border-0 shadow-sm overflow-hidden" style="min-height: 75vh;">
      <div class="card-body p-0 position-relative d-flex flex-column" style="min-height: 75vh;">
        
        <!-- Beszel Tab -->
        <div [class.d-none]="activeTab !== 'beszel'" class="w-100 flex-grow-1 d-flex flex-column">
          <iframe
            [src]="beszelUrl"
            class="w-100 flex-grow-1 border-0"
            style="min-height: 75vh;"
            title="Beszel Resource Monitor"
            allow="clipboard-read; clipboard-write"
          ></iframe>
        </div>

        <!-- Dozzle Tab -->
        <div [class.d-none]="activeTab !== 'dozzle'" class="w-100 flex-grow-1 d-flex flex-column">
          <iframe
            [src]="dozzleUrl"
            class="w-100 flex-grow-1 border-0"
            style="min-height: 75vh;"
            title="Dozzle Container Logs"
            allow="clipboard-read; clipboard-write"
          ></iframe>
        </div>

      </div>
    </div>
  `,
  styles: [`
    .gx-nav-tabs {
      border-bottom: 2px solid var(--gx-border-color, #dee2e6);
    }
    .gx-nav-tabs .nav-link {
      border: none;
      border-bottom: 2px solid transparent;
      margin-bottom: -2px;
      color: var(--gx-text-secondary, #6c757d);
      font-weight: 500;
      padding: 0.75rem 1.25rem;
      transition: all 0.2s ease;
    }
    .gx-nav-tabs .nav-link:hover {
      color: var(--gx-primary, #0d6efd);
    }
    .gx-nav-tabs .nav-link.active {
      color: var(--gx-primary, #0d6efd);
      border-bottom-color: var(--gx-primary, #0d6efd);
      background: transparent;
    }
  `]
})
export class InfrastructureComponent {
  private sanitizer = inject(DomSanitizer);

  activeTab: 'beszel' | 'dozzle' = 'beszel';

  readonly rawBeszelUrl = '/infra/beszel/';
  readonly beszelUrl: SafeResourceUrl = this.sanitizer.bypassSecurityTrustResourceUrl(this.rawBeszelUrl);
  readonly dozzleUrl: SafeResourceUrl = this.sanitizer.bypassSecurityTrustResourceUrl('/infra/dozzle/');
}
