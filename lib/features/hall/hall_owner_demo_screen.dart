import 'package:flutter/material.dart';
import 'hall_owner_tokens.dart';
import 'hall_owner_widgets.dart';

enum _HallPage {
  dashboard,
  hallsHome,
  manage,
  operators,
  calendar,
  calDay,
}

class HallOperator {
  HallOperator({
    required this.id,
    required this.name,
    required this.phone,
    required this.role,
  });

  final String id;
  final String name;
  final String phone;
  final String role; // owner | manager | staff

  bool get isOwner => role == 'owner';
}

/// Owner-side hall flow — UI parity with `OPEN-gixbee-hall-owner-demo.html`.
class HallOwnerDemoScreen extends StatefulWidget {
  const HallOwnerDemoScreen({
    super.key,
    this.businessName = 'Vijaya Convention Center',
  });

  final String businessName;

  @override
  State<HallOwnerDemoScreen> createState() => _HallOwnerDemoScreenState();
}

class _HallOwnerDemoScreenState extends State<HallOwnerDemoScreen> {
  late _HallPage _page;
  bool _hallSetupComplete = true;
  bool _packageSaved = false;
  bool _hallActive = true;
  bool _hallNameEnabled = false;
  String _hallName = '';
  int _calMonth = 12;
  int _calYear = 2026;
  int _calDay = 25;

  late List<HallOperator> _operators;

  @override
  void initState() {
    super.initState();
    _page = _HallPage.dashboard;
    _operators = [
      HallOperator(
        id: '1',
        name: 'Thomas Mathew',
        phone: '+91 94470 55566',
        role: 'owner',
      ),
      HallOperator(
        id: '2',
        name: 'John Kurian',
        phone: '+91 98765 12345',
        role: 'manager',
      ),
    ];
  }

