import 'package:flutter/material.dart';

/// Skill taxonomy for the "Register as Pro" wizard.
///
/// Each trade (category) maps to a list of concrete sub-skills the worker can
/// check off. Selections are flattened to "Trade: Sub-skill" strings and saved
/// into the talent profile's `skills` list — so the backend taxonomy stays a
/// flat string list while the UI presents a structured picker.
///
/// Derived set (modeled on the Plumber example from the product mockup) — the
/// wording can be refined later without touching the wizard.
class ProTrade {
  final String name;
  final IconData icon;
  final List<String> subSkills;
  const ProTrade(this.name, this.icon, this.subSkills);
}

const List<ProTrade> kProTrades = [
  ProTrade('Electrician', Icons.bolt_rounded, [
    'Wiring & rewiring',
    'Switch & socket repair',
    'Fan installation',
    'Light fitting',
    'MCB / fuse box',
    'Inverter & battery',
  ]),
  ProTrade('Plumber', Icons.plumbing_rounded, [
    'Pipe leaking / dripping',
    'Burst pipe emergency',
    'Wall / ceiling leakage',
    'Joint / fitting leak',
    'Drain & blockage',
    'Toilet repair',
    'Tap & faucet',
    'Water supply',
  ]),
  ProTrade('Driver', Icons.directions_car_rounded, [
    'Personal driver (hourly)',
    'Outstation trips',
    'Two-wheeler delivery',
    'Goods transport',
    'Airport pickup / drop',
  ]),
  ProTrade('Cleaner', Icons.cleaning_services_rounded, [
    'Home deep cleaning',
    'Bathroom cleaning',
    'Kitchen cleaning',
    'Sofa & carpet',
    'Office cleaning',
    'Move-in / move-out',
  ]),
  ProTrade('Nurse', Icons.medical_services_rounded, [
    'Elderly care',
    'Patient bedside care',
    'Injection & dressing',
    'Post-surgery care',
    'Baby care',
  ]),
  ProTrade('Carpenter', Icons.handyman_rounded, [
    'Furniture repair',
    'Door & window fitting',
    'Modular kitchen',
    'Bed & wardrobe',
    'Custom woodwork',
  ]),
  ProTrade('AC Technician', Icons.ac_unit_rounded, [
    'AC servicing',
    'Gas refill',
    'Installation / uninstall',
    'Cooling repair',
    'Water leakage fix',
  ]),
];
