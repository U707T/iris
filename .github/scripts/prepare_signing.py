"""Write Java properties safely from CI secrets without shell interpolation."""
import base64
import os
from pathlib import Path


def escape_property(value):
    result = []
    for character in value:
        code = ord(character)
        if character in '\\:=#! ':
            result.append('\\' + character)
        elif character == '\n':
            result.append('\\n')
        elif character == '\r':
            result.append('\\r')
        elif character == '\t':
            result.append('\\t')
        elif code > 0x7E or code < 0x20:
            for offset in range(0, len(character.encode('utf-16-be')), 2):
                unit = character.encode('utf-16-be')[offset:offset + 2]
                result.append('\\u' + unit.hex())
        else:
            result.append(character)
    return ''.join(result)


def main():
    names = ('KEYSTORE', 'STORE_PASSWORD', 'KEY_PASSWORD', 'KEY_ALIAS')
    if any(not os.environ.get(name) for name in names):
        raise SystemExit('Release signing secrets are missing; refusing unsigned release.')
    keystore = base64.b64decode(os.environ['KEYSTORE'], validate=True)
    if not keystore:
        raise SystemExit('Release keystore is empty.')
    Path('android/app/keystore.jks').write_bytes(keystore)
    values = {'storePassword': os.environ['STORE_PASSWORD'],
              'keyPassword': os.environ['KEY_PASSWORD'],
              'keyAlias': os.environ['KEY_ALIAS'], 'storeFile': 'keystore.jks'}
    Path('android/key.properties').write_text(
        ''.join(f'{key}={escape_property(value)}\n' for key, value in values.items()),
        encoding='ascii')


if __name__ == '__main__':
    main()
