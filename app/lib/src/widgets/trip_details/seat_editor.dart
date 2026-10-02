import 'package:flutter/material.dart';
import 'package:raillog/src/models/seat_selection.dart';
import 'package:raillog/src/models/ticket_seat_option.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

class SeatEditor extends StatelessWidget {
  const SeatEditor({
    super.key,
    required this.seatTypes,
    required this.seatType,
    required this.coachSeatType,
    required this.isExtraCarriage,
    required this.seatMode,
    required this.customSeatTypeController,
    required this.customSeatNumberController,
    required this.carriageNumber,
    required this.primarySeatNumber,
    required this.secondarySeatNumber,
    required this.secondarySeatNumbers,
    required this.onSeatTypeChanged,
    required this.onCoachSeatTypeChanged,
    required this.onExtraCarriageChanged,
    required this.onSeatModeChanged,
    required this.onCarriageChanged,
    required this.onPrimaryChanged,
    required this.onSecondaryChanged,
    this.onTicketSeatOptionChanged,
    this.ticketSeatOptions,
    this.noSeatOption,
    this.allowEmptyCustomSeat = false,
  });

  final List<String> seatTypes;
  final String seatType;

  /// 车体席别，非空即表示「车体席别代席别」。
  final String? coachSeatType;

  /// 加挂车厢，座位串的车厢段写成「加X车」。
  final bool isExtraCarriage;

  final String seatMode;
  final TextEditingController customSeatTypeController;
  final TextEditingController customSeatNumberController;
  final int? carriageNumber;
  final int primarySeatNumber;
  final String secondarySeatNumber;
  final List<String> secondarySeatNumbers;
  final ValueChanged<String> onSeatTypeChanged;
  final ValueChanged<String?> onCoachSeatTypeChanged;
  final ValueChanged<bool> onExtraCarriageChanged;
  final ValueChanged<String> onSeatModeChanged;
  final ValueChanged<int?> onCarriageChanged;
  final ValueChanged<int> onPrimaryChanged;
  final ValueChanged<String> onSecondaryChanged;
  final ValueChanged<TicketSeatOption>? onTicketSeatOptionChanged;
  final List<TicketSeatOption>? ticketSeatOptions;
  final TicketSeatOption? noSeatOption;
  final bool allowEmptyCustomSeat;

  bool get _showsSeatType => seatMode != '其它';
  bool get _isTicketRestricted => ticketSeatOptions != null;

  /// 落库用的完整席别串；12306 的票价选项也是这个粒度，比对时都得用它。
  String get _fullSeatType => composeSeatType(seatType, coachSeatType);

