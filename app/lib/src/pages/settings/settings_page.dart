import 'package:flutter/material.dart';
import 'package:raillog/src/models/user_profile.dart';
import 'package:raillog/src/pages/about_page.dart';
import 'package:raillog/src/pages/auth_page.dart';
import 'package:raillog/src/pages/partner_applications_page.dart';
import 'package:raillog/src/pages/settings/account_security_page.dart';
import 'package:raillog/src/pages/settings/community_page.dart';
import 'package:raillog/src/pages/settings/data_sync_settings_page.dart';
import 'package:raillog/src/pages/settings/display_settings_page.dart';
import 'package:raillog/src/pages/settings/email_connection_settings_page.dart';
import 'package:raillog/src/pages/settings/journal_settings_page.dart';
import 'package:raillog/src/pages/settings/my_reviews_page.dart';
import 'package:raillog/src/pages/settings/ticket_generator_settings_page.dart';
import 'package:raillog/src/pages/settings/ticket_ocr_settings_page.dart';
import 'package:raillog/src/pages/settings/timetable_rebuild_page.dart';
import 'package:raillog/src/pages/update_log_page.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/widgets/app_card.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';
import 'package:raillog/src/widgets/settings/settings_section.dart';

/// 设置根页面。它是底栏的 tab body，没有自己的 Scaffold/AppBar，
/// 标题与留白由这里给出，具体开关都在各子页面里。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SessionService.instance,
      builder: (context, _) {
        final user = SessionService.instance.user;
        return ColoredBox(
          color: Theme.of(context).colorScheme.surfaceContainerLowest,
          child: ListView(
            padding: AppSpacing.page,
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AppLayout.contentMaxWidth,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '设置',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _AccountHeaderCard(user: user),
                      const SizedBox(height: AppSpacing.xxl),
                      const SettingsSectionHeader(title: '个性化'),
                      const SizedBox(height: AppSpacing.sm),
                      const SettingsListCard(
                        children: [_DisplayEntry(), _JournalEntry()],
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      const SettingsSectionHeader(title: '车票'),
                      const SizedBox(height: AppSpacing.sm),
                      const SettingsListCard(
                        children: [
                          _TicketGeneratorEntry(),
                          _TicketOcrEntry(),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      const SettingsSectionHeader(title: '数据'),
                      const SizedBox(height: AppSpacing.sm),
                      const SettingsListCard(
                        children: [
                          _MailImportEntry(),
                          _DataSyncEntry(),
                          _TimetableRebuildEntry(),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      const SettingsSectionHeader(title: '应用'),
                      const SizedBox(height: AppSpacing.sm),
                      SettingsListCard(
                        children: [
                          SettingsNavTile(
                            icon: Icons.handshake_outlined,
                            title: '合作应用',
                            subtitle: '查看 RailLog 的合作应用',
                            onTap: () => _push(
                              context,
                              const PartnerApplicationsPage(),
                            ),
                          ),
                          SettingsNavTile(
                            icon: Icons.newspaper_outlined,
                            title: '更新日志',
                            subtitle: '查看最新版本的发布时间与更新内容',
                            onTap: () =>
                                _push(context, const UpdateLogPage()),
                          ),
                          SettingsNavTile(
                            icon: Icons.groups_outlined,
                            title: '社群与支持',
                            subtitle: 'QQ 交流群、爱发电与 Bilibili',
                            onTap: () => _push(context, const CommunityPage()),
                          ),
                          SettingsNavTile(
                            icon: Icons.info_outline,
                            title: '关于',
                            subtitle: '软件信息、API 与项目链接',
                            onTap: () => _push(context, const AboutPage()),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

void _push(BuildContext context, Widget page) {
  Navigator.of(context).push<void>(m3PageRoute(builder: (_) => page));
}

class _AccountHeaderCard extends StatelessWidget {
  const _AccountHeaderCard({required this.user});

  final UserProfile? user;

  /// 账户卡与「我的评价」同属一张卡：评价挂在账户名下，拆成两张反而看不出从属关系。
  @override
  Widget build(BuildContext context) {
    final user = this.user;
    if (user == null) {
      return AppCard.filled(
        title: '账户',
        icon: Icons.account_circle_outlined,
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '登录 RailLog',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '登录后可同步行程和个人资料',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton.icon(
                    onPressed: () => _push(context, const AuthPage()),
                    icon: const Icon(Icons.login),
                    label: const Text('登录或注册'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, indent: _accountRowDividerIndent),
            const _MyReviewsEntry(),
          ],
        ),
      );
    }

    final colors = Theme.of(context).colorScheme;
    return AppCard.filled(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 整卡不再可点，账户行自己是一块点击区，免得和下面那行抢手势。
          InkWell(
            onTap: () => _push(context, const AccountSecurityPage()),
            child: Padding(
              padding: AppSpacing.card,
              child: Row(
                children: [
                  UserAvatar(
                    name: user.displayName,
                    imageUrl: user.avatarUrl,
                    size: 60,
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          user.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
          const Divider(height: 1, indent: _accountRowDividerIndent),
          const _MyReviewsEntry(),
        ],
      ),
    );
  }
}

/// 分隔线从列表行的文字处起画：卡片留白 16 + ListTile 的 leading 占位 40。
const double _accountRowDividerIndent = 56;

class _DisplayEntry extends StatelessWidget {
  const _DisplayEntry();

  @override
  Widget build(BuildContext context) => SettingsNavTile(
    icon: Icons.palette_outlined,
    title: '外观与显示',
    subtitle: '主题、底图显示层级与行程详情',
    onTap: () => _push(context, const DisplaySettingsPage()),
  );
}

class _JournalEntry extends StatelessWidget {
  const _JournalEntry();

  @override
  Widget build(BuildContext context) => SettingsNavTile(
    icon: Icons.menu_book_outlined,
    title: '行程手账',
    subtitle: '手账版式与空白模板导出',
    onTap: () => _push(context, const JournalSettingsPage()),
  );
}

class _MyReviewsEntry extends StatelessWidget {
  const _MyReviewsEntry();

  @override
  Widget build(BuildContext context) => SettingsNavTile(
    icon: Icons.rate_review_outlined,
    title: '我的评价',
    subtitle: '查看并管理自己发表过的评价',
    onTap: () => _push(context, const MyReviewsPage()),
  );
}

class _TicketGeneratorEntry extends StatelessWidget {
  const _TicketGeneratorEntry();

  @override
  Widget build(BuildContext context) => SettingsNavTile(
    icon: Icons.confirmation_number_outlined,
    title: '火车票生成器',
    subtitle: '票面样式与默认票面信息',
    onTap: () => _push(context, const TicketGeneratorSettingsPage()),
  );
}

class _TicketOcrEntry extends StatelessWidget {
  const _TicketOcrEntry();

  @override
  Widget build(BuildContext context) => SettingsNavTile(
    icon: Icons.document_scanner_outlined,
    title: '车票识别',
    subtitle: '配置百度智能云或阿里云密钥，自动识别车票信息',
    onTap: () => _push(context, const TicketOcrSettingsPage()),
  );
}

class _MailImportEntry extends StatelessWidget {
  const _MailImportEntry();

  @override
  Widget build(BuildContext context) => SettingsNavTile(
    icon: Icons.alternate_email,
    title: '邮箱导入',
    subtitle: '配置 IMAP / POP3 邮箱，从 12306 购票通知邮件导入行程',
    onTap: () => _push(context, const EmailConnectionSettingsPage()),
  );
}

class _DataSyncEntry extends StatelessWidget {
  const _DataSyncEntry();

  @override
  Widget build(BuildContext context) => SettingsNavTile(
    icon: Icons.cloud_sync_outlined,
    title: '数据与同步',
    subtitle: '云同步开关与 Excel 导入导出',
    onTap: () => _push(context, const DataSyncSettingsPage()),
  );
}

class _TimetableRebuildEntry extends StatelessWidget {
  const _TimetableRebuildEntry();

  @override
  Widget build(BuildContext context) => SettingsNavTile(
    icon: Icons.auto_fix_high_outlined,
    title: '历史时刻表重建',
    subtitle: '按历史时刻表批量重建所选车票的到点与经由线路',
    onTap: () => _push(context, const TimetableRebuildPage()),
  );
}
