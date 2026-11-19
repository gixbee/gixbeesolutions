import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// Loads [citiesProvider] and lets the user type or tap a city.
/// Replaces [DropdownButtonFormField], which often cannot open in a ListView.
class GxCitySelectField extends ConsumerStatefulWidget {
  const GxCitySelectField({
    super.key,
    required this.cityId,
    required this.onSelected,
    this.controller,
    this.label = 'Location / City *',
  });

  final String? cityId;
  final ValueChanged<CityEntry?> onSelected;
  final TextEditingController? controller;
  final String label;

  @override
  ConsumerState<GxCitySelectField> createState() => _GxCitySelectFieldState();
}

class _GxCitySelectFieldState extends ConsumerState<GxCitySelectField> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController();
  late final bool _ownsController = widget.controller == null;

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _fill(List<CityEntry> cities) {
    if (widget.cityId == null) return;
    for (final city in cities) {
      if (city.id == widget.cityId && _controller.text != city.displayName) {
        _controller.text = city.displayName;
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cities = ref.watch(citiesProvider);
    return cities.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, __) => TextButton(
        onPressed: () => ref.invalidate(citiesProvider),
        child: const Text('Reload cities'),
      ),
      data: (items) {
        if (items.isEmpty) {
          return TextButton(
            onPressed: () => ref.invalidate(citiesProvider),
            child: const Text('No cities loaded. Tap to retry'),
          );
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _fill(items);
        });
        return GxCityField(
          cities: items,
          controller: _controller,
          label: widget.label,
          hint: 'Type or pick a city',
          onSelected: widget.onSelected,
        );
      },
    );
  }
}