  bool get _ticketOptionDefinesBerth =>
      ticketSeatOptions?.any(
        (option) =>
            option.seatType == _fullSeatType &&
            option.berth != null &&
            option.berth == secondarySeatNumber,
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('入座方式', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          expandedInsets: EdgeInsets.zero,
          showSelectedIcon: false,
          segments: [
            if (!_isTicketRestricted || noSeatOption != null)
              const ButtonSegment(value: '无座', label: Text('无座')),
            const ButtonSegment(value: '不对号入座', label: Text('不对号')),
            const ButtonSegment(value: '席位', label: Text('席位')),
            if (!_isTicketRestricted)
              const ButtonSegment(value: '其它', label: Text('其它')),
          ],
          selected: {seatMode},
          onSelectionChanged: (selection) {
            if (selection.isNotEmpty) onSeatModeChanged(selection.first);
          },
        ),
        const SizedBox(height: 16),
        AnimatedSize(
          duration: m3MotionDuration,
          curve: Easing.standard,
          child: M3FadeThroughSwitcher(
            alignment: Alignment.topCenter,
            child: _buildSeatDetails(),
          ),
        ),
      ],
    );
  }

  Widget _buildSeatDetails() {
    if (seatMode == '其它') {
      return _CustomSeatFields(
        key: const ValueKey('custom-seat'),
        seatTypeController: customSeatTypeController,
        seatNumberController: customSeatNumberController,
        allowEmpty: allowEmptyCustomSeat,
      );
    }
    if (_isTicketRestricted && seatMode == '无座') {
      return Column(
        key: const ValueKey('fixed-no-seat'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _FixedTicketSeat(option: noSeatOption!),
          const SizedBox(height: 12),
          _SeatNumberFields(
            seatMode: seatMode,
            showSecondaryPosition: true,
            carriageNumber: carriageNumber,
            isExtraCarriage: isExtraCarriage,
            primarySeatNumber: primarySeatNumber,
            secondarySeatNumber: secondarySeatNumber,
            secondarySeatNumbers: secondarySeatNumbers,
            onCarriageChanged: onCarriageChanged,
            onExtraCarriageChanged: onExtraCarriageChanged,
            onPrimaryChanged: onPrimaryChanged,
            onSecondaryChanged: onSecondaryChanged,
          ),
        ],
      );
    }
    return Column(
      key: ValueKey('structured-seat-$seatMode'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_showsSeatType) ...[
          _buildSeatTypeDropdown(),
          const SizedBox(height: 12),
        ],
        _SeatNumberFields(
          seatMode: seatMode,
          showSecondaryPosition: !_ticketOptionDefinesBerth,
          carriageNumber: carriageNumber,
          isExtraCarriage: isExtraCarriage,
          primarySeatNumber: primarySeatNumber,
          secondarySeatNumber: secondarySeatNumber,
          secondarySeatNumbers: secondarySeatNumbers,
          onCarriageChanged: onCarriageChanged,
          onExtraCarriageChanged: onExtraCarriageChanged,
          onPrimaryChanged: onPrimaryChanged,
          onSecondaryChanged: onSecondaryChanged,
        ),
      ],
    );
  }

  Widget _buildSeatTypeDropdown() {
    final pricedOptions = ticketSeatOptions;
    if (pricedOptions != null) {
      return _TicketSeatOptionList(
        options: pricedOptions,
        selectedSeatType: _fullSeatType,
        selectedSecondaryNumber: secondarySeatNumber,
        onChanged: (option) {
          final ticketCallback = onTicketSeatOptionChanged;
          if (ticketCallback != null) {
            ticketCallback(option);
            return;
          }
          onSeatTypeChanged(option.seatType);
          if (option.berth != null) onSecondaryChanged(option.berth!);
        },
      );
    }
    // 票面席别受限时席别由票价列表说了算，代用记法在列表里已经自带，不再单给勾选框。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: seatType,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '席别',
                  prefixIcon: Icon(Icons.airline_seat_recline_normal_outlined),
                ),
                items: seatTypes
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) onSeatTypeChanged(value);
                },
              ),
            ),
            _RowCheckbox(
              label: '代',
              value: coachSeatType != null,
              onChanged: (checked) => onCoachSeatTypeChanged(
                checked ? _defaultCoachSeatType() : null,
              ),
            ),
          ],
        ),
        if (coachSeatType != null) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: coachSeatType,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: '车体席别',
              prefixIcon: Icon(Icons.swap_horiz_outlined),
            ),
            items: seatTypes
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) onCoachSeatTypeChanged(value);
            },
          ),
        ],
      ],
    );
  }

  /// 勾上「代」时先选一个和当前席别不同的车体席别，免得一上来就是「硬座代硬座」。
  String _defaultCoachSeatType() => seatTypes.firstWhere(
    (value) => value != seatType,
    orElse: () => seatTypes.first,
  );
}

/// 跟在下拉右边的小勾选框：勾选框自带 48 的点击区，这里压紧到能塞进一个单元格。
class _RowCheckbox extends StatelessWidget {
  const _RowCheckbox({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Checkbox(
          value: value,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: enabled ? (checked) => onChanged(checked ?? false) : null,
        ),
        Text(label, style: Theme.of(context).textTheme.labelLarge),
      ],
    );
  }
}

class _TicketSeatOptionList extends StatelessWidget {
  const _TicketSeatOptionList({
    required this.options,
    required this.selectedSeatType,
    required this.selectedSecondaryNumber,
    required this.onChanged,
  });

  final List<TicketSeatOption> options;
  final String selectedSeatType;
  final String selectedSecondaryNumber;
  final ValueChanged<TicketSeatOption> onChanged;

