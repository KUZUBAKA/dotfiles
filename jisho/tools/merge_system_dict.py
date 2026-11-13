#!/usr/bin/env python3
"""Merge the official Karukan system dictionary with the karukan-kz additions.

Usage: merge_system_dict.py OFFICIAL_DICT_BIN TOP_TSV ADDITIONS_TSV[.xz] OUT_JSON [FREQ_TSV[.xz]]

  OFFICIAL_DICT_BIN  dict.bin from https://github.com/togatoga/karukan/releases
  TOP_TSV            reading<TAB>surface<TAB>note — work terms that must come
                     first among the system dictionary's candidates (right
                     after the AI's), in the order given
  ADDITIONS_TSV      reading<TAB>surface<TAB>cost<TAB>source — new words,
                     placed after the official candidates of the same reading
  OUT_JSON           input for: karukan-dict build OUT_JSON -o dict.bin

  FREQ_TSV           reading<TAB>surface<TAB>cost — Mozc's word costs. With it,
                     the candidates of a reading that Mozc knows come first, the
                     most frequent first, with Mozc's cost as their score (the
                     engine reads it as how common the word is); the others
                     follow in the order described above, from 20000 up.
                     Rows whose reading starts with 〈 are marks — 〈仮名〉 for kana
                     that is a function word (から, ます), 〈活〉 for a conjugated
                     form (話せ) — and become entries of their own.

Scores are costs (lower = earlier), on the official dictionary's scale.
"""
import collections
import json
import lzma
import struct
import sys

SOURCE_RANK = {name: i for i, name in enumerate(
    ['skk-jisyo', 'alt-cannadic', 'edict2', 'personal-names', 'place-names',
     'sudachidict', 'neologd', 'jawiki', 'nico', 'daily'])}


def read_krkn(path):
    """reading → [(surface, score)] from a KRKN v1 dictionary file."""
    with open(path, 'rb') as f:
        data = f.read()
    if data[:4] != b'KRKN':
        sys.exit(f'{path}: not a Karukan dictionary')
    version, trie_len = struct.unpack_from('<II', data, 4)
    if version != 1:
        sys.exit(f'{path}: unsupported dictionary version {version}')
    off = 12 + trie_len
    (count,) = struct.unpack_from('<I', data, off)
    off += 4
    entries = {}
    for _ in range(count):
        (n,) = struct.unpack_from('<H', data, off)
        off += 2
        reading = data[off:off + n].decode()
        off += n
        (m,) = struct.unpack_from('<H', data, off)
        off += 2
        cands = []
        for _ in range(m):
            (n,) = struct.unpack_from('<H', data, off)
            off += 2
            surface = data[off:off + n].decode()
            off += n
            (score,) = struct.unpack_from('<f', data, off)
            off += 4
            cands.append((surface, score))
        entries[reading] = sorted(cands, key=lambda c: c[1])
    return entries


# 〈仮名〉 marks kana that is a function word, 〈活〉 a conjugated form.
MARK = '〈'

DECORATION = set('…‥!！?？☆★♪♡♥〜~「」『』【】()（）<>＜＞*＊#＃^＾　 ')


def is_decorated(surface):
    return any(ch in DECORATION for ch in surface)


def open_text(path):
    return lzma.open(path, 'rt', encoding='utf-8') if path.endswith('.xz') else open(path, encoding='utf-8')


def main():
    if len(sys.argv) not in (5, 6):
        sys.exit(__doc__)
    official_path, top_path, add_path, out_path = sys.argv[1:5]
    freq = collections.defaultdict(dict)
    if len(sys.argv) == 6:
        with open_text(sys.argv[5]) as f:
            for line in f:
                if line.startswith('#') or not line.strip():
                    continue
                r, s, cost = line.rstrip('\n').split('\t')[:3]
                freq[r][s] = int(cost)
    dict_entries = read_krkn(official_path)
    print(f'official: {len(dict_entries)} readings', file=sys.stderr)

    top = collections.defaultdict(list)
    with open_text(top_path) as f:
        for line in f:
            if line.startswith('#') or not line.strip():
                continue
            r, s = line.rstrip('\n').split('\t')[:2]
            if s not in top[r]:
                top[r].append(s)

    add = collections.defaultdict(list)
    with open_text(add_path) as f:
        for line in f:
            if line.startswith('#') or not line.strip():
                continue
            r, s, cost, source = line.rstrip('\n').split('\t')[:4]
            add[r].append((s, int(cost), SOURCE_RANK.get(source, len(SOURCE_RANK))))

    marks = {r for r in freq if r.startswith(MARK)}
    readings = set(dict_entries) | set(top) | set(add) | marks
    raised = appended = new_readings = 0
    with open(out_path, 'w', encoding='utf-8') as out:
        out.write('[')
        first = True
        for r in sorted(readings, key=lambda x: x.encode()):
            if r in marks:
                obj = {'reading': r, 'candidates': [{'surface': s, 'score': float(c)} for s, c in sorted(freq[r].items(), key=lambda x: x[1])]}
                out.write(('' if first else ',') + '\n' + json.dumps(obj, ensure_ascii=False))
                first = False
                continue
            existing = dict_entries.get(r, [])
            lifted = top.get(r, [])
            lifted_set = set(lifted)
            rest = [(s, sc) for s, sc in existing if s not in lifted_set]
            cands = []
            if existing:
                low, high = existing[0][1], existing[-1][1]
            else:
                low = high = None
            # Work terms: just ahead of the official first candidate.
            base = (low if low is not None else 8000.0) - len(lifted)
            for i, s in enumerate(lifted):
                cands.append((s, base + i))
            raised += len(lifted)
            cands.extend(rest)
            known = {s for s, _ in cands}
            extra = [x for x in add.get(r, []) if x[0] not in known]
            # Plain spellings before decorated ones (愛してる before 愛してる…),
            # then edited dictionaries before web sources, then cost.
            extra.sort(key=lambda x: (is_decorated(x[0]), x[2], x[1]))
            if extra:
                if high is not None or cands:
                    start = max(sc for _, sc in cands) + 1
                    for i, (s, cost, rank) in enumerate(extra):
                        cands.append((s, start + i))
                    appended += len(extra)
                else:
                    for i, (s, cost, rank) in enumerate(extra):
                        cands.append((s, 9000.0 + 200 * rank + i))
                    new_readings += 1
                    appended += len(extra)
            # Mozc's word costs: what it knows leads, the most frequent first.
            known_cost = freq.get(r)
            if freq:
                common = sorted(((s, known_cost[s]) for s, _ in cands if known_cost and s in known_cost),
                                key=lambda c: c[1])
                others = [s for s, _ in cands if not (known_cost and s in known_cost)]
                cands = common + [(s, 20000.0 + i) for i, s in enumerate(others)]
            # The format stores at most 65535 candidates per reading.
            cands = cands[:65535]
            obj = {'reading': r, 'candidates': [{'surface': s, 'score': float(sc)} for s, sc in cands]}
            out.write(('' if first else ',') + '\n' + json.dumps(obj, ensure_ascii=False))
            first = False
        out.write('\n]\n')
    print(f'merged: {len(readings)} readings, {raised} raised work terms, '
          f'{appended} added words ({new_readings} new readings)', file=sys.stderr)


if __name__ == '__main__':
    main()
