import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/models/trip_dashboard_stats.dart';

class DbHelper {
  DbHelper._privateConstructor();
  static final DbHelper instance = DbHelper._privateConstructor();
  static Database? _database;
  Future<void> Function()? onTripsChanged;
  String? Function()? activeUserId;
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'raillog.db');

    return await openDatabase(
      path,
      version: 6,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> useInMemoryDatabaseForTesting() async {
    await _database?.close();
    _database = await openDatabase(
      inMemoryDatabasePath,
      version: 6,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE trip_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ticket_id INTEGER,
        client_id TEXT NOT NULL,
        owner_user_id TEXT,
        train_number TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        deleted_at TEXT,
        rolling_stock TEXT,
        company_name TEXT,
        from_station TEXT NOT NULL,
        to_station TEXT NOT NULL,
        departure_time TEXT,
        arrival_time TEXT,
        mileage_km REAL NOT NULL,
        via_route_segments TEXT NOT NULL, 
        seat_type TEXT,
        seat_number TEXT,
        price REAL NOT NULL,
        is_rail_trip INTEGER NOT NULL,
        is_local_only INTEGER NOT NULL DEFAULT 0,
        notes TEXT
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX ix_trip_records_client_id ON trip_records(client_id)',
    );
    await db.execute(
      'CREATE INDEX ix_trip_records_owner_user_id ON trip_records(owner_user_id)',
    );
    await _createSettingsTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE trip_records ADD COLUMN company_name TEXT');
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE trip_records ADD COLUMN client_id TEXT');
      await db.execute('ALTER TABLE trip_records ADD COLUMN updated_at TEXT');
      await db.execute('ALTER TABLE trip_records ADD COLUMN deleted_at TEXT');
      await db.execute(
        "UPDATE trip_records SET client_id = lower(hex(randomblob(16))) WHERE client_id IS NULL",
      );
      await db.execute(
        'UPDATE trip_records SET updated_at = created_at WHERE updated_at IS NULL',
      );
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS ix_trip_records_client_id ON trip_records(client_id)',
      );
      await _createSettingsTable(db);
    }
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE trip_records ADD COLUMN owner_user_id TEXT',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS ix_trip_records_owner_user_id ON trip_records(owner_user_id)',
      );
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE trip_records ADD COLUMN ticket_id INTEGER');
    }
    if (oldVersion < 6) {
      await db.execute(
        'ALTER TABLE trip_records ADD COLUMN is_local_only INTEGER NOT NULL DEFAULT 0',
      );
    }
  }

  Future<void> _createSettingsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<int> insertTrip(TripRecord trip) async {
    final db = await database;
    final values = trip.toMap()..remove('id');
    if (trip.isLocalOnly) {
      values['ticket_id'] = null;
      values['owner_user_id'] = null;
    } else {
      values['owner_user_id'] ??= activeUserId?.call();
    }
    final result = await db.insert('trip_records', values);
    _notifyTripsChanged();
    return result;
  }

  Future<int> insertTrips(List<TripRecord> trips) async {
    if (trips.isEmpty) return 0;
    final db = await database;
    final userId = activeUserId?.call();
    await db.transaction((txn) async {
      for (final trip in trips) {
        final values = trip.toMap()..remove('id');
        if (trip.isLocalOnly) {
          values
            ..['ticket_id'] = null
            ..['owner_user_id'] = null;
        } else {
          values['owner_user_id'] ??= userId;
        }
        await txn.insert('trip_records', values);
      }
    });
    _notifyTripsChanged();
    return trips.length;
  }

  Future<int> updateTrip(TripRecord trip) async {
    final db = await database;
    final updatedAt = DateTime.now().toIso8601String();
    final values = trip.toMap()
      ..remove('id')
      ..['updated_at'] = updatedAt;
    final result = await db.transaction((txn) async {
      final rows = await txn.query(
        'trip_records',
        where: 'id = ?',
        whereArgs: [trip.id],
        limit: 1,
      );
      if (rows.isEmpty) return 0;

      final existing = rows.first;
      final wasLocalOnly = (existing['is_local_only'] as num?)?.toInt() == 1;
      final hadCloudIdentity =
          existing['ticket_id'] != null || existing['owner_user_id'] != null;
      if (!wasLocalOnly && trip.isLocalOnly && hadCloudIdentity) {
        values
          ..['client_id'] = TripRecord.createClientId()
          ..['ticket_id'] = null
          ..['owner_user_id'] = null;
        final updated = await txn.update(
          'trip_records',
          values,
          where: 'id = ?',
          whereArgs: [trip.id],
        );
        final tombstone = Map<String, Object?>.from(existing)
          ..remove('id')
          ..['updated_at'] = updatedAt
          ..['deleted_at'] = updatedAt
          ..['is_local_only'] = 0;
        await txn.insert('trip_records', tombstone);
        return updated;
      }

      if (trip.isLocalOnly) {
        values
          ..['ticket_id'] = null
          ..['owner_user_id'] = null;
      } else if (wasLocalOnly) {
        values['owner_user_id'] ??= activeUserId?.call();
      }
      return txn.update(
        'trip_records',
        values,
        where: 'id = ?',
        whereArgs: [trip.id],
      );
    });
    _notifyTripsChanged();
    return result;
  }

  Future<int> deleteTrip(int id) async {
    final db = await database;
    final userId = activeUserId?.call();
    final now = DateTime.now().toIso8601String();
    final where = userId == null
        ? 'id = ? AND deleted_at IS NULL AND owner_user_id IS NULL'
        : 'id = ? AND deleted_at IS NULL AND (owner_user_id IS NULL OR owner_user_id = ?)';
    final whereArgs = userId == null ? <Object?>[id] : <Object?>[id, userId];
    final result = await db.transaction((txn) async {
      final rows = await txn.query(
        'trip_records',
        columns: ['is_local_only'],
        where: where,
        whereArgs: whereArgs,
        limit: 1,
      );
      if (rows.isEmpty) return 0;
      if ((rows.first['is_local_only'] as num?)?.toInt() == 1) {
        return txn.delete('trip_records', where: where, whereArgs: whereArgs);
      }
      return txn.update(
        'trip_records',
        {'deleted_at': now, 'updated_at': now},
        where: where,
        whereArgs: whereArgs,
      );
    });
    _notifyTripsChanged();
    return result;
  }

  Future<List<TripRecord>> getAllTrips() async {
    final db = await database;
    final userId = activeUserId?.call();
    final List<Map<String, dynamic>> maps = await db.query(
      'trip_records',
      where: userId == null
          ? 'deleted_at IS NULL AND owner_user_id IS NULL'
          : 'deleted_at IS NULL AND (owner_user_id IS NULL OR owner_user_id = ?)',
      whereArgs: userId == null ? null : [userId],
      orderBy: 'created_at DESC',
    );

    return maps.map((map) => TripRecord.fromMap(map)).toList();
  }

  Future<TripRecord?> getTripById(int id) async {
    final db = await database;
    final userId = activeUserId?.call();
    final maps = await db.query(
      'trip_records',
      where: userId == null
          ? 'id = ? AND deleted_at IS NULL AND owner_user_id IS NULL'
          : 'id = ? AND deleted_at IS NULL AND (owner_user_id IS NULL OR owner_user_id = ?)',
      whereArgs: userId == null ? [id] : [id, userId],
      limit: 1,
    );
    return maps.isEmpty ? null : TripRecord.fromMap(maps.first);
  }

  Future<TripDashboardStats> getDashboardStats() async {
    final trips = await getAllTrips();
    return TripDashboardStats.fromTrips(trips);
  }

  Future<List<TripRecord>> getTripsForSync(String userId) async {
    final db = await database;
    await db.update('trip_records', {
      'owner_user_id': userId,
    }, where: 'owner_user_id IS NULL AND is_local_only = 0');
    final maps = await db.query(
      'trip_records',
      where: 'owner_user_id = ? AND is_local_only = 0',
      whereArgs: [userId],
      orderBy: 'updated_at',
    );
    return maps.map(TripRecord.fromMap).toList();
  }

  Future<void> mergeCloudTrips(
    String userId,
    List<TripRecord> cloudTrips,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final cloudTrip in cloudTrips) {
        final existing = await txn.query(
          'trip_records',
          columns: ['id', 'ticket_id', 'updated_at', 'is_local_only'],
          where: 'client_id = ?',
          whereArgs: [cloudTrip.clientId],
          limit: 1,
        );
        if (existing.isNotEmpty &&
            (existing.first['is_local_only'] as num?)?.toInt() == 1) {
          continue;
        }
        final values = cloudTrip.toMap()
          ..remove('id')
          ..['owner_user_id'] = userId;
        if (existing.isEmpty) {
          await txn.insert('trip_records', values);
          continue;
        }
        final localUpdatedAt = DateTime.parse(
          existing.first['updated_at'] as String,
        );
        if (cloudTrip.updatedAt.isAfter(localUpdatedAt)) {
          await txn.update(
            'trip_records',
            values,
            where: 'client_id = ?',
            whereArgs: [cloudTrip.clientId],
          );
        } else if (cloudTrip.ticketId != null &&
            existing.first['ticket_id'] != cloudTrip.ticketId) {
          await txn.update(
            'trip_records',
            {'ticket_id': cloudTrip.ticketId, 'owner_user_id': userId},
            where: 'client_id = ?',
            whereArgs: [cloudTrip.clientId],
          );
        }
      }
    });
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  Future<void> setSetting(String key, String? value) async {
    final db = await database;
    if (value == null) {
      await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
    } else {
      await db.insert('app_settings', {
        'key': key,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> releaseTripsForUser(String userId) async {
    final db = await database;
    await db.update(
      'trip_records',
      {'owner_user_id': null},
      where: 'owner_user_id = ?',
      whereArgs: [userId],
    );
  }

  void _notifyTripsChanged() {
    final callback = onTripsChanged;
    if (callback != null) unawaited(callback());
  }
}
