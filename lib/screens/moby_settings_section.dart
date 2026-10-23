import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/metadata/moby_platforms.dart';
import '../services/metadata/moby_transfer.dart';
import '../utils/utils.dart';

class MobySettingsSection extends ConsumerStatefulWidget {
  const MobySettingsSection({super.key});

  @override
  ConsumerState<MobySettingsSection> createState() =>
      _MobySettingsSectionState();
}

class _MobySettingsSectionState extends ConsumerState<MobySettingsSection> {
  String _query = '';
  final _checked = <String>{};

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final sync = ref.watch(mobySyncProvider);
    final cutoff = settings.mobyStopScore;
    final catalog = ref.watch(platformsProvider).asData?.value ?? const <Platform>[];
    final platforms = [
      for (final platform in catalog)
        if (mobyPlatformSlugs.containsKey(platform.id.toLowerCase()))
          if (_query.isEmpty ||
              platform.name.toLowerCase().contains(_query) ||
              platform.id.toLowerCase().contains(_query))
            platform,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Builds a local score list from public MobyGames pages, one page '
            'per second. The first page may ask for a browser check. Check '
            'several platforms to walk them in order. Browse only filters '
            'platforms whose build has finished. Export the score list to '
            'move a finished build onto another device.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(
            children: [
              TextButton(
                onPressed: sync.running ? null : _exportScores,
                child: const Text('Export scores'),
              ),
              TextButton(
                onPressed: sync.running ? null : _importScores,
                child: const Text('Import scores'),
              ),
            ],
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
                    '${sync.activePlatform == null ? '' : ' of ${_platformName(catalog, sync.activePlatform!)}'}'
                    '${sync.activePlatform == null ? '' : ' · ${sync.platforms[sync.activePlatform!]?.stored ?? 0} titles'}',
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
            onChanged: (value) =>
                setState(() => _query = value.trim().toLowerCase()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: sync.running || platforms.isEmpty
                    ? null
                    : () => setState(() {
                        final ids = platforms.map((platform) => platform.id);
                        final allShown = ids.every(_checked.contains);
                        if (allShown) {
                          _checked.removeAll(ids);
                        } else {
                          _checked.addAll(ids);
                        }
                      }),
                child: Text(
                  platforms.isNotEmpty &&
                      platforms.every(
                        (platform) => _checked.contains(platform.id),
                      )
                      ? 'Clear shown'
                      : 'Select shown',
                ),
              ),
              TextButton(
                onPressed: sync.running || _checked.isEmpty
                    ? null
                    : () => _run(MobyJobKind.build),
                child: const Text('Build'),
              ),
              TextButton(
                onPressed: sync.running || _checked.isEmpty
                    ? null
                    : () => _run(MobyJobKind.continueJob),
                child: const Text('Continue'),
              ),
              TextButton(
                onPressed: sync.running || _checked.isEmpty
                    ? null
                    : () => _run(MobyJobKind.rebuild),
                child: const Text('Rebuild'),
              ),
            ],
          ),
        ),
        for (final platform in platforms)
          _PlatformTile(
            id: platform.id,
            name: platform.name,
            cutoff: cutoff,
            progress: sync.platforms[platform.id],
            busy: sync.running,
            active: sync.running && sync.activePlatform == platform.id,
            checked: _checked.contains(platform.id),
            onChecked: (value) => setState(() {
              if (value) {
                _checked.add(platform.id);
              } else {
                _checked.remove(platform.id);
              }
            }),
          ),
      ],
    );
  }

  Future<void> _exportScores() async {
    final transfer = await ref
        .read(mobySyncProvider.notifier)
        .exportMobyTransfer();
    if (!mounted) return;
    if (transfer.scores.isEmpty && transfer.sync.isEmpty) {
      _tell('No MobyGames scores to export.');
      return;
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export MobyGames scores',
      fileName: 'romgi-moby.json',
      bytes: Uint8List.fromList(utf8.encode(encodeMobyTransfer(transfer))),
    );
    if (!mounted || path == null) return;
    _tell('Exported ${transfer.scores.length} scores.');
  }

  Future<void> _importScores() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import MobyGames scores',
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (!mounted || picked == null || picked.files.isEmpty) return;
    final file = picked.files.single;
    final bytes = file.bytes;
    final String source;
    if (bytes != null) {
      source = utf8.decode(bytes);
    } else if (file.path != null) {
      source = await File(file.path!).readAsString();
    } else {
      _tell('Could not read that file.');
      return;
    }
    if (!mounted) return;
    try {
      final count = await ref
          .read(mobySyncProvider.notifier)
          .importMobyTransfer(source);
      if (!mounted) return;
      _tell('Imported $count scores. Download history was left as it is.');
    } on MobyTransferException catch (error) {
      if (!mounted) return;
      _tell(error.message);
    }
  }

  void _tell(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _run(MobyJobKind kind) {
    final catalog = ref.read(platformsProvider).asData?.value ?? const <Platform>[];
    final ids = [
      for (final platform in catalog)
        if (_checked.contains(platform.id)) platform.id,
    ];
    ref
        .read(mobySyncProvider.notifier)
        .runPlatforms(
          ids,
          cutoff: ref.read(settingsProvider).mobyStopScore,
          kind: kind,
        );
  }
}

String _platformName(List<Platform> catalog, String id) {
  for (final platform in catalog) {
    if (platform.id == id) return platform.name;
  }
  return PlatformNames.getDisplayName(id);
}

class _PlatformTile extends ConsumerWidget {
  final String id;
  final String name;
  final double cutoff;
  final MobyPlatformProgress? progress;
  final bool busy;
  final bool active;
  final bool checked;
  final ValueChanged<bool> onChecked;

  const _PlatformTile({
    required this.id,
    required this.name,
    required this.cutoff,
    required this.progress,
    required this.busy,
    required this.active,
    required this.checked,
    required this.onChecked,
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
      leading: Checkbox(
        value: checked,
        onChanged: busy ? null : (value) => onChecked(value ?? false),
      ),
      title: Text(name),
      subtitle: Text(_status(current, active: active)),
      trailing: PopupMenuButton<MobyJobKind>(
        enabled: canBuild || canContinue || canRebuild,
        onSelected: (kind) {
          ref
              .read(mobySyncProvider.notifier)
              .runPlatform(id, cutoff: cutoff, kind: kind);
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
