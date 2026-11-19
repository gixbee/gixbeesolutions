import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/events_repository.dart';
import '../../shared/widgets/gx_network_error.dart';
import '../../shared/widgets/gx_snackbar.dart';
import '../../theme.dart';

/// Decisions are based on confirmed API state; never infer delivery or payment
/// success from a missing response or from local UI state.
class EventCommerceRules {
  const EventCommerceRules._();

  static bool canUpload(bool customer, String quoteStatus,
      List<Map<String, dynamic>> versions) =>
      !customer && quoteStatus == 'CONFIRMED' &&
      (versions.isEmpty || versions.first['status'] == 'REVISION_REQUESTED');

  static bool canReviewDelivery(bool customer, String quoteStatus,
      List<Map<String, dynamic>> versions) =>
      customer && quoteStatus == 'CONFIRMED' &&
      versions.isNotEmpty && versions.first['status'] == 'SUBMITTED';

  static bool canReport(bool customer, String quoteStatus,
      List<Map<String, dynamic>> reports, bool openDispute) =>
      customer && quoteStatus == 'CONFIRMED' && !openDispute &&
      (reports.isEmpty || reports.first['status'] == 'REJECTED');

  static bool canAttachReceipt(bool customer, String quoteStatus,
      Map<String, dynamic>? latestReport, int evidenceCount) =>
      customer && quoteStatus == 'CONFIRMED' && evidenceCount < 5 &&
      (latestReport?['status'] == 'REPORTED' ||
       latestReport?['status'] == 'CONTESTED');

  static bool canReconcile(bool customer, String quoteStatus,
      List<Map<String, dynamic>> reports) =>
      !customer && quoteStatus == 'CONFIRMED' &&
      reports.isNotEmpty && reports.first['status'] == 'REPORTED';
}

Future<String?> _prompt(BuildContext context, String title,
    {String hint = '', int min = 1}) async {
  var value = '';
  return showDialog<String>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(title),
        content: TextField(
          maxLength: 1500,
          maxLines: 3,
          decoration: InputDecoration(hintText: hint),
          onChanged: (v) => setDialogState(() => value = v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: value.length < min
                ? null : () => Navigator.pop(dialog, value),
            child: const Text('Continue'),
          ),
        ],
      ),
    ),
  );
}

Future<bool> _confirmCommerce(
    BuildContext context, String title, String explanation) async =>
    await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Text(explanation),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ?? false;

class PhotographyDeliveryPanel extends ConsumerStatefulWidget {
  const PhotographyDeliveryPanel({
    super.key, required this.quoteId, required this.milestoneId,
    required this.customer, required this.status, this.onChanged,
  });
  final String quoteId;
  final String milestoneId;
  final bool customer;
  final String status;
  final VoidCallback? onChanged;

  @override
  ConsumerState<PhotographyDeliveryPanel> createState() =>
      _PhotographyDeliveryPanelState();
}

