import 'package:flutter/material.dart';
import 'package:raillog/src/services/entity_review_service.dart';

const _reactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🎉', '🥵', '🤔', '❔'];

class EntityReviewReactionBar extends StatefulWidget {
  const EntityReviewReactionBar({
    super.key,
    required this.reactions,
    required this.enabled,
    required this.onToggle,
  });

  final List<EntityReviewReaction> reactions;
  final bool enabled;
  final Future<void> Function(String emoji) onToggle;

  @override
  State<EntityReviewReactionBar> createState() =>
      _EntityReviewReactionBarState();
}

class _EntityReviewReactionBarState extends State<EntityReviewReactionBar> {
  final MenuController _menuController = MenuController();
  bool _saving = false;

  String? get _currentEmoji {
    for (final reaction in widget.reactions) {
      if (reaction.reactedByCurrentUser) return reaction.emoji;
    }
    return null;
  }

  Future<void> _toggle(String emoji) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await widget.onToggle(emoji);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final enabled = widget.enabled && !_saving;
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final reaction in widget.reactions)
          FilterChip(
            avatar: Text(reaction.emoji, style: const TextStyle(fontSize: 16)),
            label: Text(
              '${reaction.count}',
              style: textTheme.labelLarge?.copyWith(
                fontWeight: reaction.reactedByCurrentUser
                    ? FontWeight.w700
                    : FontWeight.w500,
              ),
            ),
            selected: reaction.reactedByCurrentUser,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            labelPadding: const EdgeInsets.only(left: 2, right: 4),
            backgroundColor: colors.surfaceContainerHigh,
            selectedColor: colors.secondaryContainer,
            disabledColor: colors.surfaceContainerHigh,
            side: BorderSide(
              color: reaction.reactedByCurrentUser
                  ? colors.primary
                  : colors.outlineVariant,
            ),
            shape: const StadiumBorder(),
            onSelected: enabled ? (_) => _toggle(reaction.emoji) : null,
          ),
        if (widget.enabled)
          MenuAnchor(
            controller: _menuController,
            alignmentOffset: const Offset(0, 6),
            style: MenuStyle(
              backgroundColor: WidgetStatePropertyAll(colors.surfaceContainer),
              surfaceTintColor: WidgetStatePropertyAll(colors.surfaceTint),
              elevation: const WidgetStatePropertyAll(3),
              padding: const WidgetStatePropertyAll(EdgeInsets.all(8)),
              shape: WidgetStatePropertyAll(
                RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: colors.outlineVariant),
                ),
              ),
            ),
            menuChildren: [
              SizedBox(
                width: 148,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final emoji in _reactionEmojis)
                      _ReviewEmojiButton(
                        emoji: emoji,
                        selected: _currentEmoji == emoji,
                        onPressed: enabled
                            ? () {
                                _menuController.close();
                                _toggle(emoji);
                              }
                            : null,
                      ),
                  ],
                ),
              ),
            ],
            builder: (context, controller, child) => IconButton(
              tooltip: '选择表情回复',
              visualDensity: VisualDensity.compact,
              style: IconButton.styleFrom(
                foregroundColor: colors.onSurfaceVariant,
              ),
              onPressed: enabled
                  ? () => controller.isOpen
                        ? controller.close()
                        : controller.open()
                  : null,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add_reaction_outlined, size: 20),
            ),
          ),
      ],
    );
  }
}

class _ReviewEmojiButton extends StatelessWidget {
  const _ReviewEmojiButton({
    required this.emoji,
    required this.selected,
    required this.onPressed,
  });

  final String emoji;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 44,
      child: IconButton(
        tooltip: emoji,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(
          backgroundColor: selected
              ? colors.secondaryContainer
              : colors.surfaceContainerHighest,
          foregroundColor: colors.onSurface,
          shape: const CircleBorder(),
        ),
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 21)),
            if (selected)
              Positioned(
                right: -4,
                bottom: -4,
                child: Icon(
                  Icons.check_circle,
                  size: 13,
                  color: colors.primary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
