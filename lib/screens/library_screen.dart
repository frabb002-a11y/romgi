import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/download_service.dart';
import '../utils/utils.dart';
import 'entry_detail_screen.dart';

/// Talks to the native side of "open with…" so we can force the system
/// chooser via Intent.createChooser instead of the user's saved default.
const _openChannel = MethodChannel('com.caprado.romgi/open');

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  bool _showSearch = false;
  late TabController _tabController;
  final Set<String> _selectedPaths = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_selectedPaths.isNotEmpty && mounted) {
        setState(_selectedPaths.clear);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final libraryState = ref.watch(libraryProvider);
    final favoritesAsync = ref.watch(favoritesProvider);

    final selecting = _selectedPaths.isNotEmpty && _tabController.index != 2;

    return Scaffold(
      bottomNavigationBar: selecting
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Text('${_selectedPaths.length} selected'),
                    const Spacer(),
                    TextButton(
                      onPressed: () => setState(_selectedPaths.clear),
                      child: const Text('Clear'),
                    ),
                    FilledButton(
                      onPressed: _manageSelection,
                      child: const Text('Manage'),
                    ),
                  ],
                ),
              ),
            )
          : null,
      appBar: AppBar(
        title: _showSearch
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search library...',
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  ref.read(libraryProvider.notifier).setSearchQuery(value);
                },
              )
            : const Text('Library'),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
                if (!_showSearch) {
                  _searchController.clear();
                  ref.read(libraryProvider.notifier).setSearchQuery('');
                }
              });
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              if (value == 'verify') {
                await ref.read(libraryProvider.notifier).verifyFiles();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Files verified')),
                  );
                }
              } else if (value == 'cleanup') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clean Up Library'),
                    content: const Text(
                      'Remove entries for files that no longer exist on disk?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Clean Up'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await ref
                      .read(libraryProvider.notifier)
                      .cleanupMissingFiles();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Library cleaned up')),
                    );
                  }
                }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'verify',
                child: ListTile(
                  leading: Icon(Icons.verified),
                  title: Text('Verify Files'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'cleanup',
                child: ListTile(
                  leading: Icon(Icons.cleaning_services),
                  title: Text('Clean Up'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.folder, size: 18),
                  const SizedBox(width: 8),
                  Text('Downloaded (${libraryState.realEntries.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text('Ghosts (${libraryState.ghostEntries.length})'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.favorite, size: 18),
                  const SizedBox(width: 8),
                  Text('Wishlist (${favoritesAsync.valueOrNull?.length ?? 0})'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFileTab(libraryState, ghosts: false),
          _buildFileTab(libraryState, ghosts: true),
          _buildWishlistTab(favoritesAsync),
        ],
      ),
    );
  }

  Widget _buildFileTab(LibraryState libraryState, {required bool ghosts}) {
    final items = libraryState.filtered(ghosts: ghosts);
    final platforms = libraryState.platformsFor(ghosts: ghosts);
    final selecting = _selectedPaths.isNotEmpty;
    return Column(
      children: [
        // Platform filter chips
        if (platforms.isNotEmpty)
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                FilterChip(
                  label: const Text('All'),
                  selected: libraryState.selectedPlatform == null,
                  onSelected: (selected) {
                    ref
                        .read(libraryProvider.notifier)
                        .setSelectedPlatform(null);
                  },
                ),
                const SizedBox(width: 8),
                ...platforms.map((platform) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(PlatformNames.getDisplayName(platform)),
                      selected: libraryState.selectedPlatform == platform,
                      onSelected: (selected) {
                        ref
                            .read(libraryProvider.notifier)
                            .setSelectedPlatform(
                              libraryState.selectedPlatform == platform
                                  ? null
                                  : platform,
                            );
                      },
                    ),
                  );
                }),
              ],
            ),
          ),

        // Library items
        Expanded(
          child: libraryState.isLoading
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
              ? _buildEmptyState(libraryState, ghosts: ghosts)
              : RefreshIndicator(
                  onRefresh: () => ref.read(libraryProvider.notifier).refresh(),
                  child: ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final filePath = item.path;
                      final selected =
                          filePath != null && _selectedPaths.contains(filePath);
                      return _LibraryItemTile(
                        item: item,
                        selected: selected,
                        selecting: selecting,
                        onTap: () {
                          if (selecting && filePath != null) {
                            _togglePath(filePath);
                          } else {
                            _openFile(item.task);
                          }
                        },
                        onLongPress: filePath == null
                            ? null
                            : () => _togglePath(filePath),
                        onManage: () => _manage([item]),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildWishlistTab(AsyncValue<List<Favorite>> favoritesAsync) {
    return favoritesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Failed to load wishlist',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
      data: (favorites) {
        if (favorites.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.favorite_border, size: 64, color: Colors.grey[400]),
                const SizedBox(height: 16),
                Text(
                  'Your wishlist is empty',
                  style: TextStyle(color: Colors.grey[600], fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap the heart icon on any ROM to add it here',
                  style: TextStyle(color: Colors.grey[500]),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          itemCount: favorites.length,
          itemBuilder: (context, index) {
            final item = favorites[index];
            return _WishlistItemTile(
              item: item,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => EntryDetailScreen(slug: item.slug),
                  ),
                );
              },
              onRemove: () async {
                final messenger = ScaffoldMessenger.of(context);
                await ref
                    .read(favoritesProvider.notifier)
                    .removeFavorite(item.slug);
                if (mounted) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Removed from wishlist')),
                  );
                }
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState(LibraryState state, {required bool ghosts}) {
    if (state.searchQuery.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No results for "${state.searchQuery}"',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    if (state.selectedPlatform != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No ${PlatformNames.getDisplayName(state.selectedPlatform!)} ROMs',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_books, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            ghosts ? 'No ghost files yet' : 'Your library is empty',
            style: TextStyle(color: Colors.grey[600], fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            ghosts
                ? 'Ghost files from Browse will appear here'
                : 'Downloaded ROMs will appear here',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Future<void> _openFile(DownloadTask item) async {
    if (item.filePath == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('File path not found')));
      return;
    }

    final type = await FileSystemEntity.type(
      item.filePath!,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('File no longer exists')));
      }
      return;
    }

    // Show file info dialog with Open with option
    if (mounted) {
      showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(item.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _infoRow('Platform', PlatformNames.getDisplayName(item.platform)),
              _infoRow('Format', item.link.format.toUpperCase()),
              _infoRow('Size', item.link.sizeStr),
              const SizedBox(height: 8),
              Text(
                'Path:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.filePath!,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.pop(dialogContext);
                try {
                  await _openChannel.invokeMethod<void>(
                    'openWithChooser',
                    {'path': item.filePath},
                  );
                } on PlatformException catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not open file: ${e.message ?? e.code}')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open with...'),
            ),
          ],
        ),
      );
    }
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
          Text(value),
        ],
      ),
    );
  }

  void _togglePath(String filePath) {
    setState(() {
      if (!_selectedPaths.add(filePath)) _selectedPaths.remove(filePath);
    });
  }

  Future<void> _manageSelection() async {
    final ghosts = _tabController.index == 1;
    final items = ref
        .read(libraryProvider)
        .filtered(ghosts: ghosts)
        .where(
          (entry) =>
              entry.path != null && _selectedPaths.contains(entry.path),
        )
        .toList();
    if (items.isEmpty) return;
    await _manage(items);
  }

  Future<void> _manage(List<LibraryEntry> items) async {
    final canConvert = items.any((entry) => entry.canConvert);
    final canInstall = items.any((entry) => entry.canInstall);
    final allGhosts = items.every((entry) => entry.ghost);
    final title = items.length == 1
        ? items.first.task.title
        : '${items.length} files';
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manage'),
        content: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'remove'),
            child: Text(
              allGhosts ? 'Remove from ghost library' : 'Remove from library',
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'delete'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete file'),
          ),
          if (canConvert)
            TextButton(
              onPressed: () => Navigator.pop(context, 'convert'),
              child: const Text('Convert to ghost'),
            ),
          if (canInstall)
            TextButton(
              onPressed: () => Navigator.pop(context, 'install'),
              child: const Text('Install game data'),
            ),
        ],
      ),
    );
    if (result == null || result == 'cancel' || !mounted) return;

    final notifier = ref.read(libraryProvider.notifier);
    var message = '';
    if (result == 'remove') {
      await notifier.removeFromLibrary(items);
      message = 'Removed from library';
    } else if (result == 'delete') {
      await notifier.deleteFiles(items);
      message = 'File deleted';
    } else if (result == 'convert') {
      final converted = await notifier.convertToGhosts(items);
      message = converted == 1
          ? 'Converted to a ghost file'
          : 'Converted $converted files to ghosts';
    } else if (result == 'install') {
      final ready = await notifier.prepareInstall(items);
      var queued = 0;
      for (final item in ready) {
        final (downloadResult, _) = await ref
            .read(downloadProvider.notifier)
            .addDownload(
              slug: item.task.slug,
              title: item.task.title,
              platform: item.task.platform,
              boxartUrl: item.task.boxartUrl,
              link: item.task.link,
            );
        if (downloadResult == AddDownloadResult.added) queued++;
      }
      message = queued == 0
          ? 'Nothing was queued'
          : 'Queued $queued download${queued == 1 ? '' : 's'}';
    }

    if (!mounted) return;
    await ref.read(downloadProvider.notifier).refresh();
    if (!mounted) return;
    setState(_selectedPaths.clear);
    ref.invalidate(downloadedSlugsProvider);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LibraryItemTile extends StatelessWidget {
  final LibraryEntry item;
  final bool selected;
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback onManage;

  const _LibraryItemTile({
    required this.item,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final task = item.task;

    return ListTile(
      selected: selected,
      onLongPress: onLongPress,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 56,
          height: 56,
          child: task.boxartUrl != null
              ? CachedNetworkImage(
                  imageUrl: task.boxartUrl!,
                  fit: BoxFit.cover,
                  placeholder: (context, string) => Container(
                    color: Colors.grey[300],
                    child: const Icon(Icons.gamepad, color: Colors.grey),
                  ),
                  errorWidget: (context, string, error) => Container(
                    color: Colors.grey[300],
                    child: const Icon(Icons.gamepad, color: Colors.grey),
                  ),
                )
              : Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.gamepad, color: Colors.grey),
                ),
        ),
      ),
      title: Text(
        task.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Row(
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                PlatformNames.getDisplayName(task.platform),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 4),
          if (task.link.sizeStr.isNotEmpty)
            Text(
              task.link.sizeStr,
              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
            ),
        ],
      ),
      trailing: selecting
          ? Icon(selected ? Icons.check_circle : Icons.circle_outlined)
          : IconButton(
              icon: const Icon(Icons.more_horiz),
              onPressed: onManage,
            ),
      onTap: onTap,
    );
  }
}

class _WishlistItemTile extends StatelessWidget {
  final Favorite item;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _WishlistItemTile({
    required this.item,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          width: 56,
          height: 56,
          child: item.boxartUrl != null
              ? CachedNetworkImage(
                  imageUrl: item.boxartUrl!,
                  fit: BoxFit.cover,
                  placeholder: (context, string) => Container(
                    color: Colors.grey[300],
                    child: const Icon(Icons.gamepad, color: Colors.grey),
                  ),
                  errorWidget: (context, string, error) => Container(
                    color: Colors.grey[300],
                    child: const Icon(Icons.gamepad, color: Colors.grey),
                  ),
                )
              : Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.gamepad, color: Colors.grey),
                ),
        ),
      ),
      title: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          PlatformNames.getDisplayName(item.platform),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onPrimaryContainer,
          ),
        ),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.favorite, color: Colors.red),
        onPressed: onRemove,
        tooltip: 'Remove from wishlist',
      ),
      onTap: onTap,
    );
  }
}
