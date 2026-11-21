import 'package:material_ui/material_ui.dart';
import 'package:raillog/src/models/dashboard_achievement.dart';
import 'package:raillog/src/pages/achievement_requirements_page.dart';
import 'package:raillog/src/services/public_user_service.dart';

/// 从解锁行程排行榜点进某个人时，展示 TA 在这个成就上的达成要求与进度。
///
/// 本页是压在排行榜之上的独立路由，返回时自然回到排行榜。
class PublicAchievementRequirementsPage extends StatefulWidget {
  const PublicAchievementRequirementsPage({
    super.key,
    required this.userId,
    required this.displayName,
    required this.achievementId,
    required this.achievementTitle,
  });

  final String userId;
  final String displayName;
  final String achievementId;
  final String achievementTitle;

  @override
  State<PublicAchievementRequirementsPage> createState() =>
      _PublicAchievementRequirementsPageState();
}

class _PublicAchievementRequirementsPageState
    extends State<PublicAchievementRequirementsPage> {
  late Future<DashboardAchievement?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<DashboardAchievement?> _load({bool forceRefresh = false}) async {
    final dashboard = await PublicUserService.fetch(
      widget.userId,
      forceRefresh: forceRefresh,
    );
    for (final achievement in dashboard.achievements) {
      if (achievement.id == widget.achievementId) return achievement;
    }
    return null;
  }

  void _retry() {
    setState(() {
      _future = _load(forceRefresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DashboardAchievement?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _StatusScaffold(
            title: widget.achievementTitle,
            message: '读取该用户的成就进度失败',
            onRetry: _retry,
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return _StatusScaffold(
            title: widget.achievementTitle,
            isLoading: true,
          );
        }
        final achievement = snapshot.data;
        if (achievement == null) {
          return _StatusScaffold(
            title: widget.achievementTitle,
            message: '没有找到这位用户的该成就记录',
          );
        }
        return AchievementRequirementsPage(
          achievement: achievement,
          ownerName: widget.displayName,
          ownerUserId: widget.userId,
        );
      },
    );
  }
}

class _StatusScaffold extends StatelessWidget {
  const _StatusScaffold({
    required this.title,
    this.message,
    this.isLoading = false,
    this.onRetry,
  });

  final String title;
  final String? message;
  final bool isLoading;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final onRetry = this.onRetry;
    return Scaffold(
      appBar: AppBar(title: Text('$title · 达成要求')),
      body: Center(
        child: isLoading
            ? const CircularProgressIndicator()
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(message ?? '暂不可用'),
                  if (onRetry != null) ...[
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('重试'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
