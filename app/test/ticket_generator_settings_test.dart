import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/services/db_helper.dart';
import 'package:raillog/src/services/ticket_generator_settings.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('车票生成器使用规定的默认设置并持久化修改', () async {
    await DbHelper.instance.database;
    await DbHelper.instance.setSetting('ticket_display_style', null);
    await DbHelper.instance.setSetting('ticket_default_passenger', null);
    await DbHelper.instance.setSetting('ticket_masked_id', null);
    await DbHelper.instance.setSetting('ticket_serial_prefix', null);
    await DbHelper.instance.setSetting('ticket_show_new_air_conditioned', null);

    await TicketGeneratorSettings.instance.initialize();
    expect(
      TicketGeneratorSettings.instance.displayStyle,
      TicketDisplayStyle.red,
    );
    expect(TicketGeneratorSettings.instance.passenger, '川建国');
    expect(TicketGeneratorSettings.instance.maskedId, '1101021946****001X');
    expect(TicketGeneratorSettings.instance.serialPrefix, '45413310010226');
    expect(TicketGeneratorSettings.instance.showNewAirConditioned, isFalse);

    await TicketGeneratorSettings.instance.setDisplayStyle(
      TicketDisplayStyle.blue,
    );
    await TicketGeneratorSettings.instance.setPassenger('测试乘车人');
    await TicketGeneratorSettings.instance.setMaskedId('1234****5678');
    await TicketGeneratorSettings.instance.setSerialPrefix('12345678901234');
    await TicketGeneratorSettings.instance.setShowNewAirConditioned(true);

    expect(await DbHelper.instance.getSetting('ticket_display_style'), 'blue');
    expect(
      await DbHelper.instance.getSetting('ticket_default_passenger'),
      '测试乘车人',
    );
    expect(
      await DbHelper.instance.getSetting('ticket_masked_id'),
      '1234****5678',
    );
    expect(
      await DbHelper.instance.getSetting('ticket_serial_prefix'),
      '12345678901234',
    );
    expect(
      await DbHelper.instance.getSetting('ticket_show_new_air_conditioned'),
      'true',
    );
  });

  test('无效票号前缀不会覆盖已保存值', () async {
    await TicketGeneratorSettings.instance.setSerialPrefix('123');

    expect(TicketGeneratorSettings.instance.serialPrefix, '12345678901234');
  });
}
