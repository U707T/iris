import 'dart:io';
import 'package:iris/utils/platform.dart';
import 'package:path/path.dart' as p;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/info.dart';
import 'package:iris/widgets/dialogs/show_release_dialog.dart';
import 'package:iris/widgets/popups/settings/dependencies.dart';
import 'package:iris/utils/get_latest_release.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/utils/url.dart';
import 'package:iris/widgets/panel.dart';
import 'package:iris/widgets/setting_row.dart';
import 'package:package_info_plus/package_info_plus.dart';

bool isMsix() {
  if (!isWindows) {
    return false;
  }
  String resolvedExecutablePath = Platform.resolvedExecutable;
  String path = p.dirname(resolvedExecutablePath);
  String manifestPath = p.join(path, 'AppxManifest.xml');
  return File(manifestPath).existsSync();
}

class About extends HookWidget {
  const About({super.key});

  static const title = 'About';

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final packageInfo = useState<PackageInfo?>(null);
    final noNewVersion = useState(false);

    useEffect(() {
      void getPackageInfo() async =>
          packageInfo.value = await PackageInfo.fromPlatform();

      getPackageInfo();
      return null;
    }, []);

    final scheme = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Image.asset('assets/images/logo_transparent.png'),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    INFO.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (packageInfo.value != null)
                    Text(
                      packageInfo.value!.version,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        PanelSection(
          children: [
            SettingRow(
              icon: Icons.update_rounded,
              label: t.check_update,
              value: noNewVersion.value ? t.no_new_version : null,
              onTap: () async {
                if (isMsix()) {
                  launchURL(
                    'ms-windows-store://pdp/?ProductId=${INFO.msStoreId}',
                  );
                  return;
                }
                noNewVersion.value = false;
                final release = await getLatestRelease();
                if (release != null && context.mounted) {
                  showReleaseDialog(context, release: release);
                } else {
                  noNewVersion.value = true;
                }
              },
            ),
            SettingRow(
              icon: Icons.code_rounded,
              label: t.source_code,
              value: 'GitHub',
              onTap: () => launchURL(INFO.githubUrl),
            ),
            SettingRow(
              icon: Icons.person_rounded,
              label: t.author,
              value: INFO.author,
              onTap: () => launchURL(INFO.authorUrl),
            ),
            SettingRow(
              icon: Icons.inventory_2_rounded,
              label: t.dependencies,
              onTap: () => showDependenciesDialog(context),
            ),
          ],
        ),
      ],
    );
  }
}
