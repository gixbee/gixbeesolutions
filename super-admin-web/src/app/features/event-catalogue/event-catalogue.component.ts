import { Component } from '@angular/core';
import { CatalogueMetaComponent } from '../catalogue-meta/catalogue-meta.component';

@Component({
  selector: 'app-event-catalogue',
  standalone: true,
  imports: [CatalogueMetaComponent],
  template: `<app-catalogue-meta kind="event" />`,
})
export class EventCatalogueComponent {}
