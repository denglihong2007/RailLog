import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const userId = 'local-trip-test-user';

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await DbHelper.instance.useInMemoryDatabaseForTesting();
    DbHelper.instance.activeUserId = () => userId;
  });

  test('本地行程持久化标记且不会进入同步集合', () async {
    final localId = await DbHelper.instance.insertTrip(
      _trip(id: 0, trainNumber: 'L1', isLocalOnly: true),
    );
    await DbHelper.instance.insertTrip(_trip(id: 0, trainNumber: 'G1'));

    final local = await DbHelper.instance.getTripById(localId);
    final syncTrips = await DbHelper.instance.getTripsForSync(userId);

    expect(local?.isLocalOnly, isTrue);
    expect(local?.ownerUserId, isNull);
    expect(syncTrips.map((trip) => trip.trainNumber), ['G1']);
  });

  test('已同步行程改为本地时重建本地身份并生成云端删除标记', () async {
    final original = _trip(
      id: 0,
      trainNumber: 'G2',
      ticketId: 42,
      ownerUserId: userId,
    );
    final id = await DbHelper.instance.insertTrip(original);

    await DbHelper.instance.updateTrip(
      _trip(
        id: id,
        trainNumber: 'G2 edited',
        clientId: original.clientId,
        ticketId: original.ticketId,
        ownerUserId: original.ownerUserId,
        isLocalOnly: true,
      ),
    );

    final local = await DbHelper.instance.getTripById(id);
    final syncTrips = await DbHelper.instance.getTripsForSync(userId);

    expect(local?.isLocalOnly, isTrue);
    expect(local?.ticketId, isNull);
    expect(local?.ownerUserId, isNull);
    expect(local?.clientId, isNot(original.clientId));
    expect(syncTrips, hasLength(1));
    expect(syncTrips.single.clientId, original.clientId);
    expect(syncTrips.single.deletedAt, isNotNull);
  });

  test('本地行程改为云端行程后会进入同步集合', () async {
    final local = _trip(id: 0, trainNumber: 'L2', isLocalOnly: true);
    final id = await DbHelper.instance.insertTrip(local);

    await DbHelper.instance.updateTrip(
      _trip(id: id, trainNumber: 'L2', clientId: local.clientId),
    );

    final syncTrips = await DbHelper.instance.getTripsForSync(userId);
    expect(syncTrips, hasLength(1));
    expect(syncTrips.single.isLocalOnly, isFalse);
    expect(syncTrips.single.ownerUserId, userId);
  });

  test('云端合并不会覆盖本地行程', () async {
    final local = _trip(id: 0, trainNumber: 'L3', isLocalOnly: true);
    final id = await DbHelper.instance.insertTrip(local);

    await DbHelper.instance.mergeCloudTrips(userId, [
      _trip(
        id: 0,
        trainNumber: 'cloud replacement',
        clientId: local.clientId,
        ownerUserId: userId,
        updatedAt: DateTime(2026, 2, 1),
      ),
    ]);

    final preserved = await DbHelper.instance.getTripById(id);
    expect(preserved?.trainNumber, 'L3');
    expect(preserved?.isLocalOnly, isTrue);
  });
}

TripRecord _trip({
  required int id,
  required String trainNumber,
  String? clientId,
  int? ticketId,
  String? ownerUserId,
  DateTime? updatedAt,
  bool isLocalOnly = false,
}) => TripRecord(
  id: id,
  trainNumber: trainNumber,
  clientId: clientId,
  ticketId: ticketId,
  ownerUserId: ownerUserId,
  updatedAt: updatedAt,
  fromStation: '北京',
  toStation: '上海',
  departureTime: DateTime(2026, 1, 1, 8),
  arrivalTime: DateTime(2026, 1, 1, 12),
  mileageKm: 1200,
  viaRouteSegments: const [],
  isLocalOnly: isLocalOnly,
);
