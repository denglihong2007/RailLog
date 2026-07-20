import 'package:flutter/material.dart';
import 'package:raillog/src/models/seat_selection.dart';
import 'package:raillog/src/models/ticket_seat_option.dart';
import 'package:raillog/src/widgets/trip_details/form_section.dart';
import 'package:raillog/src/widgets/trip_details/seat_editor.dart';

String? nullableTripText(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

String formatTripNumber(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(1);

class TripSeatFormValue {
  const TripSeatFormValue({
    required this.seatType,
    required this.seatMode,
    required this.carriageNumber,
    required this.primarySeatNumber,
    required this.secondarySeatNumber,
    required this.customSeatType,
    required this.customSeatNumber,
  });

  final String seatType;
  final String seatMode;
  final int? carriageNumber;
  final int primarySeatNumber;
  final String secondarySeatNumber;
  final String customSeatType;
  final String customSeatNumber;
}

TripSeatFormValue parseTripSeat(String? storedType, String? storedNumber) {
  final originalType = storedType?.trim() ?? '';
  final seatNumber = storedNumber?.trim() ?? '';
  final berthMatch = RegExp(r'^(.*?)(上铺|中铺|下铺)$').firstMatch(originalType);
  final seatType = berthMatch?.group(1) ?? originalType;
  final legacyBerth = berthMatch?.group(2);
  final carriageMatch = RegExp(
    r'^(?:(不指定车厢)|(\d+)车)(.*)$',
  ).firstMatch(seatNumber);
  final carriage = carriageMatch?.group(1) != null
      ? null
      : int.tryParse(carriageMatch?.group(2) ?? '');
  final remaining = carriageMatch?.group(3) ?? '';
  final normalizedType = SeatOptions.types.contains(seatType)
      ? seatType
      : '二等座';

  if (carriageMatch != null && (remaining == '无座' || remaining == '不对号入座')) {
    return TripSeatFormValue(
      seatType: normalizedType,
      seatMode: remaining,
      carriageNumber: carriage ?? 1,
      primarySeatNumber: 1,
      secondarySeatNumber: '无',
      customSeatType: '',
      customSeatNumber: '',
    );
  }
  final seatMatch = RegExp(
    r'^(\d{1,3})(?:号)?(A|B|C|D|F|上铺|中铺|下铺)?(?:号)?$',
  ).firstMatch(remaining);
  final primary = int.tryParse(seatMatch?.group(1) ?? '');
  if (carriageMatch != null &&
      seatMatch != null &&
      SeatOptions.types.contains(seatType) &&
      primary != null &&
      primary >= 1 &&
      primary <= 128) {
    return TripSeatFormValue(
      seatType: seatType,
      seatMode: '席位',
      carriageNumber: carriage ?? 1,
      primarySeatNumber: primary,
      secondarySeatNumber: seatMatch.group(2) ?? legacyBerth ?? '无',
      customSeatType: '',
      customSeatNumber: '',
    );
  }
  return TripSeatFormValue(
    seatType: '二等座',
    seatMode: '其它',
    carriageNumber: 1,
    primarySeatNumber: 1,
    secondarySeatNumber: '无',
    customSeatType: originalType,
    customSeatNumber: seatNumber,
  );
}

class TripFormShell extends StatelessWidget {
  const TripFormShell({
    super.key,
    required this.formKey,
    required this.padding,
    required this.children,
  });

  final GlobalKey<FormState> formKey;
  final EdgeInsetsGeometry padding;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: colors.surfaceContainerHighest,
          border: const OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      ),
      child: Form(
        key: formKey,
        child: FormPageScrollView(padding: padding, children: children),
      ),
    );
  }
}

class TripPropertiesSection extends StatelessWidget {
  const TripPropertiesSection({
    super.key,
    required this.isRailTrip,
    required this.isLocalOnly,
    required this.isEditing,
    required this.enabled,
    required this.onRailTripChanged,
    required this.onLocalOnlyChanged,
    this.showRailTrip = true,
  });

  final bool isRailTrip;
  final bool isLocalOnly;
  final bool isEditing;
  final bool enabled;
  final ValueChanged<bool> onRailTripChanged;
  final ValueChanged<bool> onLocalOnlyChanged;
  final bool showRailTrip;

