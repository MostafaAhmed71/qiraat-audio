"""Build reproducible source snapshot. Never infer a riwaya from a reciter name."""
import json, pathlib, urllib.request, datetime, hashlib
ROOT=pathlib.Path(__file__).resolve().parents[1]
# Source IDs are explicit. Combined classifications 9 and 11 are NOT split.
CANON=[('نافع المدني','قالون',[5,8]),('نافع المدني','ورش',[2,10,18]),('ابن كثير المكي','البزي',[4]),('ابن كثير المكي','قنبل',[6]),('أبو عمرو البصري','الدوري',[13]),('أبو عمرو البصري','السوسي',[7]),('ابن عامر الشامي','هشام',[19]),('ابن عامر الشامي','ابن ذكوان',[16]),('عاصم الكوفي','شعبة',[15]),('عاصم الكوفي','حفص',[1]),('حمزة الكوفي','خلف',[3]),('حمزة الكوفي','خلاد',[]),('الكسائي','أبو الحارث',[]),('الكسائي','الدوري',[12]),('أبو جعفر المدني','ابن وردان',[]),('أبو جعفر المدني','ابن جماز',[20]),('يعقوب الحضرمي','رويس',[]),('يعقوب الحضرمي','روح',[]),('خلف العاشر','إسحاق',[]),('خلف العاشر','إدريس',[])]
def build(refresh=False):
 raw={}
 for endpoint in ['riwayat','reciters','suwar']:
  p=ROOT/'assets'/f'{endpoint}.json'
  if refresh or not p.exists():
   p.write_bytes(urllib.request.urlopen('https://www.mp3quran.net/api/v3/'+endpoint+'?language=ar',timeout=60).read())
  raw[endpoint]=json.loads(p.read_text())
 canonical=[dict(id=i+1,qiraa=q,narrator=n,sourceIds=ids) for i,(q,n,ids) in enumerate(CANON)]
 mapping={sid:r['id'] for r in canonical for sid in r['sourceIds']}
 mushafs=[];excluded=[]
 for rec in raw['reciters']['reciters']:
  for m in rec['moshaf']:
   sid=m.get('rewaya_id')
   if sid not in mapping:
    excluded.append(dict(reciter=rec['name'],**m));continue
   surahs=sorted(set(int(s) for s in m['surah_list'].split(',') if s.strip()))
   assert surahs and all(1<=s<=114 for s in surahs)
   assert len(surahs)==int(m['surah_total']),m
   assert m['server'].startswith('https://')
   mushafs.append(dict(id=m['id'],riwaya=mapping[sid],sourceRiwaya=sid,reciterId=rec['id'],reciter=rec['name'].strip(),name=m['name'],server=m['server'],surahs=surahs))
 np=ROOT/'assets/masarawi-nquran.json'
 if np.exists():
  from masarawi import CATEGORIES
  external=json.loads(np.read_text())
  assert len(external['records'])==20
  for row in external['records']:
   rid=row['riwaya'];cat=row['category'];assert CATEGORIES[rid]==cat
   surahs=sorted(int(n) for n in row['tracks'])
   assert all(row['tracks'][str(n)]==row['server']+str(n).zfill(3)+'.mp3' for n in surahs)
   assert all(p.get('status') in [200,206] and p.get('bytes',0)>0 for p in row['probes'])
   r=canonical[rid-1]
   mushafs.append(dict(id=100000+cat,riwaya=rid,sourceRiwaya=0,reciterId=278,reciter='أحمد عيسى المعصراوي',name=f"{r['narrator']} عن {r['qiraa']} — ن للقرآن",server=row['server'],surahs=surahs,source='nquran',sourceCategory=cat,sourcePage=row['page'],webDownloads=all(p.get('cors')=='*' for p in row['probes'])))
 data=dict(checkedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),source='https://www.mp3quran.net/api/v3/',riwayat=canonical,suwar=raw['suwar']['suwar'],mushafs=mushafs)
 (ROOT/'assets/catalog.json').write_text(json.dumps(data,ensure_ascii=False,indent=2))
 (ROOT/'docs/excluded-source-records.json').write_text(json.dumps(excluded,ensure_ascii=False,indent=2))
 lines=['# تقرير تغطية الروايات والتسجيلات','',f"تاريخ جلب الفهرس: {data['checkedAt']}",'','المصادر: https://www.mp3quran.net/ar/api — https://www.nquran.com/ar/categories/603','', 'MP3Quran: الربط بحسب rewaya_id والسور بحسب surah_list. ن للقرآن: الربط بحسب تصنيف الرواية في صفحة المعصراوي، والسور من data-file للقوائم الفعلية فقط. هذا تدقيق فهرس وليس إجازة علمية أو استماعًا بشريًا لجميع التسجيلات.','', '| القراءة | الرواية | القراء | المصاحف | حالة الفهرس |','|---|---|---:|---:|---|']
 for r in canonical:
  ms=[m for m in mushafs if m['riwaya']==r['id']]
  lines.append(f"|{r['qiraa']}|{r['narrator']}|{len(set(m['reciterId'] for m in ms))}|{len(ms)}|{'متاح' if ms else 'غير متاح منفردًا في المصدر'}|")
 lines+=['','## القراء والمصاحف','']
 for r in canonical:
  lines += [f"### {r['narrator']} عن {r['qiraa']}",'','| القارئ | المصحف في المصدر | معرّف المصدر | السور المتاحة | رابط الخادم |','|---|---|---:|---:|---|']
  for m in mushafs:
   if m['riwaya']==r['id']:lines.append(f"|{m['reciter']}|{m['name']}|{m['id']}|{len(m['surahs'])}|{m['server']}|")
 lines+=['','## التصنيفات المشتركة والمستبعدة','', 'تصنيف 9: يعقوب بروايتي رويس وروح، وتصنيف 11: البزي وقنبل؛ لم يُنسبا لأي رواية منفردة. كذلك لا تمثل تصنيفات المعلم والمجود روايات مستقلة. السجلات الأصلية محفوظة في excluded-source-records.json.','', 'تصنيف 19 في المصدر مكتوب «هشام عن ابي عامر»؛ تم تصحيح اسم القراءة في العرض إلى ابن عامر، مع إبقاء النص الأصلي في اسم المصحف. يلزم تدقيق مختص قبل الإطلاق العام.','', '## المصدر وحقوق الاستخدام','', 'توثيق API الرسمي متاح، ويوفر الموقع استماعًا وتنزيلًا. لم نعثر في صفحة التوثيق على ترخيص صريح شامل يجيز إعادة توزيع التسجيلات أو استخدامها تجاريًا. لذلك لا تتضمن حزمة التطبيق ملفات صوتية، وتُجلب التلاوات مباشرة من خوادم المصدر بناءً على طلب المستخدم. إتاحة الرابط لا تعني ثبوت حقوق إعادة التوزيع. يجب الحصول على تأكيد من الجهة المالكة قبل إطلاق تجاري أو إعادة استضافة الصوت.','', '## حدود التحقق','', 'توفر السور هنا يعني أنها مدرجة في API؛ راجع audio-probes.json لنتائج فحص HTTP الفعلية لعينة من كل مصحف. فحص HTTP لا يثبت صحة الرواية سمعيًا. لا يوجد ضمان بأن كل رابط سيبقى متاحًا.']
 if np.exists():
  lines += ['', '## المعصراوي — الروايات العشرون', '',
   'أضيفت 20 قائمة من موقع ن للقرآن، كل قائمة 64 سورة من الذاريات (51) إلى الناس (114). حفص متاح أيضًا كاملًا بصوته من MP3Quran. لا توجد رواية فارغة بعد هذا الدمج، لكن اكتمال 114 سورة غير متحقق لكل الروايات.', '',
   '| الرواية | صفحة التصنيف | السور | التنزيل على أندرويد | التنزيل داخل Web/PWA |',
   '|---|---|---:|---|---|']
  for row in external['records']:
   r=canonical[row['riwaya']-1]
   lines.append(f"|{r['narrator']} عن {r['qiraa']}|{row['page']}|{len(row['tracks'])}|مدعوم|غير متاح: المصدر لا يعيد CORS|")
  lines += ['', 'تم فحص أول وآخر سورة في كل قائمة (40 رابطًا)، وأعيدت استجابات 206 ببيانات فعلية. التفاصيل في assets/masarawi-nquran.json. لم يُختبر كل تسجيل بالاستماع.', '',
   'اتفاقية ن للقرآن: https://www.nquran.com/ar/categories/603?group=service — تذكر الاستخدام غير التجاري بحسن نية، وتمنع إعادة الإنتاج أو التوزيع أو التعديل دون موافقة المالك. التطبيق يربط بالمصدر مباشرة ولا يعيد استضافة الملفات. التنزيل المحلي بطلب المستخدم، ولا يعد إتاحة زر التنزيل ترخيصًا لإعادة التوزيع أو الاستخدام التجاري.', '',
   'فحص MIME: يرسل ن للقرآن application/octet-stream؛ لذلك يقبل التنزيل هذا النوع بعد فحص مقدمة MP3، بدل رفض ملف صحيح بناءً على الرأس فقط. تم فحص ملف الذاريات برواية خلاد بالـ ffprobe وثبت أنه MP3.']
 (ROOT/'docs/COVERAGE_AR.md').write_text('\n'.join(lines)+'\n')
 print('Canonical:',len(canonical),'Mushafs:',len(mushafs),'Available riwayat:',len(set(m['riwaya'] for m in mushafs)))
if __name__=='__main__':
 import sys
 build('--refresh' in sys.argv)
