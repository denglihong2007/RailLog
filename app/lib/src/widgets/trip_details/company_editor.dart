import 'package:flutter/material.dart';
import 'package:raillog/src/models/railway_bureau.dart';

export 'package:raillog/src/models/railway_bureau.dart'
    show railwayBureauSegments;

const _otherBureau = '其它';

class CompanySelection {
  const CompanySelection({required this.bureau, required this.segment});

  final String bureau;
  final String segment;
}

CompanySelection? matchCompanySelection(String value) {
  value = normalizeCompanyValue(value);
  if (value.isEmpty) return null;
  for (final entry in railwayBureauSegments.entries) {
    for (final segment in entry.value) {
      if (segment == value) {
        return CompanySelection(bureau: entry.key, segment: segment);
      }
    }
  }
  return CompanySelection(bureau: _otherBureau, segment: value.trim());
}

String normalizeCompanyValue(String value) {
  final trimmed = value.trim();
  return trimmed == '暂无' ? '' : trimmed;
}

class CompanyEditor extends StatefulWidget {
  const CompanyEditor({super.key, required this.controller});

  final TextEditingController controller;

  @override
  State<CompanyEditor> createState() => _CompanyEditorState();
}

class _CompanyEditorState extends State<CompanyEditor> {
  String? _bureau;
  String? _segment;
  bool _writingController = false;

  @override
  void initState() {
    super.initState();
    _applyControllerValue();
    widget.controller.addListener(_controllerChanged);
  }

  @override
  void didUpdateWidget(covariant CompanyEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_controllerChanged);
    _applyControllerValue();
    widget.controller.addListener(_controllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_controllerChanged);
    super.dispose();
  }

  void _controllerChanged() {
    if (_writingController) return;
    final value = normalizeCompanyValue(widget.controller.text);
    if (value != widget.controller.text) _write(value);
    final selection = matchCompanySelection(value);
    final bureau = selection?.bureau;
    final segment = selection?.segment;
    if (bureau == _bureau && segment == _segment) return;
    setState(() {
      _bureau = bureau;
      _segment = segment;
    });
  }

  void _applyControllerValue() {
    final value = normalizeCompanyValue(widget.controller.text);
    if (value != widget.controller.text) _write(value);
    final selection = matchCompanySelection(value);
    _bureau = selection?.bureau;
    _segment = selection?.segment;
  }

  void _write(String value) {
    _writingController = true;
    widget.controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
    _writingController = false;
  }

  @override
  Widget build(BuildContext context) {
    final segments = _bureau == null || _bureau == _otherBureau
        ? const <String>[]
        : railwayBureauSegments[_bureau] ?? const <String>[];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('bureau-${_bureau ?? ''}'),
          initialValue: _bureau,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: '路局',
            prefixIcon: Icon(Icons.account_balance_outlined),
          ),
          hint: const Text('请选择'),
          items: [
            ...railwayBureauSegments.keys.map(
              (bureau) => DropdownMenuItem(value: bureau, child: Text(bureau)),
            ),
            const DropdownMenuItem(
              value: _otherBureau,
              child: Text(_otherBureau),
            ),
          ],
          onChanged: (value) {
            setState(() {
              _bureau = value;
              _segment = null;
            });
            _write('');
          },
        ),
        const SizedBox(height: 12),
        if (_bureau == _otherBureau)
          TextFormField(
            controller: widget.controller,
            decoration: const InputDecoration(
              labelText: '客运段',
              prefixIcon: Icon(Icons.business_outlined),
            ),
          )
        else
          DropdownButtonFormField<String>(
            key: ValueKey('segment-${_bureau ?? ''}-${_segment ?? ''}'),
            initialValue: segments.contains(_segment) ? _segment : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '客运段',
              prefixIcon: Icon(Icons.business_outlined),
            ),
            hint: Text(_bureau == null ? '请先选择路局' : '请选择'),
            items: segments
                .map(
                  (segment) =>
                      DropdownMenuItem(value: segment, child: Text(segment)),
                )
                .toList(growable: false),
            onChanged: _bureau == null
                ? null
                : (value) {
                    setState(() => _segment = value);
                    _write(value ?? '');
                  },
          ),
      ],
    );
  }
}