  @override
  Widget build(BuildContext context) => FormSection(
    icon: Icons.tune_outlined,
    title: '行程属性',
    child: Column(
      children: [
        if (showRailTrip) ...[
          _SwitchTile(
            title: '铁路行程',
            value: isRailTrip,
            enabled: enabled,
            onChanged: onRailTripChanged,
          ),
          const Divider(height: 1),
        ],
        _SwitchTile(
          title: isEditing ? '云端行程' : '本地行程',
          value: isEditing ? !isLocalOnly : isLocalOnly,
          enabled: enabled,
          onChanged: (value) => onLocalOnlyChanged(isEditing ? !value : value),
        ),
      ],
    ),
  );
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.title,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: value,
      onChanged: enabled ? onChanged : null,
    ),
  );
}

class TripNotesSection extends StatelessWidget {
  const TripNotesSection({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => FormSection(
    icon: Icons.notes_outlined,
    title: '备注',
    child: TextFormField(
      controller: controller,
      minLines: 3,
      maxLines: 6,
      decoration: const InputDecoration(hintText: '记录这趟旅程的其它信息'),
    ),
  );
}

class TripNumberField extends StatelessWidget {
  const TripNumberField({
    super.key,
    required this.controller,
    required this.label,
    required this.suffix,
    required this.icon,
    this.onCalculate,
    this.helperText,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final IconData icon;
  final VoidCallback? onCalculate;
  final String? helperText;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixText: suffix,
      helperText: helperText,
      suffixIcon: onCalculate == null
          ? null
          : IconButton(
              tooltip: '按经由线路计算总里程',
              onPressed: onCalculate,
              icon: const Icon(Icons.calculate_outlined),
            ),
    ),
    validator: (value) {
      if (value == null || value.trim().isEmpty) return null;
      final number = double.tryParse(value.trim());
      return number == null || number < 0 ? '请输入有效$label' : null;
    },
  );
}

class TripPriceField extends StatelessWidget {
  const TripPriceField({super.key, required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) => TripNumberField(
    controller: controller,
    label: '票价',
    suffix: '元',
    icon: Icons.payments_outlined,
  );
}

class TripSeatSection extends StatelessWidget {
  const TripSeatSection({
    super.key,
    required this.seatType,
    required this.seatMode,
    required this.customSeatTypeController,
    required this.customSeatNumberController,
    required this.carriageNumber,
    required this.primarySeatNumber,
    required this.secondarySeatNumber,
    required this.onSeatTypeChanged,
    required this.onSeatModeChanged,
    required this.onCarriageChanged,
    required this.onPrimaryChanged,
    required this.onSecondaryChanged,
    this.onTicketSeatOptionChanged,
    this.ticketSeatOptions,
    this.noSeatOption,
    this.allowEmptyCustomSeat = false,
    this.lookupFailed = false,
  });

  final String seatType;
  final String seatMode;
  final TextEditingController customSeatTypeController;
  final TextEditingController customSeatNumberController;
  final int? carriageNumber;
  final int primarySeatNumber;
  final String secondarySeatNumber;
  final ValueChanged<String> onSeatTypeChanged;
  final ValueChanged<String> onSeatModeChanged;
  final ValueChanged<int?> onCarriageChanged;
  final ValueChanged<int> onPrimaryChanged;
  final ValueChanged<String> onSecondaryChanged;
  final ValueChanged<TicketSeatOption>? onTicketSeatOptionChanged;
  final List<TicketSeatOption>? ticketSeatOptions;
  final TicketSeatOption? noSeatOption;
  final bool allowEmptyCustomSeat;
  final bool lookupFailed;

  @override
  Widget build(BuildContext context) => FormSection(
    icon: Icons.event_seat_outlined,
    title: '座位信息',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SeatEditor(
          seatTypes: SeatOptions.types,
          seatType: seatType,
          seatMode: seatMode,
          customSeatTypeController: customSeatTypeController,
          customSeatNumberController: customSeatNumberController,
          carriageNumber: carriageNumber,
          primarySeatNumber: primarySeatNumber,
          secondarySeatNumber: secondarySeatNumber,
          secondarySeatNumbers: SeatOptions.secondaryNumbers,
          onSeatTypeChanged: onSeatTypeChanged,
          onSeatModeChanged: onSeatModeChanged,
          onCarriageChanged: onCarriageChanged,
          onPrimaryChanged: onPrimaryChanged,
          onSecondaryChanged: onSecondaryChanged,
          onTicketSeatOptionChanged: onTicketSeatOptionChanged,
          ticketSeatOptions: ticketSeatOptions,
          noSeatOption: noSeatOption,
          allowEmptyCustomSeat: allowEmptyCustomSeat,
        ),
        if (lookupFailed) ...[
          const SizedBox(height: 8),
          Text(
            '未获取到当前区间的席别与票价',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    ),
  );
}
