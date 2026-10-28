import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../services/metadata/igdb_client.dart';
import '../services/metadata/igdb_platforms.dart';
import '../services/metadata/igdb_transfer.dart';
import '../utils/utils.dart';

class IgdbSettingsSection extends ConsumerStatefulWidget {
  const IgdbSettingsSection({super.key});

  @override
  ConsumerState<IgdbSettingsSection> createState() =>
      _IgdbSettingsSectionState();
}

class _IgdbSettingsSectionState extends ConsumerState<IgdbSettingsSection> {
  final _clientId = TextEditingController();
  final _clientSecret = TextEditingController();
  var _loaded = false;
  var _obscure = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(_fillFields);
  }

  @override
  void dispose() {
    _clientId.dispose();
    _clientSecret.dispose();
    super.dispose();
  }

  Future<void> _fillFields() async {
    if (_loaded) return;
    final auth = await ref.read(igdbSyncProvider.notifier).credentials();
    if (!mounted) return;
    _clientId.text = auth.clientId;
    _clientSecret.text = auth.clientSecret;
    _loaded = true;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(igdbSyncProvider);
    final catalog =
        ref.watch(platformsProvider).asData?.value ?? const <Platform>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            'Builds a local critic-score list from IGDB. Setup asks which '
            'consoles to include, optional genres, and the lowest score to keep. '
            'Browse only filters platforms that have finished Setup. Export '
            'the score list to move it onto another device.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _clientId,
            decoration: const InputDecoration(
              labelText: 'Twitch Client ID',
              isDense: true,
            ),
            autocorrect: false,
            enableSuggestions: false,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _clientSecret,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'Twitch Client Secret',
              isDense: true,
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            autocorrect: false,
            enableSuggestions: false,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton(
                onPressed: () async {
                  await ref.read(igdbSyncProvider.notifier).saveCredentials(
                    clientId: _clientId.text,
                    clientSecret: _clientSecret.text,
                  );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('IGDB login saved')),
                  );
                },
                child: const Text('Save'),
              ),
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse('https://dev.twitch.tv/console/apps'),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('Twitch console'),
              ),
              TextButton(
                onPressed: sync.running || !sync.configured
                    ? null
                    : () => _openSetup(catalog),
                child: const Text('Setup'),
              ),
              TextButton(
                onPressed: sync.running ? null : _exportScores,
                child: const Text('Export'),
              ),
              TextButton(
                onPressed: sync.running ? null : _importScores,
                child: const Text('Import'),
              ),
              if (sync.running)
                TextButton(
                  onPressed: () => ref.read(igdbSyncProvider.notifier).cancel(),
                  child: const Text('Stop'),
                ),
            ],
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
                    'Reading ${_platformName(catalog, sync.activePlatform)}'
                    ' · ${sync.platforms[sync.activePlatform]?.stored ?? 0} titles',
                  ),
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
        if (sync.platforms.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '${sync.storedTitles} titles across ${sync.platforms.length} platforms',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        for (final entry in sync.platforms.entries)
          ListTile(
            dense: true,
            title: Text(_platformName(catalog, entry.key)),
            subtitle: Text(
              entry.value.complete
                  ? 'Finished · ${entry.value.stored} titles · stop at '
                      '${entry.value.cutoff <= 0 ? 'any score' : entry.value.cutoff.toStringAsFixed(0)}'
                  : 'Stopped · ${entry.value.stored} titles',
            ),
          ),
      ],
    );
  }

  Future<void> _openSetup(List<Platform> catalog) async {
    List<IgdbGenre> genres = ref.read(igdbSyncProvider).genres;
    try {
      genres = await ref.read(igdbSyncProvider.notifier).loadGenres();
    } on IgdbException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
      return;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not reach IGDB.')),
      );
      return;
    }
    if (!mounted) return;
    final cutoff = ref.read(settingsProvider).igdbStopScore;
    final result = await showModalBottomSheet<_IgdbSetupRequest>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _IgdbSetupSheet(
        catalog: catalog,
        genres: genres,
        cutoff: cutoff,
      ),
    );
    if (result == null || !mounted) return;
    await ref.read(settingsProvider.notifier).setIgdbStopScore(result.cutoff);
    await ref.read(igdbSyncProvider.notifier).runSetup(
      platforms: result.platforms,
      genreIds: result.genreIds,
      cutoff: result.cutoff,
    );
  }

  Future<void> _exportScores() async {
    final transfer = await ref.read(igdbSyncProvider.notifier).exportTransfer();
    if (!mounted) return;
    if (transfer.scores.isEmpty && transfer.sync.isEmpty) {
      _tell('No IGDB scores to export.');
      return;
    }
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Export IGDB scores',
      fileName: 'romgi-igdb.json',
      bytes: Uint8List.fromList(utf8.encode(encodeIgdbTransfer(transfer))),
    );
    if (!mounted || path == null) return;
    _tell('Exported ${transfer.scores.length} scores.');
  }

  Future<void> _importScores() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: 'Import IGDB scores',
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
          .read(igdbSyncProvider.notifier)
          .importTransfer(source);
      if (!mounted) return;
      _tell('Imported $count scores. Download history was left as it is.');
    } on IgdbTransferException catch (error) {
      if (!mounted) return;
      _tell(error.message);
    }
  }

  void _tell(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _IgdbSetupRequest {
  final List<String> platforms;
  final List<int> genreIds;
  final double cutoff;

  const _IgdbSetupRequest({
    required this.platforms,
    required this.genreIds,
    required this.cutoff,
  });
}

class _IgdbSetupSheet extends StatefulWidget {
  final List<Platform> catalog;
  final List<IgdbGenre> genres;
  final double cutoff;

  const _IgdbSetupSheet({
    required this.catalog,
    required this.genres,
    required this.cutoff,
  });

  @override
  State<_IgdbSetupSheet> createState() => _IgdbSetupSheetState();
}

class _IgdbSetupSheetState extends State<_IgdbSetupSheet> {
  final _checked = <String>{};
  final _genres = <int>{};
  var _query = '';
  late double _cutoff;

  @override
  void initState() {
    super.initState();
    _cutoff = widget.cutoff.clamp(0, 100);
  }

  List<Platform> get _platforms {
    return [
      for (final platform in widget.catalog)
        if (igdbPlatformIds.containsKey(platform.id.toLowerCase()))
          if (_query.isEmpty ||
              platform.name.toLowerCase().contains(_query) ||
              platform.id.toLowerCase().contains(_query))
            platform,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final platforms = _platforms;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Text(
                      'IGDB Setup',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _checked.isEmpty
                          ? null
                          : () => Navigator.pop(
                              context,
                              _IgdbSetupRequest(
                                platforms: [
                                  for (final platform in widget.catalog)
                                    if (_checked.contains(platform.id))
                                      platform.id,
                                ],
                                genreIds: _genres.toList(),
                                cutoff: _cutoff,
                              ),
                            ),
                      child: const Text('Start'),
                    ),
                  ],
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
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: platforms.isEmpty
                        ? null
                        : () => setState(() {
                            final ids = platforms.map(
                              (platform) => platform.id,
                            );
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
                ),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: Text(
                        _cutoff <= 0
                            ? 'Keep every scored game'
                            : 'Keep scores of ${_cutoff.toStringAsFixed(0)} and up',
                      ),
                    ),
                    Slider(
                      value: _cutoff,
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: _cutoff.toStringAsFixed(0),
                      onChanged: (value) => setState(() => _cutoff = value),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                      child: Text(
                        'Genres',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final genre in widget.genres)
                            FilterChip(
                              label: Text(genre.name),
                              selected: _genres.contains(genre.id),
                              onSelected: (selected) => setState(() {
                                if (selected) {
                                  _genres.add(genre.id);
                                } else {
                                  _genres.remove(genre.id);
                                }
                              }),
                            ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      child: Text(
                        'Consoles',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    for (final platform in platforms)
                      CheckboxListTile(
                        dense: true,
                        value: _checked.contains(platform.id),
                        title: Text(platform.name),
                        onChanged: (value) => setState(() {
                          if (value ?? false) {
                            _checked.add(platform.id);
                          } else {
                            _checked.remove(platform.id);
                          }
                        }),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

String _platformName(List<Platform> catalog, String? id) {
  if (id == null) return 'IGDB';
  for (final platform in catalog) {
    if (platform.id == id) return platform.name;
  }
  return PlatformNames.getDisplayName(id);
}
