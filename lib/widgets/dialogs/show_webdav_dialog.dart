import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/models/storages/webdav.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/default_gateway.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:uuid/uuid.dart';

/// 新建 WebDAV 时的默认配置（固定值，默认只读；关闭开关后手动修改）
const String _defaultName = 'Dav';
const String _defaultPath = '/dav';
const String _defaultPort = '5244';
const String _defaultUsername = 'admin';
const String _defaultPassword = '123456';

Future<void> showWebDAVDialog(
  BuildContext context, {
  WebDAVStorage? storage,
}) async => await showDialog<void>(
  context: context,
  builder: (BuildContext context) {
    return WebDAVDialog(storage: storage);
  },
);

class WebDAVDialog extends HookWidget {
  const WebDAVDialog({super.key, this.storage, this.connectionTester});
  final WebDAVStorage? storage;
  final Future<bool> Function(WebDAVStorage)? connectionTester;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final bool isEdit =
        storage != null && (useStorageStore().state.storages.contains(storage));

    // 新建: 预填默认 Dav 配置（预填值，可直接修改）
    // 编辑已有连接: 按保存的值展示

    final id = useMemoized(() => storage?.id ?? const Uuid().v4());
    final name = useState(storage?.name ?? _defaultName);
    final host = useState(storage?.host ?? '');
    final basePath = useState(storage?.basePath ?? const [_defaultPath]);
    final username = useState(storage?.username ?? _defaultUsername);
    final password = useState(storage?.password ?? _defaultPassword);
    final https = useState(storage?.https ?? true);

    final nameController = useTextEditingController(text: name.value);
    final hostController = useTextEditingController(text: host.value);
    final pathController = useTextEditingController(
      text: basePath.value.join('/'),
    );
    final usernameController = useTextEditingController(text: username.value);
    final passwordController = useTextEditingController(text: password.value);
    final portController = useTextEditingController(
      text: storage?.port ?? _defaultPort,
    );

    final isGatewayLoading = useState(false);
    final gatewayError = useState(false);

    final isTested = useState(false);
    final allowHttp = useState(false);
    final testGeneration = useRef(0);

    void add() {
      useStorageStore().addStorage(
        WebDAVStorage(
          id: id,
          name: name.value,
          host: host.value,
          basePath: basePath.value,
          port: portController.text,
          username: username.value,
          password: password.value,
          https: https.value,
        ),
      );
    }

    void update() {
      useStorageStore().updateStorage(
        useStorageStore().state.storages.indexOf(storage as Storage),
        WebDAVStorage(
          id: id,
          name: name.value,
          host: host.value,
          basePath: basePath.value,
          port: portController.text,
          username: username.value,
          password: password.value,
          https: https.value,
        ),
      );
    }

    void testConnection() async {
      if (!https.value && !allowHttp.value) return;
      final generation = ++testGeneration.value;
      final snapshot = [
        host.value,
        portController.text,
        basePath.value.join('/'),
        username.value,
        password.value,
        https.value,
      ].join('\u0000');
      final bool isConnected = await (connectionTester ?? testWebDAV)(
        WebDAVStorage(
          id: id,
          name: name.value,
          host: host.value,
          basePath: basePath.value,
          port: portController.text,
          username: username.value,
          password: password.value,
          https: https.value,
        ),
      );
      if (!context.mounted || generation != testGeneration.value) return;
      final current = [
        host.value,
        portController.text,
        basePath.value.join('/'),
        username.value,
        password.value,
        https.value,
      ].join('\u0000');
      if (snapshot == current) isTested.value = isConnected;
    }

    /// 切换 HTTPS：只在标准端口 80 / 443 之间跟随，自定义端口不动。
    void setHttps(bool value) {
      isTested.value = false;
      if (value && portController.text == '80') {
        portController.text = '443';
      } else if (!value && portController.text == '443') {
        portController.text = '80';
      }
      allowHttp.value = false;
      https.value = value;
    }

    /// 读取默认网关（一般是路由器地址）填到主机框，省得手动查 IP
    Future<void> fillDefaultGateway() async {
      if (isGatewayLoading.value) return;
      isGatewayLoading.value = true;
      final gateway = await getDefaultGateway();
      if (!context.mounted) return;
      isGatewayLoading.value = false;

      if (gateway == null) {
        gatewayError.value = true;
        return;
      }

      hostController.text = gateway;
      host.value = gateway;
      gatewayError.value = false;
      isTested.value = false;
    }

    return AlertDialog(
      title: Text(isEdit ? t.edit_webdav_storage : t.add_webdav_storage),
      content: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Form(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: t.name,
                  ),
                  onChanged: (value) {
                    name.value = value.trim();
                    isTested.value = false;
                  },
                ),
                const SizedBox(height: 16.0),
                TextFormField(
                  controller: hostController,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: t.host,
                    suffixIcon: IconButton(
                      tooltip: t.default_gateway,
                      visualDensity: VisualDensity.compact,
                      onPressed: isGatewayLoading.value
                          ? null
                          : fillDefaultGateway,
                      icon: isGatewayLoading.value
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.bolt_rounded, size: 20),
                    ),
                  ),
                  onChanged: (value) {
                    gatewayError.value = false;
                    host.value = value.trim().split('//').last;
                    isTested.value = false;
                  },
                ),
                if (gatewayError.value)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        t.default_gateway_failed,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16.0),
                TextFormField(
                  controller: pathController,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: t.path,
                  ),
                  onChanged: (value) {
                    final trimmedValue = value.trim().replaceAll(
                      RegExp(r'^\/+|\/+$'),
                      '',
                    );
                    final finalPath = '/$trimmedValue';
                    basePath.value = [finalPath];
                    isTested.value = false;
                  },
                ),
                const SizedBox(height: 16.0),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: portController,
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          labelText: t.port,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (value) {
                          isTested.value = false;
                          if (value == '443') {
                            https.value = true;
                          } else if (value == '80') {
                            https.value = false;
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('HTTPS'),
                        const SizedBox(width: 4),
                        ExcludeFocus(
                          child: Switch.adaptive(
                            value: https.value,
                            onChanged: setHttps,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16.0),
                if (!https.value) ...[
                  Text(
                    t.webdav_http_warning,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.webdav_http_acknowledge),
                    value: allowHttp.value,
                    onChanged: (value) {
                      allowHttp.value = value ?? false;
                      isTested.value = false;
                      testGeneration.value++;
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: usernameController,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: t.username,
                  ),
                  onChanged: (value) {
                    username.value = value.trim();
                    isTested.value = false;
                  },
                ),
                const SizedBox(height: 16.0),
                TextFormField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: t.password,
                  ),
                  obscureText: true,
                  onChanged: (value) {
                    password.value = value;
                    isTested.value = false;
                  },
                ),
                const SizedBox(height: 16.0),
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context, 'Cancel'),
          child: Text(t.cancel),
        ),
        TextButton(
          onPressed: https.value || allowHttp.value ? testConnection : null,
          child: Text(t.test_connection),
        ),
        TextButton(
          onPressed: isTested.value && (https.value || allowHttp.value)
              ? () {
                  Navigator.pop(context, 'OK');
                  isEdit ? update() : add();
                }
              : null,
          child: Text(isEdit ? t.save : t.add),
        ),
      ],
    );
  }
}
