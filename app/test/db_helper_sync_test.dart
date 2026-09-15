import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/services/db_helper.dart';
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
}

TripRecord _trip({
  int id = 0,
  String? clientId,
  int? ticketId,
  String? notes,
}) => TripRecord(
  id: id,
  clientId: clientId,
  ticketId: ticketId,
  trainNumber: 'G1',
  fromStation: '北京南',
  toStation: '上海虹桥',
  departureTime: DateTime(2026, 9, 15, 8),
  arrivalTime: DateTime(2026, 9, 15, 12),
  mileageKm: 1318,
  viaRouteSegments: const [],
  price: 662,
  notes: notes,
);
