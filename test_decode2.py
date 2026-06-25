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

# Test strip comments function
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

cleaned_js = strip_comments(js)
print('Original length:', len(js))
print('Cleaned length:', len(cleaned_js))

try:
    j = json.loads(cleaned_js)
    print('Parse OK! keys:', list(j.keys())[:10])
    print('sites count:', len(j.get('sites', [])))
except Exception as e:
    print('Parse error:', e)
    # find error position
    pos = e.pos if hasattr(e, 'pos') else 0
    print('Context:', repr(cleaned_js[max(0,pos-50):pos+50]))
