import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/custom_text_field.dart';
import '../providers/institution_provider.dart';

enum SectionFieldType { text, multiline, number, currency, date, email, choice }

/// One field in a section row, described rather than hand-built.
///
/// Five prospectus sections have the same shape — list rows, add one, edit one,
/// remove one — so they share a widget driven by this spec instead of five
/// near-identical screens.
class SectionField {
  final String key;
  final String label;
  final String? hint;
  final SectionFieldType type;
  final bool required;

  /// For `choice`: the value → label map, plus what an empty selection means.
  final Map<String, String>? options;
  final String? emptyLabel;

  const SectionField({
    required this.key,
    required this.label,
    this.hint,
    this.type = SectionFieldType.text,
    this.required = false,
    this.options,
    this.emptyLabel,
  });
}

/// A collapsible section of the institution page: its rows, and a sheet to add
/// or edit one.
class SectionEditor extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String table;
  final List<SectionField> fields;

  /// One of the things this section holds — "contact", "requirement" — for
  /// "Add contact" and "Edit requirement". Falls back to the section title.
  final String? itemName;

  /// The headline and supporting line for a row in the list.
  final String Function(Map<String, dynamic>) summarise;
  final String Function(Map<String, dynamic>) detail;

  const SectionEditor({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.table,
    required this.fields,
    required this.summarise,
    required this.detail,
    this.itemName,
  });

  String get noun => itemName ?? title.toLowerCase();

  @override
  State<SectionEditor> createState() => _SectionEditorState();
}

