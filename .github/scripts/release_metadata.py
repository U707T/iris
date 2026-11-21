"""Derive release metadata from the checked-out version, without third-party actions."""
import json
import os
import re
import urllib.error
import urllib.request
from pathlib import Path


def main():
    match = re.search(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?)(?:\+[0-9]+)?\s*$',
                      Path('pubspec.yaml').read_text(encoding='utf-8'), re.MULTILINE)
    if not match:
        raise SystemExit('Invalid or missing pubspec version')
    tag = 'v' + match[1]
    repository = os.environ['GH_REPO']
    request = urllib.request.Request(
        f'https://api.github.com/repos/{repository}/git/ref/tags/{tag}',
        headers={'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
                 'Accept': 'application/vnd.github+json', 'User-Agent': 'iris-ci'})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            json.load(response)
        exists = True
        print(f'{tag} already exists; leaving the published release unchanged.')
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        exists = False
    with Path(os.environ['GITHUB_OUTPUT']).open('a', encoding='utf-8') as output:
        output.write(f'tag={tag}\nexists={str(exists).lower()}\nprerelease={str("-" in tag).lower()}\n')
    print('Build commit:', os.environ['BUILD_SHA'])


if __name__ == '__main__':
    main()
