import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/services/ticket_12306_crypto.dart';

void main() {
  test('SM4-ECB matches the vector from the 12306 login page', () {
    expect(
      sm4EncryptEcbBase64('1234', '1234567890123456'),
      'woPrxebr8Xvyo1qG8QxAUA==',
    );
  });

  test('password payload keeps the @ prefix and fixed key encryption', () {
    final encrypted = encryptTicket12306Password('1234');

    expect(encrypted, startsWith('@'));
    expect(encrypted, isNot(contains('1234')));
    expect(encrypted, '@${sm4EncryptEcbBase64('1234', 'tiekeyuankp12306')}');
  });
}
