import 'package:flutter/material.dart';
import 'package:raillog/src/models/seat_selection.dart';
import 'package:raillog/src/models/ticket_seat_option.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

class SeatEditor extends StatelessWidget {
  const SeatEditor({
    super.key,
    required this.seatTypes,
    required this.seatType,
    required this.seatMode,
    required this.customSeatTypeController,
    required this.customSeatNumberController,
    required this.carriageNumber,
    required this.primarySeatNumber,
    required this.secondarySeatNumber,
    required this.secondarySeatNumbers,
    required this.onSeatTypeChanged,
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
  final String seatMode;
  final TextEditingController customSeatTypeController;
  final TextEditingController customSeatNumberController;
  final int? carriageNumber;
  final int primarySeatNumber;
  final String secondarySeatNumber;
  final List<String> secondarySeatNumbers;
  final ValueChanged<String> onSeatTypeChanged;
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
  bool get _ticketOptionDefinesBerth =>
      ticketSeatOptions?.any(
        (option) =>
            option.seatType == seatType &&
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
          curve: Curves.easeOutCubic,
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
            primarySeatNumber: primarySeatNumber,
            secondarySeatNumber: secondarySeatNumber,
            secondarySeatNumbers: secondarySeatNumbers,
            onCarriageChanged: onCarriageChanged,
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
          primarySeatNumber: primarySeatNumber,
          secondarySeatNumber: secondarySeatNumber,
          secondarySeatNumbers: secondarySeatNumbers,
          onCarriageChanged: onCarriageChanged,
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
        selectedSeatType: seatType,
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
    return DropdownButtonFormField<String>(
      initialValue: seatType,
      decoration: const InputDecoration(
        labelText: '席别',
        prefixIcon: Icon(Icons.airline_seat_recline_normal_outlined),
      ),
      items: seatTypes
          .map((value) => DropdownMenuItem(value: value, child: Text(value)))
          .toList(),
      onChanged: (value) {
        if (value != null) onSeatTypeChanged(value);
      },
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
        Text('席别与票价', style: Theme.of(context).textTheme.labelLarge),
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
      return Material(
        color: selected
            ? colors.secondaryContainer
            : colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () => onChanged(option),
          leading: Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            color: selected ? colors.primary : colors.onSurfaceVariant,
          ),
          title: Text(option.seatType),
          trailing: Text(
            _formatTicketPrice(option.price),
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      );
    }

    return Material(
      color: selected ? colors.secondaryContainer : colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  selected ? Icons.check_circle : Icons.bed_outlined,
                  color: selected ? colors.primary : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  group.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
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
          ],
        ),
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
    required this.primarySeatNumber,
    required this.secondarySeatNumber,
    required this.secondarySeatNumbers,
    required this.onCarriageChanged,
    required this.onPrimaryChanged,
    required this.onSecondaryChanged,
  });

  final String seatMode;
  final bool showSecondaryPosition;
  final int? carriageNumber;
  final int primarySeatNumber;
  final String secondarySeatNumber;
  final List<String> secondarySeatNumbers;
  final ValueChanged<int?> onCarriageChanged;
  final ValueChanged<int> onPrimaryChanged;
  final ValueChanged<String> onSecondaryChanged;

  @override
  Widget build(BuildContext context) {
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
        final carriageWidth = seatMode == '席位' && !showSecondaryPosition
            ? halfWidth
            : seatMode == '席位' && compact
            ? constraints.maxWidth
            : seatMode == '席位'
            ? thirdWidth
            : constraints.maxWidth;
        final seatWidth = !showSecondaryPosition
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
              child: DropdownButtonFormField<int>(
                initialValue: carriageNumber ?? 1,
                decoration: const InputDecoration(labelText: '车厢'),
                items: carriageValues
                    .map(
                      (value) => DropdownMenuItem<int>(
                        value: value,
                        child: Text('$value'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    onCarriageChanged(value);
                  }
                },
              ),
            ),
            if (seatMode == '席位') ...[
              SizedBox(
                width: seatWidth,
                child: DropdownButtonFormField<int>(
                  initialValue: primarySeatNumber,
                  decoration: const InputDecoration(labelText: '号码'),
                  items: List<int>.generate(128, (index) => index + 1)
                      .map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text('$value'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onPrimaryChanged(value);
                  },
                ),
              ),
              if (showSecondaryPosition)
                SizedBox(
                  width: seatWidth,
                  child: DropdownButtonFormField<String>(
                    initialValue: secondarySeatNumber,
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
