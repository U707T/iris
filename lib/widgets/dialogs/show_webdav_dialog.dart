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

Future<void> showWebDAVDialog(BuildContext context,
        {WebDAVStorage? storage}) async =>
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return WebDAVDialog(storage: storage);
      },
    );

class WebDAVDialog extends HookWidget {
  const WebDAVDialog({
    super.key,
    this.storage,
  });
  final WebDAVStorage? storage;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final bool isEdit =
        storage != null && (useStorageStore().state.storages.contains(storage));

    // 新建: 默认套用固定的 Dav 配置并锁定; 关闭开关才允许手动改
    // 编辑已有连接: 按保存的值展示, 正常可编辑
    final useDefaults = useState(!isEdit);
    final bool locked = !isEdit && useDefaults.value;

    final id = useMemoized(() => storage?.id ?? const Uuid().v4());
    final name = useState(storage?.name ?? _defaultName);
    final host = useState(storage?.host ?? '');
    final basePath = useState(storage?.basePath ?? const [_defaultPath]);
    final username = useState(storage?.username ?? _defaultUsername);
    final password = useState(storage?.password ?? _defaultPassword);
    final https = useState(storage?.https ?? false);

    final nameController = useTextEditingController(text: name.value);
    final hostController = useTextEditingController(text: host.value);
    final pathController =
        useTextEditingController(text: basePath.value.join('/'));
    final usernameController = useTextEditingController(text: username.value);
    final passwordController = useTextEditingController(text: password.value);
    final portController =
        useTextEditingController(text: storage?.port ?? _defaultPort);

    final isGatewayLoading = useState(false);
    final gatewayError = useState(false);

    final isTested = useState(false);

    void setUseDefaults(bool value) {
      useDefaults.value = value;
      isTested.value = false;
      if (!value) return;

      // 重新套用默认值（覆盖手动改过的内容）
      name.value = _defaultName;
      nameController.text = _defaultName;
      pathController.text = _defaultPath;
      basePath.value = const [_defaultPath];
      username.value = _defaultUsername;
      usernameController.text = _defaultUsername;
      password.value = _defaultPassword;
      passwordController.text = _defaultPassword;
      portController.text = _defaultPort;
      https.value = false;
    }

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
      final bool isConnected = await testWebDAV(WebDAVStorage(
        id: id,
        name: name.value,
        host: host.value,
        basePath: basePath.value,
        port: portController.text,
        username: username.value,
        password: password.value,
        https: https.value,
      ));
      isTested.value = isConnected;
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
                if (!isEdit)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(t.use_default_webdav),
                    subtitle: Text(t.use_default_webdav_description),
                    value: useDefaults.value,
                    onChanged: setUseDefaults,
                  ),
                TextFormField(
                  controller: nameController,
                  readOnly: locked,
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
                      onPressed:
                          isGatewayLoading.value ? null : fillDefaultGateway,
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
                    readOnly: locked,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: t.path,
                    ),
                    onChanged: (value) {
                      final trimmedValue =
                          value.trim().replaceAll(RegExp(r'^\/+|\/+$'), '');
                      final finalPath = '/$trimmedValue';
                      basePath.value = [finalPath];
                      isTested.value = false;
                    }),
                const SizedBox(height: 16.0),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: portController,
                        readOnly: locked,
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
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 96,
                      child: ListTile(
                        contentPadding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
                        visualDensity:
                            const VisualDensity(horizontal: -4, vertical: 0),
                        title: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text('https'),
                              Focus(
                                descendantsAreFocusable: false,
                                canRequestFocus: false,
                                child: Checkbox(
                                  value: https.value,
                                  onChanged: locked
                                      ? null
                                      : (_) {
                                          isTested.value = false;
                                          if (portController.text == '80' &&
                                              https.value == false) {
                                            portController.text = '443';
                                          } else if (portController.text ==
                                                  '443' &&
                                              https.value == true) {
                                            portController.text = '80';
                                          }
                                          https.value = !https.value;
                                        },
                                ),
                              ),
                            ]),
                        onTap: locked
                            ? null
                            : () {
                                isTested.value = false;
                                if (!https.value) {
                                  portController.text = '443';
                                } else {
                                  portController.text = '80';
                                }
                                https.value = !https.value;
                              },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16.0),
                TextFormField(
                  controller: usernameController,
                  readOnly: locked,
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
                  readOnly: locked,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: t.password,
                  ),
                  obscureText: true,
                  onChanged: (value) {
                    password.value = value.trim();
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
          onPressed: testConnection,
          child: Text(t.test_connection),
        ),
        TextButton(
          onPressed: isTested.value
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
