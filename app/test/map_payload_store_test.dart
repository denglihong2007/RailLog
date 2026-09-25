import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/services/map_payload_store.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('raillog_payload'));
  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  MapPayloadStore createStore() =>
      MapPayloadStore(resolveDirectory: () async => temp);

  test('写入 html 并返回可交给 file:// 的路径', () async {
    final store = createStore();
    final file = await store.write('<html>甲</html>');

    expect(file, isNotNull);
    expect(file!.parent.path, endsWith('raillog_map'));
    expect(file.readAsStringSync(), '<html>甲</html>');
    expect(Uri.file(file.path).toString(), startsWith('file:///'));
    // 插件内部也是 Uri.file(...) 规整，两端对同一个路径得到同一个 URL
    expect(Uri.file(file.path).toString(), endsWith('.html'));
  });

  test('每次写入都是新文件，避免 WebView 命中旧内容', () async {
    final store = createStore();
    final first = await store.write('第一次');
    final second = await store.write('第二次');

    expect(first!.path, isNot(second!.path));
    expect(second.readAsStringSync(), '第二次');
  });

  test('有新请求排队时，过期的写入返回 null', () async {
    final store = createStore();
    final stale = store.write('旧');
    final fresh = store.write('新');

    expect(await stale, isNull);
    expect((await fresh)!.readAsStringSync(), '新');
  });

  test('清理旧文件，但保留当前文件和刚写入的文件', () async {
    final store = createStore();
    final current = (await store.write('当前'))!;
    final directory = current.parent;

    final stale = File('${directory.path}/map_old.html')
      ..writeAsStringSync('旧')
      ..setLastModifiedSync(
        DateTime.now().subtract(const Duration(minutes: 2)),
      );
    // 当前文件虽然也是「早先写的」，但正在显示，不能被删掉
    current.setLastModifiedSync(
      DateTime.now().subtract(const Duration(minutes: 2)),
    );

    final next = await store.write('下一份');

    expect(next, isNotNull);
    expect(stale.existsSync(), isFalse, reason: '过期文件应被清掉');
    expect(current.existsSync(), isTrue, reason: '正在显示的文件不能被删');
    expect(next!.existsSync(), isTrue);
  });

  test('dispose 删除当前文件', () async {
    final store = createStore();
    final file = (await store.write('地图'))!;

    store.dispose();

    expect(file.existsSync(), isFalse);
  });
}
