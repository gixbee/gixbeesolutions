import 'package:flutter/material.dart';
import '../../repositories/cities_repository.dart';
import '../../theme.dart';

/// Typable city field with suggestions from the live cities master.
/// The user can type freely; [onSelected] fires when they pick a suggestion.
class GxCityField extends StatefulWidget {
  final List<CityEntry> cities;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String label;
  final String? hint;
  final bool enabled;
  final bool loading;
  final EdgeInsets? scrollPadding;
  final InputDecoration? decoration;
  final ValueChanged<CityEntry?>? onSelected;

  const GxCityField({
    super.key,
    required this.cities,
    required this.controller,
    this.focusNode,
    this.label = 'City',
    this.hint,
    this.enabled = true,
    this.loading = false,
    this.scrollPadding,
    this.decoration,
    this.onSelected,
  });

  @override
  State<GxCityField> createState() => _GxCityFieldState();
}

class _GxCityFieldState extends State<GxCityField> {
  late FocusNode _node;
  bool _ownsNode = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _node = widget.focusNode!;
    } else {
      _node = FocusNode();
      _ownsNode = true;
    }
    _node.addListener(_onFocus);
  }

  @override
  void dispose() {
    _node.removeListener(_onFocus);
    if (_ownsNode) _node.dispose();
    super.dispose();
  }

  void _onFocus() {
    if (!_node.hasFocus) _commitTypedCity();
  }

  void _commitTypedCity() {
    final q = widget.controller.text.trim().toLowerCase();
    if (q.isEmpty) return;
    CityEntry? picked = matchTypedCity(widget.cities, widget.controller.text);
    if (picked == null) {
      final opts = _optionsFor(widget.controller.text).toList();
      if (opts.length == 1) picked = opts.first;
    }
    if (picked != null) widget.onSelected?.call(picked);
  }

  Iterable<CityEntry> _optionsFor(String text) {
    if (widget.cities.isEmpty) return const Iterable<CityEntry>.empty();
    final q = text.trim().toLowerCase();
    if (q.isEmpty) return widget.cities.take(8);
    return widget.cities.where((c) => cityMatchesQuery(c, text));
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<CityEntry>(
      textEditingController: widget.controller,
      focusNode: _node,
      displayStringForOption: (c) => c.displayName,
      optionsBuilder: (value) => _optionsFor(value.text),
      onSelected: (c) {
        widget.controller.text = c.displayName;
        widget.controller.selection =
            TextSelection.collapsed(offset: c.displayName.length);
        widget.onSelected?.call(c);
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        final dec = widget.decoration ??
            InputDecoration(
              labelText: widget.label,
              hintText: widget.hint ??
                  (widget.loading ? 'Loading cities…' : 'Type a city'),
              hintStyle: TextStyle(color: context.gx.ink.withValues(alpha: 0.3)),
              filled: true,
              fillColor: context.gx.card2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: context.gx.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: context.gx.border),
              ),
            );
        return TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: widget.enabled,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          scrollPadding: widget.scrollPadding ?? const EdgeInsets.all(20),
          decoration: dec,
          onSubmitted: (_) {
            _commitTypedCity();
            onFieldSubmitted();
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final opts = options.toList();
        if (opts.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            color: context.gx.card,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, minWidth: 220),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                primary: false,
                shrinkWrap: true,
                itemCount: opts.length,
                itemBuilder: (context, i) {
                  final c = opts[i];
                  return ListTile(
                    dense: true,
                    title: Text(c.name,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: context.gx.ink,
                        )),
                    subtitle: Text(c.state,
                        style: TextStyle(
                          fontSize: 12,
                          color: context.gx.ink.withValues(alpha: 0.5),
                        )),
                    onTap: () => onSelected(c),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
