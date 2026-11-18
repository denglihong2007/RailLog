import 'dart:convert';
import 'dart:io';

import 'package:raillog/src/models/ticket_12306_order.dart';
import 'package:raillog/src/services/ticket_12306_crypto.dart';

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

/// 凭证失效。导入页据此把用户引到设置页重新扫码。
class Ticket12306AuthException extends Ticket12306Exception {
  const Ticket12306AuthException(super.message);
}

/// 12306 账号登录失败时的用户可读提示。
String describeTicket12306LoginFailure(int code, String message) {
  final text = message.trim();
  if (code == 101) {
    return text.isEmpty ? '密码太久没有修改，请先在 12306 修改密码' : text;
  }
  if (const {91, 92, 94, 95, 97}.contains(code)) {
    return '该账号还需要额外身份验证，请改用扫码登录';
  }
  return text.isEmpty ? '账号或密码错误' : text;
}

/// 服务端返回的凭证有效性。两个凭证分开判断。
class Ticket12306CredentialState {
  const Ticket12306CredentialState({
    required this.loginValid,
    required this.invoiceVerified,
    this.username = '',
  });

  final bool loginValid;
  final bool invoiceVerified;
  final String username;
}

/// 本人车票查询的日期窗口。接口单次查询的跨度有限，需要分段。
class Ticket12306DateWindow {
  const Ticket12306DateWindow(this.start, this.end);

  final DateTime start;
  final DateTime end;
}

/// 可持久化的 Cookie。`dart:io` 的 [Cookie] 不能直接序列化。
class Ticket12306Cookie {
  const Ticket12306Cookie({
    required this.name,
    required this.value,
    this.domain = '',
    this.path = '/',
    this.expires,
    this.secure = false,
  });

  final String name;
  final String value;
  final String domain;
  final String path;
  final DateTime? expires;
  final bool secure;

  bool get isExpired => expires != null && !expires!.isAfter(DateTime.now());

  Map<String, dynamic> toJson() => {
    'name': name,
    'value': value,
    if (domain.isNotEmpty) 'domain': domain,
    if (path.isNotEmpty) 'path': path,
    if (expires != null) 'expires': expires!.toUtc().toIso8601String(),
    if (secure) 'secure': true,
  };

  static Ticket12306Cookie? fromJson(Object? value) {
    if (value is! Map) return null;
    final name = value['name']?.toString().trim() ?? '';
    if (name.isEmpty) return null;
    return Ticket12306Cookie(
      name: name,
      value: value['value']?.toString() ?? '',
      domain: value['domain']?.toString() ?? '',
      path: value['path']?.toString() ?? '/',
      expires: DateTime.tryParse(value['expires']?.toString() ?? ''),
      secure: value['secure'] == true,
    );
  }
}

/// 12306 会话凭证：登录 Cookie 与人证核验状态。
class Ticket12306Credentials {
  const Ticket12306Credentials({
    required this.username,
    required this.cookies,
    required this.loginAt,
    this.invoiceVerified = false,
  });

  final String username;
  final List<Ticket12306Cookie> cookies;

  /// 扫码登录的时间。后续查询只刷新 Cookie，不改这个时间。
  final DateTime loginAt;
  final bool invoiceVerified;

  bool get isComplete => cookies.any((cookie) => !cookie.isExpired);

  Map<String, dynamic> toJson() => {
    'version': 1,
    'username': username,
    'login_at': loginAt.toUtc().toIso8601String(),
    'invoice_verified': invoiceVerified,
    'cookies': [for (final cookie in cookies) cookie.toJson()],
  };

  static Ticket12306Credentials? fromJson(Object? value) {
    if (value is! Map) return null;
    final cookies = <Ticket12306Cookie>[];
    final rawCookies = value['cookies'];
    if (rawCookies is List) {
      for (final rawCookie in rawCookies) {
        final cookie = Ticket12306Cookie.fromJson(rawCookie);
        if (cookie != null) cookies.add(cookie);
      }
    }
    if (cookies.isEmpty) return null;
    return Ticket12306Credentials(
      username: value['username']?.toString() ?? '',
      cookies: cookies,
      loginAt:
          DateTime.tryParse(value['login_at']?.toString() ?? '') ??
          DateTime.now(),
      invoiceVerified: value['invoice_verified'] == true,
    );
  }
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
  static const _trainOrderPage = '$_otnBase/view/train_order.html';
  static const _personalTravelPage = '$_otnBase/view/personal_travel.html';
  static const _orderPageSize = 8;
  static const _personalTripTotalDays = 365;
  static const _personalTripWindowDays = 180;
  static const _userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 '
      'Safari/537.36 Edg/146.0.0.0';

