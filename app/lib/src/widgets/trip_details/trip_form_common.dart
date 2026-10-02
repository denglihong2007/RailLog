import 'package:flutter/material.dart';
import 'package:raillog/src/models/seat_selection.dart';
import 'package:raillog/src/models/ticket_seat_option.dart';
import 'package:raillog/src/theme/app_theme.dart';
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
    required this.coachSeatType,
    required this.isExtraCarriage,
    required this.seatMode,
    required this.carriageNumber,
    required this.primarySeatNumber,
    required this.secondarySeatNumber,
    required this.customSeatType,
    required this.customSeatNumber,
  });

  final String seatType;

  /// 车体席别，非空表示这张票是「车体席别代席别」。
  final String? coachSeatType;

  /// 加挂车厢，座位串的车厢段写成「加X车」。
  final bool isExtraCarriage;

  final String seatMode;
  final int? carriageNumber;
  final int primarySeatNumber;
  final String secondarySeatNumber;
  final String customSeatType;
  final String customSeatNumber;
}

TripSeatFormValue parseTripSeat(String? storedType, String? storedNumber) {
  final originalType = storedType?.trim() ?? '';
  final originalNumber = storedNumber?.trim() ?? '';
  // 位置字母只有大写一种写法（19C号）。12306 给的是大写，但票面 OCR 可能识别成小写，
  // 统一成大写再解析；认不出而落回「其它」时仍写回原文，不改用户自由输入的文本。
  final seatNumber = originalNumber.toUpperCase();
  final berthMatch = RegExp(r'^(.*?)(上铺|中铺|下铺)$').firstMatch(originalType);
  // 「车体席别代席别」先拆出基准席别；拆不出时保留原文，后面照旧按未知席别处理。
  final split = splitSeatType(berthMatch?.group(1) ?? originalType);
  final seatType = split.seatType;
  final coachSeatType = split.coachSeatType;
  final legacyBerth = berthMatch?.group(2);
  final carriageMatch = RegExp(
    r'^(?:(不指定车厢)|(加)?(\d+)车)(.*)$',
  ).firstMatch(seatNumber);
  final carriage = carriageMatch?.group(1) != null
      ? null
      : int.tryParse(carriageMatch?.group(3) ?? '');
  // 车厢未知时「加X车」没有意义，读写都不保留，免得界面上勾着而落库没有。
  final isExtraCarriage =
      carriageMatch?.group(2) != null &&
      carriage != null &&
      carriage != SeatOptions.unknownNumber;
  final remaining = carriageMatch?.group(4) ?? '';
  final normalizedType = SeatOptions.types.contains(seatType)
      ? seatType
      : '二等座';

  if (carriageMatch != null && (remaining == '无座' || remaining == '不对号入座')) {
    return TripSeatFormValue(
      seatType: normalizedType,
      coachSeatType: coachSeatType,
      isExtraCarriage: isExtraCarriage,
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
      primary >= SeatOptions.unknownNumber &&
      primary <= 128) {
    return TripSeatFormValue(
      seatType: seatType,
      coachSeatType: coachSeatType,
      isExtraCarriage: isExtraCarriage,
      seatMode: '席位',
      carriageNumber: carriage ?? 1,
      primarySeatNumber: primary,
      secondarySeatNumber: seatMatch.group(2) ?? legacyBerth ?? '无',
      customSeatType: '',
      customSeatNumber: '',
    );
  }
  // 认不出来就整条交给自定义输入，原文即真相。
  return TripSeatFormValue(
    seatType: '二等座',
    coachSeatType: null,
    isExtraCarriage: false,
    seatMode: '其它',
    carriageNumber: 1,
    primarySeatNumber: 1,
    secondarySeatNumber: '无',
    customSeatType: originalType,
    customSeatNumber: originalNumber,
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
            borderRadius: BorderRadius.all(
              Radius.circular(AppRadius.extraSmall),
            ),
          ),
          enabledBorder: const OutlineInputBorder(
            borderSide: BorderSide.none,
            borderRadius: BorderRadius.all(
              Radius.circular(AppRadius.extraSmall),
            ),
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
    required this.enabled,
    required this.onRailTripChanged,
    required this.onLocalOnlyChanged,
    this.showRailTrip = true,
  });

  final bool isRailTrip;
  final bool isLocalOnly;
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
          title: '云端行程',
          value: !isLocalOnly,
          enabled: enabled,
          onChanged: (value) => onLocalOnlyChanged(!value),
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
    this.hintText,
  });

  final TextEditingController controller;
  final String label;
  final String suffix;
  final IconData icon;
  final VoidCallback? onCalculate;
  final String? helperText;
  final String? hintText;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixText: suffix,
      helperText: helperText,
      hintText: hintText,
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
    hintText: '积分兑换请填0',
  );
}

class TripSeatSection extends StatelessWidget {
  const TripSeatSection({
    super.key,
    required this.seatType,
    required this.coachSeatType,
    required this.isExtraCarriage,
    required this.seatMode,
    required this.customSeatTypeController,
    required this.customSeatNumberController,
    required this.carriageNumber,
    required this.primarySeatNumber,
    required this.secondarySeatNumber,
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
    this.lookupFailed = false,
  });

  final String seatType;
  final String? coachSeatType;
  final bool isExtraCarriage;
  final String seatMode;
  final TextEditingController customSeatTypeController;
  final TextEditingController customSeatNumberController;
  final int? carriageNumber;
  final int primarySeatNumber;
  final String secondarySeatNumber;
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
          coachSeatType: coachSeatType,
          isExtraCarriage: isExtraCarriage,
          seatMode: seatMode,
          customSeatTypeController: customSeatTypeController,
          customSeatNumberController: customSeatNumberController,
          carriageNumber: carriageNumber,
          primarySeatNumber: primarySeatNumber,
          secondarySeatNumber: secondarySeatNumber,
          secondarySeatNumbers: SeatOptions.secondaryNumbers,
          onSeatTypeChanged: onSeatTypeChanged,
          onCoachSeatTypeChanged: onCoachSeatTypeChanged,
          onExtraCarriageChanged: onExtraCarriageChanged,
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
            '未获取到当前区间的座位信息',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    ),
  );
}
