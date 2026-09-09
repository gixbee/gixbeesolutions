import 'package:flutter/material.dart';
import '../../theme.dart';

/// The last step before a request is sent. These values also form the request.
class InstantBookingReview extends StatelessWidget {
  const InstantBookingReview({
    super.key,
    required this.skill,
    required this.address,
    required this.description,
    required this.contact,
    required this.languages,
    required this.hourlyRate,
  });

  final String skill;
  final String address;
  final String description;
  final String contact;
  final List<String> languages;
  final double hourlyRate;

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final rate = hourlyRate.round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Review your request',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w900, color: gx.ink)),
        const SizedBox(height: 8),
        Text('Check the details before we notify nearby professionals.',
            style:
                TextStyle(color: gx.ink.withValues(alpha: 0.65), height: 1.5)),
        const SizedBox(height: 20),
        _detail(context, 'Service', skill),
        _detail(context, 'Service address', address),
        _detail(context, 'Task details', description),
        _detail(context, 'Person at the location', contact),
        _detail(context, 'Languages', languages.join(', ')),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
              color: gx.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: gx.border)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your offered rate: ₹$rate / hour',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: gx.accent)),
            const SizedBox(height: 8),
            Text(
                'Minimum service charge: ₹$rate (1 hour). After the first hour, '
                'service is billed per elapsed work minute. The final total depends on work time.',
                style: TextStyle(color: gx.ink, height: 1.5)),
            const SizedBox(height: 12),
            Text(
                'Travel is extra: a one-way charge based on the professional’s recorded '
                'distance when accepting. Check travel details after acceptance. '
                'Materials are separate; agree any additional work or purchases in chat before work starts.',
                style: TextStyle(
                    color: gx.ink.withValues(alpha: 0.7), height: 1.5)),
          ]),
        ),
        const SizedBox(height: 18),
        _detail(
            context,
            'Payment',
            'Pay the professional directly by cash or UPI after the job. '
                'You and the professional each confirm payment in Gixbee.'),
        _detail(
            context,
            'Arrival and completion',
            'Share the arrival OTP only once the professional is there and you have agreed the task. '
                'It starts work time. The completion OTP ends work; payment is confirmed separately.'),
        _detail(
            context,
            'Cancellation',
            'Free while searching or within 3 minutes after acceptance. Later, cancellation '
                'requires the professional’s agreement or may count as a late cancellation. '
                'After arrival or work starts, use the booking’s issue and support options. '
                'Three late cancellations block new Instant Help requests until applicable travel compensation is paid.'),
        _detail(
            context,
            'Availability',
            'Your request is confirmed when a professional accepts. '
                'If nobody accepts, no service charge is due.'),
      ],
    );
  }

  Widget _detail(BuildContext context, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.gx.ink.withValues(alpha: 0.6))),
          const SizedBox(height: 4),
          Text(value,
              style:
                  TextStyle(fontSize: 14, height: 1.5, color: context.gx.ink)),
        ]),
      );
}
