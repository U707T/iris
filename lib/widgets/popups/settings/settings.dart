import 'package:material_ui/material_ui.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:iris/widgets/panel.dart';
import 'package:iris/widgets/popups/settings/about.dart';
import 'package:iris/widgets/popups/settings/general.dart';
import 'package:iris/widgets/popups/settings/play.dart';

/// 设置：一页，从上到下 —— 通用、播放、关于。
///
/// 以前是四个页签 + 底部再一条标题栏。页签本身不是问题，问题在于页签把
/// 每一页都撑成整块面板：通用页只有三行，下面空着 500px。现在一页滚到底，
/// 面板按内容收缩；内容超过上限才滚动。
class Settings extends StatelessWidget {
  const Settings({super.key});

  static const title = 'Settings';

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PanelHeader(title: Text(t.settings)),
        const PanelDivider(),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: const [General(), Play(), About()],
          ),
        ),
      ],
    );
  }
}
