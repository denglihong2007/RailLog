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

  test('resetDatabase clears trips and settings', () async {
    await DbHelper.instance.insertTrip(_trip());
    await DbHelper.instance.setSetting('auth_token', 'token-1');

    expect(await DbHelper.instance.getAllTrips(), hasLength(1));

    await DbHelper.instance.resetDatabase();

    expect(await DbHelper.instance.getAllTrips(), isEmpty);
    expect(await DbHelper.instance.getSetting('auth_token'), isNull);
  });

  test('the database is usable again after a reset', () async {
    await DbHelper.instance.insertTrip(_trip());
    await DbHelper.instance.resetDatabase();

    await DbHelper.instance.insertTrip(_trip(clientId: 'after-reset'));
    await DbHelper.instance.setSetting('auth_token', 'token-2');

    final trips = await DbHelper.instance.getAllTrips();
    expect(trips, hasLength(1));
    expect(trips.single.clientId, 'after-reset');
    expect(await DbHelper.instance.getSetting('auth_token'), 'token-2');
  });
}

TripRecord _trip({String? clientId}) => TripRecord(
  id: 0,
  clientId: clientId,
  trainNumber: 'G1',
  fromStation: '北京南',
  toStation: '上海虹桥',
  departureTime: DateTime(2026, 9, 15, 8),
  arrivalTime: DateTime(2026, 9, 15, 12),
  mileageKm: 1318,
  viaRouteSegments: const [],
  price: 662,
);
