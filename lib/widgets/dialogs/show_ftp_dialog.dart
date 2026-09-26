import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:iris/models/storages/ftp.dart';
import 'package:iris/models/storages/storage.dart';
import 'package:iris/store/use_storage_store.dart';
import 'package:iris/utils/get_localizations.dart';
import 'package:uuid/uuid.dart';

Future<void> showFTPDialog(BuildContext context, {FTPStorage? storage}) async =>
    await showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return FTPDialog(storage: storage);
      },
    );

class FTPDialog extends HookWidget {
  const FTPDialog({
    super.key,
    this.storage,
  });
  final FTPStorage? storage;

  @override
  Widget build(BuildContext context) {
    final t = getLocalizations(context);
    final bool isEdit =
        storage != null && (useStorageStore().state.storages.contains(storage));

    final id = useMemoized(() => storage?.id ?? const Uuid().v4());
    final name = useState(storage?.name ?? '');
    final host = useState(storage?.host ?? '');
    final basePath = useState(storage?.basePath ?? ['/']);
    final username = useState(storage?.username ?? '');
    final password = useState(storage?.password ?? '');

    final isTested = useState(false);

    final TextEditingController portController =
        useTextEditingController(text: storage?.port ?? '21');

    void add() {
      useStorageStore().addStorage(
        FTPStorage(
          id: id,
          name: name.value,
          host: host.value,
          basePath: basePath.value,
          port: portController.text,
          username: username.value,
          password: password.value,
        ),
      );
    }

    void update() {
      useStorageStore().updateStorage(
        useStorageStore().state.storages.indexOf(storage as Storage),
        FTPStorage(
          id: id,
          name: name.value,
          host: host.value,
          basePath: basePath.value,
          port: portController.text,
          username: username.value,
          password: password.value,
        ),
      );
    }

    void testConnection() async {
      final bool isConnected = await testFTP(FTPStorage(
        id: id,
        name: name.value,
        host: host.value,
        basePath: basePath.value,
        port: portController.text,
        username: username.value,
        password: password.value,
      ));
      isTested.value = isConnected;
    }

    return AlertDialog(
      title: Text(isEdit ? t.edit_ftp_storage : t.add_ftp_storage),
      content: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Form(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: t.name,
                  ),
                  initialValue: name.value,
                  onChanged: (value) {
                    name.value = value.trim();
                    isTested.value = false;
                  },
                ),
                const SizedBox(height: 16.0),
                TextFormField(
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: t.host,
                  ),
                  initialValue: host.value,
                  onChanged: (value) {
                    host.value = value.trim().split('//').last;
                    isTested.value = false;
                  },
                ),
                const SizedBox(height: 16.0),
                TextFormField(
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: t.path,
                    ),
                    initialValue: basePath.value.join('/'),
                    onChanged: (value) {
                      final trimmedValue =
                          value.trim().replaceAll(RegExp(r'^\/+|\/+$'), '');
                      final finalPath = '/$trimmedValue';
                      basePath.value = [finalPath];
                      isTested.value = false;
                    }),
                const SizedBox(height: 16.0),
                TextFormField(
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: t.port,
                  ),
                  controller: portController,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  onChanged: (value) {
                    isTested.value = false;
                  },
                ),
                const SizedBox(height: 16.0),
                TextFormField(
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: t.username,
                  ),
                  initialValue: username.value,
                  onChanged: (value) {
                    username.value = value.trim();
                    isTested.value = false;
                  },
                ),
                const SizedBox(height: 16.0),
                TextFormField(
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: t.password,
                  ),
                  initialValue: password.value,
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
