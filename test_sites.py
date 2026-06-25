import base64, re, json

f = open(r'e:\mediamix-young-\test_fantaiying.bin', 'rb')
d = f.read()
f.close()

idx = d.rfind(b'\xff\xd9')
t = d[idx+2:]
text = t.decode('utf-8', 'replace')
mi = text.find('**')
b64 = text[mi+2:].strip()
cleaned = re.sub(r'[^A-Za-z0-9+/=]', '', b64)
decoded = base64.b64decode(cleaned)
js = decoded.decode('utf-8')

# strip comments
def strip_comments(text):
    sb = []
    i = 0
    in_string = False
    string_char = None
    while i < len(text):
        if in_string:
            ch = text[i]
            sb.append(ch)
            if ch == '\\' and i + 1 < len(text):
                i += 1
                sb.append(text[i])
            elif ch == string_char:
                in_string = False
            i += 1
            continue
        if text[i] == '"' or text[i] == "'":
            in_string = True
            string_char = text[i]
            sb.append(text[i])
            i += 1
        elif i + 1 < len(text) and text[i] == '/' and text[i+1] == '/':
            i += 2
            while i < len(text) and text[i] not in '\n\r':
                i += 1
        elif i + 1 < len(text) and text[i] == '/' and text[i+1] == '*':
            i += 2
            while i + 1 < len(text) and not (text[i] == '*' and text[i+1] == '/'):
                i += 1
            i += 2
        else:
            sb.append(text[i])
            i += 1
    return ''.join(sb)

j = json.loads(strip_comments(js))

print('Total sites:', len(j['sites']))
print('\nFirst 10 sites:')
for i, s in enumerate(j['sites'][:10]):
    ext = s.get('ext')
    print(f"{i+1}. key={s.get('key')}, name={s.get('name')}, type={s.get('type')}, api={s.get('api')[:50] if isinstance(s.get('api'), str) else 'N/A'}, ext_type={type(ext).__name__}, ext={str(ext)[:80] if ext else 'null'}")

# Find any site with http ext
http_ext_sites = [s for s in j['sites'] if s.get('ext') and isinstance(s.get('ext'), str) and s['ext'].startswith('http')]
print(f'\nSites with HTTP ext: {len(http_ext_sites)}')
for s in http_ext_sites[:5]:
    print(f"  - {s.get('name')}: {s['ext'][:100]}")