class _PhotographyDeliveryPanelState
    extends ConsumerState<PhotographyDeliveryPanel> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    _future = ref.read(eventsRepositoryProvider)
        .deliveryVersions(widget.quoteId, widget.milestoneId);
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
      if (!mounted) return;
      setState(_refresh);
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) showGxSnack(context, eventError(e), type: GxSnackType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf', 'zip'],
      withData: true,
    );
    if (selection == null || !mounted) return;
    final file = selection.files.single;
    final Uint8List? content = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (content == null || content.isEmpty || content.length > 12 * 1024 * 1024) {
      showGxSnack(context, 'Choose a file up to 12 MB.',
          type: GxSnackType.error);
      return;
    }
    final note = await _prompt(context, 'Delivery notes',
        hint: 'What changed in this version?', min: 0);
    if (note == null || !mounted) return;
    await _run(() async {
      await ref.read(eventsRepositoryProvider).uploadDelivery(
        widget.quoteId, widget.milestoneId, file.name, content, note);
    });
  }

  Future<void> _review(String decision) async {
    final note = decision == 'REQUEST_REVISION'
        ? await _prompt(context, 'Describe the requested changes',
            hint: 'Be specific about what needs revision.', min: 10)
        : await _confirmCommerce(context, 'Approve photography delivery?',
            'You confirm this version meets the agreed deliverable. '
            'The delivery milestone will be recorded as completed.')
            ? '' : null;
    if (note == null || !mounted) return;
    await _run(() => ref.read(eventsRepositoryProvider).reviewDelivery(
        widget.quoteId, widget.milestoneId, decision, note));
  }

  Future<void> _download(Map<String, dynamic> version) async {
    await _run(() async {
      final bytes = await ref.read(eventsRepositoryProvider)
          .downloadDelivery(widget.quoteId, version['id'].toString());
      final originalName = version['fileName']?.toString() ?? 'delivery.bin';
      final safeName = originalName.split(RegExp(r'[/\\]')).last;
      await FilePicker.platform.saveFile(
        dialogTitle: 'Save private delivery file',
        fileName: safeName,
        bytes: bytes,
      );
    });
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const LinearProgressIndicator();
          }
          if (snapshot.hasError) {
            return GxNetworkError(error: snapshot.error,
              title: 'Deliveries unavailable',
              onRetry: () => setState(_refresh));
          }
          final versions = snapshot.data ?? const <Map<String, dynamic>>[];
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Private photography deliveries',
              style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            const Text('Only the event customer and photographer can access '
              'these files. Versions remain available after revision requests.',
              style: TextStyle(fontSize: 12)),
            if (versions.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No file has been submitted yet.')),
            for (final version in versions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text('Version ${version['version']} · ${version['fileName']}',
                  maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text([
                  version['status']?.toString() ?? '',
                  if ((version['note']?.toString() ?? '').isNotEmpty)
                    version['note'].toString(),
                  if ((version['feedback']?.toString() ?? '').isNotEmpty)
                    'Feedback: ${version['feedback']}',
                ].join(' · ')),
                trailing: IconButton(
                  tooltip: 'Download private file',
                  icon: const Icon(Icons.download_outlined),
                  onPressed: _busy ? null : () => _download(version),
                ),
              ),
            if (EventCommerceRules.canUpload(widget.customer, widget.status, versions))
              FilledButton.icon(
                onPressed: _busy ? null : _upload,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(versions.isEmpty
                    ? 'Upload delivery' : 'Upload revised version'),
              ),
            if (EventCommerceRules.canReviewDelivery(
                widget.customer, widget.status, versions))
              Wrap(spacing: 8, children: [
                FilledButton(
                  onPressed: _busy ? null : () => _review('APPROVE'),
                  child: const Text('Approve delivery'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : () => _review('REQUEST_REVISION'),
                  child: const Text('Request revision'),
                ),
              ]),
          ]);
        },
      );
}

class EventPaymentPanel extends ConsumerStatefulWidget {
  const EventPaymentPanel({
    super.key, required this.quoteId, required this.milestoneId,
    required this.customer, required this.status, required this.amount,
    this.onChanged,
  });
  final String quoteId;
  final String milestoneId;
  final bool customer;
  final String status;
  final Object? amount;
  final VoidCallback? onChanged;

  @override
  ConsumerState<EventPaymentPanel> createState() => _EventPaymentPanelState();
}

class _PaymentView {
  const _PaymentView(this.reports, this.disputes, this.evidence);
  final List<Map<String, dynamic>> reports;
  final List<Map<String, dynamic>> disputes;
  final List<Map<String, dynamic>> evidence;
}

