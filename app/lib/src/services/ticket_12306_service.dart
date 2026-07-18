import 'dart:convert';
import 'dart:io';

import 'package:raillog/src/models/ticket_12306_order.dart';

class Ticket12306QrCode {
  const Ticket12306QrCode({required this.uuid, required this.imageBase64});

  final String uuid;
  final String imageBase64;
}

class Ticket12306QrStatus {
  const Ticket12306QrStatus({
    required this.code,
    required this.message,
    this.uamtk,
  });

  final String code;
  final String message;
  final String? uamtk;
}

class Ticket12306Exception implements Exception {
  const Ticket12306Exception(this.message);

  final String message;

  @override
  String toString() => message;
}

class Ticket12306Service {
  Ticket12306Service({HttpClient? httpClient})
    : _client = httpClient ?? HttpClient() {
    _client
      ..connectionTimeout = const Duration(seconds: 30)
      ..idleTimeout = const Duration(seconds: 30)
      ..userAgent = _userAgent;
  }

  static const _host = 'kyfw.12306.cn';
  static const _passportBase = 'https://$_host/passport/web';
  static const _otnBase = 'https://$_host/otn';
  static const _loginPage = '$_otnBase/resources/login.html';
  static const _passportRedirect =
      '$_otnBase/passport?redirect=/otn/login/userLogin';
  static const _invoiceIndexPage = '$_otnBase/view/invoice_index.html';
  static const _invoiceListPage =
      '$_otnBase/view/invoice_ticket_list.html?tab_type=1';
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 '
      'Safari/537.36 Edg/146.0.0.0';

  final HttpClient _client;
  final Map<String, Cookie> _cookies = {};
  bool _disposed = false;

  Future<Ticket12306QrCode> createQrCode() async {
    _ensureActive();
    _cookies.clear();
    final json = await _postForm(
      '$_passportBase/create-qr64',
      const {'appid': 'otn'},
      referer: _loginPage,
      accept: '*/*',
    );
    final uuid = _readString(json, 'uuid');
    final image = _readString(json, 'image');
    if (uuid.isEmpty || image.isEmpty) {
      throw const Ticket12306Exception('12306 未返回有效二维码');
    }
    return Ticket12306QrCode(uuid: uuid, imageBase64: image);
  }

  Future<Ticket12306QrStatus> checkQrStatus(String uuid) async {
    final json = await _postForm(
      '$_passportBase/checkqr',
      {'uuid': uuid, 'appid': 'otn'},
      referer: _loginPage,
      accept: '*/*',
    );
    return Ticket12306QrStatus(
      code: _readValue(json, 'result_code'),
      message: _readString(json, 'result_message'),
      uamtk: _nullable(_readString(json, 'uamtk')),
    );
  }

  Future<String> completeLogin(String uamtk) async {
    await _navigate('$_otnBase/login/userLogin', referer: _loginPage);
    _storeCookie(
      Cookie('uamtk', uamtk)
        ..domain = _host
        ..path = '/passport',
    );

    final auth = await _postForm(
      '$_passportBase/auth/uamtk',
      const {'appid': 'otn'},
      referer: _passportRedirect,
      accept: 'application/json, text/javascript, */*; q=0.01',
    );
    if (_readInt(auth, 'result_code') != 0) {
      throw Ticket12306Exception(
        'UAMTK 验证失败：${_readString(auth, 'result_message')}',
      );
    }
    final appToken = _readString(auth, 'newapptk');
    if (appToken.isEmpty) {
      throw const Ticket12306Exception('12306 未返回登录票据');
    }

    final clientAuth = await _postForm(
      '$_otnBase/uamauthclient',
      {'tk': appToken},
      referer: _passportRedirect,
      accept: '*/*',
    );
    if (_readInt(clientAuth, 'result_code') != 0) {
      throw Ticket12306Exception(
        '登录认证失败：${_readString(clientAuth, 'result_message')}',
      );
    }
    await _navigate('$_otnBase/login/userLogin', referer: _passportRedirect);
    return _readString(clientAuth, 'username');
  }

  Future<Ticket12306QrCode> createInvoiceVerificationQr() async {
    await _navigate(_invoiceIndexPage, referer: '$_otnBase/login/userLogin');
    final json = await _postForm(
      '$_passportBase/create-verifyqr64',
      const {'appid': 'otn', 'authType': 'itinerary'},
      referer: _invoiceIndexPage,
      accept: '*/*',
    );
    final uuid = _readString(json, 'uuid');
    final image = _readString(json, 'image');
    if (uuid.isEmpty || image.isEmpty) {
      throw const Ticket12306Exception('12306 未返回有效的电子发票核验二维码');
    }
    return Ticket12306QrCode(uuid: uuid, imageBase64: image);
  }

