"""Menu string catalog audit for the cn/nr-menu fork.

Extracts string literals from the menu UI surface (files that render through
MenuUi/MenuLocale or live under menu/), rebuilds the visible lookup keys the
same way MenuLocale::Label does (strip at '##', keep '###' suffix out of the
key), and diffs them against MenuStrings.inl.

Outputs:
  - catalog-gaps.txt    live keys with no zh entry (these render English)
  - catalog-dead.txt    table keys not found in any scanned source (candidates)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HOST = ROOT / 'OptiScaler-DLSSNR-PreSR-Multipass-main/OptiScaler'
INL = HOST / 'menu/MenuStrings.inl'

# Files whose literals are treated as live menu keys.
SURFACE = sorted(set(
    list((HOST / 'menu').glob('*.cpp')) + list((HOST / 'menu').glob('*.h')) +
    [HOST / 'dlssnr/DlssNr_Menu.cpp', HOST / 'dlssnr/DlssNr_PipelineUi.h']
))
# For dead-entry checks, scan every source file in the host tree.
ALL_SOURCES = sorted(set(list(HOST.rglob('*.cpp')) + list(HOST.rglob('*.h'))))

STR = re.compile(r'"((?:[^"\\]|\\.)*)"')
CAT_LINE = re.compile(r'^\s*\{\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*\}\s*,?\s*$')


_ESCAPES = {'n': '\n', 't': '\t', 'r': '\r', '\\': '\\', '"': '"', "'": "'",
            '0': '\0', 'a': '\a', 'b': '\b', 'f': '\f', 'v': '\v', '?': '?'}


def unescape(lit: str) -> str:
    """C string literal -> text, without unicode_escape's UTF-8 corruption."""
    out = []
    i = 0
    while i < len(lit):
        ch = lit[i]
        if ch == '\\' and i + 1 < len(lit):
            nxt = lit[i + 1]
            if nxt in _ESCAPES:
                out.append(_ESCAPES[nxt])
                i += 2
                continue
            if nxt == 'x':  # hex escape
                j = i + 2
                while j < len(lit) and lit[j] in '0123456789abcdefABCDEF':
                    j += 1
                if j > i + 2:
                    out.append(chr(int(lit[i + 2:j], 16) & 0xFF))
                    i = j
                    continue
            # Unknown escape: keep as-is (compiler would warn too).
            out.append(nxt)
            i += 2
            continue
        out.append(ch)
        i += 1
    return ''.join(out)


def visible_key(text: str) -> str:
    # MenuLocale::Label translates the part before '##'; '###' keeps the id but the
    # translated label is the pre-'##' text. Trailing newlines are part of the key.
    return text.split('##', 1)[0]


# Widget calls whose FIRST argument is a translated label.
CALL = re.compile(r'\bMenu(?:Ui|Locale)::(\w+)\s*\(')
LABEL_FNS = {
    'Checkbox', 'SliderFloat', 'SliderInt', 'SliderScalar', 'InputText', 'InputInt',
    'InputFloat', 'Button', 'SmallButton', 'RadioButton', 'Selectable', 'TreeNode',
    'CollapsingHeader', 'SeparatorText', 'Text', 'TextWrapped', 'TextDisabled',
    'TextUnformatted', 'MenuItem', 'BulletText', 'Label', 'ValueLabel', 'BeginPopupModal',
    'OpenPopup', 'Combo', 'InputScalarN', 'ListBox', 'BeginTabItem', 'TabItemButton',
}
LIT_GROUP = re.compile(r'(?:"(?:[^"\\]|\\.)*"\s*)+')
CITY = re.compile(r'\b(?:MenuSectionTitle|MenuCard)\s*\(')


def concatenated_literals(source: str):
    """Every string literal in the file (joined runs), for the dead-key index."""
    for chunk in STR.findall(source):
        yield unescape(chunk)


