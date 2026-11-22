#!/usr/bin/env python3
"""把 src/ 里的样式、脚本和 App 的图片、音乐拼成一个可以直接打开的 index.html。

用法：python3 demo/build.py [另存一份不带 <html> 外壳的版本的路径]
"""
import base64, glob, json, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, 'src')
RES = os.path.join(HERE, '..', 'HumanContent', 'Resources')

def read(name):
    path = os.path.join(SRC, name)
    return open(path, encoding='utf-8').read() if os.path.exists(path) else ''

def data_url(path, mime):
    return f'data:{mime};base64,' + base64.b64encode(open(path, 'rb').read()).decode()

assets = {}
for path in sorted(glob.glob(os.path.join(RES, 'Assets.xcassets', '*.imageset', '*.*'))):
    name, ext = os.path.splitext(os.path.basename(path))
    if ext in ('.jpg', '.png'):
        assets[name] = data_url(path, 'image/jpeg' if ext == '.jpg' else 'image/png')
assets['bgm'] = data_url(os.path.join(RES, 'bgm_default.m4a'), 'audio/mp4')

asset_js = 'window.ASSET = {\n' + ',\n'.join(f'  {k}: "{v}"' for k, v in assets.items()) + '\n};'
fate_data = json.load(open(os.path.join(RES, 'fate.json'), encoding='utf-8'))
asset_js += '\nwindow.FATE_DATA = ' + json.dumps(fate_data, ensure_ascii=False).replace('</', '<\\/') + ';'
scripts = ''.join(f'<script>\n{read(n)}\n</script>\n' for n in ('core.js', 'sound.js', 'ui.js', 'lab.js', 'fate.js', 'login.js', 'ceremony.js', 'ui2.js') if read(n))

content = f'''<title>人类含量</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Noto+Serif+SC:wght@700;900&display=swap">
<style>
{read('style.css')}
{read('lab.css')}
{read('fate.css')}
</style>
<div id="shell">
  <div id="view"></div>
  <div id="dock"></div>
  <nav id="tabbar" aria-label="主要页面"></nav>
  <div id="sheet"></div>
  <div id="cover"></div>
  <div id="toast" role="status"></div>
  <div id="flash" aria-live="polite"></div>
</div>
<script>
{asset_js}
</script>
{scripts}'''

page = f'''<!doctype html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<style>html{{box-sizing:border-box;padding:env(safe-area-inset-top,0px) 0 env(safe-area-inset-bottom,0px)}}body{{margin:0}}[hidden]{{display:none!important}}</style>
</head>
<body>
{content}
</body>
</html>
'''
open(os.path.join(HERE, 'index.html'), 'w', encoding='utf-8').write(page)
if len(sys.argv) > 1:
    open(sys.argv[1], 'w', encoding='utf-8').write(content)
print(f'index.html {len(page) // 1024} KB, {len(assets)} assets')
