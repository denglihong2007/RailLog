import 'package:flutter/material.dart';
import 'package:raillog/src/models/public_user_dashboard.dart';
import 'package:raillog/src/models/search_result.dart';
import 'package:raillog/src/pages/entity_detail_page.dart';
import 'package:raillog/src/pages/home_page.dart';
import 'package:raillog/src/pages/trip_record_details_page.dart';
import 'package:raillog/src/services/public_trip_service.dart';
import 'package:raillog/src/services/search_service.dart';
import 'package:raillog/src/services/session_service.dart';
import 'package:raillog/src/widgets/cached_avatar.dart';
import 'package:raillog/src/widgets/login_required_view.dart';
import 'package:raillog/src/widgets/motion/m3_motion.dart';

const _searchMaxWidth = 720.0;
const _searchRadius = 8.0;

enum _SearchScope { station, route, company, rollingStock, train, user, trip }

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  _SearchScope _scope = _SearchScope.station;
  int _requestId = 0;
  bool _loading = false;
  bool _hasSearched = false;
  String? _error;
  List<EntitySearchResult> _entities = const [];
  List<UserSearchResult> _users = const [];
  late bool _wasSignedIn;

  @override
  void initState() {
    super.initState();
    _wasSignedIn = SessionService.instance.isSignedIn;
    SessionService.instance.addListener(_handleSessionChanged);
  }

  @override
  void dispose() {
    SessionService.instance.removeListener(_handleSessionChanged);
    _controller.dispose();
    super.dispose();
  }

  void _handleSessionChanged() {
    if (!mounted) return;
    final isSignedIn = SessionService.instance.isSignedIn;
    if (isSignedIn == _wasSignedIn) return;
    _wasSignedIn = isSignedIn;
    _requestId++;
    _controller.clear();
    setState(() {
      _loading = false;
      _hasSearched = false;
      _error = null;
      _entities = const [];
      _users = const [];
    });
  }

  void _loadAfterSignIn() {
    if (!mounted || !SessionService.instance.isSignedIn) return;
    setState(() {});
  }

  void _selectScope(_SearchScope? scope) {
    if (scope == null || scope == _scope) return;
    _requestId++;
    setState(() {
      _scope = scope;
      _loading = false;
      _hasSearched = false;
      _error = null;
      _entities = const [];
      _users = const [];
    });
  }

  void _clear() {
    _requestId++;
    _controller.clear();
    setState(() {
      _loading = false;
      _hasSearched = false;
      _error = null;
      _entities = const [];
      _users = const [];
    });
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      _clear();
      return;
    }

    final scope = _scope;
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _hasSearched = true;
      _error = null;
      _entities = const [];
      _users = const [];
    });

    try {
      switch (scope) {
        case _SearchScope.station:
        case _SearchScope.route:
        case _SearchScope.company:
        case _SearchScope.rollingStock:
        case _SearchScope.train:
          final entities = await SearchService.searchEntities(
            type: scope.typeKey,
            query: query,
          );
          if (!mounted || requestId != _requestId) return;
          setState(() {
            _loading = false;
            _entities = entities;
          });
          return;
        case _SearchScope.user:
          final users = await SearchService.searchUsers(query);
          if (!mounted || requestId != _requestId) return;
          setState(() {
            _loading = false;
            _users = users;
          });
          return;
        case _SearchScope.trip:
          if (!RegExp(r'^\d+$').hasMatch(query)) {
            throw const PublicTripException('行程 ID 应为数字');
          }
          final ticketId = int.tryParse(query);
          if (ticketId == null) {
            throw const PublicTripException('行程 ID 超出范围');
          }
          final details = await PublicTripService.fetch(ticketId);
          if (!mounted || requestId != _requestId) return;
          setState(() {
            _loading = false;
            _hasSearched = false;
          });
          _openTrip(details);
          return;
      }
    } catch (error) {
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _openEntity(EntitySearchResult result) {
    final type = _scope.entityType;
    if (type == null) return;
    openEntityPage(context, type, result.entityKey);
  }

  void _openUser(String userId) {
    Navigator.of(
      context,
    ).push(m3PageRoute(builder: (_) => PublicUserPage(userId: userId)));
  }

  void _openTrip(PublicTripDetails details) {
    Navigator.of(context).push(
      m3PageRoute(
        builder: (_) => TripRecordDetailsPage.public(
          ticketId: details.trip.ticketId!,
          onOwnerTap: () => _openUser(details.user.id),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!SessionService.instance.isSignedIn) {
      return LoginRequiredView(
        message: '登录后使用搜索',
        icon: Icons.search,
        onSignedIn: _loadAfterSignIn,
      );
    }
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerLowest,
      child: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _searchMaxWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('搜索', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 16),
                  _SearchConditionsCard(
                    scope: _scope,
                    controller: _controller,
                    loading: _loading,
                    onScopeChanged: _selectScope,
                    onChanged: () => setState(() {}),
                    onClear: _clear,
                    onSearch: _search,
                  ),
                  const SizedBox(height: 24),
                  _buildResults(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(BuildContext context) {
    Widget content;
    String? countLabel;
    if (_loading) {
      content = const _SearchStatusCard(
        isLoading: true,
        title: '正在搜索',
        message: '正在查询全站数据',
      );
    } else if (_error case final error?) {
      content = _SearchStatusCard(
        icon: Icons.cloud_off_outlined,
        title: '搜索失败',
        message: error,
        actionLabel: '重试',
        onAction: _search,
      );
    } else if (!_hasSearched) {
      content = _SearchStatusCard(
        icon: _scope.icon,
        title: '搜索${_scope.label}',
        message: _scope.emptyMessage,
      );
    } else {
      final resultCount = _scope == _SearchScope.user
          ? _users.length
          : _entities.length;
      if (resultCount == 0) {
        content = const _SearchStatusCard(
          icon: Icons.search_off_outlined,
          title: '没有找到结果',
          message: '请尝试其他关键词',
        );
      } else {
        countLabel = '$resultCount 条';
        content = Card.filled(
          margin: EdgeInsets.zero,
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_searchRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: _scope == _SearchScope.user
              ? _UserResultList(users: _users, onTap: _openUser)
              : _EntityResultList(
                  entities: _entities,
                  icon: _scope.icon,
                  onTap: _openEntity,
                ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '搜索结果',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (countLabel != null)
              Text(
                countLabel,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        content,
      ],
    );
  }
}

class _SearchConditionsCard extends StatelessWidget {
  const _SearchConditionsCard({
    required this.scope,
    required this.controller,
    required this.loading,
    required this.onScopeChanged,
    required this.onChanged,
    required this.onClear,
    required this.onSearch,
  });

  final _SearchScope scope;
  final TextEditingController controller;
  final bool loading;
  final ValueChanged<_SearchScope?> onScopeChanged;
  final VoidCallback onChanged;
  final VoidCallback onClear;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_searchRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.search, size: 20, color: colors.primary),
                const SizedBox(width: 10),
                Text('查询条件', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 560;
                final scopeField = DropdownButtonFormField<_SearchScope>(
                  initialValue: scope,
                  decoration: const InputDecoration(
                    labelText: '搜索范围',
                    prefixIcon: Icon(Icons.category_outlined),
                    border: OutlineInputBorder(),
                  ),
                  items: _SearchScope.values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Row(
                            children: [
                              Icon(item.icon, size: 18),
                              const SizedBox(width: 8),
                              Text(item.label),
                            ],
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: onScopeChanged,
                );
                final keywordField = TextField(
                  controller: controller,
                  keyboardType: scope == _SearchScope.trip
                      ? TextInputType.number
                      : TextInputType.text,
                  textInputAction: TextInputAction.search,
                  onChanged: (_) => onChanged(),
                  onSubmitted: (_) => onSearch(),
                  decoration: InputDecoration(
                    labelText: '关键词',
                    hintText: scope.hint,
                    prefixIcon: Icon(scope.icon),
                    suffixIcon: controller.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: '清除',
                            onPressed: onClear,
                            icon: const Icon(Icons.close),
                          ),
                    border: const OutlineInputBorder(),
                  ),
                );

                if (!wide) {
                  return Column(
                    children: [
                      scopeField,
                      const SizedBox(height: 12),
                      keywordField,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 220, child: scopeField),
                    const SizedBox(width: 12),
                    Expanded(child: keywordField),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: loading ? null : onSearch,
                icon: loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(loading ? '搜索中' : '搜索'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntityResultList extends StatelessWidget {
  const _EntityResultList({
    required this.entities,
    required this.icon,
    required this.onTap,
  });

  final List<EntitySearchResult> entities;
  final IconData icon;
  final ValueChanged<EntitySearchResult> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < entities.length; index++) ...[
          _EntityResultTile(
            entity: entities[index],
            icon: icon,
            onTap: () => onTap(entities[index]),
          ),
          if (index < entities.length - 1) const Divider(height: 1, indent: 72),
        ],
      ],
    );
  }
}

class _UserResultList extends StatelessWidget {
  const _UserResultList({required this.users, required this.onTap});

  final List<UserSearchResult> users;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < users.length; index++) ...[
          _UserResultTile(
            user: users[index],
            onTap: () => onTap(users[index].id),
          ),
          if (index < users.length - 1) const Divider(height: 1, indent: 72),
        ],
      ],
    );
  }
}

class _EntityResultTile extends StatelessWidget {
  const _EntityResultTile({
    required this.entity,
    required this.icon,
    required this.onTap,
  });

  final EntitySearchResult entity;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: colors.secondaryContainer,
        foregroundColor: colors.onSecondaryContainer,
        child: Icon(icon, size: 20),
      ),
      title: Text(
        entity.entityKey,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${entity.tripCount} 次',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class _UserResultTile extends StatelessWidget {
  const _UserResultTile({required this.user, required this.onTap});

  final UserSearchResult user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bio = user.bio?.trim() ?? '';
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CachedAvatar(
        name: user.displayName,
        imageUrl: user.avatarUrl,
        size: 44,
      ),
      title: Text(
        user.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ID · ${user.id}', maxLines: 1, overflow: TextOverflow.ellipsis),
          if (bio.isNotEmpty)
            Text(bio, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
      trailing: Text('${user.tripCount} 趟'),
    );
  }
}

class _SearchStatusCard extends StatelessWidget {
  const _SearchStatusCard({
    required this.title,
    required this.message,
    this.icon,
    this.isLoading = false,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String message;
  final IconData? icon;
  final bool isLoading;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(_searchRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            if (isLoading)
              const CircularProgressIndicator()
            else if (icon != null)
              Icon(icon, size: 36, color: colors.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

extension on _SearchScope {
  String get label => switch (this) {
    _SearchScope.station => '车站',
    _SearchScope.route => '线路',
    _SearchScope.company => '承运单位',
    _SearchScope.rollingStock => '车型',
    _SearchScope.train => '车次',
    _SearchScope.user => '用户',
    _SearchScope.trip => '行程',
  };

  String get hint => switch (this) {
    _SearchScope.station => '输入车站名称',
    _SearchScope.route => '输入线路名称',
    _SearchScope.company => '输入承运单位名称',
    _SearchScope.rollingStock => '输入车型代码',
    _SearchScope.train => '输入车次',
    _SearchScope.user => '输入用户名或用户 ID',
    _SearchScope.trip => '输入完整行程 ID',
  };

  String get emptyMessage => switch (this) {
    _SearchScope.station => '输入车站名称后点击搜索',
    _SearchScope.route => '输入线路名称后点击搜索',
    _SearchScope.company => '输入承运单位名称后点击搜索',
    _SearchScope.rollingStock => '输入车型代码后点击搜索',
    _SearchScope.train => '输入车次后点击搜索',
    _SearchScope.user => '输入用户名或用户 ID 后点击搜索',
    _SearchScope.trip => '输入完整行程 ID 后点击搜索',
  };

  IconData get icon => switch (this) {
    _SearchScope.station => Icons.location_on_outlined,
    _SearchScope.route => Icons.route_outlined,
    _SearchScope.company => Icons.business_outlined,
    _SearchScope.rollingStock => Icons.directions_railway_outlined,
    _SearchScope.train => Icons.train_outlined,
    _SearchScope.user => Icons.person_search_outlined,
    _SearchScope.trip => Icons.receipt_long_outlined,
  };

  String get typeKey => switch (this) {
    _SearchScope.station => 'station',
    _SearchScope.route => 'route',
    _SearchScope.company => 'company',
    _SearchScope.rollingStock => 'rollingstock',
    _SearchScope.train => 'train',
    _ => '',
  };

  EntityType? get entityType => switch (this) {
    _SearchScope.station => EntityType.station,
    _SearchScope.route => EntityType.route,
    _SearchScope.company => EntityType.company,
    _SearchScope.rollingStock => EntityType.rollingStock,
    _SearchScope.train => EntityType.train,
    _ => null,
  };
}
