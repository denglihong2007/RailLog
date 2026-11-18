import 'package:flutter_test/flutter_test.dart';
import 'package:raillog/src/services/entity_review_service.dart';

void main() {
  test('出行指南排序方式的线上取值与后端约定一致', () {
    expect(TravelGuideMode.hot.wire, 'hot');
    expect(TravelGuideMode.related.wire, 'related');
    expect(TravelGuideMode.hot.label, '全站热门');
    expect(TravelGuideMode.related.label, '与我相关');
    // 分页游标按整页推进，页大小变更会影响「是否还有下一页」的判断。
    expect(EntityReviewService.pageSize, 20);
  });

  test('EntityRating 解析综合星级与参与人数', () {
    final rated = EntityRating.fromJson({
      'averageRating': 4.25,
      'reviewCount': 7,
      'raterCount': 5,
    });
    expect(rated.averageRating, 4.25);
    expect(rated.reviewCount, 7);
    expect(rated.raterCount, 5);

    final empty = EntityRating.fromJson({
      'averageRating': null,
      'reviewCount': 0,
      'raterCount': 0,
    });
    expect(empty.averageRating, isNull);
  });

  test('EntityReview parses associated public trips', () {
    final review = EntityReview.fromJson({
      'id': 1,
      'entityType': 'station',
      'entityKey': '济南西',
      'reviewType': 'transfer',
      'userId': 'user-1',
      'displayName': '测试用户',
      'avatarUrl': null,
      'achievementExperience': 125,
      'rating': 5,
      'comment': '换乘方便',
      'tripId': 101,
      'secondTripId': 102,
      'transferMinutes': 35,
      'dish': null,
      'price': null,
      'createdAt': '2026-09-14T10:00:00Z',
      'trip': _tripJson(101, 'G1', '北京南', '济南西'),
      'secondTrip': _tripJson(102, 'G2', '济南西', '上海虹桥'),
    });

    expect(review.entityType, 'station');
    expect(review.entityKey, '济南西');
    expect(review.trip?.ticketId, 101);
    expect(review.trip?.fromStation, '北京南');
    expect(review.secondTrip?.ticketId, 102);
    expect(review.secondTrip?.toStation, '上海虹桥');
    expect(review.transferMinutes, 35);
    expect(review.achievementExperience, 125);
  });

  test('EntityReview parses the selected route segment', () {
    final review = EntityReview.fromJson({
      'id': 2,
      'entityType': 'route',
      'entityKey': '京沪高铁',
      'reviewType': 'route',
      'userId': 'user-1',
      'displayName': '测试用户',
      'avatarUrl': null,
      'rating': 5,
      'comment': '沿途风景不错',
      'tripId': 101,
      'secondTripId': null,
      'transferMinutes': null,
      'routeFromStation': '北京南',
      'routeToStation': '济南西',
      'dish': null,
      'price': null,
      'createdAt': '2026-09-14T10:00:00Z',
      'trip': _tripJson(101, 'G1', '北京南', '上海虹桥'),
      'secondTrip': null,
      'reactions': [
        {'emoji': '👍', 'count': 3, 'reactedByCurrentUser': true},
      ],
    });

    expect(review.routeFromStation, '北京南');
    expect(review.routeToStation, '济南西');
    expect(review.reactions.single.emoji, '👍');
    expect(review.reactions.single.count, 3);
    expect(review.reactions.single.reactedByCurrentUser, isTrue);
  });

  test('withReactions 只换表情回应，其余字段保持不变', () {
    final review = EntityReview.fromJson({
      'id': 3,
      'entityType': 'station',
      'entityKey': '济南西',
      'reviewType': 'station',
      'userId': 'user-1',
      'displayName': '测试用户',
      'avatarUrl': null,
      'rating': 4,
      'comment': '候车室干净',
      'tripId': null,
      'secondTripId': null,
      'transferMinutes': null,
      'dish': null,
      'price': null,
      'createdAt': '2026-09-14T10:00:00Z',
      'trip': null,
      'secondTrip': null,
      'reactions': [
        {'emoji': '👍', 'count': 1, 'reactedByCurrentUser': true},
      ],
    });

    final updated = review.withReactions([
      const EntityReviewReaction(
        emoji: '🎉',
        count: 2,
        reactedByCurrentUser: false,
      ),
    ]);

    expect(updated.id, review.id);
    expect(updated.entityKey, review.entityKey);
    expect(updated.comment, review.comment);
    expect(updated.rating, review.rating);
    expect(updated.reactions.single.emoji, '🎉');
    expect(updated.reactions.single.count, 2);
    // 原对象不能被改动。
    expect(review.reactions.single.emoji, '👍');
  });

  group('reactionsAfterToggle', () {
    test('首次回应新增一个表情并标记为本人', () {
      final result = reactionsAfterToggle([
        const EntityReviewReaction(
          emoji: '👍',
          count: 2,
          reactedByCurrentUser: false,
        ),
      ], null, '❤️');

      expect(_counts(result), {'👍': 2, '❤️': 1});
      expect(_mine(result), {'❤️'});
    });

    test('换表情时旧表情减一、新表情加一并转移本人标记', () {
      final result = reactionsAfterToggle([
        const EntityReviewReaction(
          emoji: '👍',
          count: 3,
          reactedByCurrentUser: true,
        ),
        const EntityReviewReaction(
          emoji: '❤️',
          count: 1,
          reactedByCurrentUser: false,
        ),
      ], '👍', '❤️');

      expect(_counts(result), {'👍': 2, '❤️': 2});
      expect(_mine(result), {'❤️'});
    });

    test('取消本人唯一的回应后该表情消失', () {
      final result = reactionsAfterToggle([
        const EntityReviewReaction(
          emoji: '👍',
          count: 1,
          reactedByCurrentUser: true,
        ),
        const EntityReviewReaction(
          emoji: '🎉',
          count: 1,
          reactedByCurrentUser: false,
        ),
      ], '👍', '👍');

      expect(_counts(result), {'🎉': 1});
      expect(_mine(result), isEmpty);
    });

    test('顺序与后端一致：数量降序，同数量按表情排序', () {
      final result = reactionsAfterToggle([
        const EntityReviewReaction(
          emoji: '👍',
          count: 2,
          reactedByCurrentUser: false,
        ),
        const EntityReviewReaction(
          emoji: '🎉',
          count: 1,
          reactedByCurrentUser: false,
        ),
      ], null, '❤️');

      expect(result.map((reaction) => reaction.emoji), ['👍', '❤️', '🎉']);
    });
  });
  test('EntityReview parses mentions', () {
    final review = EntityReview.fromJson({
      'id': 4,
      'entityType': 'station',
      'entityKey': '济南西',
      'reviewType': 'station',
      'userId': 'user-1',
      'displayName': '测试用户',
      'avatarUrl': null,
      'rating': 5,
      'comment': '同行的 @旧名字 也这么觉得',
      'tripId': null,
      'secondTripId': null,
      'transferMinutes': null,
      'dish': null,
      'price': null,
      'createdAt': '2026-09-14T10:00:00Z',
      'trip': null,
      'secondTrip': null,
      'mentions': [
        {'userId': 'user-2', 'displayName': '新名字', 'mentionedName': '旧名字'},
      ],
    });

    expect(review.mentions.single.userId, 'user-2');
    expect(review.mentions.single.displayName, '新名字');
    expect(review.mentions.single.mentionedName, '旧名字');
  });

  group('matchReviewMentions', () {
    test('长名字优先，避免被短名字截断', () {
      final matches = matchReviewMentions('找 @张三丰 和 @张三', const [
        EntityReviewMention(
          userId: 'short',
          displayName: '张三',
          mentionedName: '张三',
        ),
        EntityReviewMention(
          userId: 'long',
          displayName: '张三丰',
          mentionedName: '张三丰',
        ),
      ]);

      expect(matches.map((match) => match.mention.userId), ['long', 'short']);
    });

    test('名字后紧跟文字时不算提及', () {
      final matches = matchReviewMentions('@张三丰来了', const [
        EntityReviewMention(
          userId: 'short',
          displayName: '张三',
          mentionedName: '张三',
        ),
      ]);

      expect(matches, isEmpty);
    });

    test('normalizeReviewMentionNames 把旧名字换成当前名字', () {
      final text = normalizeReviewMentionNames('感谢 @旧名字 的建议', const [
        EntityReviewMention(
          userId: 'user-2',
          displayName: '新名字',
          mentionedName: '旧名字',
        ),
      ]);

      expect(text, '感谢 @新名字 的建议');
    });

    test('usedReviewMentions 丢掉正文里已经删掉的提及', () {
      final mentions = usedReviewMentions('只剩 @保留', const [
        EntityReviewMention(
          userId: 'kept',
          displayName: '保留',
          mentionedName: '保留',
        ),
        EntityReviewMention(
          userId: 'removed',
          displayName: '删除',
          mentionedName: '删除',
        ),
      ]);

      expect(mentions.map((mention) => mention.userId), ['kept']);
    });
  });
}

Map<String, int> _counts(List<EntityReviewReaction> reactions) => {
  for (final reaction in reactions) reaction.emoji: reaction.count,
};

Set<String> _mine(List<EntityReviewReaction> reactions) => {
  for (final reaction in reactions)
    if (reaction.reactedByCurrentUser) reaction.emoji,
};

Map<String, dynamic> _tripJson(
  int ticketId,
  String trainNumber,
  String fromStation,
  String toStation,
) => {
  'ticketId': ticketId,
  'createdAt': '2026-09-14T08:00:00Z',
  'trainNumber': trainNumber,
  'rollingStock': null,
  'companyName': null,
  'fromStation': fromStation,
  'toStation': toStation,
  'departureTime': '2026-09-14T08:00:00Z',
  'arrivalTime': '2026-09-14T09:00:00Z',
  'mileageKm': 100,
  'viaRoutes': '[]',
  'seatType': '二等座',
  'seatNumber': null,
  'price': 50,
  'notes': null,
  'isRailTrip': true,
};
