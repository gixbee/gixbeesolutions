import { Component, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { FormsModule } from '@angular/forms';

@Component({
  selector: 'app-redis-viewer',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="d-flex flex-column h-100 p-3 bg-dark text-light overflow-hidden">
      <div class="mb-3 d-flex gap-2">
        <input
          type="text"
          class="form-control bg-dark text-light border-secondary"
          [(ngModel)]="searchPattern"
          (keyup.enter)="searchKeys()"
          placeholder="Search keys (e.g. worker:*)"
        />
        <button class="btn btn-primary" (click)="searchKeys()" [disabled]="isLoading()">
          <i class="bi bi-search me-1"></i>Search
        </button>
      </div>

      <div class="flex-grow-1 d-flex gap-3 overflow-hidden">
        <!-- Key List -->
        <div class="col-4 d-flex flex-column border border-secondary rounded h-100 overflow-hidden">
          <div class="p-2 border-bottom border-secondary bg-darker fw-bold d-flex justify-content-between align-items-center">
            <span>Keys ({{keys().length}})</span>
            <span *ngIf="truncated()" class="badge bg-warning text-dark fw-normal" title="Scan stopped at its cap — narrow the pattern to see the rest">
              capped
            </span>
          </div>
          
          <div class="flex-grow-1 overflow-auto">
            <div *ngIf="isLoading()" class="p-3 text-center text-secondary">
              <div class="spinner-border spinner-border-sm me-2"></div>Loading...
            </div>
            
            <div *ngIf="!isLoading() && keys().length === 0" class="p-3 text-center text-secondary">
              No keys found
            </div>
            
            <div class="list-group list-group-flush rounded-0 bg-dark">
              <button 
                *ngFor="let key of keys()" 
                type="button" 
                class="list-group-item list-group-item-action bg-dark text-light border-secondary text-truncate"
                [class.active]="selectedKey() === key"
                (click)="loadKeyDetails(key)">
                {{key}}
              </button>
            </div>
          </div>
        </div>

        <!-- Key Details -->
        <div class="col-8 d-flex flex-column border border-secondary rounded h-100 overflow-hidden">
          <div class="p-2 border-bottom border-secondary bg-darker fw-bold d-flex justify-content-between">
            <span>Details</span>
            <span *ngIf="selectedKeyDetails()" class="badge bg-secondary">{{selectedKeyDetails()?.type}}</span>
          </div>
          
          <div class="flex-grow-1 overflow-auto p-3 bg-black">
            <div *ngIf="isDetailsLoading()" class="text-center text-secondary mt-3">
              <div class="spinner-border spinner-border-sm me-2"></div>Loading details...
            </div>
            
            <div *ngIf="!selectedKeyDetails() && !isDetailsLoading()" class="text-secondary text-center mt-5">
              Select a key to view its contents
            </div>
            
            <div *ngIf="selectedKeyDetails() && !isDetailsLoading()">
              <div class="mb-3 d-flex gap-4 text-secondary small">
                <div><strong>Key:</strong> {{selectedKeyDetails()?.key}}</div>
                <div><strong>TTL:</strong> {{selectedKeyDetails()?.ttl}}s</div>
              </div>
              <pre class="text-success" style="white-space: pre-wrap; word-break: break-all;">{{selectedKeyDetails()?.value | json}}</pre>
            </div>
          </div>
        </div>
      </div>
    </div>
  `,
  styles: [`
    .bg-darker { background-color: #1a1d20; }
    .list-group-item.active {
      background-color: #0d6efd !important;
      border-color: #0d6efd !important;
      color: white !important;
    }
    .list-group-item:hover:not(.active) {
      background-color: #2b3035 !important;
    }
    pre {
      font-size: 0.85rem;
    }
  `]
})
export class RedisViewerComponent {
  private http = inject(HttpClient);
  
  searchPattern = '*';
  keys = signal<string[]>([]);
  /** Server stopped the scan at its cap; the listing is partial. */
  truncated = signal<boolean>(false);
  isLoading = signal<boolean>(false);
  
  selectedKey = signal<string | null>(null);
  selectedKeyDetails = signal<any>(null);
  isDetailsLoading = signal<boolean>(false);

  ngOnInit() {
    this.searchKeys();
  }

  searchKeys() {
    this.isLoading.set(true);
    this.selectedKey.set(null);
    this.selectedKeyDetails.set(null);
    
    this.http.get<{keys: string[]; truncated?: boolean}>(`/api/redis/admin/keys`, {
      params: { pattern: this.searchPattern }
    }).subscribe({
      next: (res) => {
        this.keys.set(res.keys || []);
        this.truncated.set(!!res.truncated);
        this.isLoading.set(false);
      },
      error: (err) => {
        console.error('Error fetching redis keys', err);
        this.truncated.set(false);
        this.isLoading.set(false);
      }
    });
  }

  loadKeyDetails(key: string) {
    this.selectedKey.set(key);
    this.isDetailsLoading.set(true);
    
    this.http.get<any>(`/api/redis/admin/key`, {
      params: { id: key }
    }).subscribe({
      next: (res) => {
        this.selectedKeyDetails.set(res);
        this.isDetailsLoading.set(false);
      },
      error: (err) => {
        console.error('Error fetching redis key details', err);
        this.isDetailsLoading.set(false);
      }
    });
  }
}
