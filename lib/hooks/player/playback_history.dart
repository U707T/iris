import 'package:iris/models/progress.dart';
import 'package:iris/store/use_history_store.dart';

/// A content URI has no recorded durable grant on FileItem. Do not store a
/// temporary Android Intent/picker grant as restorable history.
bool canPersistPlaybackUri(String uri) =>
    Uri.tryParse(uri)?.scheme.toLowerCase() != 'content';

Future<void> savePlaybackHistory(
  Progress progress, {
  Future<void> Function(Progress)? write,
  Future<void> Function()? flush,
}) async {
  if (!canPersistPlaybackUri(progress.file.uri)) return;
  await (write ?? useHistoryStore().add)(progress);
  await (flush ?? useHistoryStore().flush)();
}
