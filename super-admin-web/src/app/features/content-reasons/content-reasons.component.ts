import { Component, OnInit, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { HttpClient, HttpParams } from '@angular/common/http';

@Component({
  selector: 'app-content-reasons',
  standalone: true,
  imports: [CommonModule, RouterLink],
  template: `
    <div class="gx-page-title">Content & reasons</div>
    <div class="gx-page-sub">Banners, deals and help copy. Use plain text only — no scripts or secrets in templates.</div>
    @for (block of blocks; track block.type) {
      <div class="card mb-3">
        <div class="card-header">{{ block.title }}</div>
        <ul class="list-group list-group-flush">
          @for (e of block.items; track e.id) {
            <li class="list-group-item d-flex justify-content-between">
              <span>{{ e.label }} — {{ e.value | slice:0:80 }}</span>
              <span class="badge" [class.bg-success]="e.isActive" [class.bg-secondary]="!e.isActive">{{ e.isActive ? 'Active' : 'Off' }}</span>
            </li>
          } @empty {
            <li class="list-group-item text-muted">None</li>
          }
        </ul>
      </div>
    }
    <a routerLink="/master-entries" class="btn btn-primary">Manage in Master Entries</a>
  `,
})
export class ContentReasonsComponent implements OnInit {
  private http = inject(HttpClient);
  blocks: { type: string; title: string; items: any[] }[] = [];

  ngOnInit() {
    const types = [
      { type: 'BANNER', title: 'Home carousel' },
      { type: 'DEAL', title: 'Deals' },
      { type: 'CONFIGURATION', title: 'Help / copy keys (configuration)' },
    ];
    for (const t of types) {
      this.http
        .get<any>('/api/master-entries/admin/list', {
          params: new HttpParams().set('type', t.type).set('limit', '50'),
        })
        .subscribe((res) => this.blocks.push({ ...t, items: res.items ?? [] }));
    }
  }
}
