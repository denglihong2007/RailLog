import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:raillog/src/models/rolling_stock_lookup_result.dart';
import 'package:raillog/src/models/rolling_stock_record.dart';
import 'package:raillog/src/models/station_pair_distance.dart';
import 'package:raillog/src/models/ticket_seat_option.dart';
import 'package:raillog/src/models/train_distance_info.dart';
import 'package:raillog/src/models/train_search_result.dart';
import 'package:raillog/src/models/train_schedule_stop.dart';
import 'package:raillog/src/models/timetable_source.dart';
import 'package:raillog/src/services/api_client.dart';

class TrainService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
    ),
  );
  static final Dio _ticketDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      followRedirects: true,
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Referer': 'https://kyfw.12306.cn/otn/leftTicket/init',
        'Accept': '*/*',
      },
    ),
  );
  static Map<String, String> _stationCodes = const {};
  static Future<Map<String, String>>? _stationCodeRequest;
  static final Map<String, String> _ticketCookies = {};
  static Future<void>? _ticketSessionRequest;
  static bool _browserSessionInitialized = false;

  TrainService._();

  static Future<Map<String, String>> initializeStationCodes() async {
    if (_stationCodes.isNotEmpty) return _stationCodes;
    final existingRequest = _stationCodeRequest;
    if (existingRequest != null) return existingRequest;

    final request = _loadStationCodesAndSession();
    _stationCodeRequest = request;
    final result = await request;
    if (result.isNotEmpty) {
      _stationCodes = Map.unmodifiable(result);
    } else {
      _stationCodeRequest = null;
    }
    return _stationCodes;
  }

  static Future<Map<String, String>> _loadStationCodesAndSession() async {
    final stationCodes = await _fetchStationCodes();
    await _ensureTicketSession();
    return stationCodes;
  }

  static Future<Map<String, String>> _fetchStationCodes() async {
    try {
      final response = await _ticketDio.get<String>(
        'https://kyfw.12306.cn/otn/resources/js/framework/station_name.js',
        options: _ticketRequestOptions(),
      );
      if (response.statusCode != 200) return const {};
      return parseStationCodes(response.data ?? '');
    } on DioException {
      return const {};
    }
  }

  static Future<void> _ensureTicketSession({bool force = false}) async {
    if (!force &&
        (_ticketCookies.containsKey('JSESSIONID') ||
            (kIsWeb && _browserSessionInitialized))) {
      return;
    }
    final existingRequest = _ticketSessionRequest;
    if (existingRequest != null) return existingRequest;

    final request = _startTicketSession();
    _ticketSessionRequest = request;
    try {
      await request;
    } finally {
      _ticketSessionRequest = null;
    }
  }

  static Future<void> _startTicketSession() async {
    try {
      final response = await _ticketDio.get<String>(
        'https://kyfw.12306.cn/otn/leftTicket/init',
        options: _ticketRequestOptions(),
      );
      _captureTicketCookies(response.headers);
      _browserSessionInitialized = response.statusCode == 200;
    } on DioException {
      _browserSessionInitialized = false;
    }
  }

  static Options _ticketRequestOptions() {
    return Options(
      responseType: ResponseType.plain,
      headers: {
        if (!kIsWeb && _ticketCookies.isNotEmpty)
          'Cookie': _ticketCookies.entries
              .map((entry) => '${entry.key}=${entry.value}')
              .join('; '),
      },
    );
  }

  static void _captureTicketCookies(Headers headers) {
    if (kIsWeb) return;
    for (final header in headers['set-cookie'] ?? const <String>[]) {
      final pair = header.split(';').first;
      final separator = pair.indexOf('=');
      if (separator <= 0) continue;
      final name = pair.substring(0, separator).trim();
      final value = pair.substring(separator + 1).trim();
      if (name.isNotEmpty && value.isNotEmpty) _ticketCookies[name] = value;
    }
  }

  static Map<String, String> parseStationCodes(String script) {
    final result = <String, String>{};
    for (final entry in script.split('@').skip(1)) {
      final fields = entry.split('|');
      if (fields.length < 3) continue;
      final stationName = fields[1].trim();
      final telecode = fields[2].trim().toUpperCase();
      if (stationName.isNotEmpty && telecode.isNotEmpty) {
        result[stationName] = telecode;
      }
    }
    return result;
  }

  static Future<TicketSeatAvailability?> fetchTicketSeatAvailability({
    required String trainNumber,
    required String fromStation,
    required String toStation,
  }) async {
    final stationCodes = await initializeStationCodes();
    final fromCode = stationCodes[fromStation.trim()];
    final toCode = stationCodes[toStation.trim()];
    if (fromCode == null || toCode == null) return null;

    final lookupDates = ticketPriceLookupDates(DateTime.now());
    for (final lookupDate in lookupDates) {
      final availability = await _fetchTicketSeatAvailabilityForDate(
        trainNumber: trainNumber,
        travelDate: lookupDate,
        fromCode: fromCode,
        toCode: toCode,
      );
      if (availability != null) return availability;
    }
    return null;
  }

  static List<DateTime> ticketPriceLookupDates(DateTime now) {
    final chinaNow = now.add(const Duration(hours: 8));
    final tomorrow = DateTime(chinaNow.year, chinaNow.month, chinaNow.day + 1);
    return List.unmodifiable([
      tomorrow,
      DateTime(tomorrow.year, tomorrow.month, tomorrow.day + 1),
    ]);
  }

  static Future<TicketSeatAvailability?> _fetchTicketSeatAvailabilityForDate({
    required String trainNumber,
    required DateTime travelDate,
    required String fromCode,
    required String toCode,
  }) async {
    final formattedDate =
        '${travelDate.year.toString().padLeft(4, '0')}-'
        '${travelDate.month.toString().padLeft(2, '0')}-'
        '${travelDate.day.toString().padLeft(2, '0')}';
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        _ticketCookies.clear();
        _browserSessionInitialized = false;
        await _ensureTicketSession(force: true);
      }
      try {
        final response = await _ticketDio.get<String>(
          'https://kyfw.12306.cn/otn/leftTicket/queryG',
          queryParameters: {
            'leftTicketDTO.train_date': formattedDate,
            'leftTicketDTO.from_station': fromCode,
            'leftTicketDTO.to_station': toCode,
            'purpose_codes': 'ADULT',
          },
          options: _ticketRequestOptions(),
        );
        _captureTicketCookies(response.headers);
        final payload = _decodeTicketPayload(response.data);
        if (response.statusCode != 200 || payload == null) continue;
        final data = payload['data'];
        final rows = data is Map<String, dynamic> ? data['result'] : null;
        if (rows is! List) return null;

        final normalizedTrainNumber = trainNumber.trim().toUpperCase();
        for (final row in rows.whereType<String>()) {
          final fields = row.split('|');
          if (fields.length <= 53 ||
              fields[3].trim().toUpperCase() != normalizedTrainNumber ||
              fields[6] != fromCode || fields[7] != toCode) {
            continue;
          }
          final availability = parseTicketSeatPrices(fields[39], fields[53]);
          return availability.isEmpty ? null : availability;
        }
        return null;
      } on DioException {
        if (attempt == 1) return null;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _decodeTicketPayload(String? rawPayload) {
    final payload = rawPayload?.trimLeft().replaceFirst('\uFEFF', '') ?? '';
    if (!payload.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static TicketSeatAvailability parseTicketSeatPrices(
    String priceString,
    String berthString,
  ) {
    const seatNames = {
      'A': '高级动卧',
      'D': '优选一等座',
      'F': '动卧',
      'H': '一人软包',
      'I': '一等卧',
      'J': '二等卧',
      'M': '一等座',
      'O': '二等座',
      'P': '特等座',
      'Q': '多功能座',
      '1': '硬座',
      '2': '软座',
      '3': '硬卧',
      '4': '软卧',
      '6': '高级软卧',
      '7': '一等软座',
      '8': '二等软座',
      '9': '商务座',
    };
    const berthNames = {'1': '下铺', '2': '中铺', '3': '上铺'};
    final options = <TicketSeatOption>[];
    final seenSeatCodes = <String>{};
    final berthBaseNames = <String>{};
    TicketSeatOption? noSeatOption;

    for (var offset = 0; offset + 10 <= priceString.length; offset += 10) {
      final unit = priceString.substring(offset, offset + 10);
      final seatCode = unit[0].toUpperCase();
      final rawPrice = int.tryParse(unit.substring(1, 6));
      if (rawPrice == null) continue;
      final seatType = seatNames[seatCode] ?? '未知席别($seatCode)';
      final option = TicketSeatOption(
        seatType: seatType,
        price: rawPrice / 10,
        isNoSeat: seenSeatCodes.contains(seatCode),
      );
      if (option.isNoSeat) {
        noSeatOption ??= option;
      } else {
        seenSeatCodes.add(seatCode);
        options.add(option);
      }
    }

    for (var offset = 0; offset + 7 <= berthString.length; offset += 7) {
      final unit = berthString.substring(offset, offset + 7);
      final seatCode = unit[0].toUpperCase();
      final berthCode = unit[1];
      final rawPrice = int.tryParse(unit.substring(2, 7));
      if (rawPrice == null) continue;
      final baseName = seatNames[seatCode] ?? '未知卧铺($seatCode)';
      final berthName = berthNames[berthCode] ?? '未知铺位($berthCode)';
      berthBaseNames.add(baseName);
      options.add(
        TicketSeatOption(
          seatType: baseName,
          price: rawPrice / 10,
          berth: berthName,
        ),
      );
    }

    options.removeWhere(
      (option) =>
          option.berth == null && berthBaseNames.contains(option.seatType),
    );

    final uniqueOptions = <String, TicketSeatOption>{};
    for (final option in options) {
      final key = '${option.seatType}\u0000${option.berth ?? ''}';
      uniqueOptions.putIfAbsent(key, () => option);
    }
    return TicketSeatAvailability(
      seatOptions: List.unmodifiable(uniqueOptions.values),
      noSeatOption: noSeatOption,
    );
  }

  static Future<List<TrainSearchResult>> searchTrains(
    String trainNumber,
    DateTime travelDate,
  ) async {
    final queryDate = trainQueryDate(travelDate, now: DateTime.now());
    final String formattedDate =
        '${queryDate.year}'
        '${queryDate.month.toString().padLeft(2, '0')}'
        '${queryDate.day.toString().padLeft(2, '0')}';

    try {
      // 发起网络请求
      final response = await _dio.get<Map<String, dynamic>>(
        'https://search.12306.cn/search/v1/train/search',
        queryParameters: {'keyword': trainNumber, 'date': formattedDate},
      );

      if (response.statusCode == 200 && response.data != null) {
        final List<dynamic>? dataList = response.data!['data'];

        if (dataList != null) {
          return dataList
              .map(
                (item) =>
                    TrainSearchResult.fromJson(item as Map<String, dynamic>),
              )
              .toList();
        }
      }

      return [];
    } on DioException catch (_) {
      return [];
    }
  }

  static Future<List<TrainScheduleStop>> fetchTrainSchedule(
    String trainNo,
    DateTime travelDate, {
    TimetableSource source = TimetableSource.online,
  }) async {
    if (!source.isOnline) {
      return _fetchHistoricalTrainSchedule(trainNo, source.year!);
    }
    final queryDate = trainQueryDate(travelDate, now: DateTime.now());
    final formattedDate =
        '${queryDate.year}-'
        '${queryDate.month.toString().padLeft(2, '0')}-'
        '${queryDate.day.toString().padLeft(2, '0')}';

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        'https://kyfw.12306.cn/otn/queryTrainInfo/query',
        queryParameters: {
          'leftTicketDTO.train_no': trainNo,
          'leftTicketDTO.train_date': formattedDate,
          'rand_code': '',
        },
      );

      final payload = response.data;
      final schedule = payload?['data']?['data'];
      if (response.statusCode == 200 && schedule is List) {
        return schedule
            .whereType<Map<String, dynamic>>()
            .map(TrainScheduleStop.fromJson)
            .toList();
      }

      return [];
    } on DioException catch (_) {
      return [];
    }
  }

  static Future<List<TrainScheduleStop>> _fetchHistoricalTrainSchedule(
    String trainNumber,
    int year,
  ) async {
    try {
      final response = await ApiClient.instance.dio.get<Map<String, dynamic>>(
        '/api/train-timetables',
        queryParameters: {'trainNumber': trainNumber, 'year': year},
      );
      final stops = response.data?['stops'];
      if (response.statusCode != 200 || stops is! List) return const [];
      return stops
          .whereType<Map<String, dynamic>>()
          .map(TrainScheduleStop.fromJson)
          .toList(growable: false);
    } on DioException catch (_) {
      return const [];
    }
  }

  static Future<List<TrainSearchResult>> searchHistoricalTrains(
    String trainNumberPrefix,
    int year,
  ) async {
    try {
      final response = await ApiClient.instance.dio.get<Map<String, dynamic>>(
        '/api/train-timetables/search',
        queryParameters: {'trainNumber': trainNumberPrefix, 'year': year},
      );
      final trains = response.data?['trains'];
      if (response.statusCode != 200 || trains is! List) return const [];
      return trains
          .whereType<Map<String, dynamic>>()
          .map(TrainSearchResult.fromJson)
          .toList(growable: false);
    } on DioException catch (_) {
      return const [];
    }
  }

  static DateTime trainQueryDate(DateTime selectedDate, {DateTime? now}) {
    final chinaNow = (now ?? DateTime.now()).add(const Duration(hours: 8));
    final today = DateTime(chinaNow.year, chinaNow.month, chinaNow.day);
    final selected = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day,
    );
    final earliest = today.subtract(const Duration(days: 2));
    final latest = today.add(const Duration(days: 21));
    if (selected.isBefore(earliest)) return earliest;
    if (selected.isAfter(latest)) return latest;
    return selected;
  }

  static List<TrainScheduleStop> resolveScheduleDateTimes(
    List<TrainScheduleStop> stops,
    DateTime boardingDate,
    int boardingStopIndex,
  ) {
    if (stops.isEmpty ||
        boardingStopIndex < 0 ||
        boardingStopIndex >= stops.length) {
      return stops;
    }

    final normalizedBoardingDate = DateTime(
      boardingDate.year,
      boardingDate.month,
      boardingDate.day,
    );
    final boardingStop = stops[boardingStopIndex];
    final boardingDayDifference =
        boardingStop.arriveDayDifference +
        (_departsAfterMidnight(boardingStop) ? 1 : 0);
    final originDate = normalizedBoardingDate.subtract(
      Duration(days: boardingDayDifference),
    );

    return stops
        .map((stop) {
          final stopDate = originDate.add(
            Duration(days: stop.arriveDayDifference),
          );
          final departureDate = stopDate.add(
            Duration(days: _departsAfterMidnight(stop) ? 1 : 0),
          );
          return stop.copyWith(
            arrivalDateTime: _combineDateAndTime(stopDate, stop.arriveTime),
            departureDateTime: _combineDateAndTime(
              departureDate,
              stop.startTime,
            ),
          );
        })
        .toList(growable: false);
  }

  static Future<TrainDistanceInfo?> fetchDistanceInfo({
    required String trainNumber,
    required String startStation,
    required String endStation,
  }) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        'https://api.xfkenzify.com:3443/api/train/distance-info',
        data: {
          'trainNumber': trainNumber,
          'startStation': startStation,
          'endStation': endStation,
        },
      );
      final data = response.data;
      final distance = data?['distance'];
      if (response.statusCode == 200 && distance is num) {
        return TrainDistanceInfo.fromJson(data!);
      }
    } on DioException catch (_) {
      return null;
    }
    return null;
  }

  static Future<List<StationPairDistance>> fetchStationPairDistances(
    String trainNumber,
    List<TrainScheduleStop> stops,
    int departureStopIndex,
    int arrivalStopIndex,
  ) async {
    final sectionCount = arrivalStopIndex - departureStopIndex;
    if (sectionCount <= 0) return const [];
    final results = List<StationPairDistance?>.filled(sectionCount, null);
    var nextSection = 0;

    Future<void> worker() async {
      while (true) {
        final sectionOffset = nextSection++;
        if (sectionOffset >= sectionCount) return;
        final fromStop = stops[departureStopIndex + sectionOffset];
        final toStop = stops[departureStopIndex + sectionOffset + 1];
        final distanceInfo = await fetchDistanceInfo(
          trainNumber: trainNumber,
          startStation: fromStop.stationName,
          endStation: toStop.stationName,
        );
        results[sectionOffset] = StationPairDistance(
          fromStation: fromStop.stationName,
          toStation: toStop.stationName,
          distanceKm: distanceInfo?.distance,
        );
      }
    }

    final workerCount = sectionCount.clamp(1, 4);
    await Future.wait(List.generate(workerCount, (_) => worker()));
    return results.whereType<StationPairDistance>().toList(growable: false);
  }

  static Future<RollingStockLookupResult?> fetchRollingStock({
    required String trainNumber,
    required DateTime terminalDate,
  }) async {
    try {
      final response = await _dio.get<dynamic>(
        'https://api.rail.re/train/${Uri.encodeComponent(trainNumber)}',
      );
      final records = _rollingStockRecords(response.data);
      if (response.statusCode != 200 || records.isEmpty) return null;

      records.sort((a, b) => b.date.compareTo(a.date));
      final targetDate = DateTime(
        terminalDate.year,
        terminalDate.month,
        terminalDate.day,
      );
      final matchingRecords = records
          .where((record) => _isSameDate(record.date, targetDate))
          .toList();
      if (matchingRecords.isNotEmpty) {
        return RollingStockLookupResult(
          rollingStock: _formatRollingStocks(matchingRecords),
          usedLatestFallback: false,
          referenceTerminalDate: matchingRecords.first.date,
        );
      }

      final latestDateRecords = records
          .where((record) => _isSameDate(record.date, records.first.date))
          .toList();
      return RollingStockLookupResult(
        rollingStock: _rollingStockModels(latestDateRecords),
        usedLatestFallback: true,
        referenceTerminalDate: records.first.date,
      );
    } on DioException catch (_) {
      return null;
    }
  }

  static bool shouldFetchRollingStock(String trainNumber) {
    return RegExp(
      r'^[GDCS]',
      caseSensitive: false,
    ).hasMatch(trainNumber.trim());
  }

  static DateTime? _combineDateAndTime(DateTime date, String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (match == null) return null;
    return DateTime(
      date.year,
      date.month,
      date.day,
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
    );
  }

  static bool _departsAfterMidnight(TrainScheduleStop stop) {
    final arrivalMinutes = _minutesSinceMidnight(stop.arriveTime);
    final departureMinutes = _minutesSinceMidnight(stop.startTime);
    return arrivalMinutes != null &&
        departureMinutes != null &&
        departureMinutes < arrivalMinutes;
  }

  static int? _minutesSinceMidnight(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
    if (match == null) return null;
    return int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!);
  }

  static List<RollingStockRecord> _rollingStockRecords(dynamic payload) {
    dynamic decodedPayload = payload;
    if (payload is String) {
      try {
        decodedPayload = jsonDecode(payload);
      } on FormatException {
        try {
          decodedPayload = jsonDecode(
            '[${payload.replaceFirst(RegExp(r',\s*$'), '')}]',
          );
        } on FormatException {
          return const [];
        }
      }
    }

    final source = decodedPayload is List
        ? decodedPayload
        : decodedPayload is Map<String, dynamic> &&
              decodedPayload['data'] is List
        ? decodedPayload['data'] as List<dynamic>
        : decodedPayload is Map<String, dynamic> &&
              decodedPayload.containsKey('emu_no')
        ? <dynamic>[decodedPayload]
        : const <dynamic>[];
    return source
        .whereType<Map<String, dynamic>>()
        .map((item) {
          return RollingStockRecord.tryFromJson(item);
        })
        .whereType<RollingStockRecord>()
        .toList();
  }

  static bool _isSameDate(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  static String _formatRollingStock(String value) {
    final normalized = value.trim().toUpperCase();
    final match = RegExp(r'^(.*?)(\d{4})$').firstMatch(normalized);
    if (match == null) return normalized;
    final model = match.group(1)!.replaceFirst(RegExp(r'[-\s]+$'), '');
    return '$model-${match.group(2)}';
  }

  static String _formatRollingStocks(List<RollingStockRecord> records) {
    final emuNumbers = records
        .map((record) => record.emuNumber.trim().toUpperCase())
        .toSet()
        .toList();
    emuNumbers.sort();
    final parsed = emuNumbers.map(_rollingStockParts).toList();
    final models = parsed.map((parts) => parts.$1).toSet();
    if (models.length == 1 && parsed.every((parts) => parts.$2 != null)) {
      final trainSetNumbers = parsed.map((parts) => parts.$2!).toList()..sort();
      final numbers = trainSetNumbers.join('&');
      return '${models.first}-$numbers';
    }
    return emuNumbers.map(_formatRollingStock).join('&');
  }

  static String _rollingStockModels(List<RollingStockRecord> records) {
    return records
        .map((record) => _rollingStockModel(record.emuNumber))
        .toSet()
        .join('&');
  }

  static (String, String?) _rollingStockParts(String value) {
    final normalized = value.trim().toUpperCase();
    final match = RegExp(r'^(.*?)(\d{4})$').firstMatch(normalized);
    if (match == null) return (normalized, null);
    final model = match.group(1)!.replaceFirst(RegExp(r'[-\s]+$'), '');
    return (model, match.group(2));
  }

  static String _rollingStockModel(String value) {
    final normalized = value.trim().toUpperCase();
    return normalized.replaceFirst(RegExp(r'[-\s]?\d{4}$'), '');
  }
}
