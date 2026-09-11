import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../repositories/matching_repository.dart';
import '../../repositories/events_repository.dart' show eventDate, eventMoney, eventError;
import '../../shared/widgets/gx_button.dart';
import '../../shared/widgets/gx_calendar.dart';
import '../../shared/widgets/gx_text_field.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';

class HiringProgressScreen extends ConsumerStatefulWidget {
  const HiringProgressScreen({super.key, required this.interestId});
  final String interestId;
  @override
  ConsumerState<HiringProgressScreen> createState() => _HiringProgressScreenState();
}

class _HiringProgressScreenState extends ConsumerState<HiringProgressScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  bool _busy = false;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final data = await ref.read(matchingRepositoryProvider).applicationProgress(widget.interestId);
      if (mounted) setState(() { _data = data; _error = null; });
    } catch (e) { if (mounted) setState(() => _error = eventError(e)); }
  }

  Future<void> _send(String action, Map<String, dynamic> input) async {
    if (_busy || _data == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(matchingRepositoryProvider).updateApplication(widget.interestId, action,
        {...input, 'revision': _data!['revision']});
      await _load();
    } catch (e) {
      if (mounted) showGxSnack(context, eventError(e));
      await _load();
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _confirm(String action, String title, String text) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(title), content: SingleChildScrollView(child: Text(text)),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Go back')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm'))],
    ));
    if (confirmed == true && mounted) await _send(action, {});
  }

  Future<void> _form(String action) async {
    final result = await Navigator.push<Map<String, dynamic>>(context, MaterialPageRoute(
      builder: (_) => _ApplicationForm(action: action, initial: Map<String, dynamic>.from(_data!['progress'] as Map))));
    if (result != null && mounted) await _send(action, result);
  }

  Widget _button(String label, VoidCallback action) => Padding(padding: const EdgeInsets.only(top: 12),
    child: GxButton(label: label, onTap: _busy ? null : action, filled: false));

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final p = data?['progress'] as Map? ?? {};
    final employer = data?['isEmployer'] == true;
    final stage = '${p['stage'] ?? data?['decision'] ?? 'PENDING'}';
    final editable = data?['decision'] == 'SHORTLISTED';
    const labels = {'PENDING': 'Awaiting shortlist', 'SHORTLISTED': 'Shortlisted',
      'INTERVIEW_PROPOSED': 'Interview invitation', 'INTERVIEW_ACCEPTED': 'Interview confirmed',
      'INTERVIEW_DECLINED': 'Interview declined', 'INTERVIEW_COMPLETED': 'Interview completed',
      'OFFERED': 'Offer awaiting response', 'ACCEPTED': 'Offer accepted · joining next',
      'OFFER_DECLINED': 'Offer declined', 'JOINED': 'Joining confirmed', 'WITHDRAWN': 'Application closed',
      'HIRED': 'Hired', 'REJECTED': 'Not selected'};
    final history = (p['history'] as List? ?? []).reversed;
    return Scaffold(
      appBar: AppBar(title: const Text('Application progress'), actions: [IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh))]),
      body: data == null ? Center(child: _error == null ? const CircularProgressIndicator()
        : Column(mainAxisSize: MainAxisSize.min, children: [Text(_error!), TextButton(onPressed: _load, child: const Text('Try again'))]))
        : RefreshIndicator(onRefresh: _load, child: ListView(padding: const EdgeInsets.all(20), children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!),
          Text('${data['jobType']}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: context.gx.ink)),
          const SizedBox(height: 8),
          Text(employer ? '${data['candidateName'] ?? 'Candidate'}' : '${data['businessName'] ?? 'Employer'}'),
          Text('${data['location'] ?? ''}'),
          const SizedBox(height: 12),
          Text(data['decision'] == 'REJECTED' && stage != 'WITHDRAWN' ? 'Not selected' : labels[stage] ?? stage,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if (!employer && data['businessPhone'] != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: SelectableText('Employer contact: ${data['businessPhone']}')),
          if (p['interviewAt'] != null) ...[
            const Divider(height: 32), const Text('Interview', style: TextStyle(fontWeight: FontWeight.w800)),
            Text(eventDate(p['interviewAt'])), SelectableText('${p['interviewPlace'] ?? ''}'),
          ],
          if (p['offerTerms'] != null) ...[
            const Divider(height: 32), const Text('Offer', style: TextStyle(fontWeight: FontWeight.w800)),
            Text('${eventMoney(p['salary'])} per month'),
            Text('Joining: ${eventDate(p['joiningAt'])}'), SelectableText('${p['offerTerms']}'),
          ],
          if (stage == 'ACCEPTED' || stage == 'JOINED') ...[
            const SizedBox(height: 16),
            Text('Joining: employer ${p['employerJoinedAt'] == null ? 'pending' : 'confirmed'}, '
              'candidate ${p['candidateJoinedAt'] == null ? 'pending' : 'confirmed'}'),
          ],
          if (p['withdrawalReason'] != null) Text('Reason: ${p['withdrawalReason']}'),
          if (editable) ...[
            if (employer) ...[
              if (['SHORTLISTED', 'INTERVIEW_PROPOSED', 'INTERVIEW_ACCEPTED', 'INTERVIEW_DECLINED', 'INTERVIEW_COMPLETED', 'OFFER_DECLINED'].contains(stage))
                _button('Schedule / reschedule interview', () => _form('interview')),
              if (stage == 'INTERVIEW_ACCEPTED') _button('Mark interview completed', () => _confirm('complete-interview',
                'Interview completed?', 'Confirm the interview has taken place.')),
              if (['SHORTLISTED', 'INTERVIEW_COMPLETED', 'OFFER_DECLINED', 'OFFERED'].contains(stage))
                _button(stage == 'OFFERED' ? 'Update employment offer' : 'Send employment offer', () => _form('offer')),
            ] else ...[
              if (stage == 'INTERVIEW_PROPOSED') ...[
                _button('Accept interview', () => _confirm('accept-interview', 'Accept interview?',
                  '${eventDate(p['interviewAt'])}\n${p['interviewPlace']}')),
                _button('Decline interview', () => _confirm('decline-interview', 'Decline this interview time?',
                  'The employer can suggest another time.')),
              ],
              if (stage == 'OFFERED') ...[
                _button('Accept employment offer', () => _confirm('accept-offer', 'Accept this offer?',
                  'Monthly salary: ${eventMoney(p['salary'])}\nJoining: ${eventDate(p['joiningAt'])}\n\n${p['offerTerms']}')),
                _button('Decline employment offer', () => _confirm('decline-offer', 'Decline this offer?',
                  'The employer will see your response and may send a revised offer.')),
              ],
            ],
            if (stage == 'ACCEPTED' && p[employer ? 'employerJoinedAt' : 'candidateJoinedAt'] == null)
              _button(employer ? 'Confirm candidate joined' : 'Confirm I joined', () => _confirm('joined', 'Confirm joining?',
                'Confirm actual joining on or after the agreed start time. The hire is recorded once both parties acknowledge joining.')),
            _button(employer ? 'Close application / withdraw offer' : 'Withdraw application', () => _form('withdraw')),
          ],
          if (history.isNotEmpty) ...[
            const Divider(height: 32), const Text('Activity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            for (final entry in history) ListTile(contentPadding: EdgeInsets.zero,
              title: Text('${entry['by']} · ${entry['action']}'.replaceAll('-', ' ')),
              subtitle: Text(eventDate(entry['at'])),
              onTap: () => showDialog<void>(context: context, builder: (context) => AlertDialog(
                title: const Text('Saved update'), content: SingleChildScrollView(child: SelectableText(
                  (entry['details'] as Map? ?? {}).entries.map((e) => '${e.key}: ${e.value}').join('\n\n'))),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))]))),
          ],
        ])),
    );
  }
}

