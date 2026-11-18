import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/dashboard_unlock_entry.dart';
import 'package:raillog/src/models/trip_dashboard_stats.dart';
import 'package:raillog/src/models/trip_record.dart';

TripRecord _trip({required int id, String? rollingStock, String? company}) =>
    TripRecord(
      id: id,
      trainNumber: 'G$id',
      fromStation: '北京南',
      toStation: '上海虹桥',
      departureTime: DateTime(2026, 1, id),
      rollingStock: rollingStock,
      companyName: company,
      viaRouteSegments: const [],
    );

Map<String, int> _counts(Iterable<DashboardUnlockEntry> entries) => {
  for (final entry in entries) entry.name: entry.tripCount,
};

void main() {
  test('车号口径按车型加车号统计，没写车号的行程不计入', () {
    final stats = TripDashboardStats.fromTrips([
      _trip(id: 1, rollingStock: 'CR400AF-2011+CR400AF-2012'),
      _trip(id: 2, rollingStock: 'CR400AF-2011'),
      _trip(id: 3, rollingStock: 'CR400AF'),
      _trip(id: 4, rollingStock: 'YZ25T 345678'),
    ]);

    expect(_counts(stats.rollingStockUnlocks), {'CR400AF': 3, '25T': 1});
    expect(_counts(stats.rollingStockNumberUnlocks), {
      'CR400AF-2011': 2,
      'CR400AF-2012': 1,
      'YZ25T 345678': 1,
    });
  });

  test('路局口径把承运单位归并到路局，自定义单位归入其它', () {
    final stats = TripDashboardStats.fromTrips([
      _trip(id: 1, company: '京局北京客运段'),
      _trip(id: 2, company: '京局天津客运段'),
      _trip(id: 3, company: '上局上海段'),
      _trip(id: 4, company: '某某铁路公司'),
      _trip(id: 5),
    ]);

    expect(_counts(stats.bureauUnlocks), {'北京局': 2, '上海局': 1, '其它': 1});
  });
}
