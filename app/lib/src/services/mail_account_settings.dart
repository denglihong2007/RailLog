import 'package:shared_preferences/shared_preferences.dart';

/// 邮件接收协议。两者都只做「拉取邮件」，不发送、不删除。
enum MailProtocol {
  imap(label: 'IMAP', defaultPort: 993),
  pop3(label: 'POP3', defaultPort: 995);

  const MailProtocol({required this.label, required this.defaultPort});

  final String label;
  final int defaultPort;

  static MailProtocol fromName(String? name) => values.firstWhere(
    (protocol) => protocol.name == name,
    orElse: () => MailProtocol.imap,
  );
}

/// 邮箱连接配置。密码/授权码按项目现有做法保存在本机偏好设置里，
/// 与车票识别密钥一致，不上传服务器。
class MailAccountConfig {
  const MailAccountConfig({
    required this.emailAddress,
    required this.password,
    required this.host,
    required this.port,
    this.protocol = MailProtocol.imap,
    this.useTls = true,
  });

  final String emailAddress;
  final String password;
  final String host;
  final int port;
  final MailProtocol protocol;
  final bool useTls;

  bool get isComplete =>
      emailAddress.trim().isNotEmpty &&
      password.isNotEmpty &&
      host.trim().isNotEmpty &&
      port > 0;

  String get missingSettingsMessage => '请先在设置中配置邮箱连接';

  MailAccountConfig copyWith({
    String? emailAddress,
    String? password,
    String? host,
    int? port,
    MailProtocol? protocol,
    bool? useTls,
  }) => MailAccountConfig(
    emailAddress: emailAddress ?? this.emailAddress,
    password: password ?? this.password,
    host: host ?? this.host,
    port: port ?? this.port,
    protocol: protocol ?? this.protocol,
    useTls: useTls ?? this.useTls,
  );
}

abstract final class MailAccountSettings {
  static const _emailKey = 'mail_account.email';
  static const _passwordKey = 'mail_account.password';
  static const _hostKey = 'mail_account.host';
  static const _portKey = 'mail_account.port';
  static const _protocolKey = 'mail_account.protocol';
  static const _useTlsKey = 'mail_account.use_tls';

  static Future<MailAccountConfig?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final email = preferences.getString(_emailKey) ?? '';
    final password = preferences.getString(_passwordKey) ?? '';
    final host = preferences.getString(_hostKey) ?? '';
    if (email.trim().isEmpty && password.isEmpty && host.trim().isEmpty) {
      return null;
    }
    final protocol = MailProtocol.fromName(preferences.getString(_protocolKey));
    final port = preferences.getInt(_portKey) ?? 0;
    return MailAccountConfig(
      emailAddress: email,
      password: password,
      host: host,
      port: port > 0 ? port : protocol.defaultPort,
      protocol: protocol,
      useTls: preferences.getBool(_useTlsKey) ?? true,
    );
  }

  static Future<void> save(MailAccountConfig config) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setString(_emailKey, config.emailAddress.trim()),
      preferences.setString(_passwordKey, config.password),
      preferences.setString(_hostKey, config.host.trim()),
      preferences.setInt(_portKey, config.port),
      preferences.setString(_protocolKey, config.protocol.name),
      preferences.setBool(_useTlsKey, config.useTls),
    ]);
  }

  static Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.remove(_emailKey),
      preferences.remove(_passwordKey),
      preferences.remove(_hostKey),
      preferences.remove(_portKey),
      preferences.remove(_protocolKey),
      preferences.remove(_useTlsKey),
    ]);
  }

  /// 常见邮箱的服务器地址。识别不出来时返回 null，由用户自行填写。
  static String? suggestHost(String emailAddress, MailProtocol protocol) {
    final at = emailAddress.lastIndexOf('@');
    if (at < 0 || at == emailAddress.length - 1) return null;
    final domain = emailAddress.substring(at + 1).trim().toLowerCase();
    final prefix = protocol == MailProtocol.imap ? 'imap' : 'pop';
    return switch (domain) {
      'qq.com' || 'foxmail.com' || 'vip.qq.com' => '$prefix.qq.com',
      '163.com' || 'vip.163.com' => '$prefix.163.com',
      '126.com' || 'vip.126.com' => '$prefix.126.com',
      'yeah.net' => '$prefix.yeah.net',
      'sina.com' || 'sina.cn' || 'vip.sina.com' => '$prefix.sina.com',
      'outlook.com' ||
      'hotmail.com' ||
      'live.com' ||
      'msn.com' => 'outlook.office365.com',
      'gmail.com' || 'googlemail.com' => '$prefix.gmail.com',
      'icloud.com' || 'me.com' || 'mac.com' => '$prefix.mail.me.com',
      '139.com' => '$prefix.139.com',
      '189.cn' => '$prefix.189.cn',
      'aliyun.com' =>
        protocol == MailProtocol.imap ? 'imap.aliyun.com' : 'pop3.aliyun.com',
      'sohu.com' =>
        protocol == MailProtocol.imap ? 'imap.sohu.com' : 'pop3.sohu.com',
      '21cn.com' => '$prefix.21cn.com',
      'yahoo.com' => '$prefix.mail.yahoo.com',
      _ => null,
    };
  }

  /// 兼容旧调用方：默认按 IMAP 推断。
  static String? suggestImapHost(String emailAddress) =>
      suggestHost(emailAddress, MailProtocol.imap);
}