  Future<Ticket12306QrStatus> checkInvoiceVerificationQr(String uuid) async {
    final json = await _postForm(
      '$_otnBase/psr/checkVerifyqr',
      {'uuid': uuid, 'appid': 'otn'},
      referer: _invoiceIndexPage,
      accept: 'application/json, text/javascript, */*; q=0.01',
    );
    final code = _readValue(json, 'data');
    final message = switch (code) {
      '0' => '等待扫描核验二维码',
      '1' => '已扫描，请在铁路 12306 App 中确认',
      '2' => '电子发票访问核验通过',
      _ => '等待电子发票访问核验',
    };
    return Ticket12306QrStatus(code: code, message: message);
  }

  Future<List<Ticket12306Order>> queryInvoiceTrips({DateTime? now}) async {
    await _prepareInvoiceQuery();
    final today = _dateOnly(now ?? DateTime.now());
    final start = today.subtract(const Duration(days: 179));
    final merged = <String, Ticket12306Order>{};

    for (final type in const [1, 2]) {
      for (final order in await _queryInvoicesByType(start, today, type)) {
        merged[order.id] = order;
      }
    }
    final result = merged.values.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    return result;
  }

  Future<void> _prepareInvoiceQuery() async {
    await _navigate(_invoiceListPage, referer: _invoiceIndexPage);
    final login = await _postForm(
      '$_otnBase/login/conf',
      const {},
      referer: _invoiceListPage,
      accept: '*/*',
    );
    final loginData = login['data'];
    if (login['status'] != true ||
        loginData is! Map ||
        loginData['psr_qr_code_result']?.toString() != 'Y') {
      throw const Ticket12306Exception('电子发票访问核验已失效，请重新扫码');
    }
    final info = await _postForm(
      '$_otnBase/eInvoice/queryInfo',
      const {},
      referer: _invoiceListPage,
      accept: 'application/json, text/javascript, */*; q=0.01',
    );
    if (info['status'] != true) {
      throw const Ticket12306Exception('电子发票服务初始化失败');
    }
  }

  Future<List<Ticket12306Order>> _queryInvoicesByType(
    DateTime start,
    DateTime end,
    int type,
  ) async {
    if (end.isBefore(start)) return const [];
    final result = <Ticket12306Order>[];
    var pageIndex = 1;
    var total = 1 << 30;
    var fetched = 0;

    while (fetched < total) {
      final json = await _postForm(
        '$_otnBase/eInvoice/queryPsr',
        {
          'from_date': _formatCompactDate(start),
          'end_date': _formatCompactDate(end),
          'order_num': '',
          'pageIndex': '$pageIndex',
          'ticket_type': '',
          'type': '$type',
        },
        referer: _invoiceListPage,
        accept: 'application/json, text/javascript, */*; q=0.01',
      );
      if (json['status'] != true) {
        throw Ticket12306Exception('电子发票行程查询失败（type=$type）');
      }
      final data = json['data'];
      if (data is! Map<String, dynamic>) break;
      total = _asInt(data['total']) ?? 0;
      final rows = data['results'];
      if (rows is! List || rows.isEmpty) break;
      for (final rawRow in rows) {
        if (rawRow is! Map) continue;
        final parsed = parseInvoiceTicket(Map<String, dynamic>.from(rawRow));
        if (parsed != null) result.add(parsed);
      }
      fetched += rows.length;
      final returnedPage = _asInt(data['pageIndex']) ?? pageIndex;
      final pageSize = _asInt(data['pageSize']) ?? rows.length;
      if (returnedPage * pageSize >= total) break;
      pageIndex++;
    }
    return result;
  }

  static Ticket12306Order? parseInvoiceTicket(Map<String, dynamic> ticket) {
    final startTime = _parseCompactDateTime(
      _readString(ticket, 'local_start_time'),
    );
    final arriveTime = _parseCompactDateTime(
      _readString(ticket, 'local_arrive_time'),
    );
    if (startTime == null || arriveTime == null) return null;
    final sequenceNo = _readString(ticket, 'sequence_no');
    final trainCode = _readString(ticket, 'board_train_code').isNotEmpty
        ? _readString(ticket, 'board_train_code')
        : _readString(ticket, 'train_code');
    final passengerName = _readString(ticket, 'passenger_name');
    final id = [
      _readString(ticket, 'ext_ticket_no'),
      sequenceNo,
      _readString(ticket, 'batch_no'),
      trainCode,
      startTime.toIso8601String(),
      passengerName,
    ].join('|');

    return Ticket12306Order(
      id: id,
      sequenceNo: sequenceNo,
      startTime: startTime,
      arriveTime: arriveTime,
      trainCode: trainCode,
      fromStation: _readString(ticket, 'from_station_name'),
      toStation: _readString(ticket, 'to_station_name'),
      distance: _parseNumber(_readString(ticket, 'distance')),
      passengerName: passengerName,
      seatType: _readString(ticket, 'seat_type_name'),
      coachName: _readString(ticket, 'coach_name'),
      seatName: _readString(ticket, 'seat_name'),
      price: _parseNumber(_readString(ticket, 'ticket_price')) / 10,
      statusText: _readString(ticket, 'status_name'),
    );
  }

