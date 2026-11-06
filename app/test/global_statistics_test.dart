import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/models/global_statistics.dart';

void main() {
  test('ElementRankingEntry 解析平均评分', () {
    final entry = ElementRankingEntry.fromJson({
      'rank': 1,
      'name': '济南西',
      'value': 12,
      'averageRating': 4.5,
    });

    expect(entry.rank, 1);
    expect(entry.name, '济南西');
    expect(entry.value, 12);
    expect(entry.averageRating, 4.5);
  });

  test('ElementRankingEntry 在没有评价时 averageRating 为空', () {
    final entry = ElementRankingEntry.fromJson({
      'rank': 2,
      'name': '济南',
      'value': 5,
      'averageRating': null,
    });

    expect(entry.averageRating, isNull);
  });

  test('旧版接口缺少 averageRating 字段时按无评分处理', () {
    final entry = ElementRankingEntry.fromJson({
      'rank': 3,
      'name': '京沪高铁',
      'value': 8,
    });

    expect(entry.averageRating, isNull);
  });
}