/// 历史时刻表库的版本号（快照日期，形如 `2003.11.25`）与「行程日期 → 版本」的推导规则。
///
/// 数据源是一批按抓取日期命名的时刻表快照，快照之间间隔不均（实测最大 415 天，
/// 约 20% 的相邻快照间隔超过一个月），所以规则分两步：
///
/// 1. 行程日期**之后第一个**快照，且间隔不超过 [_forwardWindow] —— 用它；
/// 2. 否则取**绝对距离最近**的快照（并列时取较早的，保证结果确定）。
///
/// 第 2 步是回退：当行程落在两个快照之间且后面的那个离得太远时，最近的快照可能仍在
/// 行程之后，这是刻意如此——按需求「否则选最近的」执行。
library;

/// 「之后第一个快照」的容许间隔。超过它就认为那个快照离行程太远，转为按距离取最近。
const Duration _forwardWindow = Duration(days: 31);

/// 解析版本号为日期；格式不对返回 null。
DateTime? parseTimetableVersion(String version) {
  final match = RegExp(r'^(\d{4})\.(\d{2})\.(\d{2})$').firstMatch(version.trim());
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final parsed = DateTime(year, month, day);
  // 排掉 2023.02.31 这类会被 DateTime 顺延的非法日期。
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return parsed;
}

/// 把日期归一到「当天零点」，避免行程日期带的时间影响比较。
DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// 按上述规则挑出该行程日期对应的版本；没有可用版本时返回 null。
String? resolveTimetableVersion(DateTime date, List<String> versions) {
  final parsed = <(DateTime, String)>[];
  for (final version in versions) {
    final day = parseTimetableVersion(version);
    if (day != null) parsed.add((day, version));
  }
  if (parsed.isEmpty) return null;
  parsed.sort((first, second) => first.$1.compareTo(second.$1));

  final target = _dateOnly(date);

  for (final (day, version) in parsed) {
    if (!day.isBefore(target)) {
      // 第一个不早于行程日期的快照。
      if (day.difference(target) <= _forwardWindow) return version;
      break;
    }
  }

  // 回退：绝对距离最近，并列取较早的。
  var best = parsed.first;
  var bestDistance = (best.$1.difference(target).inDays).abs();
  for (final candidate in parsed.skip(1)) {
    final distance = (candidate.$1.difference(target).inDays).abs();
    if (distance < bestDistance) {
      best = candidate;
      bestDistance = distance;
    }
  }
  return best.$2;
}
