import 'package:flutter/material.dart';
import 'package:raillog/src/models/ticket_12306_order.dart';
import 'package:raillog/src/models/timetable_version.dart';
import 'package:raillog/src/models/train_schedule_stop.dart';
import 'package:raillog/src/pages/train_trip_form_page.dart';
import 'package:raillog/src/services/train_service.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

class PreparedTicketOrder {
  const PreparedTicketOrder({
    required this.stops,
    required this.departureIndex,
    required this.arrivalIndex,
    this.historicalVersion,
    this.usedFallback = false,
  });

  final List<TrainScheduleStop> stops;
  final int departureIndex;
  final int arrivalIndex;

  /// 站序来自哪一版历史时刻表；推导不出版本时为 `null`。
  final String? historicalVersion;

  /// 是否退成了「订单始发/终到」两站合成站序。
  final bool usedFallback;
}

Future<bool> showTicketImportConfirmationDialog(
  BuildContext context,
  int count,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.fact_check_outlined),
      title: const Text('逐条确认行程'),
      content: Text('接下来将依次确认 $count 条行程，并自动补全担当公司、车型和经由线路。每次确认后保存当前一条。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('开始确认'),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// 站序一律取自历史时刻表；取不到就退成订单始发/终到的两站合成站序，
/// 不再回退到 12306 的在线查询 —— 在线接口按「现在」的同号车次作答，
/// 用在补录的老订单上会串段。
Future<PreparedTicketOrder> prepareTicketOrder(
  Ticket12306Order order,
  List<String> versions,
) async {
  final version = resolveTimetableVersion(order.startTime, versions);
  final schedule = version == null
      ? null
      : (await TrainService.lookupHistoricalSchedule(
          trainNumber: order.trainCode,
          boardingDate: order.startTime,
          version: version,
        ))?.stops;
  if (schedule != null) {
    final departureIndex = schedule.indexWhere(
      (stop) => _sameStation(stop.stationName, order.fromStation),
    );
    final arrivalIndex = schedule.indexWhere(
      (stop) => _sameStation(stop.stationName, order.toStation),
    );
    if (departureIndex >= 0 && arrivalIndex > departureIndex) {
      final resolved = TrainService.resolveScheduleDateTimes(
        schedule,
        order.startTime,
        departureIndex,
      ).toList();
      resolved[departureIndex] = resolved[departureIndex].copyWith(
        departureDateTime: order.startTime,
      );
      final arrivalTime =
          order.arriveTime ??
          resolved[arrivalIndex].arrivalDateTime ??
          resolved[arrivalIndex].departureDateTime ??
          order.startTime;
      resolved[arrivalIndex] = resolved[arrivalIndex].copyWith(
        arrivalDateTime: arrivalTime,
      );
      return PreparedTicketOrder(
        stops: resolved,
        departureIndex: departureIndex,
        arrivalIndex: arrivalIndex,
        historicalVersion: version,
        usedFallback: false,
      );
    }
  }
  return _fallbackPreparedOrder(order, historicalVersion: version);
}

/// 依次打开行程确认页；每保存一条就回调 [onImported]。
/// 用户取消时提前返回，返回值是已导入的条数。
Future<int> confirmTicketOrderImport({
  required BuildContext context,
  required List<Ticket12306Order> orders,
  required List<String> versions,
  required ValueChanged<int?> onPreparing,
  required ValueChanged<Ticket12306Order> onImported,
}) async {
  var importedCount = 0;
  for (var index = 0; index < orders.length; index++) {
    if (!context.mounted) return importedCount;
    final order = orders[index];
    onPreparing(index + 1);
    final prepared = await prepareTicketOrder(order, versions);
    if (!context.mounted) return importedCount;
    onPreparing(null);
    final saved = await Navigator.of(context).push<bool>(
      m3PageRoute(
        builder: (context) => TrainTripFormPage(
          trainNumber: order.trainCode,
          scheduleStops: prepared.stops,
          historicalVersion: prepared.historicalVersion,
          forceHistoricalJourney: true,
          keepOnlineLookups: true,
          departureStopIndex: prepared.departureIndex,
          arrivalStopIndex: prepared.arrivalIndex,
          initialSeatType: order.seatType,
          initialSeatNumber: order.seatNumber,
          initialMileageKm: order.distance,
          initialPrice: order.price,
          initialNotes: order.statusText,
          initialPrompt: prepared.usedFallback
              ? '未从历史时刻表取到该车次站序，已按订单始发/终到生成，请核对'
              : null,
          reviewPosition: index + 1,
          reviewTotal: orders.length,
        ),
      ),
    );
    if (!context.mounted) return importedCount;
    if (saved != true) break;
    importedCount++;
    onImported(order);
  }
  onPreparing(null);
  return importedCount;
}

/// 一次批量导入的执行结果。
class TicketImportRun {
  const TicketImportRun({
    required this.importedCount,
    required this.total,
    this.cancelled = false,
  });

  final int importedCount;
  final int total;

  /// 用户在整批确认对话框里点了取消。
  final bool cancelled;

  bool get completed => total > 0 && importedCount == total;
}

/// 三个导入入口共用的执行流程：多条时先确认整批操作，再逐条打开行程表单；
/// 单条直接进入确认，不再弹整批确认框。
Future<TicketImportRun> runTicketImport({
  required BuildContext context,
  required List<Ticket12306Order> orders,
  required ValueChanged<int?> onPreparing,
  required ValueChanged<Ticket12306Order> onImported,
}) async {
  if (orders.isEmpty) {
    return const TicketImportRun(importedCount: 0, total: 0);
  }

  if (orders.length > 1) {
    final confirmed = await showTicketImportConfirmationDialog(
      context,
      orders.length,
    );
    if (!confirmed || !context.mounted) {
      return TicketImportRun(
        importedCount: 0,
        total: orders.length,
        cancelled: true,
      );
    }
  }

  // 版本列表只取一次：service 内部有缓存，但空结果不缓存，
  // 逐单重复调会在服务端没配时刻表库时白白打一遍网络。
  final versions = await TrainService.fetchTimetableVersions();
  if (!context.mounted) {
    return TicketImportRun(
      importedCount: 0,
      total: orders.length,
      cancelled: true,
    );
  }

  final importedCount = await confirmTicketOrderImport(
    context: context,
    orders: orders,
    versions: versions,
    onPreparing: onPreparing,
    onImported: onImported,
  );
  return TicketImportRun(importedCount: importedCount, total: orders.length);
}

/// 三个导入入口共用的结果提示文案。
String ticketImportOutcomeMessage(TicketImportRun run) {
  if (run.cancelled || run.importedCount == 0) {
    return '已取消导入，行程仍保留在待确认列表中';
  }
  if (run.completed) return '已确认并导入 ${run.importedCount} 条行程';
  return '已导入 ${run.importedCount} 条，其余行程尚未确认';
}

PreparedTicketOrder _fallbackPreparedOrder(
  Ticket12306Order order, {
  String? historicalVersion,
}) {
  final arrival = order.arriveTime ?? order.startTime;
  final dayDifference = DateTime(arrival.year, arrival.month, arrival.day)
      .difference(
        DateTime(
          order.startTime.year,
          order.startTime.month,
          order.startTime.day,
        ),
      )
      .inDays;
  return PreparedTicketOrder(
    stops: [
      TrainScheduleStop(
        stationName: order.fromStation,
        stationNo: '01',
        arriveTime: '--',
        startTime: _formatClock(order.startTime),
        runningTime: '00:00',
        arriveDay: '当日',
        arriveDayDifference: 0,
        departureDateTime: order.startTime,
        arrivalDateTime: order.startTime,
      ),
      TrainScheduleStop(
        stationName: order.toStation,
        stationNo: '02',
        arriveTime: _formatClock(arrival),
        startTime: '--',
        runningTime: '',
        arriveDay: dayDifference == 0 ? '当日' : '第${dayDifference + 1}日',
        arriveDayDifference: dayDifference,
        departureDateTime: arrival,
        arrivalDateTime: arrival,
      ),
    ],
    departureIndex: 0,
    arrivalIndex: 1,
    historicalVersion: historicalVersion,
    usedFallback: true,
  );
}

String _formatClock(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

bool _sameStation(String first, String second) =>
    normalizeStationName(first) == normalizeStationName(second);
