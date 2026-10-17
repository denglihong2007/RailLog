import 'package:raillog/src/journal/journal_entry.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/via_route_segment.dart';

/// 一份「北京南 → 上海虹桥 G1」的合理行程，各用例只覆盖自己要变的字段。
TripRecord journalTrip({
  int id = 1,
  int? ticketId = 7,
  String trainNumber = 'G1',
  String? rollingStock = '复兴号 CR400BF',
  String fromStation = '北京南',
  String toStation = '上海虹桥',
  DateTime? departureTime,
  DateTime? arrivalTime,
  bool hasArrival = true,
  double mileageKm = 1318.4,
  List<ViaRouteSegment>? viaRouteSegments,
  String? seatType = '二等座',
  String? seatNumber = '05车12F',
  double price = 662,
  bool isRailTrip = true,
  bool isLocalOnly = false,
  String? notes,
}) {
  final depart = departureTime ?? DateTime(2026, 8, 2, 8);
  return TripRecord(
    id: id,
    ticketId: ticketId,
    trainNumber: trainNumber,
    rollingStock: rollingStock,
    fromStation: fromStation,
    toStation: toStation,
    departureTime: depart,
    arrivalTime: hasArrival
        ? (arrivalTime ?? depart.add(const Duration(hours: 4, minutes: 38)))
        : null,
    mileageKm: mileageKm,
    viaRouteSegments:
        viaRouteSegments ??
        const [
          ViaRouteSegment(
            routeName: '京沪高速铁路',
            fromStation: '北京南',
            toStation: '上海虹桥',
            mileageKm: 1318.4,
          ),
        ],
    seatType: seatType,
    seatNumber: seatNumber,
    price: price,
    isRailTrip: isRailTrip,
    isLocalOnly: isLocalOnly,
    notes: notes,
  );
}

/// 全 ASCII 的一条手账内容。
///
/// 渲染器测试专用：`pw.Font.helvetica()` 是 WinAnsi 核心字体，喂中文进去
/// 编出来的是乱码字节。那组用例只守结构——负坐标、非法尺寸、未闭合路径
/// 会在那里炸，而不是等真机导出才发现。
JournalEntry asciiEntry({
  String trainLabel = 'G1',
  String dateLabel = '2026-08-02',
  String weekdayLabel = 'SUN',
  String fromStation = 'Beijing South',
  String toStation = 'Shanghai Hongqiao',
  String departLabel = '08:00',
  String arriveLabel = '12:38',
  String durationLabel = '4h38m',
  String mileageLabel = '1318 km',
  String priceLabel = 'CNY 662.00',
  String seatLabel = '2nd Class 05-12F',
  String rollingStockLabel = 'CR400BF',
  String routeLabel = 'via Jinghu HSR',
  String notesLabel = '',
  String kindLabel = 'Rail',
  bool isRailTrip = true,
}) => JournalEntry(
  trainLabel: trainLabel,
  dateLabel: dateLabel,
  weekdayLabel: weekdayLabel,
  fromStation: fromStation,
  toStation: toStation,
  departLabel: departLabel,
  arriveLabel: arriveLabel,
  durationLabel: durationLabel,
  mileageLabel: mileageLabel,
  priceLabel: priceLabel,
  seatLabel: seatLabel,
  rollingStockLabel: rollingStockLabel,
  routeLabel: routeLabel,
  notesLabel: notesLabel,
  kindLabel: kindLabel,
  isRailTrip: isRailTrip,
);
