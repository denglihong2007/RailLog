import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/services/trip_excel_import_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await DbHelper.instance.useInMemoryDatabaseForTesting();
    DbHelper.instance.activeUserId = () => 'user-1';
  });

  tearDown(() {
    DbHelper.instance.activeUserId = null;
  });

  test(
    'sync queue contains only dirty trips and clears acknowledged rows',
    () async {
      await DbHelper.instance.insertTrip(_trip());

      final pending = await DbHelper.instance.getTripsForSync('user-1');
      expect(pending, hasLength(1));

      await DbHelper.instance.markTripsSynced('user-1', pending);

      expect(await DbHelper.instance.getTripsForSync('user-1'), isEmpty);
    },
  );

  test('acknowledging a snapshot does not clear a newer local edit', () async {
    final id = await DbHelper.instance.insertTrip(_trip());
    final pending = await DbHelper.instance.getTripsForSync('user-1');

    await Future<void>.delayed(const Duration(milliseconds: 2));
    await DbHelper.instance.updateTrip(
      _trip(id: id, notes: 'updated while syncing'),
    );
    await DbHelper.instance.markTripsSynced('user-1', pending);

    final remaining = await DbHelper.instance.getTripsForSync('user-1');
    expect(remaining, hasLength(1));
    expect(remaining.single.notes, 'updated while syncing');
  });

  test('cloud rows enter the local database as already synced', () async {
    final cloudTrip = _trip(
      clientId: 'cloud-trip',
      ticketId: 42,
      notes: 'from server',
    );

    await DbHelper.instance.mergeCloudTrips('user-1', [cloudTrip]);

    expect(await DbHelper.instance.getTripsForSync('user-1'), isEmpty);
    final local = await DbHelper.instance.getAllTrips();
    expect(local, hasLength(1));
    expect(local.single.ticketId, 42);
    expect(local.single.notes, 'from server');
  });

  test('cloud rows carry the group name', () async {
    await DbHelper.instance.mergeCloudTrips('user-1', [
      _trip(clientId: 'cloud-group', groupName: '分组甲'),
    ]);

    final local = await DbHelper.instance.getAllTrips();
    expect(local.single.groupName, '分组甲');
  });

  test(
    'bulk grouping trims, queues cloud rows and clears local-only rows',
    () async {
      final first = await DbHelper.instance.insertTrip(_trip());
      final second = await DbHelper.instance.insertTrip(_trip());
      final localOnly = await DbHelper.instance.insertTrip(
        _trip(isLocalOnly: true),
      );

      final affected = await DbHelper.instance.updateTripGroups([
        first,
        second,
        localOnly,
      ], '  京沪往返  ');
      expect(affected, 3);

      final trips = await DbHelper.instance.getAllTrips();
      expect(trips.where((trip) => trip.groupName == '京沪往返'), hasLength(3));

      final pending = await DbHelper.instance.getTripsForSync('user-1');
      expect(pending.map((trip) => trip.id), containsAll([first, second]));
      expect(pending.map((trip) => trip.id), isNot(contains(localOnly)));

      final row = await (await DbHelper.instance.database).query(
        'trip_records',
        columns: ['sync_dirty'],
        where: 'id = ?',
        whereArgs: [localOnly],
      );
      expect(row.single['sync_dirty'], 0);

      await DbHelper.instance.updateTripGroups([first], null);
      expect((await DbHelper.instance.getTripById(first))!.groupName, isNull);
    },
  );

  test('bulk grouping ignores trips owned by another user', () async {
    final other = await DbHelper.instance.insertTrip(
      _trip(ownerUserId: 'user-2'),
    );

    final affected = await DbHelper.instance.updateTripGroups([other], 'x');

    expect(affected, 0);
    final row = await (await DbHelper.instance.database).query(
      'trip_records',
      columns: ['group_name'],
      where: 'id = ?',
      whereArgs: [other],
    );
    expect(row.single['group_name'], isNull);
  });

  test('Excel import keeps a group when the 分组 column is absent', () async {
    final id = await DbHelper.instance.insertTrip(_trip(groupName: '旧分组'));
    final workbook = Excel.createExcel();
    final sheet = workbook['行程'];
    sheet.appendRow(
      TripExcelImportService.requiredHeaders.map(TextCellValue.new).toList(),
    );
    sheet.appendRow(_importRow(id));

    await TripExcelImportService.importBytes(_save(workbook));

    expect((await DbHelper.instance.getTripById(id))!.groupName, '旧分组');
  });

  test('Excel import clears a group when the cell is empty', () async {
    final id = await DbHelper.instance.insertTrip(_trip(groupName: '旧分组'));
    final workbook = Excel.createExcel();
    final sheet = workbook['行程'];
    sheet.appendRow([
      ...TripExcelImportService.requiredHeaders.map(TextCellValue.new),
      TextCellValue('分组'),
    ]);
    sheet.appendRow([..._importRow(id), TextCellValue('')]);

    await TripExcelImportService.importBytes(_save(workbook));

    expect((await DbHelper.instance.getTripById(id))!.groupName, isNull);
  });
}

List<CellValue> _importRow(int id) => [
  TextCellValue('$id'),
  TextCellValue('G101'),
  TextCellValue('北京南'),
  TextCellValue('上海虹桥'),
  TextCellValue('2025-01-02 08:15:00'),
];

Uint8List _save(Excel workbook) => Uint8List.fromList(workbook.save()!);

TripRecord _trip({
  int id = 0,
  String? clientId,
  int? ticketId,
  String? notes,
  String? ownerUserId,
  String? groupName,
  bool isLocalOnly = false,
}) => TripRecord(
  id: id,
  clientId: clientId,
  ticketId: ticketId,
  ownerUserId: ownerUserId,
  trainNumber: 'G1',
  fromStation: '北京南',
  toStation: '上海虹桥',
  departureTime: DateTime(2026, 9, 15, 8),
  arrivalTime: DateTime(2026, 9, 15, 12),
  mileageKm: 1318,
  viaRouteSegments: const [],
  price: 662,
  notes: notes,
  groupName: groupName,
  isLocalOnly: isLocalOnly,
);
