import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/oauth_consent.dart';

void main() {
  test('parses an OAuth consent response', () {
    final consent = OAuthConsent.fromJson({
      'clientId': 'rk_test',
      'name': '万花筒 RailKale',
      'logoUrl': 'https://www.raillog.top/partners/railkale.png',
      'scopes': ['profile'],
      'createdAt': '2026-11-22T12:00:00+08:00',
    });

    expect(consent.clientId, 'rk_test');
    expect(consent.name, '万花筒 RailKale');
    expect(consent.logoUrl, 'https://www.raillog.top/partners/railkale.png');
    expect(consent.scopeLabel, '账号 ID、昵称和头像');
    expect(consent.createdAt.toUtc(), DateTime.utc(2026, 11, 22, 4));
  });

  test('tolerates missing logo and scopes', () {
    final consent = OAuthConsent.fromJson({
      'clientId': 'rk_x',
      'name': 'X',
      'createdAt': '2026-11-22T00:00:00Z',
    });

    expect(consent.logoUrl, isNull);
    expect(consent.scopes, isEmpty);
    expect(consent.scopeLabel, isEmpty);
  });
}
