import { Component, Input, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { MasterAdminService } from '../../core/services/master-admin.service';

@Component({
  selector: 'app-catalogue-meta',
  standalone: true,
  imports: [CommonModule, RouterLink],
  template: `
    <div class="gx-page-title">{{ heading }}</div>
    <div class="gx-page-sub">{{ note }}</div>
    <div class="card mb-3"><div class="card-body"><pre class="mb-0 small">{{ meta | json }}</pre></div></div>
    <a class="btn btn-outline-primary" routerLink="/master-entries">Edit presentation in Master Entries</a>
  `,
})
export class CatalogueMetaComponent implements OnInit {
  @Input({ required: true }) kind!: 'rental' | 'event';

  heading = '';
  note = '';
  meta: unknown = null;
  private api = inject(MasterAdminService);

  ngOnInit() {
    if (this.kind === 'event') {
      this.heading = 'Event catalogue';
      this.api.eventMeta().subscribe((m) => {
        this.meta = m;
        this.note = (m as any)?.note ?? '';
      });
    } else {
      this.heading = 'Rental catalogue choices';
      this.api.rentalMeta().subscribe((m) => {
        this.meta = m;
        this.note = (m as any)?.note ?? '';
      });
    }
  }
}
