import '../models/models.dart';
import '../utils/archive_files.dart';
import 'download_service.dart';
import 'link_resolver.dart';
import 'rom_database_service.dart';

class BatchAcquireReport {
  int ghosts = 0;
  int queued = 0;
  int skippedArchives = 0;
  int duplicates = 0;
  int missing = 0;

  bool get addedAnything => ghosts > 0 || queued > 0;
}

/// Ghost or queue every selected slug. A multi-disc group is ghosted only
/// when every selected member can be ghosted. A group that contains an
/// archive is left for a real download. The playlist is written only when
/// the whole group is ghosted.
Future<BatchAcquireReport> acquireSelection({
  required List<String> slugs,
  required bool ghost,
  required RomDatabaseService db,
  required DownloadService downloads,
  required LinkResolverPrefs prefs,
}) async {
  final report = BatchAcquireReport();
  final selected = slugs.toSet();
  final handledGroups = <String>{};
  final resolver = LinkResolver(sourcePriority: kKnownSourcePriority);

  for (final slug in slugs) {
    final group = await db.getEntryGroup(slug);
    if (group != null && group.members.length > 1) {
      if (!handledGroups.add(group.id)) continue;
      final members = group.members
          .where((member) => selected.contains(member.slug))
          .toList();
      await _acquireGroup(
        group: group,
        members: members,
        ghost: ghost,
        db: db,
        downloads: downloads,
        prefs: prefs,
        resolver: resolver,
        report: report,
      );
      continue;
    }
    await _acquireOne(
      slug: slug,
      ghost: ghost,
      db: db,
      downloads: downloads,
      prefs: prefs,
      resolver: resolver,
      report: report,
    );
  }
  return report;
}

Future<void> _acquireGroup({
  required EntryGroup group,
  required List<EntryGroupMember> members,
  required bool ghost,
  required RomDatabaseService db,
  required DownloadService downloads,
  required LinkResolverPrefs prefs,
  required LinkResolver resolver,
  required BatchAcquireReport report,
}) async {
  if (members.isEmpty) return;
  if (!ghost) {
    if (members.length == group.members.length) {
      final result = await downloads.addDiscGroup(
        group,
        prefs: prefs,
        sourcePriority: kKnownSourcePriority,
      );
      report.queued += result.added;
      report.duplicates += result.duplicates;
      report.missing += result.skipped;
      return;
    }
    for (final member in members) {
      await _acquireOne(
        slug: member.slug,
        ghost: false,
        db: db,
        downloads: downloads,
        prefs: prefs,
        resolver: resolver,
        report: report,
      );
    }
    return;
  }

  final resolved =
      <({EntryGroupMember member, RomEntry entry, DownloadLink link})>[];
  var sawArchive = false;
  var sawMissing = false;
  for (final member in members) {
    final entry = await db.getEntry(member.slug);
    final ranked = entry == null
        ? const <ResolvedLink>[]
        : resolver.rank(entry.links, prefs);
    final link = _bestLink(ranked);
    if (entry == null || link == null) {
      sawMissing = true;
      continue;
    }
    if (!canGhostRelease(filename: link.filename, format: link.format)) {
      sawArchive = true;
      continue;
    }
    resolved.add((member: member, entry: entry, link: link));
  }
  if (sawArchive || sawMissing || resolved.length != members.length) {
    if (sawArchive) {
      report.skippedArchives += members.length;
    } else {
      report.missing += members.length;
    }
    return;
  }

  final wholeGroup = members.length == group.members.length;
  for (final item in resolved) {
    final (result, _) = await downloads.createGhost(
      slug: item.entry.slug,
      title: item.entry.title,
      platform: item.entry.platform,
      boxartUrl: item.entry.boxartUrl,
      link: item.link,
      groupId: wholeGroup ? group.id : null,
      groupIndex: wholeGroup ? item.member.index : null,
      groupTitle: wholeGroup ? group.title : null,
      groupTotal: wholeGroup ? group.members.length : null,
    );
    if (result == AddDownloadResult.added) {
      report.ghosts++;
    } else {
      report.duplicates++;
    }
  }
}

Future<void> _acquireOne({
  required String slug,
  required bool ghost,
  required RomDatabaseService db,
  required DownloadService downloads,
  required LinkResolverPrefs prefs,
  required LinkResolver resolver,
  required BatchAcquireReport report,
}) async {
  final entry = await db.getEntry(slug);
  if (entry == null) {
    report.missing++;
    return;
  }
  final link = _bestLink(resolver.rank(entry.links, prefs));
  if (link == null) {
    report.missing++;
    return;
  }
  if (ghost && !canGhostRelease(filename: link.filename, format: link.format)) {
    report.skippedArchives++;
    return;
  }
  if (ghost) {
    final (result, _) = await downloads.createGhost(
      slug: entry.slug,
      title: entry.title,
      platform: entry.platform,
      boxartUrl: entry.boxartUrl,
      link: link,
    );
    if (result == AddDownloadResult.added) {
      report.ghosts++;
    } else {
      report.duplicates++;
    }
    return;
  }
  final (result, _) = await downloads.addDownload(
    slug: entry.slug,
    title: entry.title,
    platform: entry.platform,
    boxartUrl: entry.boxartUrl,
    link: link,
  );
  if (result == AddDownloadResult.added) {
    report.queued++;
  } else {
    report.duplicates++;
  }
}

DownloadLink? _bestLink(List<ResolvedLink> ranked) {
  for (final item in ranked) {
    if (item.score < 0) continue;
    return item.link;
  }
  return ranked.isEmpty ? null : ranked.first.link;
}
