import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/metadata/moby_platforms.dart';
import '../utils/utils.dart';

class MobySettingsSection extends ConsumerStatefulWidget {
  const MobySettingsSection({super.key});

  @override
  ConsumerState<MobySettingsSection> createState() =>
      _MobySettingsSectionState();
}

class _MobySettingsSectionState extends ConsumerState<MobySettingsSection> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final sync = ref.watch(mobySyncProvider);
    final cutoff = settings.mobyStopScore;
    final platforms = mobyPlatformsToSync(full: true).where((id) {
      if (_query.isEmpty) return true;
      final name = PlatformNames.getDisplayName(id).toLowerCase();
      return name.contains(_query) || id.contains(_query);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Builds a local score list from public MobyGames pages, one page '
            'per second. Pick a platform when you want it. Browse only filters '
            'platforms whose build has finished.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        ListTile(
          title: Text(
            cutoff <= 0
                ? 'Stop at the first unscored game'
                : 'Stop below ${cutoff.toStringAsFixed(1)}',
          ),
          subtitle: const Text('0 keeps every scored game'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider(
            value: cutoff,
            min: 0,
            max: 10,
            divisions: 20,
            label: cutoff.toStringAsFixed(1),
            onChanged: sync.running
                ? null
                : (value) {
                    ref.read(settingsProvider.notifier).setMobyStopScore(value);
                  },
          ),
        ),
        if (sync.running)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Reading page ${sync.activePage + 1}'
                    '${sync.activePlatform == null ? '' : ' of ${PlatformNames.getDisplayName(sync.activePlatform!)}'}',
                  ),
                ),
                TextButton(
                  onPressed: () => ref.read(mobySyncProvider.notifier).cancel(),
                  child: const Text('Stop'),
                ),
              ],
            ),
          ),
        if (sync.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              sync.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Find a platform',
              isDense: true,
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
          ),
        ),
        for (final id in platforms)
          _PlatformTile(
            id: id,
            cutoff: cutoff,
            progress: sync.platforms[id],
            busy: sync.running,
            active: sync.running && sync.activePlatform == id,
          ),
      ],
    );
  }
}

class _PlatformTile extends ConsumerWidget {
  final String id;
  final double cutoff;
  final MobyPlatformProgress? progress;
  final bool busy;
  final bool active;

  const _PlatformTile({
    required this.id,
    required this.cutoff,
    required this.progress,
    required this.busy,
    required this.active,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = progress;
    final canBuild = current == null && !busy;
    final canContinue =
        !busy &&
        current != null &&
        (!current.complete || current.cutoff > cutoff + 0.001);
    final canRebuild = !busy && current != null;

    return ListTile(
      title: Text(PlatformNames.getDisplayName(id)),
      subtitle: Text(_status(current, active: active)),
      trailing: PopupMenuButton<MobyJobKind>(
        enabled: canBuild || canContinue || canRebuild,
        onSelected: (kind) {
          ref.read(mobySyncProvider.notifier).runPlatform(
            id,
            cutoff: cutoff,
            kind: kind,
          );
        },
        itemBuilder: (context) => [
          if (canBuild)
            const PopupMenuItem(value: MobyJobKind.build, child: Text('Build')),
          if (canContinue)
            const PopupMenuItem(
              value: MobyJobKind.continueJob,
              child: Text('Continue'),
            ),
          if (canRebuild)
            const PopupMenuItem(
              value: MobyJobKind.rebuild,
              child: Text('Rebuild'),
            ),
        ],
      ),
    );
  }

  String _status(MobyPlatformProgress? current, {required bool active}) {
    if (active) return 'Reading…';
    if (current == null) return 'Not built';
    final stop = current.cutoff <= 0
        ? 'unscored games'
        : current.cutoff.toStringAsFixed(1);
    if (!current.complete) {
      return 'Stopped on page ${current.nextPage + 1} · ${current.stored} titles';
    }
    return 'Finished · ${current.stored} titles · stop at $stop';
  }
}