  final HttpClient _client;
  final Map<String, Cookie> _cookies = {};
  String? _username;
  bool _disposed = false;

  bool get hasSession => _cookies.isNotEmpty;

  String? get username => _username;

  /// 恢复持久化的会话凭证。过期 Cookie 会被丢弃。
  bool restoreCredentials(Ticket12306Credentials credentials) {
    _ensureActive();
    _cookies.clear();
    final name = credentials.username.trim();
    _username = name.isEmpty ? null : name;
    final now = DateTime.now();
    for (final item in credentials.cookies) {
      if (item.expires != null && !item.expires!.isAfter(now)) continue;
      final cookie = Cookie(item.name, item.value)
        ..domain = item.domain.isEmpty ? _host : item.domain
        ..path = item.path.isEmpty ? '/' : item.path
        ..secure = item.secure;
      if (item.expires != null) cookie.expires = item.expires;
      _storeCookie(cookie);
    }
    return _cookies.isNotEmpty;
  }

  /// 导出当前会话，用于持久化。只保留未过期的 Cookie。
  Ticket12306Credentials exportCredentials({
    required bool invoiceVerified,
    DateTime? loginAt,
  }) {
    final now = DateTime.now();
    return Ticket12306Credentials(
      username: _username ?? '',
      cookies: [
        for (final cookie in _cookies.values)
          if (cookie.expires == null || cookie.expires!.isAfter(now))
            Ticket12306Cookie(
              name: cookie.name,
              value: cookie.value,
              domain: cookie.domain ?? _host,
              path: cookie.path ?? '/',
              expires: cookie.expires,
              secure: cookie.secure,
            ),
      ],
      loginAt: loginAt ?? now,
      invoiceVerified: invoiceVerified,
    );
  }

  void clearSession() {
    _cookies.clear();
    _username = null;
  }

  Future<Ticket12306QrCode> createQrCode() async {
    _ensureActive();
    _cookies.clear();
    _username = null;
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
    final username = _readString(clientAuth, 'username');
    _username = username.isEmpty ? null : username;
    return username;
  }

  /// 检查账号登录前是否还需要短信 / 滑块验证。
  /// 返回 0 表示可直接登录，3 表示需要短信验证，其余值暂不支持。
  Future<String> checkLoginVerify(String username) async {
    _ensureActive();
    _cookies.clear();
    _username = null;
    await _navigate(_loginPage, referer: '$_otnBase/');
    final json = await _postForm(
      '$_passportBase/checkLoginVerify',
      {'username': username.trim(), 'appid': 'otn'},
      referer: _loginPage,
      accept: '*/*',
    );
    final message = _readString(json, 'result_message');
    if (_readInt(json, 'result_code') != 0) {
      throw Ticket12306Exception(message.isEmpty ? '无法检查账号登录状态' : message);
    }
    return _readValue(json, 'login_check_code');
  }

  /// 发送短信验证码。[idSuffix] 是账号绑定证件号的后四位。
  Future<void> requestSmsCode({
    required String username,
    required String idSuffix,
  }) async {
    final json = await _postForm(
      '$_passportBase/getMessageCode',
      {'appid': 'otn', 'username': username.trim(), 'castNum': idSuffix.trim()},
      referer: _loginPage,
      accept: '*/*',
    );
    final message = _readString(json, 'result_message');
    if (_readInt(json, 'result_code') != 0) {
      throw Ticket12306Exception(message.isEmpty ? '短信验证码发送失败' : message);
    }
  }

