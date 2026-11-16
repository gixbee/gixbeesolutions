import 'package:flutter/material.dart';

/// One catering food category. Changes are committed to the package
/// only when Apply is tapped; back navigation discards pending choices.
class CateringModulePickerScreen extends StatefulWidget {
  const CateringModulePickerScreen({
    super.key,
    required this.title,
    required this.emoji,
    required this.dishes,
    required this.selectedIds,
  });

  final String title;
  final String emoji;
  final List<Map<String, dynamic>> dishes;
  final Set<String> selectedIds;

  @override
  State<CateringModulePickerScreen> createState() =>
      _CateringModulePickerScreenState();
}

class _CateringModulePickerScreenState
    extends State<CateringModulePickerScreen> {
  final _query = TextEditingController();
  late final Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.selectedIds);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final term = _query.text.trim().toLowerCase();
    final dishes = widget.dishes.where((dish) =>
        dish['name'].toString().toLowerCase().contains(term)).toList();
    final count = widget.dishes.where((dish) =>
        _selected.contains(dish['id'])).length;

    return Scaffold(
      appBar: AppBar(title: Text('${widget.emoji}  ${widget.title}')),
      body: SafeArea(child: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${widget.dishes.length} available · $count selected',
              style: const TextStyle(color: Colors.blueGrey)),
            const SizedBox(height: 12),
            TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search dishes in this module...',
                border: OutlineInputBorder(),
              ),
            ),
          ]),
        ),
        Expanded(child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          children: [
            if (dishes.isEmpty)
              const Padding(padding: EdgeInsets.all(12),
                  child: Text('No matching dishes.')),
            for (final dish in dishes)
              Card(child: CheckboxListTile(
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(dish['name']?.toString() ?? ''),
                subtitle: Text(
                  dish['diet'] == 'non_veg' ? 'Non-vegetarian' : 'Vegetarian'),
                value: _selected.contains(dish['id']),
                onChanged: (checked) => setState(() {
                  final id = dish['id'] as String;
                  if (checked == true) {
                    _selected.add(id);
                  } else {
                    _selected.remove(id);
                  }
                }),
              )),
          ],
        )),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: const BoxDecoration(border: Border(
            top: BorderSide(color: Color(0xFFE2E8F0)))),
          child: SizedBox(width: double.infinity, child: FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              padding: const EdgeInsets.symmetric(vertical: 15)),
            onPressed: () => Navigator.of(context).pop(_selected),
            child: Text('Apply ($count)'),
          )),
        ),
      ])),
    );
  }
}
