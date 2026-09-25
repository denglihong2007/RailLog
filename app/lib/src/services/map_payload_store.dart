import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 把地图 HTML 落成临时文件，供 WebView 用 `file://` 加载。
///
/// 两个平台都不能直接把大段 HTML 交给 WebView：
///
/// * Windows：`webview_windows` 的 `loadStringContent` 落到 WebView2 的
///   `NavigateToString`，上限 1.5 MiB（1,572,864 个 UTF-8 字节，实测恰好到这个数
///   就被拒），超了它返回错误码、而插件把这个返回码丢掉了（既不导航也不报错），
///   页面停在 `about:blank`，看起来就是一片空白。
/// * 安卓：`loadHtmlString` 落到 `loadDataWithBaseURL`，HTML 要当 data URL 经 Binder
///   送进渲染进程，事务上限约 1 MB，超了同样是「不显示、不报错」。
///
/// 落盘后用 `file://` 加载没有这个上限：Windows 上实测 11 MB 的地图能正常渲染。
/// 代价是行程数据会短暂出现在用户自己的临时目录里，退出时删除、其余按时间清理。
class MapPayloadStore {
  MapPayloadStore({Future<Directory> Function()? resolveDirectory})
    : _resolveDirectory = resolveDirectory ?? getTemporaryDirectory,
      _runId = DateTime.now().microsecondsSinceEpoch.toString();

  final Future<Directory> Function() _resolveDirectory;

  /// 每个 store 一个前缀，避免同一路径被 WebView 当成缓存命中旧内容。
  final String _runId;

  File? _current;
  int _seq = 0;
  int _requested = 0;

  /// 写入一份 HTML，返回可交给 `file://` 的文件；期间若已有更新的请求排队，
  /// 说明这份内容已经过时，返回 null 表示调用方不必再导航。
  Future<File?> write(String html) async {
    final request = ++_requested;
    final directory = Directory(
      '${(await _resolveDirectory()).path}/raillog_map',
    );
    await directory.create(recursive: true);
    await _prune(directory);
    final file = File('${directory.path}/map_${_runId}_${_seq++}.html');
    await file.writeAsString(html, flush: true);
    if (request != _requested) return null;
    _current = file;
    return file;
  }

  /// 清掉早先留下的文件；当前正在显示的那个不碰，最近一分钟内的也不碰
  /// （可能还被 WebView 读着）。
  Future<void> _prune(Directory directory) async {
    final cutoff = DateTime.now().subtract(const Duration(minutes: 1));
    try {
      await for (final entity in directory.list()) {
        if (entity is! File || _isCurrent(entity)) continue;
        if (entity.statSync().modified.isBefore(cutoff)) await entity.delete();
      }
    } catch (_) {
      // 清理失败不影响绘制
    }
  }

  /// Windows 上 `Directory.list()` 给的路径分隔符可能和自己拼出来的不一致
  /// （`...\raillog_map\a.html` 与 `...\raillog_map/a.html`），不能直接比字符串。
  bool _isCurrent(FileSystemEntity entity) {
    final current = _current;
    if (current == null) return false;
    String normalize(String path) => path.replaceAll(r'\', '/');
    return normalize(entity.path) == normalize(current.path);
  }

  /// 页面销毁后删除当前文件；文件还被 WebView 占着时删除会失败，忽略即可。
  void dispose() {
    try {
      _current?.deleteSync();
    } catch (_) {}
  }
}
