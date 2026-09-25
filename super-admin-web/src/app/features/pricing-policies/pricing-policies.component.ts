import { Component } from '@angular/core';
import { SettingsPanelComponent } from '../master-settings/settings-panel.component';

@Component({
  selector: 'app-pricing-policies',
  standalone: true,
  imports: [SettingsPanelComponent],
  template: `
    <app-settings-panel
      mode="pricing"
      title="Pricing & policies"
      subtitle="Values stored as CONFIGURATION master entries and read by the Rust backend. Existing orders keep their snapshots; changes apply to new calculations only."
    />
  `,
})
export class PricingPoliciesComponent {}
