import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:raillog/src/services/entity_review_service.dart';

/// 评价正文。被 @ 的用户渲染成可点击的名字，点击打开对方主页。
class ReviewCommentText extends StatefulWidget {
  const ReviewCommentText({
    super.key,
    required this.comment,
    required this.mentions,
    this.style,
  });

  final String comment;
  final List<EntityReviewMention> mentions;
  final TextStyle? style;

  @override
  State<ReviewCommentText> createState() => _ReviewCommentTextState();
}

class _ReviewCommentTextState extends State<ReviewCommentText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _resetRecognizers();
    super.dispose();
  }

  void _resetRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _resetRecognizers();
    final matches = matchReviewMentions(widget.comment, widget.mentions);
    if (matches.isEmpty) {
      return SelectionArea(
        child: Text(widget.comment, style: widget.style),
      );
    }

    final colors = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(text: widget.comment.substring(cursor, match.start)),
        );
      }
      final userId = match.mention.userId.trim();
      final recognizer = TapGestureRecognizer()
        ..onTap = userId.isEmpty ? null : () => _openUser(userId);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: '@${match.mention.displayName.trim()}',
          recognizer: userId.isEmpty ? null : recognizer,
          style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
        ),
      );
      cursor = match.end;
    }
    if (cursor < widget.comment.length) {
      spans.add(TextSpan(text: widget.comment.substring(cursor)));
    }
    return SelectionArea(
      child: Text.rich(TextSpan(children: spans), style: widget.style),
    );
  }

  void _openUser(String userId) {
    Navigator.of(context).pushNamed('/users/${Uri.encodeComponent(userId)}');
  }
}
