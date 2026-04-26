import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/worker.dart';
import '../../shared/widgets/glass_container.dart';
import '../../repositories/booking_repository.dart';
import '../../repositories/wallet_repository.dart';
import 'waiting_for_worker_screen.dart';
import 'event_location_picker_screen.dart';

class BookingScreen extends ConsumerStatefulWidget {
  final Worker worker;
  final double? baseAmount;
  final String? bookingDescription;
  final PickedLocation? initialLocation;

  const BookingScreen({
    super.key,
    required this.worker,
    this.baseAmount,
    this.bookingDescription,
    this.initialLocation,
  });

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  int _currentStep = 0;
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  // Issue #21: User-editable address instead of hardcoded fake address
  late final TextEditingController _addressController;
  bool _isProcessing = false;
  double? _walletBalance;

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController(text: widget.initialLocation?.address ?? '');
    _fetchBalance();
  }

  Future<void> _fetchBalance() async {
    try {
      final balance = await ref.read(walletRepositoryProvider).getBalance();
      if (mounted) setState(() => _walletBalance = balance);
    } catch (_) {}
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < 2) {
      setState(() => _currentStep++);
    } else {
      _confirmBooking();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _confirmBooking() async {
    setState(() => _isProcessing = true);
    try {
      // Issue #17 fix: Check wallet balance before confirming
      final balance = await ref.read(walletRepositoryProvider).getBalance();
      final totalAmount = widget.baseAmount ?? widget.worker.hourlyRate;

      if (balance < totalAmount) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Insufficient balance (₹$balance). Please add funds.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _isProcessing = false);
        return;
      }

      final scheduledAt = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );

      final result = await ref.read(bookingRepositoryProvider).createBooking(
        workerId: widget.worker.id,
        scheduledAt: scheduledAt,
        amount: totalAmount,
        address: _addressController.text.trim(),
        description: widget.bookingDescription,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => WaitingForWorkerScreen(
              bookingId: result['id'],
              worker: widget.worker,
              skill: widget.worker.title,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Booking failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _prevStep,
        ),
      ),
      body: Column(
        children: [
          // Amazon-Style Step Indicator
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildStep(0, 'Schedule'),
                _buildDivider(),
                _buildStep(1, 'Address'),
                _buildDivider(),
                _buildStep(2, 'Payment'),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _buildCurrentStepView(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Total Amount', style: TextStyle(fontSize: 12)),
                Text(
                  '₹${(widget.baseAmount ?? widget.worker.hourlyRate).toInt()}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 20),
                ),
              ],
            ),
            SizedBox(
              width: 180,
              height: 50,
              child: ElevatedButton(
                onPressed: _canProceed() ? _nextStep : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                ),
                child: _isProcessing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_currentStep == 2 ? 'Pay & Confirm' : 'Continue'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canProceed() {
    if (_currentStep == 0) {
      return _selectedDate != null && _selectedTime != null;
    }
    if (_currentStep == 1) {
      return _addressController.text.trim().isNotEmpty;
    }
    return true;
  }

  Widget _buildStep(int step, String label) {
    final isActive = _currentStep >= step;
    final color =
        isActive ? Theme.of(context).colorScheme.primary : Colors.grey;

    return Column(
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: color,
          child: Text(
            '${step + 1}',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal),
        ),
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 40,
      height: 1,
      color: Colors.grey.shade400,
      margin: const EdgeInsets.only(left: 8, right: 8, bottom: 20),
    );
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case 0:
        return _buildScheduleStep();
      case 1:
        return _buildAddressStep();
      case 2:
        return _buildPaymentStep();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildScheduleStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Select a Schedule'),
        const SizedBox(height: 16),
        InkWell(
          onTap: _pickDate,
          child: _buildSelectionTile(
            icon: Icons.calendar_today,
            title: _selectedDate == null
                ? 'Choose Date'
                : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
          ),
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: _pickTime,
          child: _buildSelectionTile(
            icon: Icons.access_time,
            title: _selectedTime == null
                ? 'Choose Time'
                : _selectedTime!.format(context),
          ),
        ),
      ],
    );
  }

  Widget _buildAddressStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Delivery Address'),
        const SizedBox(height: 16),
        TextField(
          controller: _addressController,
          decoration: InputDecoration(
            hintText: 'Enter your address',
            prefixIcon: Icon(Icons.location_on, color: Theme.of(context).colorScheme.primary),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.add),
          label: const Text('Add New Address'),
        ),
      ],
    );
  }

  Widget _buildPaymentStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Booking Summary'),
        const SizedBox(height: 16),
        GlassContainer(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildSummaryRow('Professional', widget.worker.name),
              const Divider(),
              _buildSummaryRow(
                'Schedule',
                '${_selectedDate!.day}/${_selectedDate!.month} @ ${_selectedTime!.format(context)}',
              ),
              const Divider(),
              _buildSummaryRow('Address', _addressController.text.isNotEmpty ? _addressController.text : 'Not provided'),
              const Divider(),
              _buildSummaryRow(
                  'Service Fee', '₹${widget.worker.hourlyRate.toInt()}'),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildSectionTitle('Select Payment Method'),
        const SizedBox(height: 12),
        _buildSelectionTile(
          icon: Icons.account_balance_wallet,
          title: _walletBalance != null ? 'UPI / Wallet (Balance: ₹${_walletBalance!.toInt()})' : 'UPI / Wallet...',
          isAction: true,
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
    );
  }

  Widget _buildSelectionTile(
      {required IconData icon, required String title, bool isAction = false}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 16),
          Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w500))),
          if (isAction) const Icon(Icons.keyboard_arrow_right),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }
}

