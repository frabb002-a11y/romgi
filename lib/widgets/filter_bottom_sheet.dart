import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../utils/rom_pick.dart';

class FilterBottomSheet extends ConsumerStatefulWidget {
  const FilterBottomSheet({super.key});

  @override
  ConsumerState<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends ConsumerState<FilterBottomSheet> {
  late Set<String> _selectedPlatforms;
  late Set<String> _selectedRegions;
  late bool _retroAchievementsOnly;
  late bool _scoreOnly;
  late double _minimumScore;
  late bool _oneGameOneRom;
  late List<String> _excludeTerms;
  final _termController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final searchState = ref.read(searchProvider);

    _selectedPlatforms = searchState.selectedPlatforms.toSet();
    _selectedRegions = searchState.selectedRegions.toSet();
    _retroAchievementsOnly = searchState.retroAchievementsOnly;
    _scoreOnly = searchState.scoreOnly;
    _minimumScore = searchState.minimumScore;
    _oneGameOneRom = searchState.oneGameOneRom;
    _excludeTerms = List.of(ref.read(settingsProvider).excludeTerms);
  }

  @override
  void dispose() {
    _termController.dispose();
    super.dispose();
  }

  void _addTerm(String raw) {
    final next = normalizeExcludeTerms([..._excludeTerms, raw]);
    if (next.length == _excludeTerms.length) return;
    setState(() => _excludeTerms = next);
    _termController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final platformsAsync = ref.watch(platformsProvider);
    final regionsAsync = ref.watch(regionsProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Filters',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _selectedPlatforms.clear();
                          _selectedRegions.clear();
                          _retroAchievementsOnly = false;
                          _scoreOnly = false;
                          _minimumScore = 0;
                          _oneGameOneRom = false;
                        });
                      },
                      child: const Text('Clear all'),
                    ),
                  ],
                ),
              ),

              const Divider(),

              // Filter content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    // RetroAchievements section
                    if (ref.read(romDatabaseProvider).hasRaColumns) ...[
                      Text(
                        'RetroAchievements',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilterChip(
                            label: const Text('Has Achievements'),
                            selected: _retroAchievementsOnly,
                            onSelected: (selected) {
                              setState(() {
                                _retroAchievementsOnly = selected;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Regions section
                    Text(
                      'Regions',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    regionsAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, stackTrace) =>
                          Text('Error loading regions: $error'),
                      data: (regions) => Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: regions.map((region) {
                          final isSelected = _selectedRegions.contains(
                            region.id,
                          );
                          return FilterChip(
                            label: Text(region.name),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedRegions.add(region.id);
                                } else {
                                  _selectedRegions.remove(region.id);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),

                    const SizedBox(height: 24),

                    Text(
                      'IGDB score',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Only platforms finished in IGDB Setup are filtered. '
                      'The rest stay in the results.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Has a score'),
                      value: _scoreOnly,
                      onChanged: (value) =>
                          setState(() => _scoreOnly = value),
                    ),
                    Text(
                      _minimumScore <= 0
                          ? 'Any score'
                          : 'At least ${_minimumScore.toStringAsFixed(0)}',
                    ),
                    Slider(
                      value: _minimumScore,
                      min: 0,
                      max: 100,
                      divisions: 20,
                      label: _minimumScore.toStringAsFixed(0),
                      onChanged: _scoreOnly
                          ? (value) => setState(() => _minimumScore = value)
                          : null,
                    ),

                    const SizedBox(height: 24),

                    Text(
                      'One game, one ROM',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Keeps one release per game: USA, then Europe, then Japan. '
                      'Global counts as USA. The highest version wins, so (v2.00) '
                      'beats (v1.01). Titles '
                      'matching the terms below are removed first.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('1G1R'),
                      value: _oneGameOneRom,
                      onChanged: (value) =>
                          setState(() => _oneGameOneRom = value),
                    ),

                    const SizedBox(height: 8),
                    Text(
                      'Hide titles',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'A term matches a whole word in the title, such as FIFA, '
                      '(Beta), or (Minis).',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final term in _excludeTerms)
                          InputChip(
                            label: Text(term),
                            onDeleted: () => setState(() {
                              _excludeTerms = [
                                for (final item in _excludeTerms)
                                  if (item != term) item,
                              ];
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _termController,
                      decoration: const InputDecoration(
                        hintText: 'Add a term',
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: _addTerm,
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () => setState(
                          () => _excludeTerms = List.of(defaultExcludeTerms),
                        ),
                        child: const Text('Restore default terms'),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Platforms section
                    Text(
                      'Platforms',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    platformsAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (error, stackTrace) =>
                          Text('Error loading platforms: $error'),
                      data: (platforms) => _buildPlatformsList(platforms),
                    ),
                  ],
                ),
              ),

              // Apply button
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () async {
                        await ref
                            .read(settingsProvider.notifier)
                            .setExcludeTerms(_excludeTerms);
                        if (!context.mounted) return;
                        ref.read(searchProvider.notifier)
                          ..setSelectedPlatforms(_selectedPlatforms.toList())
                          ..setSelectedRegions(_selectedRegions.toList())
                          ..setRetroAchievementsOnly(_retroAchievementsOnly)
                          ..setScoreOnly(_scoreOnly)
                          ..setMinimumScore(_minimumScore)
                          ..setOneGameOneRom(_oneGameOneRom)
                          ..search();
                        Navigator.pop(context);
                      },
                      child: const Text('Apply Filters'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPlatformsList(List<Platform> platforms) {
    final grouped = <String, List<Platform>>{};
    for (final platform in platforms) {
      grouped.putIfAbsent(platform.brand, () => []).add(platform);
    }

    final sortedBrands = grouped.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sortedBrands.map((brand) {
        final brandPlatforms = grouped[brand]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Text(
                brand,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: brandPlatforms.map((platform) {
                final isSelected = _selectedPlatforms.contains(platform.id);
                return FilterChip(
                  label: Text(platform.name),
                  selected: isSelected,
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedPlatforms.add(platform.id);
                      } else {
                        _selectedPlatforms.remove(platform.id);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
        );
      }).toList(),
    );
  }
}
