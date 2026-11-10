"""Publish only the verified assets from this main-branch build."""
import hashlib
import json
import os
from pathlib import Path
import subprocess


def gh(*args, check=True):
    return subprocess.run(['gh', *args], text=True, capture_output=True, check=check)


def main():
    if os.environ['GITHUB_REF'] != 'refs/heads/main':
        raise ValueError('Only main can publish stable releases.')
    repo = os.environ['GITHUB_REPOSITORY']
    commit = os.environ['GITHUB_SHA']
    folder = Path('release-assets')
    manifest = json.loads((folder / 'release.json').read_text())
    if manifest['commit'] != commit:
        raise ValueError('Artifacts do not belong to this commit.')
    assets = [folder / entry['file'] for entry in manifest['apks']]
    for path, entry in zip(assets, manifest['apks']):
        if path.parent != folder or hashlib.sha256(path.read_bytes()).hexdigest() != entry['sha256']:
            raise ValueError('Artifact checksum mismatch.')
    assets += [folder / 'release.json', folder / 'SHA256SUMS.txt']
    tag = 'v' + manifest['version']
    # A tag must never be repointed or silently reused for another source.
    ref = gh('api', f'repos/{repo}/git/ref/tags/{tag}', check=False)
    if ref.returncode == 0 and json.loads(ref.stdout)['object']['sha'] != commit:
        raise ValueError('Version tag already points to another commit. Increment the version.')
    found = gh('release', 'view', tag, '--repo', repo, '--json', 'isDraft,targetCommitish', check=False)
    if found.returncode == 0:
        release = json.loads(found.stdout)
        if release['targetCommitish'] != commit or not release['isDraft']:
            raise ValueError('This version is already published or belongs to another commit.')
    else:
        gh('release', 'create', tag, '--repo', repo, '--target', commit, '--draft',
           '--title', 'YOMI ' + manifest['version'], '--notes-file', 'docs/release-1.2.0.md')
    gh('release', 'upload', tag, '--repo', repo, '--clobber', *(str(path) for path in assets))
    gh('release', 'edit', tag, '--repo', repo, '--draft=false', '--prerelease=false', '--latest')
    print(f'Published {repo}/releases/tag/{tag}')


if __name__ == '__main__':
    main()
