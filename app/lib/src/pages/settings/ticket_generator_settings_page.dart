import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:raillog/src/services/ticket_generator_settings.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/help_dialog.dart';
import 'package:raillog/src/widgets/settings/settings_section.dart';
import 'package:raillog/src/widgets/settings/settings_sub_page.dart';

class TicketGeneratorSettingsPage extends StatefulWidget {
  const TicketGeneratorSettingsPage({super.key});

  @override
  State<TicketGeneratorSettingsPage> createState() =>
      _TicketGeneratorSettingsPageState();
}

class _TicketGeneratorSettingsPageState
    extends State<TicketGeneratorSettingsPage> {
  /// 输入过程中不逐字落盘：停顿这么久、或输入框失焦时才写入。
  static const _saveDebounceDuration = Duration(milliseconds: 500);

  late final TextEditingController _passengerController;
  late final TextEditingController _maskedIdController;
  late final TextEditingController _serialPrefixController;
  late final List<FocusNode> _focusNodes;
  Timer? _saveDebounce;

  @override
  void initState() {
    super.initState();
    final settings = TicketGeneratorSettings.instance;
    _passengerController = TextEditingController(text: settings.passenger);
    _maskedIdController = TextEditingController(text: settings.maskedId);
    _serialPrefixController = TextEditingController(
      text: settings.serialPrefix,
    );
    _focusNodes = [
      for (var index = 0; index < 3; index++)
        FocusNode()..addListener(_flushWhenUnfocused),
    ];
  }

  @override
  void dispose() {
    // 防抖窗口内直接返回时补写一次，避免丢掉最后一次输入；推迟到本帧结束，
    // 免得在销毁过程中触发监听者重建。
    if (_saveDebounce?.isActive ?? false) {
      final passenger = _passengerController.text;
      final maskedId = _maskedIdController.text;
      final serialPrefix = _serialPrefixController.text;
      scheduleMicrotask(() {
        final settings = TicketGeneratorSettings.instance;
        unawaited(settings.setPassenger(passenger));
        unawaited(settings.setMaskedId(maskedId));
        unawaited(settings.setSerialPrefix(serialPrefix));
      });
    }
    _saveDebounce?.cancel();
    for (final node in _focusNodes) {
      node.dispose();
    }
    _passengerController.dispose();
    _maskedIdController.dispose();
    _serialPrefixController.dispose();
    super.dispose();
  }

  void _flushWhenUnfocused() {
    if (_focusNodes.any((node) => node.hasFocus)) return;
    _flush();
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(_saveDebounceDuration, _flush);
  }

  void _flush() {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    // 下面三个 setter 各自在值没变或格式不合法时提前返回，所以整组一起写是安全的。
    final settings = TicketGeneratorSettings.instance;
    unawaited(settings.setPassenger(_passengerController.text));
    unawaited(settings.setMaskedId(_maskedIdController.text));
    unawaited(settings.setSerialPrefix(_serialPrefixController.text));
  }

  Future<void> _showSerialNumberHelp(BuildContext context) => showHelpDialog(
    context,
    title: '铁路磁票票号说明',
    message:
        '铁路磁票（报销凭证）的21位票号由以下五部分顺序构成：\n\n'
        '• 前5位：数字格式的车站TMIS码（可前往 rail.re 查询具体车站）；\n'
        '• 第6至7位：出票机器类型（00-09为人工售票窗口，20-29为车票代售点，30-39为自动售票机）；\n'
        '• 第8至10位：3位数字的出票机器编号；\n'
        '• 第11至14位：MMDD格式的4位结算日期（一般为打印日期的下一天，'
        '即行程录入时间的次日，由软件自动生成而无需设置）；\n'
        '• 最后7位：票纸编号（通常由1位字母和6位数字组合而成，由软件自动生成而无需设置）。',
  );

  @override
  Widget build(BuildContext context) {
    return SettingsSubPage(
      title: '火车票生成器',
      children: [
        AnimatedBuilder(
          animation: TicketGeneratorSettings.instance,
          builder: (context, _) {
            final settings = TicketGeneratorSettings.instance;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsCard(
                  title: '展示样式',
                  icon: Icons.confirmation_number_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SegmentedButton<TicketDisplayStyle>(
                        segments: const [
                          ButtonSegment(
                            value: TicketDisplayStyle.red,
                            icon: Icon(Icons.confirmation_number_outlined),
                            label: Text('红票'),
                          ),
                          ButtonSegment(
                            value: TicketDisplayStyle.blue,
                            icon: Icon(Icons.airplane_ticket_outlined),
                            label: Text('蓝票'),
                          ),
                          ButtonSegment(
                            value: TicketDisplayStyle.md3,
                            icon: Icon(Icons.view_agenda_outlined),
                            label: Text('MD3'),
                          ),
                        ],
                        selected: {settings.displayStyle},
                        showSelectedIcon: false,
                        onSelectionChanged: (selection) =>
                            settings.setDisplayStyle(selection.single),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.ac_unit_outlined),
                        title: const Text('普速显示“新空调”'),
                        subtitle: const Text('硬座、硬卧、软座和软卧等席别自动添加前缀'),
                        value: settings.showNewAirConditioned,
                        onChanged: settings.setShowNewAirConditioned,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SettingsCard(
                  title: '默认票面信息',
                  icon: Icons.badge_outlined,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _passengerController,
                        focusNode: _focusNodes[0],
                        decoration: const InputDecoration(
                          labelText: '默认乘车人',
                          prefixIcon: Icon(Icons.person_outline),
                          border: OutlineInputBorder(),
                        ),
                        maxLength: 30,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => _scheduleSave(),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        controller: _maskedIdController,
                        focusNode: _focusNodes[1],
                        decoration: const InputDecoration(
                          labelText: '脱敏身份证号码',
                          prefixIcon: Icon(Icons.badge_outlined),
                          border: OutlineInputBorder(),
                        ),
                        maxLength: 30,
                        textInputAction: TextInputAction.next,
                        onChanged: (_) => _scheduleSave(),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextFormField(
                        controller: _serialPrefixController,
                        focusNode: _focusNodes[2],
                        decoration: InputDecoration(
                          labelText: '票号前缀',
                          helperText: '21 位票号的前 10 位',
                          prefixIcon: const Icon(Icons.numbers_outlined),
                          suffixIcon: IconButton(
                            tooltip: '票号构成说明',
                            onPressed: () => _showSerialNumberHelp(context),
                            icon: const Icon(Icons.help_outline),
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        maxLength: 10,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) => _scheduleSave(),
                        validator: (value) =>
                            RegExp(r'^\d{10}$').hasMatch(value ?? '')
                            ? null
                            : '请输入 10 位数字',
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