class _EventPaymentPanelState extends ConsumerState<EventPaymentPanel> {
  late Future<_PaymentView> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    final repo = ref.read(eventsRepositoryProvider);
    _future = Future.wait([
      repo.paymentReports(widget.quoteId, widget.milestoneId),
      repo.quoteDisputes(widget.quoteId),
      repo.paymentEvidence(widget.quoteId, widget.milestoneId),
    ]).then((results) => _PaymentView(results[0],
        results[1].where((d) => d['milestoneId'] == widget.milestoneId).toList(),
        results[2]));
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await job();
      if (!mounted) return;
      setState(_refresh);
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) showGxSnack(context, eventError(e), type: GxSnackType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _attachReceipt() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: true,
    );
    if (selection == null || !mounted) return;
    final file = selection.files.single;
    final Uint8List? bytes = file.bytes ??
        (file.path == null ? null : await File(file.path!).readAsBytes());
    if (bytes == null || bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
      showGxSnack(context, 'Choose a JPG, PNG, WebP or PDF up to 5 MB.',
          type: GxSnackType.error);
      return;
    }
    await _run(() => ref.read(eventsRepositoryProvider)
      .uploadPaymentEvidence(widget.quoteId, widget.milestoneId, file.name, bytes));
  }

  Future<void> _downloadReceipt(Map<String, dynamic> evidence) async {
    await _run(() async {
      final bytes = await ref.read(eventsRepositoryProvider)
        .downloadPaymentEvidence(widget.quoteId, evidence['id'].toString());
      final name = (evidence['fileName']?.toString() ?? 'receipt.pdf')
        .split(RegExp(r'[/\\]')).last;
      await FilePicker.platform.saveFile(
        dialogTitle: 'Save private payment evidence', fileName: name,
        bytes: bytes,
      );
    });
  }

  Future<void> _report() async {
    String method = 'UPI', reference = '', note = '';
    final draft = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report direct payment'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('Agreed installment: ${eventMoney(widget.amount)}'),
              const SizedBox(height: 8),
              const Text('This does not transfer or independently verify money.',
                  style: TextStyle(fontSize: 12)),
              DropdownButtonFormField<String>(
                initialValue: method,
                items: const [
                  DropdownMenuItem(value: 'UPI', child: Text('UPI')),
                  DropdownMenuItem(value: 'BANK', child: Text('Bank transfer')),
                  DropdownMenuItem(value: 'CASH', child: Text('Cash')),
                  DropdownMenuItem(value: 'OTHER', child: Text('Other')),
                ],
                onChanged: (value) => setDialogState(() => method = value ?? 'UPI'),
              ),
              TextField(
                maxLength: 120,
                decoration: const InputDecoration(
                  labelText: 'Transaction reference / receipt ID',
                  hintText: 'For cash, enter a receipt identifier'),
                onChanged: (value) => setDialogState(() => reference = value.trim()),
              ),
              TextField(
                maxLength: 1500,
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Payment notes'),
                onChanged: (value) => note = value.trim(),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancel')),
            FilledButton(
              onPressed: reference.length < 4
                ? null : () => Navigator.pop(dialog, {
                    'method': method, 'reference': reference, 'note': note,
                  }),
              child: const Text('Report payment sent'),
            ),
          ],
        ),
      ),
    );
    if (draft == null || !mounted) return;
    await _run(() => ref.read(eventsRepositoryProvider).reportDirectPayment(
      widget.quoteId, widget.milestoneId,
      method: draft['method']!, reference: draft['reference']!,
      note: draft['note']!,
    ));
  }

  Future<void> _vendorDecision(String decision) async {
    final note = decision == 'CONTEST'
      ? await _prompt(context, 'Why was the payment not received?',
          hint: 'Include the mismatch or evidence to review.', min: 10)
      : await _confirmCommerce(context, 'Confirm direct receipt?',
          'Confirm only if you independently verified that the agreed '
          'installment reached you. Gixbee does not verify bank transactions.')
            ? '' : null;
    if (note == null || !mounted) return;
    await _run(() => ref.read(eventsRepositoryProvider)
      .reviewDirectPayment(widget.quoteId, widget.milestoneId, decision, note));
  }

  Future<void> _openDispute() async {
    final reason = await _prompt(context, 'Open a payment dispute',
        hint: 'Explain the payment disagreement and known references.', min: 10);
    if (reason == null || !mounted) return;
    await _run(() => ref.read(eventsRepositoryProvider)
      .openQuoteDispute(widget.quoteId, widget.milestoneId, reason));
  }

  Future<void> _comment(Map<String, dynamic> dispute) async {
    final text = await _prompt(context, 'Add dispute evidence / comments',
      hint: 'Reference numbers, dates and other verifiable details.', min: 1);
    if (text == null || !mounted) return;
    await _run(() => ref.read(eventsRepositoryProvider)
      .disputeMessage(widget.quoteId, dispute['id'].toString(), text));
  }

  Future<void> _resolve(Map<String, dynamic> dispute, String decision) async {
    final agreed = await _confirmCommerce(context,
      decision == 'SETTLED' ? 'Agree payment was settled?'
                            : 'Agree payment was not received?',
      'This records your proposed resolution. The dispute closes only if '
      'the other participant chooses the same outcome. This is not bank verification.');
    if (!agreed || !mounted) return;
    await _run(() => ref.read(eventsRepositoryProvider).resolveQuoteDispute(
      widget.quoteId, dispute['id'].toString(), decision, ''));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_PaymentView>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const LinearProgressIndicator();
      }
      if (snapshot.hasError) {
        return GxNetworkError(error: snapshot.error,
          title: 'Reconciliation unavailable',
          onRetry: () => setState(_refresh));
      }
      final data = snapshot.data!;
      final latest = data.reports.firstOrNull;
      final open = data.disputes.any((d) => d['status'] == 'OPEN');
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Direct-payment reconciliation',
          style: Theme.of(context).textTheme.titleSmall),
        Text('Installment: ${eventMoney(widget.amount)}',
          style: TextStyle(color: context.gx.ink)),
        const Text('Payment claims and receipt confirmations are declarations '
          'by the participants, not verified bank transactions.',
          style: TextStyle(fontSize: 12)),
        if (latest == null)
          const Padding(padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No payment has been reported.')),
        for (final report in data.reports)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.receipt_long_outlined),
            title: Text('Report v${report['version']} · ${report['status']}'),
            subtitle: Text(
              '${report['method']} · ${report['reference']}\n'
              '${report['note'] ?? ''}'
              '${report['reviewNote'] == null || report['reviewNote'] == '' ? '' : '\nVendor: ${report['reviewNote']}'}',
            ),
          ),
        if (data.evidence.isNotEmpty)
          const Text('Attached receipts',
            style: TextStyle(fontWeight: FontWeight.w700)),
        for (final receipt in data.evidence)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(receipt['fileName']?.toString() ?? 'Receipt'),
            subtitle: const Text('Participant-provided evidence; not bank verified'),
            trailing: IconButton(
              tooltip: 'Download private receipt',
              icon: const Icon(Icons.download_outlined),
              onPressed: _busy ? null : () => _downloadReceipt(receipt),
            ),
          ),
        if (EventCommerceRules.canAttachReceipt(
            widget.customer, widget.status, latest, data.evidence.length))
          TextButton.icon(
            onPressed: _busy ? null : _attachReceipt,
            icon: const Icon(Icons.attach_file_outlined),
            label: const Text('Attach receipt (PDF or image)'),
          ),
        if (EventCommerceRules.canReport(
            widget.customer, widget.status, data.reports, open))
          FilledButton.icon(
            onPressed: _busy ? null : _report,
            icon: const Icon(Icons.add_card_outlined),
            label: const Text('Report payment sent'),
          ),
        if (EventCommerceRules.canReconcile(
            widget.customer, widget.status, data.reports))
          Wrap(spacing: 8, children: [
            FilledButton(
              onPressed: _busy ? null : () => _vendorDecision('CONFIRM'),
              child: const Text('Confirm receipt'),
            ),
            OutlinedButton(
              onPressed: _busy ? null : () => _vendorDecision('CONTEST'),
              child: const Text('Contest claim'),
            ),
          ]),
        if (!open && latest?['status'] != 'CONFIRMED' &&
            widget.status == 'CONFIRMED')
          TextButton.icon(
            onPressed: _busy ? null : _openDispute,
            icon: const Icon(Icons.report_problem_outlined),
            label: const Text('Open a payment dispute'),
          ),
        if (data.disputes.isNotEmpty)
          const Divider(height: 24),
        for (final dispute in data.disputes)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dispute · ${dispute['status']}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(dispute['reason']?.toString() ?? ''),
                  Text('Customer: ${dispute['customerVote'] ?? 'No vote'} · '
                      'Vendor: ${dispute['vendorVote'] ?? 'No vote'}'),
                  for (final event in (dispute['events'] as List? ?? []).whereType<Map>())
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text('${event['action']}: ${event['message']}',
                        style: const TextStyle(fontSize: 12)),
                    ),
                  if (dispute['status'] == 'OPEN')
                    Wrap(spacing: 8, children: [
                      TextButton(
                        onPressed: _busy ? null : () => _comment(dispute),
                        child: const Text('Add evidence / note'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => _resolve(dispute, 'SETTLED'),
                        child: const Text('Agree settled'),
                      ),
                      TextButton(
                        onPressed: _busy ? null : () => _resolve(dispute, 'UNPAID'),
                        child: const Text('Agree unpaid'),
                      ),
                    ]),
                ]),
            ),
          ),
      ]);
    },
  );
}
