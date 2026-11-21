import 'dart:async';
import 'dart:io';

import 'package:iris/utils/file_size_convert.dart';
import 'package:iris/utils/platform.dart';
import 'package:path/path.dart' as p;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:iris/utils/get_latest_release.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/url.dart';
import 'package:iris/pages/player/player_handoff.dart';

bool isPortable() {
  String resolvedExecutablePath = Platform.resolvedExecutable;
  String path = p.dirname(resolvedExecutablePath);
  String batFilePath = p.join(path, 'iris-updater.ps1');
  return File(batFilePath).existsSync();
}

Future<void> showReleaseDialog(
  BuildContext context, {
  required Release release,
}) async => await showDialog<void>(
  context: context,
  builder: (context) => ReleaseDialog(release: release),
);

class ReleaseDialog extends HookWidget {
  const ReleaseDialog({super.key, required this.release});

  final Release release;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    final updateScriptIsExists = useState(false);

    useEffect(() {
      if (isWindows) {
        updateScriptIsExists.value = isPortable();
      }
      return null;
    }, []);

    final updating = useState(false);

    Future<void> update() async {
      if (!isWindows || updating.value || !isTrustedPortableUpdate(release)) {
        return;
      }
      updating.value = true;
      try {
        await activeHandoffPlayer?.saveProgress();
        final directory = p.dirname(Platform.resolvedExecutable);
        final staging = await Directory.systemTemp.createTemp('iris-updater-');
        final script = await File(p.join(directory, 'iris-updater.ps1'))
            .copy(p.join(staging.path, 'iris-updater.ps1'));
        final ready = File(p.join(staging.path, 'ready'));
        await Process.start(
          p.join(
            Platform.environment['SystemRoot'] ?? r'C:\Windows',
            'System32',
            'WindowsPowerShell',
            'v1.0',
            'powershell.exe',
          ),
          [
            '-NoProfile',
            '-File',
            script.path,
            '-InstallDirectory',
            directory,
            '-DownloadUrl',
            release.downloadUrl,
            '-Sha256',
            release.sha256!,
            '-ReadyFile',
            ready.path,
            '-ParentProcessId',
            '$pid',
          ],
          workingDirectory: staging.path,
          mode: ProcessStartMode.detached,
        );
        var started = false;
        for (var attempt = 0; attempt < 40; attempt++) {
          if (await ready.exists()) {
            started = true;
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        if (!started) throw StateError('Updater did not start');
        exit(0);
      } catch (_) {
        if (!context.mounted) return;
        updating.value = false;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t.download_error)));
      }
    }

    Future<void> cancel() async {
      if (context.mounted) {
        Navigator.pop(context, 'Cancel');
      }
    }

    return AlertDialog(
      title: Text('${t.checked_new_version}: ${release.version}'),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 600),
        child: SingleChildScrollView(
          child: MarkdownBody(data: release.changeLog, shrinkWrap: true),
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: cancel, child: Text(t.cancel)),
        TextButton(
          onPressed: () => launchURL(release.url),
          child: Text(t.releasePage),
        ),
        // Visibility(
        //   visible: !isDesktop,
        //   child: TextButton(
        //     onPressed: () {
        //       launchURL(release.url);
        //       Navigator.pop(context, 'OK');
        //     },
        //     child: Text(t.download),
        //   ),
        // ),
        Visibility(
          visible:
              isDesktop &&
              updateScriptIsExists.value &&
              isTrustedPortableUpdate(release),
          child: TextButton(
            onPressed: updating.value ? null : update,
            child: Text(
              '${t.download_and_update} (${fileSizeConvert(release.size)} MB)',
            ),
          ),
        ),
      ],
    );
  }
}