def call_arguments(source: str, start: int):
    """Yield label candidates for a call whose '(' is at `start`.

    Adjacent literals separated only by whitespace are C++ concatenation (one
    key). A ',', ':' or '}' between literals starts a new candidate (call
    argument separators, ternary branches, array items)."""
    run = []
    pending = []

    def flush():
        if pending:
            run.append(unescape(''.join(pending)))
            pending.clear()

    depth = 0
    i = start
    n = len(source)
    while i < n:
        ch = source[i]
        if ch == '"':
            j = i + 1
            while j < n:
                if source[j] == '\\' and j + 1 < n:
                    pending.append(source[j:j + 2]); j += 2; continue
                if source[j] == '"':
                    break
                pending.append(source[j]); j += 1
            i = j + 1
            continue
        if ch == '(':
            depth += 1
        elif ch == ')':
            if depth == 0:
                flush()
                for text in run:
                    yield text
                return
            depth -= 1
        elif ch in ',:}':
            flush()
            for text in run:
                yield text
            run = []
        i += 1


def call_literals(source: str):
    """Yield label candidates: first-arg literals of translated calls, plus
    every \\0-separated item of Combo item lists (third argument)."""
    for m in CALL.finditer(source):
        if m.group(1) not in LABEL_FNS:
            continue
        parts = list(call_arguments(source, m.end()))
        if parts:
            yield parts[0]
        if m.group(1) == 'Combo' and len(parts) >= 3:
            seg_text = parts[2]
            if '\0' in seg_text:
                for item in seg_text.split('\0'):
                    if item:
                        yield item
    for m in CITY.finditer(source):
        for text in call_arguments(source, m.end()):
            yield text
            break


def live_keys(source: str):
    # Translate() only ever sees the text before '##' (MenuLocale::Label strips it),
    # and Text* formats are looked up as full strings without '##'. Reporting the
    # visible key alone avoids false gaps for suffixed labels.
    for lit in call_literals(source):
        yield visible_key(lit)


def main():
    catalog = {}
    order = []
    for raw in INL.read_text(encoding='utf-8').splitlines():
        m = CAT_LINE.match(raw.strip())
        if not m:
            continue
        key = unescape(m.group(1))
        catalog[key] = unescape(m.group(2))
        order.append(key)
    print(f'catalog entries: {len(catalog)} (unique keys)')

    # Live key candidates from the UI surface, plus the full-text index for dead checks.
    live = set()
    for path in SURFACE:
        try:
            text = path.read_text(encoding='utf-8-sig', errors='replace')
        except OSError:
            continue
        for lit in live_keys(text):
            live.add(lit)
    print(f'live label candidates: {len(live)} (from {len(SURFACE)} files)')

    # Full-tree literal set for dead-key checks (exact-match against catalog keys).
    tree_lits = set()
    for path in ALL_SOURCES:
        try:
            text = path.read_text(encoding='utf-8-sig', errors='replace')
        except OSError:
            continue
        for lit in concatenated_literals(text):
            tree_lits.add(lit)
            tree_lits.add(visible_key(lit))
    print(f'full-tree literal candidates: {len(tree_lits)}')

    gaps = sorted(k for k in live
                  if k not in catalog and k.strip() and not k.startswith('//')
                  and '###' not in k and not k.endswith('.h"') and not k.endswith('.cpp"'))
    dead = sorted(k for k in catalog if k not in tree_lits)

    out_dir = ROOT / 'work/scratch'
    (out_dir / 'catalog-gaps.txt').write_text(
        '\n'.join(g.replace('\n', '\\n') for g in gaps), encoding='utf-8')
    (out_dir / 'catalog-dead.txt').write_text(
        '\n'.join(k.replace('\n', '\\n') for k in dead), encoding='utf-8')
    print(f'coverage gaps (live keys without zh entry): {len(gaps)} -> work/scratch/catalog-gaps.txt')
    print(f'dead catalog keys (not found in any source): {len(dead)} -> work/scratch/catalog-dead.txt')


if __name__ == '__main__':
    sys.exit(main())