  Future<Map<String, dynamic>> _postForm(
    String url,
    Map<String, String> form, {
    required String referer,
    required String accept,
  }) async {
    _ensureActive();
    final request = await _client.postUrl(Uri.parse(url));
    _prepareRequest(request, referer: referer, accept: accept);
    request.headers.contentType = ContentType(
      'application',
      'x-www-form-urlencoded',
      charset: 'UTF-8',
    );
    request.write(Uri(queryParameters: form).query);
    final response = await request.close();
    return _readJsonResponse(response);
  }

  Future<void> _navigate(String startUrl, {required String referer}) async {
    var current = Uri.parse(startUrl);
    var currentReferer = referer;
    for (var redirects = 0; redirects <= 5; redirects++) {
      final request = await _client.getUrl(current);
      request.followRedirects = false;
      _prepareRequest(
        request,
        referer: currentReferer,
        accept:
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        ajax: false,
      );
      final response = await request.close();
      _captureCookies(response);
      await response.drain<void>();
      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (location == null) {
          throw const Ticket12306Exception('12306 登录跳转响应无效');
        }
        currentReferer = current.toString();
        current = current.resolve(location);
        continue;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Ticket12306Exception('12306 请求失败 (${response.statusCode})');
      }
      return;
    }
    throw const Ticket12306Exception('12306 登录跳转次数过多');
  }

  void _prepareRequest(
    HttpClientRequest request, {
    required String referer,
    required String accept,
    bool ajax = true,
  }) {
    request.headers
      ..set(HttpHeaders.acceptHeader, accept)
      ..set(HttpHeaders.acceptLanguageHeader, 'zh-CN,zh;q=0.9,en;q=0.8')
      ..set(HttpHeaders.refererHeader, referer);
    if (ajax) {
      request.headers
        ..set('Origin', 'https://$_host')
        ..set('X-Requested-With', 'XMLHttpRequest');
    }
    final now = DateTime.now();
    request.cookies.addAll(
      _cookies.values.where(
        (cookie) => cookie.expires == null || cookie.expires!.isAfter(now),
      ),
    );
  }

  Future<Map<String, dynamic>> _readJsonResponse(
    HttpClientResponse response,
  ) async {
    _captureCookies(response);
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Ticket12306Exception('12306 请求失败 (${response.statusCode})');
    }
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Handled below with a stable user-facing message.
    }
    throw const Ticket12306Exception('12306 返回了无效数据');
  }

  void _captureCookies(HttpClientResponse response) {
    for (final cookie in response.cookies) {
      _storeCookie(cookie);
    }
  }

  void _storeCookie(Cookie cookie) {
    final key =
        '${cookie.name}|${cookie.domain ?? _host}|${cookie.path ?? '/'}';
    if (cookie.maxAge == 0 ||
        (cookie.expires != null && cookie.expires!.isBefore(DateTime.now()))) {
      _cookies.remove(key);
    } else {
      _cookies[key] = cookie;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cookies.clear();
    _client.close(force: true);
  }

  void _ensureActive() {
    if (_disposed) throw const Ticket12306Exception('12306 会话已关闭');
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);
  static String _formatCompactDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}';
  static String _readString(Map<String, dynamic> map, String key) =>
      map[key]?.toString().trim() ?? '';
  static String _readValue(Map<String, dynamic> map, String key) =>
      map[key]?.toString() ?? '';
  static int _readInt(Map<String, dynamic> map, String key) =>
      _asInt(map[key]) ?? -1;
  static int? _asInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
  static String? _nullable(String value) => value.isEmpty ? null : value;

  static double _parseNumber(String value) {
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(value);
    final parsed = double.tryParse(match?.group(0) ?? '') ?? 0;
    return parsed < 0 ? 0 : parsed;
  }

  static DateTime? _parseCompactDateTime(String value) {
    if (!RegExp(r'^\d{12}$').hasMatch(value)) return null;
    return DateTime(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(4, 6)),
      int.parse(value.substring(6, 8)),
      int.parse(value.substring(8, 10)),
      int.parse(value.substring(10, 12)),
    );
  }
}
