import { Component } from '@angular/core';
import { SettingsPanelComponent } from '../master-settings/settings-panel.component';

@Component({
  selector: 'app-operational-settings',
  standalone: true,
  imports: [SettingsPanelComponent],
  template: `
    <app-settings-panel
      mode="operational"
      title="Operational settings"
      subtitle="Bounded numeric limits consumed by workers, go-live and matching flows. Workflow enums remain code-defined."
    />
  `,
})
export class OperationalSettingsComponent {}
