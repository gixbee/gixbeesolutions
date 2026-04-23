import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';

@Component({
  selector: 'app-businesses',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="card shadow-sm">
      <div class="card-header bg-white py-3">
        <h4 class="mb-0">Business Moderation</h4>
      </div>
      <div class="card-body">
        <div class="alert alert-info">
          Business review and approval tools will appear here. Coming soon!
        </div>
      </div>
    </div>
  `
})
export class BusinessesComponent {}
