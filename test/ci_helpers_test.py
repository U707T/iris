import base64
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


def load_script(name):
    path = Path(__file__).resolve().parents[1] / '.github' / 'scripts' / f'{name}.py'
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


signing = load_script('prepare_signing')


class SigningPropertiesTest(unittest.TestCase):
    def test_special_characters_are_literal_properties(self):
        self.assertEqual(signing.escape_property('a $()`"\\\n\r\t:=#! '),
                         'a\\ $()`"\\\\\\n\\r\\t\\:\\=\\#\\!\\ ')
        self.assertEqual(signing.escape_property('密😀'), '\\u5bc6\\ud83d\\ude00')

    def test_missing_credentials_do_not_create_material(self):
        with patch.dict(os.environ, {}, clear=True):
            with self.assertRaises(SystemExit):
                signing.main()

    def test_write_uses_environment_without_shell_interpolation(self):
        previous = Path.cwd()
        with tempfile.TemporaryDirectory() as temporary:
            try:
                os.chdir(temporary)
                Path('android/app').mkdir(parents=True)
                values = {'KEYSTORE': base64.b64encode(b'fixture-keystore').decode(),
                          'STORE_PASSWORD': ' "$(never-execute)\\\n',
                          'KEY_PASSWORD': '密', 'KEY_ALIAS': 'key:alias'}
                with patch.dict(os.environ, values, clear=True):
                    signing.main()
                self.assertEqual(Path('android/app/keystore.jks').read_bytes(), b'fixture-keystore')
                properties = Path('android/key.properties').read_text(encoding='ascii')
                self.assertIn('storePassword=' + signing.escape_property(values['STORE_PASSWORD']) + '\n', properties)
                self.assertIn('keyPassword=\\u5bc6\n', properties)
            finally:
                os.chdir(previous)


if __name__ == '__main__':
    unittest.main()
