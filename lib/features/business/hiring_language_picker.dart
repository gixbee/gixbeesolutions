import 'package:flutter/material.dart';

import '../../theme.dart';
import 'hiring_wizard_chips.dart';

/// Stable hiring language codes aligned with `hiring-catalogue.json`.
class HiringLanguageCatalog {
  static const defaults = ['en', 'ml'];

  static const quick = [
    _Lang('en', 'English'),
    _Lang('ml', 'Malayalam'),
    _Lang('hi', 'Hindi'),
    _Lang('ta', 'Tamil'),
  ];

  static const all = [
    ...quick,
    _Lang('kn', 'Kannada'),
    _Lang('te', 'Telugu'),
    _Lang('mr', 'Marathi'),
    _Lang('bn', 'Bengali'),
    _Lang('gu', 'Gujarati'),
    _Lang('pa', 'Punjabi'),
    _Lang('or', 'Odia'),
    _Lang('as', 'Assamese'),
    _Lang('ur', 'Urdu'),
    _Lang('ar', 'Arabic'),
    _Lang('kok', 'Konkani'),
    _Lang('tcy', 'Tulu'),
  ];

  static String labelFor(String id) {
    for (final l in all) {
      if (l.id == id) return l.label;
    }
    return id;
  }

  static List<_Lang> fromApi(List<Map<String, dynamic>>? rows) {
    if (rows == null || rows.isEmpty) return all;
    return rows
        .where((r) => r['isActive'] != false)
        .map((r) => _Lang('${r['id']}', '${r['label']}'))
        .toList();
  }
}

class _Lang {
  final String id;
  final String label;
  const _Lang(this.id, this.label);
}

typedef LanguagePickChanged = void Function(List<String> ids);

class HiringLanguageSection extends StatefulWidget {
  const HiringLanguageSection({
    super.key,
    required this.selectedIds,
    required this.onChanged,
    this.catalogRows,
    this.restoredDraft = false,
    this.applyEmployerDefaults = false,
    this.minSelection = 0,
  });

  final List<String> selectedIds;
  final LanguagePickChanged onChanged;
  final List<Map<String, dynamic>>? catalogRows;
  final bool restoredDraft;
  final bool applyEmployerDefaults;
  final int minSelection;

  @override
  State<HiringLanguageSection> createState() => _HiringLanguageSectionState();
}

class _HiringLanguageSectionState extends State<HiringLanguageSection> {
  late List<String> _ids;

  List<_Lang> get _catalog => HiringLanguageCatalog.fromApi(widget.catalogRows);

  List<_Lang> get _quickPick {
    if (widget.catalogRows != null && widget.catalogRows!.isNotEmpty) {
      final fromApi = _catalog.where((l) {
        for (final r in widget.catalogRows!) {
          if ('${r['id']}' == l.id && r['quickPick'] == true) return true;
        }
        return HiringLanguageCatalog.quick.any((q) => q.id == l.id);
      }).toList();
      if (fromApi.isNotEmpty) return fromApi;
    }
    return _catalog
        .where((l) => HiringLanguageCatalog.quick.any((q) => q.id == l.id))
        .toList();
  }

  int get _uniqueCount => _ids.toSet().length;

  @override
  void initState() {
    super.initState();
    _ids = _dedupe(widget.selectedIds);
    if (widget.applyEmployerDefaults && !widget.restoredDraft && _ids.isEmpty) {
      _ids = [...HiringLanguageCatalog.defaults];
      WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
    }
  }

  @override
  void didUpdateWidget(covariant HiringLanguageSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIds != widget.selectedIds) {
      _ids = _dedupe(widget.selectedIds);
    }
  }

  List<String> _dedupe(List<String> raw) {
    final seen = <String>{};
    final out = <String>[];
    for (final id in raw) {
      if (seen.add(id)) out.add(id);
    }
    return out;
  }

  void _emit() => widget.onChanged(_dedupe(_ids));

  void _toggle(String id) {
    setState(() {
      if (_ids.contains(id)) {
        if (_ids.length <= widget.minSelection) return;
        _ids.remove(id);
      } else {
        _ids.add(id);
      }
      _ids = _dedupe(_ids);
    });
    _emit();
  }

  Future<void> _openSheet() async {
    final draft = _dedupe(_ids).toSet();
    final qCtrl = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final q = qCtrl.text.trim().toLowerCase();
            final filtered = _catalog.where((l) {
              if (q.isEmpty) return true;
              return l.label.toLowerCase().contains(q) ||
                  l.id.toLowerCase().contains(q);
            }).toList();
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Add languages',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                color: context.gx.ink,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(ctx),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: qCtrl,
                        decoration: const InputDecoration(hintText: 'Search languages'),
                        onChanged: (_) => setSheet(() {}),
                      ),
                    ),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final lang in filtered)
                            CheckboxListTile(
                              value: draft.contains(lang.id),
                              title: Text(lang.label),
                              onChanged: (v) {
                                setSheet(() {
                                  if (v == true) {
                                    draft.add(lang.id);
                                  } else if (draft.length > widget.minSelection) {
                                    draft.remove(lang.id);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {
                            setState(() => _ids = draft.toList()..sort());
                            _emit();
                            Navigator.pop(ctx);
                          },
                          child: Text(
                            draft.isEmpty ? 'OK' : 'OK (${draft.length} selected)',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    qCtrl.dispose();
  }

  Widget _chip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    VoidCallback? onRemove,
  }) {
    final gx = context.gx;
    final bg = selected ? GixbeeTheme.accentGreen : Colors.white;
    final fg = selected ? gx.onAccent : gx.ink;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? GixbeeTheme.accentGreen : gx.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected && onRemove == null)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(Icons.check, size: 16, color: fg),
                ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
              if (onRemove != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onRemove,
                  child: Icon(Icons.close, size: 16, color: fg),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final gx = context.gx;
    final quick = _quickPick;
    final quickIdSet = quick.map((l) => l.id).toSet();
    final extraIds =
        _ids.where((id) => !quickIdSet.contains(id)).toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Languages ($_uniqueCount selected)',
          style: TextStyle(fontWeight: FontWeight.w800, color: gx.ink),
        ),
        const SizedBox(height: 4),
        Text(
          'Candidates who speak these languages rank higher in matching.',
          style: TextStyle(fontSize: 12, color: gx.ink.withValues(alpha: 0.55)),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final lang in quick)
              _chip(
                label: lang.label,
                selected: _ids.contains(lang.id),
                onTap: () => _toggle(lang.id),
              ),
            for (final id in extraIds)
              _chip(
                label: HiringLanguageCatalog.labelFor(id),
                selected: true,
                onTap: () {},
                onRemove: _ids.length <= widget.minSelection
                    ? null
                    : () => _toggle(id),
              ),
          ],
        ),
        const SizedBox(height: 10),
        HiringAddButton(label: 'Add languages', onPressed: _openSheet),
      ],
    );
  }
}
