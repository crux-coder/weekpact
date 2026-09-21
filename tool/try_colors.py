#!/usr/bin/env python3
"""Try colours in the real app without committing to them.

Swaps the named constants in `weekpact_theme.dart`, renders the app's main
screens through the same capture harness the design previews use, writes the
PNGs, and puts the theme file back exactly as it was. Nothing is left behind
unless you ask for it.

    tool/try_colors.py crewProgress=F4B942
    tool/try_colors.py crewProgress=F4B942 mintGreen=A8D2CC --out /tmp/amber
    tool/try_colors.py pactPalette=A8D2CC,9FCBD9,B4C9D4,...   # ten tints
    tool/try_colors.py crewProgress=F4B942 --keep             # actually apply it

`--keep` writes the change and skips the restore; every other run is a dry run.
Contrast against card ink is reported for each colour, since the system asks
every card tint to clear 8.5:1.
"""

import argparse
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
THEME = ROOT / 'lib/src/theme/weekpact_theme.dart'
CARD_INK = '191B19'
SCREENS = ['home', 'home-middle', 'home-last', 'home-empty', 'feed', 'pacts', 'crews', 'account']


def luminance(hex_colour):
    channels = [int(hex_colour[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    channels = [c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4 for c in channels]
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


def contrast(hex_colour, other=CARD_INK):
    first, second = luminance(hex_colour), luminance(other)
    high, low = max(first, second), min(first, second)
    return (high + 0.05) / (low + 0.05)


def parse(pair):
    if '=' not in pair:
        sys.exit(f'Expected NAME=HEX, got {pair!r}')
    name, value = pair.split('=', 1)
    values = [v.strip().lstrip('#').upper() for v in value.split(',')]
    for v in values:
        if not re.fullmatch(r'[0-9A-F]{6}', v):
            sys.exit(f'{name}: {v!r} is not a six-digit hex colour')
    return name.strip(), values


def swap(source, name, values):
    if name == 'pactPalette':
        if len(values) != 10:
            sys.exit(f'pactPalette takes ten tints, got {len(values)}')
        block = ('static const pactPalette = <Color>[\n'
                 + ''.join(f'    Color(0xFF{v}),\n' for v in values) + '  ];')
        source, found = re.subn(r'static const pactPalette = <Color>\[.*?\];', block,
                                source, flags=re.S)
    else:
        if len(values) != 1:
            sys.exit(f'{name} takes one colour, got {len(values)}')
        source, found = re.subn(
            rf'(static const {re.escape(name)} = Color\(0x)FF[0-9A-Fa-f]{{6}}(\))',
            rf'\g<1>FF{values[0]}\g<2>', source)
    if found != 1:
        sys.exit(f'{name} is not a colour constant in {THEME.name}'
                 if not found else f'{name} matched {found} times')
    return source


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('colours', nargs='+', metavar='NAME=HEX')
    parser.add_argument('--out', default='/tmp/weekpact-try', help='where the PNGs go')
    parser.add_argument('--keep', action='store_true', help='apply the change instead of reverting')
    parser.add_argument('--no-render', action='store_true', help='report contrast only')
    args = parser.parse_args()

    pairs = [parse(pair) for pair in args.colours]
    for name, values in pairs:
        for value in values:
            ratio = contrast(value)
            flag = '' if ratio >= 8.5 else '  ← under 8.5:1 on a card'
            print(f'  {name:>14s}  #{value}  {ratio:5.2f}:1 vs card ink{flag}')

    source = THEME.read_text()
    for name, values in pairs:
        source = swap(source, name, values)

    if args.no_render:
        if args.keep:
            THEME.write_text(source)
            print(f'\nApplied to {THEME.relative_to(ROOT)}.')
        return

    backup = pathlib.Path(tempfile.mkdtemp()) / THEME.name
    shutil.copy(THEME, backup)
    out = pathlib.Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    try:
        THEME.write_text(source)
        subprocess.run(['flutter', 'test', '--dart-define=CAPTURE_DESIGN=true',
                        'test/design_preview_test.dart'], cwd=ROOT, check=True,
                       stdout=subprocess.DEVNULL)
        for screen in SCREENS:
            shot = pathlib.Path(f'/tmp/weekpact-dark-{screen}.png')
            if shot.exists():
                shutil.copy(shot, out / f'{screen}.png')
    finally:
        if not args.keep:
            shutil.copy(backup, THEME)

    print(f'\nScreens in {out}/')
    print('Theme file kept as it was.' if not args.keep
          else f'Applied to {THEME.relative_to(ROOT)}.')


if __name__ == '__main__':
    main()
