"""Import a vendor DLSSNR-AMD release into the fork's ASI payload layout.

The vendor ships an installer-oriented tree (optiscaler/asi/, dxvk/, reshade/,
its own host build); the fork vendors only the NR plugin resources and maps
them onto the layout tools/release/PACKAGE_RELEASE.ps1 consumes:

  optiscaler/asi/dlssnr-amd.asi      -> OptiScaler/plugins/dlssnr-amd.asi (+ root copy)
  optiscaler/asi/nr_present_probe.exe-> nr_present_probe.exe
  optiscaler/asi/*-LICENSE.txt       -> Licenses/
  ini/*, model-tools/*, experimental/*, optimized/*, dlssnr-amd/* -> same paths
  (CJK language pack) lang/*         -> dlssnr-amd/lang/*

dxvk/, vulkan/, reshade/, optiscaler/release/ and the vendor installer files are
excluded: the fork ships its own host and launcher.

Usage:
  python tools/release/import-asi-payload.py --main <vendor win zip> \
      --cjk <vendor lang zip> --out third_party/mochizuki-asi/payload-0.0.9

Verifies every member the packager requires, writes a per-file sha256 manifest
next to the payload, and refuses to overwrite an existing directory unless
--force is given.
"""
import argparse
import hashlib
import json
import shutil
import sys
import zipfile
from pathlib import Path

REQUIRED_FILES = [
    'OptiScaler/plugins/dlssnr-amd.asi',
    'nr_present_probe.exe',
    'ini/dlssnr-amd-optiscaler.ini',
    'ini/dlssnr-amd-optiscaler-renodx.ini',
    'model-tools/dlssnr_extract_model.exe',
    'model-tools/dlssnr-int4-weights.exe',
    'experimental/dlssnr-small-experimental.delta',
    'optimized/dlssnr-optimized.delta',
]
REQUIRED_DIRS = ['dlssnr-amd/shaders']
EXCLUDED_PREFIXES = ('dxvk/', 'vulkan/', 'reshade/')  # vendor runtime shims and its own installer bits
EXCLUDED_ROOT = {'install.bat', 'install.ps1', 'README.txt'}
# Vendor layout -> fork payload layout. The plugin, probe and their licenses live
# under optiscaler/asi/ in the vendor package; everything else keeps its path.
RENAME = {
    'optiscaler/asi/dlssnr-amd.asi': 'OptiScaler/plugins/dlssnr-amd.asi',
    'optiscaler/asi/nr_present_probe.exe': 'nr_present_probe.exe',
    'optiscaler/asi/DearImGui-LICENSE.txt': 'Licenses/DearImGui-LICENSE.txt',
    'optiscaler/asi/Inter-LICENSE.txt': 'Licenses/Inter-LICENSE.txt',
}
COPIES = {'OptiScaler/plugins/dlssnr-amd.asi': 'dlssnr-amd.asi'}  # extra root copy


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def wanted(zip_path: Path, strip: str = ''):
    """Yield (archive_name, relative_target) for a zip's non-excluded files."""
    z = zipfile.ZipFile(zip_path)
    for name in z.namelist():
        if name.endswith('/'):
            continue
        rel = name[len(strip):] if strip and name.startswith(strip) else name
        if any(rel.startswith(p) for p in EXCLUDED_PREFIXES):
            continue
        # Keep only the plugin files from the vendor's optiscaler/ tree (its
        # release/ holds the vendor's own unmodified OptiScaler host build).
        if rel.startswith('optiscaler/') and not rel.startswith('optiscaler/asi/'):
            continue
        # Keep only the plugin files from the vendor's optiscaler/ tree (its
        # release/ holds the vendor's own unmodified OptiScaler host build).
        if rel.startswith('optiscaler/') and not rel.startswith('optiscaler/asi/'):
            continue
        if '/' not in rel and rel in EXCLUDED_ROOT:
            continue
        yield name, rel


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--main', required=True, type=Path, help='vendor Windows release zip')
    ap.add_argument('--cjk', type=Path, help='vendor CJK language zip (optional but recommended)')
    ap.add_argument('--out', required=True, type=Path)
    ap.add_argument('--stamp', default='', help='vendor version label for the manifest')
    ap.add_argument('--force', action='store_true')
    args = ap.parse_args()

    out = args.out.resolve()
    if out.exists() and any(out.iterdir()) and not args.force:
        sys.exit(f'refusing to overwrite non-empty {out}; pass --force')

    if out.exists():
        shutil.rmtree(out)

    copied = {}
    main_z = zipfile.ZipFile(args.main)
    total = 0
    for name, rel in list(wanted(args.main)):
        data = main_z.read(name)
        rel = RENAME.get(rel, rel)
        if rel == 'OptiScaler/plugins/dlssnr-amd.asi':
            targets = [rel, COPIES[rel]]
        else:
            targets = [rel]
        for target in targets:
            dest = out / target
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data)
            copied[target] = len(data)
            total += 1
    if args.cjk:
        cjk_z = zipfile.ZipFile(args.cjk)
        for name, rel in wanted(args.cjk):
            if not rel.startswith('lang/'):
                continue
            dest = out / 'dlssnr-amd' / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(cjk_z.read(name))
            copied[f'dlssnr-amd/{rel}'] = dest.stat().st_size
            total += 1

    missing = [r for r in REQUIRED_FILES if not (out / r).is_file()]
    missing += [f'{d}/ (directory)' for d in REQUIRED_DIRS if not (out / d).is_dir()]
    if missing:
        sys.exit('payload incomplete, missing: ' + ', '.join(missing))

    manifest = {
        'stamp': args.stamp,
        'source': {'main': args.main.name, 'cjk': args.cjk.name if args.cjk else None},
        'files': total,
        'bytes': sum(copied.values()),
        'sha256': {rel: digest(out / rel) for rel in sorted(copied)},
        'key_members': {rel: {'size': copied[rel], 'sha256': digest(out / rel)}
                        for rel in REQUIRED_FILES},
    }
    manifest_path = out.parent / (out.name + '.manifest.json')
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')

    asi = manifest['key_members']['OptiScaler/plugins/dlssnr-amd.asi']
    print(f'payload ready: {out}')
    print(f'  files={total} bytes={manifest["bytes"]:,}')
    print(f'  dlssnr-amd.asi: {asi["size"]:,} B sha256={asi["sha256"][:16]}...')
    print(f'  manifest: {manifest_path}')


if __name__ == '__main__':
    main()
