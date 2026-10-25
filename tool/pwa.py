"""Precache the complete local Flutter shell, including renderer and fonts.
Run only after a successful --no-web-resources-cdn web build.
"""
from pathlib import Path
import hashlib,json
root=Path(__file__).resolve().parents[1]/'build/web'
assert (root/'main.dart.js').exists(),'Build Flutter Web first'
files=sorted(p for p in root.rglob('*') if p.is_file() and p.name not in ['sw.js','flutter_service_worker.js'] and p.suffix not in ['.map'])
version=hashlib.sha256(b''.join(p.read_bytes() for p in files)).hexdigest()[:16]
urls=['./']+[p.relative_to(root).as_posix() for p in files]
script='''const CACHE = 'qiraat-shell-VERSION';
const FILES = URLS;
self.addEventListener('install', event => event.waitUntil((async () => {
  const cache = await caches.open(CACHE);
  await cache.addAll(FILES);
  await self.skipWaiting();
})()));
self.addEventListener('activate', event => event.waitUntil((async () => {
  for (const key of await caches.keys()) {
    if (key.startsWith('qiraat-shell-') && key !== CACHE) await caches.delete(key);
  }
  await self.clients.claim();
})()));
self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    if (req.mode === 'navigate') {
      try { return await fetch(req); }
      catch (_) { return (await cache.match('./')) || Response.error(); }
    }
    const hit = await cache.match(req);
    return hit || fetch(req);
  })());
});
'''.replace('VERSION',version).replace('URLS',json.dumps(urls,ensure_ascii=False))
(root/'sw.js').write_text(script)
print('PWA shell:',len(files),'files, cache',version)
