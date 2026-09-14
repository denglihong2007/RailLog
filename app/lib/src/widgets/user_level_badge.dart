import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const _levelMinimumExperience = [0, 1, 50, 125, 250, 450, 800];

int userLevelForExperience(int experience) {
  final normalized = experience < 0 ? 0 : experience;
  for (var level = _levelMinimumExperience.length - 1; level > 0; level--) {
    if (normalized >= _levelMinimumExperience[level]) return level;
  }
  return 0;
}

class UserLevelProgress {
  const UserLevelProgress({
    required this.experience,
    required this.level,
    required this.minimumExperience,
    required this.nextLevelExperience,
  });

  final int experience;
  final int level;
  final int minimumExperience;
  final int? nextLevelExperience;

  bool get isMaxLevel => nextLevelExperience == null;

  int get remainingExperience =>
      nextLevelExperience == null ? 0 : nextLevelExperience! - experience;

  double get value {
    final next = nextLevelExperience;
    if (next == null) return 1;
    final range = next - minimumExperience;
    if (range <= 0) return 1;
    return ((experience - minimumExperience) / range)
        .clamp(0.0, 1.0)
        .toDouble();
  }
}

UserLevelProgress userLevelProgressForExperience(int experience) {
  final normalized = experience < 0 ? 0 : experience;
  final level = userLevelForExperience(normalized);
  return UserLevelProgress(
    experience: normalized,
    level: level,
    minimumExperience: _levelMinimumExperience[level],
    nextLevelExperience: level == _levelMinimumExperience.length - 1
        ? null
        : _levelMinimumExperience[level + 1],
  );
}

class UserLevelBadge extends StatelessWidget {
  const UserLevelBadge({super.key, required this.experience, this.width = 28});

  final int experience;
  final double width;

  @override
  Widget build(BuildContext context) {
    final level = userLevelForExperience(experience);
    final label = 'LV$level · $experience XP';
    return Tooltip(
      message: label,
      child: Semantics(
        image: true,
        label: label,
        child: SvgPicture.asset(
          'assets/level/LV$level.svg',
          width: width,
          height: width / 1.856,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
        ),
      ),
    );
  }
}