class _SectionEditorState extends State<SectionEditor> {
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final rows = await context.read<InstitutionProvider>().listSection(
      widget.table,
    );
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
      // Open automatically when empty: an unfilled section is the thing the
      // completeness meter is complaining about.
      _expanded = rows.isEmpty;
    });
  }

  Future<void> _edit([Map<String, dynamic>? row]) async {
    // A full page with a back arrow, not a sheet. A sheet could only be
    // dismissed by dragging it down, which people do not discover — so
    // someone who opened "Add requirement" by mistake had no visible way out.
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _RowSheet(
          title: widget.noun,
          table: widget.table,
          fields: widget.fields,
          row: row,
        ),
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _remove(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this?'),
        content: Text(widget.summarise(row)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await context.read<InstitutionProvider>().deleteSectionRow(
      widget.table,
      row['id'] as String,
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(widget.icon, size: 20, color: colors.accent),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.title, style: text.titleMedium),
                          Text(
                            _loading
                                ? 'Loading…'
                                : _rows.isEmpty
                                ? 'Nothing added yet'
                                : '${_rows.length} added',
                            style: text.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _expanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      color: colors.textLight,
                    ),
                  ],
                ),
              ),
            ),

            if (_expanded) ...[
              Divider(height: 1, color: colors.divider),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.subtitle,
                      style: text.bodySmall?.copyWith(height: 1.45),
                    ),
                    const SizedBox(height: 14),
                    ..._rows.map(
                      (row) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () => _edit(row),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: colors.surfaceVariant,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.summarise(row),
                                        style: text.titleSmall,
                                      ),
                                      Text(
                                        widget.detail(row),
                                        style: text.bodySmall,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove',
                                  onPressed: () => _remove(row),
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    size: 19,
                                    color: colors.error,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _edit(),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: Text('Add ${widget.noun}'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── The add/edit sheet ──────────────────────────────────────────────────────

class _RowSheet extends StatefulWidget {
  final String title;
  final String table;
  final List<SectionField> fields;
  final Map<String, dynamic>? row;

  const _RowSheet({
    required this.title,
    required this.table,
    required this.fields,
    this.row,
  });

  @override
  State<_RowSheet> createState() => _RowSheetState();
}

class _RowSheetState extends State<_RowSheet> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers = {
    for (final f in widget.fields)
      if (f.type != SectionFieldType.choice)
        f.key: TextEditingController(
          text: f.type == SectionFieldType.currency
              ? formatAmountWithCommas(widget.row?[f.key])
              : (widget.row?[f.key]?.toString() ?? ''),
        ),
  };
  late final Map<String, String?> _choices = {
    for (final f in widget.fields)
      if (f.type == SectionFieldType.choice)
        f.key: widget.row?[f.key] as String?,
  };

  bool _saving = false;

  /// What the form held when it opened, to tell whether leaving loses work.
  late final Map<String, String> _initialText = {
    for (final e in _controllers.entries) e.key: e.value.text,
  };
  late final Map<String, String?> _initialChoices = Map.of(_choices);

  bool get _dirty =>
      _controllers.entries.any((e) => e.value.text != _initialText[e.key]) ||
      _choices.entries.any((e) => e.value != _initialChoices[e.key]);

  /// Back, asking first only if something was typed. An untouched form just
  /// closes — the case of opening it to look, or by mistake.
  Future<void> _leave() async {
    if (_saving) return;
    if (!_dirty) {
      Navigator.of(context).pop(false);
      return;
    }
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('What you have typed here will not be saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            style: TextButton.styleFrom(foregroundColor: context.colors.error),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop(false);
  }

  bool _wasDirty = false;

  @override
  void initState() {
    super.initState();
    // Typing does not rebuild the page, but PopScope reads `_dirty` at build
    // time — so a swipe back would skip the question. Rebuild only when the
    // answer to "would leaving lose something?" changes.
    for (final c in _controllers.values) {
      c.addListener(() {
        if (_dirty != _wasDirty) setState(() => _wasDirty = _dirty);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(SectionField field) async {
    final now = DateTime.now();
    final existing = DateTime.tryParse(_controllers[field.key]!.text);

    final picked = await showDatePicker(
      context: context,
      initialDate: existing ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
      helpText: field.label,
    );

    if (picked != null) {
      setState(() {
        _controllers[field.key]!.text = picked
            .toIso8601String()
            .split('T')
            .first;
      });
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);

    final values = <String, dynamic>{};
    for (final field in widget.fields) {
      if (field.type == SectionFieldType.choice) {
        values[field.key] = _choices[field.key];
        continue;
      }
      final raw = _controllers[field.key]!.text.trim();
      values[field.key] = raw.isEmpty
          ? null
          : (field.type == SectionFieldType.number ||
                field.type == SectionFieldType.currency)
          ? num.tryParse(raw.replaceAll(',', ''))
          : raw;
    }

    final provider = context.read<InstitutionProvider>();
    final ok = await provider.saveSectionRow(
      widget.table,
      values,
      rowId: widget.row?['id'] as String?,
    );

    if (!mounted) return;
    setState(() => _saving = false);

    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(provider.error ?? 'Could not save.'),
          backgroundColor: context.colors.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final heading = widget.row == null
        ? 'Add ${widget.title}'
        : 'Edit ${widget.title}';

    // PopScope routes the system back gesture and Android's back button
    // through the same check as the arrow.
    return PopScope(
      canPop: !_dirty && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _leave,
          ),
          centerTitle: true,
          title: Text(heading),
          actions: [
            // Save where iOS puts it on an edit screen: top right, as a word.
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _saving
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : TextButton(
                      onPressed: _save,
                      style: TextButton.styleFrom(
                        foregroundColor: colors.textPrimary,
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      child: const Text('Save'),
                    ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...widget.fields.map((field) {
                    if (field.type == SectionFieldType.choice) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: DropdownButtonFormField<String>(
                          initialValue: _choices[field.key],
                          decoration: InputDecoration(labelText: field.label),
                          items: [
                            DropdownMenuItem(
                              value: null,
                              child: Text(field.emptyLabel ?? 'Not specified'),
                            ),
                            ...field.options!.entries.map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _choices[field.key] = v),
                        ),
                      );
                    }

                    final isDate = field.type == SectionFieldType.date;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: CustomTextField(
                        controller: _controllers[field.key],
                        label: field.label,
                        hint: field.hint ?? (isDate ? 'Tap to choose' : null),
                        readOnly: isDate,
                        onTap: isDate ? () => _pickDate(field) : null,
                        maxLines: field.type == SectionFieldType.multiline
                            ? 4
                            : 1,
                        keyboardType: switch (field.type) {
                          SectionFieldType.number =>
                            const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          SectionFieldType.currency => TextInputType.number,
                          SectionFieldType.email => TextInputType.emailAddress,
                          _ => TextInputType.text,
                        },
                        inputFormatters: switch (field.type) {
                          SectionFieldType.number => [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.]'),
                            ),
                          ],
                          SectionFieldType.currency => const [
                            ThousandsSeparatorInputFormatter(
                              allowDecimal: true,
                            ),
                          ],
                          _ => null,
                        },
                        textCapitalization: field.type == SectionFieldType.email
                            ? TextCapitalization.none
                            : TextCapitalization.sentences,
                        validator: field.required
                            ? (v) => (v == null || v.trim().isEmpty)
                                  ? '${field.label} is required'
                                  : null
                            : null,
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
