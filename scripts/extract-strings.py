# Lists the interface strings found in the Swift sources (keys for scripts/i18n). Usage: python -X utf8 scripts/extract-strings.py
import glob, json, os, re

ROOT = os.path.join(os.path.dirname(__file__), '..')
STR = r'"((?:[^"\\]|\\.)*)"'
CALLS = ['String\\(localized: ', '\\bText\\(', 'Label\\(', 'Button\\(', 'Link\\(', 'navigationTitle\\(', 'Section\\(', 'Picker\\(',
         'DisclosureGroup\\(', 'Toggle\\(', 'HintCard\\(text: ', 'accessibilityLabel\\(Text\\(']
SKIP = {'SWISH ALLEY'}


def keys():
    out = []
    for f in sorted(glob.glob(os.path.join(ROOT, 'SwishAlley', '**', '*.swift'), recursive=True)):
        s = open(f, encoding='utf-8').read()
        for c in CALLS:
            for m in re.finditer(c + STR, s):
                k = m.group(1)
                if '\\(' in k or k in SKIP or k in out:
                    continue
                out.append(k.replace('\\"', '"'))
    return out


if __name__ == '__main__':
    ks = keys()
    print(len(ks))
    print(json.dumps(ks, ensure_ascii=False, indent=1))
