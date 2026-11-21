import 'dart:io';

import 'package:iris/utils/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

const legacyMigrationMarker = '.legacy-migration-complete';
typedef CopyMigrationFile = Future<void> Function(File source, File staging);

/// Retry missing files after an interrupted migration. Existing destination
/// files always win; only a complete pass creates the separate completion flag.
Future<bool> migrateLegacyDirectory({
  required Directory source,
  required Directory destination,
  CopyMigrationFile? copyFile,
}) async {
  final marker = File(p.join(destination.path, legacyMigrationMarker));
  if (await marker.exists() || !await source.exists()) return false;
  await destination.create(recursive: true);
  final entities = await source.list(followLinks: false).toList();
  for (final entity in entities) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (name == legacyMigrationMarker ||
        name.endsWith('.tmp') ||
        name.endsWith('.bak')) {
      continue;
    }
    final target = File(p.join(destination.path, name));
    if (await target.exists()) continue;
    final staging = File(p.join(destination.path, '.migration-$name.tmp'));
    if (copyFile == null) {
      await entity.copy(staging.path);
    } else {
      await copyFile(entity, staging);
    }
    // Do not replace a file created while copying (for example by a previous
    // application instance). An interrupted staging copy is safely retried.
    if (await target.exists()) {
      if (await staging.exists()) await staging.delete();
      continue;
    }
    await staging.rename(target.path);
  }
  await marker.writeAsString('complete\n', flush: true);
  return true;
}

Future<bool> dataMigration() async {
  if (!Platform.isWindows) return false;
  try {
    final destination = await getApplicationSupportDirectory();
    final source = Directory(
      p.normalize('${destination.path}/../../nini22p.iris/iris'),
    );
    if (!await File(p.join(source.path, 'flutter_secure_storage.dat'))
        .exists()) {
      return false;
    }
    return await migrateLegacyDirectory(
      source: source,
      destination: destination,
    );
  } catch (e) {
    logger('Data migration failed; missing files will be retried: $e');
    return false;
  }
}
