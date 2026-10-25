"""Probe one real advertised surah per mushaf; do not call it a full audio audit."""
import concurrent.futures,json,pathlib,urllib.request,datetime
root=pathlib.Path(__file__).resolve().parents[1]
c=json.loads((root/'assets/catalog.json').read_text())
def probe(m):
 u=m['server'].rstrip('/')+'/'+str(m['surahs'][0]).zfill(3)+'.mp3'
 try:
  req=urllib.request.Request(u,headers={'Range':'bytes=0-1023','Origin':'https://qiraat-audio.vercel.app'})
  with urllib.request.urlopen(req,timeout=15) as r:
   sample=r.read(1024)
   return dict(mushaf=m['id'],url=u,status=r.status,bytes=len(sample),contentType=r.headers.get('Content-Type'),cors=r.headers.get('Access-Control-Allow-Origin'),acceptRanges=r.headers.get('Accept-Ranges'),checkedAt=datetime.datetime.now(datetime.timezone.utc).isoformat())
 except Exception as e:return dict(mushaf=m['id'],url=u,error=str(e))
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:results=list(pool.map(probe,c['mushafs']))
(root/'docs/audio-probes.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
print('Probed',len(results),'Successful',sum(x.get('status') in [200,206] for x in results))