  @override
  Widget build(BuildContext context) {
    final groups = _groupTicketSeatOptions(options);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('座位信息', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        for (var index = 0; index < groups.length; index++) ...[
          _TicketSeatGroupCard(
            group: groups[index],
            selectedSeatType: selectedSeatType,
            selectedSecondaryNumber: selectedSecondaryNumber,
            onChanged: onChanged,
          ),
          if (index != groups.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _TicketSeatGroupCard extends StatelessWidget {
  const _TicketSeatGroupCard({
    required this.group,
    required this.selectedSeatType,
    required this.selectedSecondaryNumber,
    required this.onChanged,
  });

  final _TicketSeatGroup group;
  final String selectedSeatType;
  final String selectedSecondaryNumber;
  final ValueChanged<TicketSeatOption> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = group.options.any(
      (option) =>
          _isSelectedOption(option, selectedSeatType, selectedSecondaryNumber),
    );
    if (!group.isBerthGroup) {
      final option = group.options.single;
      return AppCard.filled(
        color: selected
            ? colors.secondaryContainer
            : colors.surfaceContainerHigh,
        padding: EdgeInsets.zero,
        onTap: () => onChanged(option),
        child: ListTile(
          leading: Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            color: selected ? colors.primary : colors.onSurfaceVariant,
          ),
          title: Text(option.seatType),
          trailing: Text(
            _formatTicketPrice(option.price),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    }

    return AppCard.filled(
      color: selected ? colors.secondaryContainer : colors.surfaceContainerHigh,
      leading: Icon(
        selected ? Icons.check_circle : Icons.bed_outlined,
        color: selected ? colors.primary : colors.onSurfaceVariant,
      ),
      title: group.name,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: group.options.map((option) {
          final berth = option.berth!;
          return ChoiceChip(
            selected: _isSelectedOption(
              option,
              selectedSeatType,
              selectedSecondaryNumber,
            ),
            onSelected: (_) => onChanged(option),
            label: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(berth),
                Text(
                  _formatTicketPrice(option.price),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TicketSeatGroup {
  const _TicketSeatGroup({
    required this.name,
    required this.options,
    required this.isBerthGroup,
  });

  final String name;
  final List<TicketSeatOption> options;
  final bool isBerthGroup;
}

List<_TicketSeatGroup> _groupTicketSeatOptions(List<TicketSeatOption> options) {
  final groups = <String, List<TicketSeatOption>>{};
  final berthGroups = <String>{};
  for (final option in options) {
    final key = option.seatType;
    groups.putIfAbsent(key, () => []).add(option);
    if (option.berth != null) berthGroups.add(key);
  }
  const berthOrder = {'上铺': 0, '中铺': 1, '下铺': 2};
  return groups.entries.map((entry) {
    final values = entry.value;
    if (berthGroups.contains(entry.key)) {
      values.sort((first, second) {
        final firstBerth = first.berth!;
        final secondBerth = second.berth!;
        return berthOrder[firstBerth]!.compareTo(berthOrder[secondBerth]!);
      });
    }
    return _TicketSeatGroup(
      name: entry.key,
      options: values,
      isBerthGroup: berthGroups.contains(entry.key),
    );
  }).toList();
}

bool _isSelectedOption(
  TicketSeatOption option,
  String selectedSeatType,
  String selectedSecondaryNumber,
) {
  return option.seatType == selectedSeatType &&
      (option.berth == null || option.berth == selectedSecondaryNumber);
}

class _FixedTicketSeat extends StatelessWidget {
  const _FixedTicketSeat({required this.option});

  final TicketSeatOption option;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: '席别',
        prefixIcon: Icon(Icons.airline_seat_recline_normal_outlined),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 12,
        runSpacing: 4,
        children: [
          Text(option.seatType),
          Text(_formatTicketPrice(option.price)),
        ],
      ),
    );
  }
}

class _CustomSeatFields extends StatelessWidget {
  const _CustomSeatFields({
    super.key,
    required this.seatTypeController,
    required this.seatNumberController,
    required this.allowEmpty,
  });

  final TextEditingController seatTypeController;
  final TextEditingController seatNumberController;
  final bool allowEmpty;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final width = constraints.maxWidth >= 520
            ? (constraints.maxWidth - gap) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(
              width: width,
              child: TextFormField(
                controller: seatTypeController,
                decoration: const InputDecoration(labelText: '自定义席别'),
                validator: (value) {
                  if (allowEmpty &&
                      (value?.trim().isEmpty ?? true) &&
                      seatNumberController.text.trim().isEmpty) {
                    return null;
                  }
                  return value == null || value.trim().isEmpty ? '请输入席别' : null;
                },
              ),
            ),
            SizedBox(
              width: width,
              child: TextFormField(
                controller: seatNumberController,
                decoration: const InputDecoration(labelText: '自定义座位'),
                validator: (value) {
                  if (allowEmpty &&
                      (value?.trim().isEmpty ?? true) &&
                      seatTypeController.text.trim().isEmpty) {
                    return null;
                  }
                  return value == null || value.trim().isEmpty ? '请输入座位' : null;
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SeatNumberFields extends StatelessWidget {
  const _SeatNumberFields({
    required this.seatMode,
    required this.showSecondaryPosition,
    required this.carriageNumber,
    required this.isExtraCarriage,
    required this.primarySeatNumber,
    required this.secondarySeatNumber,
    required this.secondarySeatNumbers,
    required this.onCarriageChanged,
    required this.onExtraCarriageChanged,
    required this.onPrimaryChanged,
    required this.onSecondaryChanged,
  });

  final String seatMode;
  final bool showSecondaryPosition;
  final int? carriageNumber;
  final bool isExtraCarriage;
  final int primarySeatNumber;
  final String secondarySeatNumber;
  final List<String> secondarySeatNumbers;
  final ValueChanged<int?> onCarriageChanged;
  final ValueChanged<bool> onExtraCarriageChanged;
  final ValueChanged<int> onPrimaryChanged;
  final ValueChanged<String> onSecondaryChanged;

  @override
  Widget build(BuildContext context) {
    final showsSecondaryPosition =
        showSecondaryPosition && primarySeatNumber != SeatOptions.unknownNumber;
    final carriageValues = {
      ...SeatOptions.carriageNumbers,
      ?carriageNumber,
    }.toList()..sort();
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final compact = constraints.maxWidth < 520;
        final halfWidth = (constraints.maxWidth - gap) / 2;
        final thirdWidth = (constraints.maxWidth - gap * 2) / 3;
        final carriageWidth = seatMode == '席位' && !showsSecondaryPosition
            ? halfWidth
            : seatMode == '席位' && compact
            ? constraints.maxWidth
            : seatMode == '席位'
            ? thirdWidth
            : constraints.maxWidth;
        final seatWidth = !showsSecondaryPosition
            ? halfWidth
            : compact
            ? halfWidth
            : thirdWidth;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(
              width: carriageWidth,
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: carriageNumber ?? 1,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '车厢'),
                      items: carriageValues
                          .map(
                            (value) => DropdownMenuItem<int>(
                              value: value,
                              child: Text(
                                value == SeatOptions.unknownNumber
                                    ? '未知'
                                    : '$value',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        onCarriageChanged(value);
                        // 车厢未知时「加X车」没有意义，顺手把加车也取消掉。
                        if (value == SeatOptions.unknownNumber) {
                          onExtraCarriageChanged(false);
                        }
                      },
                    ),
                  ),
                  _RowCheckbox(
                    label: '加',
                    value: isExtraCarriage,
                    enabled:
                        carriageNumber != null &&
                        carriageNumber != SeatOptions.unknownNumber,
                    onChanged: onExtraCarriageChanged,
                  ),
                ],
              ),
            ),
            if (seatMode == '席位') ...[
              SizedBox(
                width: seatWidth,
                child: DropdownButtonFormField<int>(
                  initialValue: primarySeatNumber,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: '号码'),
                  items:
                      [
                            SeatOptions.unknownNumber,
                            ...List<int>.generate(128, (index) => index + 1),
                          ]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(
                                value == SeatOptions.unknownNumber
                                    ? '未知'
                                    : '$value',
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: (value) {
                    if (value != null) onPrimaryChanged(value);
                  },
                ),
              ),
              if (showsSecondaryPosition)
                SizedBox(
                  width: seatWidth,
                  child: DropdownButtonFormField<String>(
                    initialValue: secondarySeatNumber,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '位置'),
                    items: secondarySeatNumbers
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value == '无' ? '无后缀' : value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) onSecondaryChanged(value);
                    },
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

String _formatTicketPrice(double price) {
  final value = price == price.roundToDouble()
      ? price.toInt().toString()
      : price.toStringAsFixed(1);
  return '¥$value';
}
