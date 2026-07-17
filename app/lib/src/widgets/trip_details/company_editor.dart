import 'package:flutter/material.dart';

const railwayBureauSegments = <String, List<String>>{
  '哈尔滨局': ['哈局哈尔滨段', '哈局牡丹江段', '哈局齐齐哈尔段'],
  '呼和浩特局': ['呼和局包头段', '集通公司呼和段'],
  '郑州局': ['郑州局郑州段'],
  '南昌局': ['南昌局南昌段', '南昌局福州段'],
  '上海局': ['上局上海段', '上局南京段', '上局杭州段', '上局合肥段', '合九公司', '金温公司'],
  '兰州局': ['兰州局兰州段', '兰州局银川段'],
  '济南局': ['济南局济南段', '济南局青岛段', '济南局威海地铁'],
  '昆明局': ['昆明局昆明段', '昆明局万象段', '老中铁路公司'],
  '武汉局': ['武汉局武汉段', '武汉局襄阳段'],
  '青藏公司': ['青藏公司西宁段'],
  '北京局': ['京局北京客运段', '京局天津客运段', '京局石家庄客运段', '北京局承德车务段'],
  '广铁集团': ['广铁广九段', '广铁广州段', '广铁长沙段', '广东城际公司', '广州局海口车务段', '广州局长沙车辆段'],
  '乌鲁木齐局': ['乌局乌鲁木齐段', '乌局库尔勒段'],
  '沈阳局': ['沈局长春段', '沈局大连段', '沈局吉林段', '沈局锦州段', '沈局沈阳段'],
  '太原局': ['太原局太原客运段'],
  '成都局': ['成都局成都客运段', '成都局贵阳客运段', '成都局重庆客运段'],
  '香港铁路公司': ['港铁公司'],
  '西安局': ['西安局西安段'],
  '南宁局': ['南宁局南宁客运段', '广西沿海铁路公司'],
};

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
