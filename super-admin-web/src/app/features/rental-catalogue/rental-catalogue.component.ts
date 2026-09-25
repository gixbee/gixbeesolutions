import { Component } from '@angular/core';
import { CatalogueMetaComponent } from '../catalogue-meta/catalogue-meta.component';

@Component({
  selector: 'app-rental-catalogue',
  standalone: true,
  imports: [CatalogueMetaComponent],
  template: `<app-catalogue-meta kind="rental" />`,
})
export class RentalCatalogueComponent {}
