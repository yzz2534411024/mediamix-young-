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

print('JSON length:', len(js))
print('Last 200 chars:', repr(js[-200:]))
print()

# Try parsing
try:
    j = json.loads(js)
    print('Parse OK')
except json.JSONDecodeError as e:
    print(f'Parse error: {e}')
    # Show context around error
    pos = e.pos
    print(f'Error at position {pos}')
    print(f'Context: {repr(js[max(0,pos-50):pos+50])}')

# Check if there's trailing content after the JSON
# Find the last }
last_brace = js.rfind('}')
print(f'\nLast }} at position: {last_brace}')
print(f'Total length: {len(js)}')
if last_brace < len(js) - 1:
    trailing = js[last_brace+1:]
    print(f'Trailing after last }}: {repr(trailing[:100])}')
