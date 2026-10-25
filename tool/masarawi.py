"""Audit Masarawi's twenty explicitly-labelled nQuran categories.
No guessed surahs: read data-fileexists and data-file from each source list.
"""
import concurrent.futures,datetime,hashlib,html,json,pathlib,re,urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[1]
CATEGORIES={1:690,2:689,3:697,4:706,5:698,6:691,7:704,8:705,9:703,10:688,11:692,12:700,13:693,14:699,15:707,16:696,17:702,18:701,19:695,20:694}
def fetch(riwaya,category):
 page=f'https://www.nquran.com/ar/categories/{category}/'
 text=urllib.request.urlopen(page,timeout=40).read().decode('utf-8')
 headings=[html.unescape(re.sub('<[^>]+>','',x)).strip() for x in re.findall(r'<h1\b[^>]*>(.*?)</h1>',text,re.S)]
 h1=next(x for x in headings if x).splitlines()[0].strip()
 tracks={}
 for block in re.findall(r'<li\b[^>]*class="qlist\b.*?</li>',text,re.S):
  if 'data-fileexists="1"' not in block:continue
  m=re.search(r'data-file="([^"]+\.mp3)"',block)
  if not m:continue
  path=html.unescape(m.group(1));n=int(re.search(r'/(\d{3})\.mp3$',path).group(1))
  assert 1<=n<=114
  assert path.startswith('/audiof/quran/ahmedmesarawi/')
  tracks[n]='https://www.nquran.com'+path
 assert tracks,category
 servers={u.rsplit('/',1)[0]+'/' for u in tracks.values()};assert len(servers)==1
 return dict(riwaya=riwaya,category=category,label=h1,page=page,server=servers.pop(),tracks=tracks,htmlSha256=hashlib.sha256(text.encode()).hexdigest())
def probe(url):
 try:
  req=urllib.request.Request(url,headers={'Range':'bytes=0-1023','Origin':'https://qiraat-audio.vercel.app'})
  with urllib.request.urlopen(req,timeout=25) as r:
   b=r.read(1024)
   return dict(url=url,resolvedUrl=r.geturl(),status=r.status,contentType=r.headers.get('content-type'),cors=r.headers.get('access-control-allow-origin'),bytes=len(b))
 except Exception as e:return dict(url=url,error=str(e))
if __name__=='__main__':
 with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
  records=list(pool.map(lambda item:fetch(*item),CATEGORIES.items()))
 for row in records:
  ss=sorted(row['tracks']);row['probes']=[probe(row['tracks'][ss[0]]),probe(row['tracks'][ss[-1]])]
  print(row['riwaya'],row['category'],row['label'],len(ss),ss[0],ss[-1],row['probes'],flush=True)
 payload=dict(checkedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),readerPage='https://www.nquran.com/ar/categories/603',records=records)
 (ROOT/'assets/masarawi-nquran.json').write_text(json.dumps(payload,ensure_ascii=False,indent=2))