class _ApplicationForm extends StatefulWidget {
  const _ApplicationForm({required this.action, required this.initial});
  final String action;
  final Map<String, dynamic> initial;
  @override
  State<_ApplicationForm> createState() => _ApplicationFormState();
}

class _ApplicationFormState extends State<_ApplicationForm> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _text;
  late final TextEditingController _salary;
  DateTime _date = DateTime.now().add(const Duration(days: 2));
  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: '${widget.initial[widget.action == 'offer' ? 'offerTerms' : widget.action == 'interview' ? 'interviewPlace' : 'unused'] ?? ''}');
    _salary = TextEditingController(text: '${widget.initial['salary'] ?? ''}');
  }
  @override
  void dispose() { _text.dispose(); _salary.dispose(); super.dispose(); }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showGxCalendar(context, title: 'Date', initialDate: _date,
      firstDate: DateTime(now.year, now.month, now.day), lastDate: now.add(const Duration(days: 730)));
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_date));
    if (time != null && mounted) setState(() => _date = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.action == 'offer';
    final withdraw = widget.action == 'withdraw';
    return Scaffold(appBar: AppBar(title: Text(withdraw ? 'Close application' : offer ? 'Employment offer' : 'Schedule interview')),
      body: Form(key: _key, child: ListView(padding: const EdgeInsets.all(20), children: [
        if (!withdraw) ...[
          ListTile(contentPadding: EdgeInsets.zero, title: Text(offer ? 'Joining date and time' : 'Interview date and time'),
            subtitle: Text(eventDate(_date.toIso8601String())), trailing: const Icon(Icons.calendar_month), onTap: _pickDate),
          const Text('Times are shown in your device timezone.'), const SizedBox(height: 20),
        ],
        if (offer) ...[
          GxTextField(controller: _salary, label: 'Monthly salary (₹)', keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: (v) { final n = double.tryParse(v ?? ''); return n == null || !n.isFinite || n <= 0 || n > 99999999 ? 'Enter a positive monthly salary' : null; }),
          const SizedBox(height: 20),
        ],
        GxTextField(controller: _text, label: withdraw ? 'Reason' : offer ? 'Role, workplace, hours and offer terms' : 'Meeting address / video link and instructions',
          maxLines: 6, maxLength: offer ? 5000 : 2000, validator: (v) => v == null || v.trim().isEmpty ? 'Enter the details' : null),
        const SizedBox(height: 24),
        GxButton(label: withdraw ? 'Close application' : 'Send for candidate response', onTap: () {
          if (!_key.currentState!.validate()) return;
          if (!withdraw && !_date.isAfter(DateTime.now())) { showGxSnack(context, 'Choose a future time'); return; }
          Navigator.pop(context, <String, dynamic>{
            if (withdraw) 'reason': _text.text.trim()
            else if (offer) ...{'salary': double.parse(_salary.text), 'joiningAt': _date.toUtc().toIso8601String(), 'offerTerms': _text.text.trim()}
            else ...{'interviewAt': _date.toUtc().toIso8601String(), 'interviewPlace': _text.text.trim()},
          });
        }),
      ])),
    );
  }
}
