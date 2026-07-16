import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:raillog/src/models/trip_record.dart';
import 'package:raillog/src/services/api_client.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/services/session_service.dart';

class CloudSyncService extends ChangeNotifier {
  CloudSyncService._();

  static final CloudSyncService instance = CloudSyncService._();
  bool _isSyncing = false;
  bool _autoSyncEnabled = true;
  DateTime? _lastSyncedAt;
  String? _lastError;
  VoidCallback? onDataChanged;

  bool get isSyncing => _isSyncing;
  bool get autoSyncEnabled => _autoSyncEnabled;
  DateTime? get lastSyncedAt => _lastSyncedAt;
  String? get lastError => _lastError;

  Future<void> initialize() async {
    final value = await DbHelper.instance.getSetting('last_synced_at');
    _lastSyncedAt = value == null ? null : DateTime.tryParse(value);
    final autoSyncValue = await DbHelper.instance.getSetting(
      'auto_sync_enabled',
    );
    _autoSyncEnabled = autoSyncValue == null || autoSyncValue == 'true';
  }

  Future<void> syncIfSignedIn() async {
    if (!_autoSyncEnabled ||
        !SessionService.instance.isSignedIn ||
        _isSyncing) {
      return;
    }
    try {
      await sync();
    } on SessionException {
      // Automatic sync errors are exposed through lastError for manual retry.
    }
  }

  Future<void> setAutoSyncEnabled(bool value) async {
    if (_autoSyncEnabled == value) return;
    _autoSyncEnabled = value;
    await DbHelper.instance.setSetting('auto_sync_enabled', value.toString());
    notifyListeners();
    if (value) await syncIfSignedIn();
  }

  Future<void> sync() async {
    final token = SessionService.instance.token;
    final userId = SessionService.instance.user?.id;
    if (token == null) throw const SessionException('请先登录');
    if (userId == null) throw const SessionException('请先登录');
    if (_isSyncing) return;
    _isSyncing = true;
    _lastError = null;
    notifyListeners();
    try {
      final localTrips = await DbHelper.instance.getTripsForSync(userId);
      final response = await ApiClient.instance.dio.post<Map<String, dynamic>>(
        '/api/trips/sync',
        options: ApiClient.instance.authorized(token),
        data: {'trips': localTrips.map(_toCloudJson).toList()},
      );
      final rows = response.data?['trips'] as List<dynamic>? ?? const [];
      final cloudTrips = rows
          .map((row) => _fromCloudJson(row as Map<String, dynamic>))
          .toList();
      await DbHelper.instance.mergeCloudTrips(userId, cloudTrips);
      onDataChanged?.call();
      _lastSyncedAt = DateTime.now();
      await DbHelper.instance.setSetting(
        'last_synced_at',
        _lastSyncedAt!.toIso8601String(),
      );
    } on DioException catch (error) {
      _lastError = apiErrorMessage(error);
      if (error.response?.statusCode == 401) {
        await SessionService.instance.invalidate();
      }
      throw SessionException(_lastError!);
    } catch (error) {
      _lastError = error is SessionException ? error.message : '同步失败，请稍后重试';
      throw SessionException(_lastError!);
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Map<String, dynamic> _toCloudJson(TripRecord trip) => {
    'ticketId': trip.ticketId,
    'clientId': trip.clientId,
    'createdAt': trip.createdAt.toIso8601String(),
    'trainNumber': trip.trainNumber,
    'travelDate': trip.departureTime.toIso8601String(),
    'rollingStock': trip.rollingStock,
    'companyName': trip.companyName,
    'fromStation': trip.fromStation,
    'toStation': trip.toStation,
    'departureTime': trip.departureTime.toIso8601String(),
    'arrivalTime': trip.arrivalTime?.toIso8601String(),
    'mileageKm': trip.mileageKm,
    'viaRoutes': jsonEncode(
      trip.viaRouteSegments.map((segment) => segment.toJson()).toList(),
    ),
    'seatType': trip.seatType,
    'seatNumber': trip.seatNumber,
    'price': trip.price,
    'notes': trip.notes,
    'isRailTrip': trip.isRailTrip,
    'updatedAt': trip.updatedAt.toIso8601String(),
    'deletedAt': trip.deletedAt?.toIso8601String(),
  };

  TripRecord _fromCloudJson(Map<String, dynamic> row) {
    final departure = row['departureTime'] as String?;
    return TripRecord.fromMap({
      'id': 0,
      'ticket_id': row['ticketId'],
      'client_id': row['clientId'],
      'created_at': row['createdAt'],
      'updated_at': row['updatedAt'],
      'deleted_at': row['deletedAt'],
      'train_number': row['trainNumber'],
      'rolling_stock': row['rollingStock'],
      'company_name': row['companyName'],
      'from_station': row['fromStation'],
      'to_station': row['toStation'],
      'departure_time': departure ?? row['travelDate'],
      'arrival_time': row['arrivalTime'],
      'mileage_km': row['mileageKm'],
      'via_route_segments': row['viaRoutes'] ?? '[]',
      'seat_type': row['seatType'],
      'seat_number': row['seatNumber'],
      'price': row['price'],
      'is_rail_trip': row['isRailTrip'] == true ? 1 : 0,
      'notes': row['notes'],
    });
  }
}