  /// 账号密码登录。成功时返回后续统一认证需要的 UAMTK。
  Future<String> loginWithPassword(
    String username,
    String password, {
    String smsCode = '',
  }) async {
    _ensureActive();
    final json = await _postForm(
      '$_passportBase/login',
      {
        'sessionId': '',
        'sig': '',
        'if_check_slide_passcode_token': '',
        'scene': '',
        'checkMode': smsCode.isEmpty ? '' : '0',
        'randCode': smsCode.trim(),
        'username': username.trim(),
        'password': encryptTicket12306Password(password),
        'appid': 'otn',
      },
      referer: _loginPage,
      accept: 'application/json, text/javascript, */*; q=0.01',
    );
    final code = _readInt(json, 'result_code');
    if (code != 0) {
      throw Ticket12306AuthException(
        describeTicket12306LoginFailure(
          code,
          _readString(json, 'result_message'),
        ),
      );
    }
    final uamtk = _readString(json, 'uamtk');
    if (uamtk.isEmpty) {
      throw const Ticket12306Exception('登录成功，但未获得登录票据');
    }
    return uamtk;
  }

  /// 向服务端确认登录凭证与人证核验凭证是否仍然有效。
  Future<Ticket12306CredentialState> checkCredentials() async {
    _ensureActive();
    // 电子发票列表页的登录配置里同时带有 is_login 与 psr_qr_code_result。
    await _navigate(_invoiceListPage, referer: _invoiceIndexPage);
    final json = await _postForm(
      '$_otnBase/login/conf',
      const {},
      referer: _invoiceListPage,
      accept: '*/*',
    );
    final data = json['data'];
    final map = data is Map
        ? Map<String, dynamic>.from(data)
        : const <String, dynamic>{};
    final loginValid =
        json['status'] == true && map['is_login']?.toString() == 'Y';
    final invoiceVerified =
        loginValid && map['psr_qr_code_result']?.toString() == 'Y';
    final name = _readString(map, 'name');
    if (name.isNotEmpty) _username = name;
    return Ticket12306CredentialState(
      loginValid: loginValid,
      invoiceVerified: invoiceVerified,
      username: name,
    );
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
      throw const Ticket12306AuthException('无法获取人证核验二维码，登录凭证可能已失效');
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
      '2' => '人证核验通过',
      _ => '等待人证核验',
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

  /// 查询普通订单行程，仅需登录，无需人证核验。
  Future<List<Ticket12306Order>> queryOrderTrips({DateTime? now}) async {
    await _navigate(_trainOrderPage, referer: '$_otnBase/login/userLogin');
    final today = _dateOnly(now ?? DateTime.now());
    final start = _minusOneMonth(today);
    final merged = <String, Ticket12306Order>{};

    for (final queryWhere in const ['H', 'G']) {
      final end = queryWhere == 'H'
          ? today.subtract(const Duration(days: 1))
          : today;
      for (final order in await _queryOrdersByType(start, end, queryWhere)) {
        merged[order.dedupKey] = order;
      }
    }
    final result = merged.values.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    return result;
  }

  /// 查询「本人车票」。需要与人证核验相同的第二凭证。
  ///
  /// 单次查询的日期跨度有限，按 180 天分段；最多回溯一年，并逐页取完。
  Future<List<Ticket12306Order>> queryPersonalTrips({DateTime? now}) async {
    final windows = buildPersonalTripWindows(now ?? DateTime.now());
    await _navigate(_personalTravelPage, referer: '$_otnBase/login/userLogin');
    await _ensureIdentityVerified(_personalTravelPage);

    final merged = <String, Ticket12306Order>{};
    for (final window in windows) {
      for (final ticketType in const [1, 3]) {
        for (final order in await _queryPersonalWindow(window, ticketType)) {
          merged[order.id] = order;
        }
      }
    }
    final result = merged.values.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
    return result;
  }

  /// 把最近一年切成不超过 180 天的查询窗口，避免超过接口的日期跨度上限。
  static List<Ticket12306DateWindow> buildPersonalTripWindows(
    DateTime now, {
    int totalDays = _personalTripTotalDays,
    int maxWindowDays = _personalTripWindowDays,
  }) {
    if (totalDays <= 0 || maxWindowDays <= 0) return const [];
    final today = _dateOnly(now);
    final earliest = today.subtract(Duration(days: totalDays - 1));
    final windows = <Ticket12306DateWindow>[];
    var end = today;
    while (!end.isBefore(earliest)) {
      final candidate = end.subtract(Duration(days: maxWindowDays - 1));
      final start = candidate.isBefore(earliest) ? earliest : candidate;
      windows.add(Ticket12306DateWindow(start, end));
      if (!start.isAfter(earliest)) break;
      end = start.subtract(const Duration(days: 1));
    }
    return windows;
  }

  Future<List<Ticket12306Order>> _queryPersonalWindow(
    Ticket12306DateWindow window,
    int ticketType,
  ) async {
    final result = <Ticket12306Order>[];
    var pageIndex = 1;
    var total = 1 << 30;
    var fetched = 0;

    while (fetched < total) {
      final json = await _postForm(
        '$_otnBase/psr/query',
        {
          'from_date': _formatCompactDate(window.start),
          'end_date': _formatCompactDate(window.end),
          'order_num': '',
          'pageIndex': '$pageIndex',
          'ticket_type': '$ticketType',
        },
        referer: _personalTravelPage,
        accept: 'application/json, text/javascript, */*; q=0.01',
      );
      if (json['status'] != true) {
        throw const Ticket12306AuthException('本人车票查询失败，人证核验可能已失效');
      }
      final data = json['data'];
      if (data is! Map) break;
      final psr = data['psr'];
      if (psr is! Map) break;
      total = _asInt(psr['total']) ?? 0;
      final rows = psr['results'];
      if (rows is! List || rows.isEmpty) break;
      for (final rawRow in rows) {
        if (rawRow is! Map) continue;
        final parsed = parsePersonalTicket(Map<String, dynamic>.from(rawRow));
        if (parsed != null) result.add(parsed);
      }
      fetched += rows.length;
      final pageSize = _asInt(psr['pageSize']) ?? rows.length;
      if (pageSize <= 0) break;
      if (pageIndex * pageSize >= total) break;
      pageIndex++;
    }
    return result;
  }

  static Ticket12306Order? parsePersonalTicket(Map<String, dynamic> ticket) {
    final startTime = _parsePersonalDateTime(
      _readString(ticket, 'local_start_time'),
      _readString(ticket, 'start_date'),
      _readString(ticket, 'start_time'),
    );
    if (startTime == null) return null;
    final arriveTime = _parsePersonalDateTime(
      _readString(ticket, 'local_arrive_time'),
      _readString(ticket, 'arrive_date'),
      _readString(ticket, 'arrive_time'),
    );
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

  static DateTime? _parsePersonalDateTime(
    String local,
    String date,
    String time,
  ) {
    final compact = _parseCompactDateTime(local);
    if (compact != null) return compact;
    final spaced = _parseSpaceDateTime('$date $time');
    if (spaced != null) return spaced;
    if (!RegExp(r'^\d{8}$').hasMatch(date)) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(time.trim());
    if (match == null) return null;
    return DateTime(
      int.parse(date.substring(0, 4)),
      int.parse(date.substring(4, 6)),
      int.parse(date.substring(6, 8)),
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
    );
  }

  Future<List<Ticket12306Order>> _queryOrdersByType(
    DateTime start,
    DateTime end,
    String queryWhere,
  ) async {
    if (end.isBefore(start)) return const [];
    final result = <Ticket12306Order>[];
    var pageIndex = 0;
    var total = 1 << 30;

    while (pageIndex * _orderPageSize < total) {
      final json = await _postForm(
        '$_otnBase/queryOrder/queryMyOrder',
        {
          'come_from_flag': 'my_order',
          'pageIndex': '$pageIndex',
          'pageSize': '$_orderPageSize',
          'query_where': queryWhere,
          'queryStartDate': _formatDate(start),
          'queryEndDate': _formatDate(end),
          'queryType': '1',
          'sequeue_train_name': '',
        },
        referer: _trainOrderPage,
        accept: 'application/json, text/javascript, */*; q=0.01',
      );
      if (json['status'] != true) {
        throw Ticket12306AuthException(
          '12306 订单查询失败（query_where=$queryWhere），登录凭证可能已失效',
        );
      }
      final data = json['data'];
      if (data is! Map) break;
      final reportedTotal = _asInt(data['order_total_number']);
      if (reportedTotal != null && reportedTotal > 0) {
        total = reportedTotal;
      }
      final orders = data['OrderDTODataList'];
      if (orders is! List || orders.isEmpty) break;

      var currentCount = 0;
      for (final rawOrder in orders) {
        if (rawOrder is! Map) continue;
        currentCount++;
        final order = Map<String, dynamic>.from(rawOrder);
        final sequenceNo = _readString(order, 'sequence_no');
        final tickets = order['tickets'];
        if (tickets is! List) continue;
        for (final rawTicket in tickets) {
          if (rawTicket is! Map) continue;
          final parsed = parseOrderTicket(
            Map<String, dynamic>.from(rawTicket),
            sequenceNo: sequenceNo,
          );
          if (parsed != null) result.add(parsed);
        }
      }
      if (currentCount < _orderPageSize) break;
      pageIndex++;
    }
    return result;
  }

  Future<void> _ensureIdentityVerified(String referer) async {
    final login = await _postForm(
      '$_otnBase/login/conf',
      const {},
      referer: referer,
      accept: '*/*',
    );
    final loginData = login['data'];
    if (login['status'] != true ||
        loginData is! Map ||
        loginData['psr_qr_code_result']?.toString() != 'Y') {
      throw const Ticket12306AuthException('人证核验已失效，请前往设置重新核验');
    }
  }

  Future<void> _prepareInvoiceQuery() async {
    await _navigate(_invoiceListPage, referer: _invoiceIndexPage);
    await _ensureIdentityVerified(_invoiceListPage);
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
        throw Ticket12306AuthException('电子发票行程查询失败（type=$type）');
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

  static Ticket12306Order? parseOrderTicket(
    Map<String, dynamic> ticket, {
    String sequenceNo = '',
  }) {
    final startTime = _parseSpaceDateTime(
      _readString(ticket, 'start_train_date_page'),
    );
    if (startTime == null) return null;

    final stationTrain = ticket['stationTrainDTO'];
    final station = stationTrain is Map
        ? Map<String, dynamic>.from(stationTrain)
        : const <String, dynamic>{};
    final passenger = ticket['passengerDTO'];
    final passengerMap = passenger is Map
        ? Map<String, dynamic>.from(passenger)
        : const <String, dynamic>{};

    final trainCode = _readString(station, 'station_train_code');
    final passengerName = _readString(passengerMap, 'passenger_name');
    final coachName = _readString(ticket, 'coach_name');
    final seatName = _readString(ticket, 'seat_name');
    final arriveTime = _parseSpaceDateTime(
      '${_readString(station, 'arrive_date_local')} '
      '${_readString(station, 'arrive_time_local')}',
    );
    final orderNo = sequenceNo.trim();

    return Ticket12306Order(
      id: [
        orderNo,
        trainCode,
        startTime.toIso8601String(),
        passengerName,
        coachName,
        seatName,
      ].join('|'),
      sequenceNo: orderNo,
      startTime: startTime,
      arriveTime: arriveTime,
      trainCode: trainCode,
      fromStation: _readString(station, 'from_station_name'),
      toStation: _readString(station, 'to_station_name'),
      distance: _parseNumber(_readString(station, 'distance')),
      passengerName: passengerName,
      seatType: _readString(ticket, 'seat_type_name'),
      coachName: coachName,
      seatName: seatName,
      price: _parseNumber(_readString(ticket, 'str_ticket_price_page')),
      statusText: _readString(ticket, 'ticket_status_name'),
    );
  }

  /// 合并两个来源的行程：同一张票以 [extra]（信息更全的来源）为准。
  static List<Ticket12306Order> mergeTrips(
    List<Ticket12306Order> base,
    List<Ticket12306Order> extra,
  ) {
    final merged = <String, Ticket12306Order>{
      for (final order in base) order.dedupKey: order,
    };
    for (final order in extra) {
      merged[order.dedupKey] = order;
    }
    return merged.values.toList()
      ..sort((a, b) => b.startTime.compareTo(a.startTime));
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
  static DateTime _minusOneMonth(DateTime value) =>
      DateTime(value.year, value.month - 1, value.day);
  static String _formatDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
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

  /// 解析 `yyyy-MM-dd HH:mm`（订单接口）及 `yyyy年M月d日 HH:mm` 等变体。
  static DateTime? _parseSpaceDateTime(String value) {
    final normalized = value
        .trim()
        .replaceAll('年', '-')
        .replaceAll('月', '-')
        .replaceAll('日', ' ')
        .replaceAll('/', '-');
    final match = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2})[ T]+(\d{1,2}):(\d{2})',
    ).firstMatch(normalized);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
    );
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
