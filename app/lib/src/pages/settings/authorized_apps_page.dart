import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:raillog/src/models/oauth_consent.dart';
import 'package:raillog/src/services/oauth_consent_service.dart';
import 'package:raillog/src/theme/app_theme.dart';
import 'package:raillog/src/widgets/settings/settings_section.dart';
import 'package:raillog/src/widgets/settings/settings_sub_page.dart';

/// 设置里的「已授权的应用」：查看并解除第三方应用对账户的 OAuth 授权。
class AuthorizedAppsPage extends StatefulWidget {
  const AuthorizedAppsPage({super.key});

  @override
  State<AuthorizedAppsPage> createState() => _AuthorizedAppsPageState();
}

class _AuthorizedAppsPageState extends State<AuthorizedAppsPage> {
  List<OAuthConsent> _consents = const [];
  bool _loading = true;
  String? _error;
  String? _revoking;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final consents = await OAuthConsentService.fetch();
      if (!mounted) return;
      setState(() {
        _consents = consents;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error is OAuthConsentException ? error.message : '加载失败，请稍后重试';
        _loading = false;
      });
    }
  }

  Future<void> _revoke(OAuthConsent consent) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('解除授权？'),
        content: Text('解除后「${consent.name}」将无法再确认你的账户身份，已签发的令牌会立即失效。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('解除授权'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _revoking = consent.clientId);
    try {
      await OAuthConsentService.revoke(consent.clientId);
      if (!mounted) return;
      setState(() {
        _consents = _consents
            .where((item) => item.clientId != consent.clientId)
            .toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已解除「${consent.name}」的授权')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is OAuthConsentException ? error.message : '解除授权失败，请稍后重试',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _revoking = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsSubPage(
      title: '已授权的应用',
      actions: [
        IconButton(
          tooltip: '刷新',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      children: [
        Text(
          '这些第三方应用可以通过 RailLog 确认你的账户身份。解除授权后，对方将无法再使用已签发的令牌。',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.6,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          _StateCard(
            icon: Icons.cloud_off_outlined,
            message: _error!,
            action: TextButton(onPressed: _load, child: const Text('重试')),
          )
        else if (_consents.isEmpty)
          const _StateCard(
            icon: Icons.verified_user_outlined,
            message: '暂无已授权的应用',
          )
        else
          _consentCard(context),
      ],
    );
  }

  Widget _consentCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SettingsListCard(
      title: '授权记录',
      icon: Icons.apps_outlined,
      children: [
        for (final consent in _consents)
          _consentTile(context, consent, colors),
      ],
    );
  }

  Widget _consentTile(
    BuildContext context,
    OAuthConsent consent,
    ColorScheme colors,
  ) {
    final revoking = _revoking == consent.clientId;
    return ListTile(
      leading: _logo(consent, colors),
      title: Text(consent.name),
      subtitle: Text(
        '${consent.scopeLabel} · 授权于 ${_formatDate(consent.createdAt)}',
      ),
      trailing: TextButton(
        onPressed: _revoking == null ? () => _revoke(consent) : null,
        child: revoking
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('解除授权'),
      ),
    );
  }

  Widget _logo(OAuthConsent consent, ColorScheme colors) {
    final fallback = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.small),
      ),
      child: Icon(Icons.vpn_key_outlined, color: colors.onSurfaceVariant),
    );
    final url = consent.logoUrl;
    if (url == null || url.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.small),
      child: CachedNetworkImage(
        imageUrl: url,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }

  static String _formatDate(DateTime value) {
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$day';
  }
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SettingsListCard(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.lg,
          ),
          child: Column(
            children: [
              Icon(icon, size: 32, color: colors.onSurfaceVariant),
              const SizedBox(height: AppSpacing.sm),
              Text(message, textAlign: TextAlign.center),
              if (action != null) ...[
                const SizedBox(height: AppSpacing.sm),
                action!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}
