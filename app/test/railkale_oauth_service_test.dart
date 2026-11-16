import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/services/railkale_oauth_service.dart';

void main() {
  final service = RailKaleOAuthService.instance;

  group('RailKale OAuth 链接解析', () {
    test('从标准链接中取出密钥', () {
      final uri = Uri.parse(
        'raillog://oauth/rk/5fb2e0001b9497f01f82f88cb03f9461'
        '122fb3f7480bbf14d4888b06a8288513',
      );
      expect(
        service.extractKey(uri),
        '5fb2e0001b9497f01f82f88cb03f9461122fb3f7480bbf14d4888b06a8288513',
      );
    });

    test('路径层级不足时返回 null', () {
      expect(service.extractKey(Uri.parse('raillog://oauth/rk')), isNull);
      expect(service.extractKey(Uri.parse('raillog://oauth')), isNull);
    });

    test('路径前缀不是 rk 时返回 null', () {
      expect(
        service.extractKey(Uri.parse('raillog://oauth/other/abc')),
        isNull,
      );
    });

    test('密钥为空时返回 null', () {
      expect(service.extractKey(Uri.parse('raillog://oauth/rk/')), isNull);
      expect(service.extractKey(Uri.parse('raillog://oauth/rk/%20')), isNull);
    });

    test('带查询参数不影响解析', () {
      final uri = Uri.parse('raillog://oauth/rk/abcdef123?foo=bar');
      expect(service.extractKey(uri), 'abcdef123');
    });

    test('非本服务的链接会被忽略', () {
      // 这些链接不应触发任何网络请求，handleUri 内部会直接返回
      expect(
        () => service.handleUri(Uri.parse('https://example.com/oauth/rk/abc')),
        returnsNormally,
      );
      expect(
        () => service.handleUri(Uri.parse('raillog://other/rk/abc')),
        returnsNormally,
      );
    });
  });

  group('常量约定', () {
    test('万花筒服务器地址固定', () {
      expect(
        RailKaleOAuthService.railKaleBaseUrl,
        'https://next.laide.net.cn/api/v3',
      );
    });

    test('跳回万花筒的 scheme 与对方一致', () {
      expect(RailKaleOAuthService.railKaleScheme, 'railkale');
    });
  });
}