  void _go(_HallPage p) => setState(() => _page = p);

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  bool get _requirePackage {
    if (_packageSaved) return true;
    _toast('Save Price & packages first (complete all steps and tap Save on Review).');
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: HallOwnerTokens.green,
          primary: HallOwnerTokens.green,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          bottom: false,
          child: switch (_page) {
            _HallPage.dashboard => _buildDashboard(),
            _HallPage.hallsHome => _buildHallsHome(),
            _HallPage.manage => _buildManage(),
            _HallPage.operators => _buildOperators(),
            _HallPage.calendar => _buildCalendar(),
            _HallPage.calDay => _buildCalDay(),
          },
        ),
      ),
    );
  }

  Widget _buildDashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HallLmbTopBar(
          leading: HallGreenPill(
            label: 'Home',
            icon: Icons.home_rounded,
            onTap: () => Navigator.maybePop(context),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _dashCard(
                icon: '🏛️',
                name: widget.businessName,
                type: 'Marriage Hall',
                onManage: () => _go(_HallPage.hallsHome),
              ),
              _dashCard(
                icon: '🍽️',
                name: 'Thilaka Catering',
                type: 'Catering Service',
                onManage: () => _toast('Catering module — separate in full app.'),
              ),
              _dashCard(
                icon: '⚡',
                name: 'Rajan Power Rentals',
                type: 'Rental Business',
                onManage: () => _toast('Rental module — separate in full app.'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dashCard({
    required String icon,
    required String name,
    required String type,
    required VoidCallback onManage,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HallOwnerTokens.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(icon, style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                Text(
                  type,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: HallOwnerTokens.muted,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _miniAction('Calendar', () {}),
                    const SizedBox(width: 8),
                    _miniAction('Requests', () {}),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _miniAction('Manage', onManage, filled: true),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniAction(String label, VoidCallback onTap, {bool filled = false}) {
    return Material(
      color: filled ? HallOwnerTokens.green : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: filled ? null : Border.all(color: HallOwnerTokens.line),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: filled ? Colors.white : HallOwnerTokens.ink,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHallsHome() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HallLmbTopBar(
          leading: HallGreenPill(
            label: '← Dash',
            onTap: () => _go(_HallPage.dashboard),
          ),
          title: widget.businessName,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Text(
                widget.businessName,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: HallOwnerTokens.navy,
                ),
              ),
              if (_hallSetupComplete) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: HallOwnerTokens.line),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    '🚗 Cars: 80 · 🏍 Bikes: 120\nShared parking',
                    style: TextStyle(fontSize: 13, height: 1.45),
                  ),
                ),
              ],
              const HallSectionLabel('Your halls'),
              _hallCard(),
              const SizedBox(height: 12),
              HallPrimaryButton(
                label: '+ Add hall',
                outline: true,
                onTap: () {
                  _go(_HallPage.manage);
                  _toast('Add hall — set name and Save hall at bottom.');
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _hallCard() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _hallActive ? Colors.white : const Color(0xFFFAFAFA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _hallActive ? HallOwnerTokens.line : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.businessName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    if (_hallNameEnabled && _hallName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFEDE9FE), Color(0xFFD1FAE5)],
                            ),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            _hallName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                              color: Color(0xFF5B21B6),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: _hallActive,
                activeTrackColor: HallOwnerTokens.blue,
                onChanged: (v) => setState(() => _hallActive = v),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (_packageSaved) ...[
                Expanded(
                  child: _hallPick('Calendar', () {
                    if (_requirePackage && _hallActive) _go(_HallPage.calendar);
                  }),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _hallPick('Requests', () {
                    if (_requirePackage) _toast('Booking requests — demo.');
                  }),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                flex: _packageSaved ? 1 : 3,
                child: _hallPick(
                  'Manage',
                  () => _go(_HallPage.manage),
                  active: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hallPick(String label, VoidCallback onTap, {bool active = false}) {
    return Material(
      color: active ? HallOwnerTokens.greenSoft : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: active ? HallOwnerTokens.green : HallOwnerTokens.line,
              width: active ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: active ? HallOwnerTokens.greenDark : HallOwnerTokens.ink,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildManage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HallLmbTopBar(
          leading: HallGreenPill(
            label: '← Halls',
            onTap: () => _go(_HallPage.hallsHome),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              const Text(
                'Manage & grow',
                style: TextStyle(fontSize: 12, color: HallOwnerTokens.muted),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'This hall has its own name (optional)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                value: _hallNameEnabled,
                activeColor: HallOwnerTokens.green,
                onChanged: _hallActive
                    ? (v) => setState(() {
                          _hallNameEnabled = v ?? false;
                          if (!_hallNameEnabled) _hallName = '';
                        })
                    : null,
              ),
              if (_hallNameEnabled)
                TextField(
                  decoration: InputDecoration(
                    labelText: 'Hall name',
                    hintText: 'e.g. Koinonia',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (v) => _hallName = v,
                ),
              const HallSectionLabel('Manage'),
              HallManageMenuRow(
                title: 'Calendar',
                subtitle: 'Availability and blocked dates',
                onTap: () {
                  if (!_requirePackage || !_hallActive) return;
                  _go(_HallPage.calendar);
                },
              ),
              const SizedBox(height: 10),
              HallManageMenuRow(
                title: 'Price & packages',
                subtitle: 'Slots, pricing, cancellation policy',
                onTap: () {
                  setState(() => _packageSaved = true);
                  _toast('Package saved — calendar and operators unlocked.');
                },
              ),
              const SizedBox(height: 10),
              HallManageMenuRow(
                title: 'Booking requests',
                subtitle: 'Accept or decline customer bookings',
                showDot: true,
                onTap: () {
                  if (_requirePackage) _toast('Requests — demo.');
                },
              ),
              const SizedBox(height: 10),
              HallManageMenuRow(
                title: 'Operators',
                subtitle: 'Who can manage this hall',
                onTap: () {
                  if (!_requirePackage || !_hallActive) return;
                  _go(_HallPage.operators);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOperators() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HallLmbTopBar(
          leading: HallGreenPill(
            label: '← Back',
            onTap: () => _go(_HallPage.manage),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            children: [
              const Text(
                'Operators',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: HallOwnerTokens.navy,
                ),
              ),
              Text(
                'Who can manage this business · ${widget.businessName}',
                style: const TextStyle(fontSize: 13, color: HallOwnerTokens.muted),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: HallOwnerTokens.line),
                ),
                child: const Text(
                  'Operators can manage bookings and calendar but cannot delete the business or change billing.',
                  style: TextStyle(fontSize: 13, height: 1.45),
                ),
              ),
              const HallSectionLabel('Current operators'),
              for (var i = 0; i < _operators.length; i++)
                _operatorTile(_operators[i], i),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: HallPrimaryButton(
            label: 'Add Operator',
            onTap: _hallActive ? _showAddOperator : null,
          ),
        ),
      ],
    );
  }

  Widget _operatorTile(HallOperator op, int index) {
    const colors = [
      HallOwnerTokens.green,
      HallOwnerTokens.blue,
      Color(0xFF7C3AED),
      Color(0xFFEA580C),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: HallOwnerTokens.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: colors[index % colors.length],
            child: Text(
              op.name.isNotEmpty ? op.name[0].toUpperCase() : '?',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  op.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                Text(
                  '${op.phone} · ${op.isOwner ? 'Owner' : op.role == 'manager' ? 'Manager' : 'Staff'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: HallOwnerTokens.muted,
                  ),
                ),
              ],
            ),
          ),
          if (op.isOwner)
            const Text(
              'Owner',
              style: TextStyle(
                color: HallOwnerTokens.greenDark,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            )
          else
            TextButton(
              onPressed: () => _confirmRemoveOperator(op),
              child: const Text(
                'Remove',
                style: TextStyle(
                  color: HallOwnerTokens.red,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showAddOperator() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    var role = 'manager';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            16 + MediaQuery.viewInsetsOf(ctx).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Add Operator',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: HallOwnerTokens.navy,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: 'Full name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Mobile number',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: role,
                decoration: InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'manager', child: Text('Manager')),
                  DropdownMenuItem(value: 'staff', child: Text('Staff')),
                ],
                onChanged: (v) => role = v ?? 'manager',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: HallPrimaryButton(
                      label: 'Cancel',
                      outline: true,
                      onTap: () => Navigator.pop(ctx),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: HallPrimaryButton(
                      label: 'Add Operator',
                      onTap: () {
                        if (nameCtrl.text.trim().isEmpty ||
                            phoneCtrl.text.trim().isEmpty) {
                          _toast('Enter name and phone.');
                          return;
                        }
                        setState(() {
                          _operators.add(
                            HallOperator(
                              id: DateTime.now().millisecondsSinceEpoch.toString(),
                              name: nameCtrl.text.trim(),
                              phone: phoneCtrl.text.trim(),
                              role: role,
                            ),
                          );
                        });
                        Navigator.pop(ctx);
                        _toast('Operator added.');
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmRemoveOperator(HallOperator op) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove operator?'),
        content: Text('Remove ${op.name}? They will lose access to this hall.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Remove',
              style: TextStyle(color: HallOwnerTokens.red),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() => _operators.removeWhere((o) => o.id == op.id));
      _toast('Operator removed.');
    }
  }

  Widget _buildCalendar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HallLmbTopBar(
          leading: HallGreenPill(
            label: '←',
            onTap: () => _go(_HallPage.manage),
          ),
          title: 'Calendar & Availability',
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _tabChip('Calendar', true),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _tabChip('Booking Settings', false, () {
                      _toast('Booking window saved in HTML demo — wire API here.');
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    onPressed: () => setState(() => _calMonth--),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    _monthLabel(_calMonth, _calYear),
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: HallOwnerTokens.navy,
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _calMonth++),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              _calendarGrid(),
              const SizedBox(height: 12),
              HallPrimaryButton(
                label: 'Month: ${_monthLabel(_calMonth, _calYear)}',
                outline: true,
                onTap: () => _toast('Month picker — same as HTML sheet.'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tabChip(String label, bool on, [VoidCallback? tap]) {
    return Material(
      color: on ? HallOwnerTokens.greenSoft : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: tap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: on ? HallOwnerTokens.green : HallOwnerTokens.line,
              width: on ? 1.5 : 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: on ? HallOwnerTokens.greenDark : HallOwnerTokens.ink,
            ),
          ),
        ),
      ),
    );
  }

  String _monthLabel(int m, int y) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final idx = (m - 1).clamp(0, 11);
    return '${names[idx]} $y';
  }

  Widget _calendarGrid() {
    final first = DateTime(_calYear, _calMonth, 1);
    final dim = DateTime(_calYear, _calMonth + 1, 0).day;
    final cells = <Widget>[];
    for (var i = 0; i < first.weekday % 7; i++) {
      cells.add(const SizedBox());
    }
    for (var d = 1; d <= dim; d++) {
      final sel = d == _calDay;
      cells.add(
        Material(
          color: sel ? HallOwnerTokens.green : const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () {
              setState(() => _calDay = d);
              _go(_HallPage.calDay);
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '$d',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: sel ? Colors.white : HallOwnerTokens.ink,
                ),
              ),
            ),
          ),
        ),
      );
    }
    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: cells,
    );
  }

  Widget _buildCalDay() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HallLmbTopBar(
          leading: HallGreenPill(
            label: '←',
            onTap: () => _go(_HallPage.calendar),
          ),
          title: 'Select Date',
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              Text(
                '$_calDay ${_monthLabel(_calMonth, _calYear)}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: HallOwnerTokens.navy,
                ),
              ),
              const SizedBox(height: 16),
              _slotCard(
                'Morning (10:00 AM – 3:00 PM)',
                'Available',
                true,
                'Block Slot',
              ),
              _slotCard(
                'Evening (5:00 PM – 11:00 PM)',
                'Booked (Gixbee)',
                false,
                'Manage Booking',
              ),
              _slotCard(
                'Full Day (9:00 AM – 9:00 PM)',
                'Unavailable (Evening occupied)',
                false,
                null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _slotCard(
    String title,
    String status,
    bool available,
    String? action,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: HallOwnerTokens.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: available
                  ? HallOwnerTokens.greenSoft
                  : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              status,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: available
                    ? HallOwnerTokens.greenDark
                    : HallOwnerTokens.muted,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _priceChip('With AC ₹75,000', true),
              _priceChip('Without AC ₹55,000', false),
            ],
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            HallPrimaryButton(
              label: action,
              outline: !available,
              onTap: () => _toast('$action — full flow in HTML demo v36.'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _priceChip(String label, bool ac) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: ac ? HallOwnerTokens.greenSoft : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: ac ? const Color(0xFFA7F3D0) : const Color(0xFFBFDBFE),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: ac ? HallOwnerTokens.greenDark : HallOwnerTokens.blue,
        ),
      ),
    );
  }
}
