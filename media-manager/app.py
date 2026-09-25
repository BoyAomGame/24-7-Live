import os, secrets
from pathlib import Path
from typing import Annotated
from urllib.parse import urlparse
from fastapi import Depends, FastAPI, File, HTTPException, UploadFile
from fastapi.responses import HTMLResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from pydantic import BaseModel
ROOT=Path('/media'); VIDEOS=ROOT/'videos'; NORMALIZED=ROOT/'normalized'; PLAYLIST=ROOT/'playlist.txt'; PLAYBACK=ROOT/'playback.enabled'; MODE=ROOT/'playlist.mode'
ALLOWED={'.mp4','.m4v','.mov','.mkv','.webm'}; USER=os.getenv('MEDIA_ADMIN_USERNAME','admin'); PASSWORD=os.getenv('MEDIA_ADMIN_PASSWORD','')
security=HTTPBasic(); app=FastAPI(docs_url=None,redoc_url=None)
def auth(c:Annotated[HTTPBasicCredentials,Depends(security)]):
 if not PASSWORD or not(secrets.compare_digest(c.username,USER) and secrets.compare_digest(c.password,PASSWORD)): raise HTTPException(401,'Invalid credentials',{'WWW-Authenticate':'Basic'})
def name(x):
 x=Path(x).name
 if not x or Path(x).suffix.lower() not in ALLOWED: raise HTTPException(400,'Use MP4, M4V, MOV, MKV, or WebM files.')
 return x
def item(x):
 if x.startswith(('http://','https://')):
  if not urlparse(x).netloc or Path(urlparse(x).path).suffix.lower() not in {'.mp4','.m3u8'}: raise HTTPException(400,'Use a direct HTTP(S) MP4 or HLS M3U8 URL.')
  return x
 return name(x)
def items(): return [x.strip() for x in PLAYLIST.read_text().splitlines() if x.strip()] if PLAYLIST.exists() else []
def save(x): PLAYLIST.with_suffix('.tmp').write_text('\n'.join(x)+('\n' if x else '')); PLAYLIST.with_suffix('.tmp').replace(PLAYLIST)
def clear_normalized(filename):
 (NORMALIZED/(filename+'.mp4')).unlink(missing_ok=True)
 (NORMALIZED/(filename+'.stamp')).unlink(missing_ok=True)
class ListUpdate(BaseModel): files:list[str]
class State(BaseModel): enabled:bool
class ModeUpdate(BaseModel): mode:str
class RemoteSource(BaseModel): url:str
@app.on_event('startup')
def startup():
 if not PASSWORD: raise RuntimeError('Set MEDIA_ADMIN_PASSWORD in .env')
 VIDEOS.mkdir(parents=True,exist_ok=True); PLAYLIST.touch(exist_ok=True)
 if not PLAYBACK.exists(): PLAYBACK.write_text('on\n')
 if not MODE.exists(): MODE.write_text('loop\n')
@app.get('/',response_class=HTMLResponse,dependencies=[Depends(auth)])
def home(): return '''<!doctype html><title>Media</title><style>body{font:16px system-ui;max-width:700px;margin:3rem auto}button{margin:.25rem}.on{background:#176b3a;color:#fff}</style><h1>Local Media Library</h1><p id=s>Loading…</p><button id=loop onclick=m('loop')>Loop playlist</button><button id=once onclick=m('once')>Play once (keep file)</button><button id=bars onclick=p(false)>Show color bars</button><button onclick=p(true)>Play playlist</button><hr><form id=f><input type=file name=file accept="video/*" required><button id=uploadButton>Upload</button></form><progress id=uploadProgress max=100 value=0 hidden></progress> <span id=uploadStatus role=status aria-live=polite></span><p><input id=url size=55 placeholder="https://example.com/video.mp4 or stream.m3u8"><button onclick=addUrl()>Add online source</button></p><ol id=l></ol><button onclick=saveList()>Save playlist</button><script>let files=[],list=[],$=x=>document.querySelector(x);async function r(u,o={}){let x=await fetch(u,o);if(!x.ok)throw Error(await x.text());return x.json()}async function load(){let d=await r('/api/media'),q=await r('/api/status');files=d.files;list=d.playlist;$('#s').textContent='Fallback: '+(!q.enabled?'color bars':q.mode==='once'?'play once (keep file)':'loop playlist');['loop','once','bars'].forEach(x=>$('#'+x).classList.toggle('on',x==='bars'?!q.enabled:q.enabled&&x===q.mode));draw()}function draw(){let l=$('#l');l.innerHTML='';[...files,...list.filter(x=>x.startsWith('http'))].forEach(n=>{let i=document.createElement('li'),c=document.createElement('input');c.type='checkbox';c.checked=list.includes(n);c.onchange=()=>{list=c.checked?[...list,n]:list.filter(x=>x!==n);draw()};i.append(c,' ',n);if(!n.startsWith('http')){let d=document.createElement('button');d.textContent='Delete';d.onclick=async()=>{if(confirm('Delete '+n+'?')){await r('/api/media/'+encodeURIComponent(n),{method:'DELETE'});load()}};i.append(d)}l.append(i)})}async function p(e){await r('/api/playback',{method:'PUT',headers:{'content-type':'application/json'},body:JSON.stringify({enabled:e})});load()}async function m(x){await r('/api/playlist/mode',{method:'PUT',headers:{'content-type':'application/json'},body:JSON.stringify({mode:x})});p(true)}async function saveList(){await r('/api/playlist',{method:'PUT',headers:{'content-type':'application/json'},body:JSON.stringify({files:list})});load()}async function addUrl(){let u=$('#url').value.trim();if(!u)return;await r('/api/playlist/remote',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({url:u})});$('#url').value='';load()}function upload(form){return new Promise((resolve,reject)=>{let x=new XMLHttpRequest();x.open('POST','/api/upload');x.upload.onprogress=e=>{if(e.lengthComputable){let percent=Math.round(e.loaded/e.total*100);$('#uploadProgress').value=percent;$('#uploadStatus').textContent=percent<100?'Uploading '+percent+'%':'Processing upload…'}else $('#uploadStatus').textContent='Uploading…'};x.onload=()=>x.status>=200&&x.status<300?resolve():reject(Error(x.responseText||'HTTP '+x.status));x.onerror=()=>reject(Error('Network error'));x.send(new FormData(form))})}$('#f').onsubmit=async e=>{e.preventDefault();let button=$('#uploadButton'),progress=$('#uploadProgress');button.disabled=true;progress.hidden=false;progress.value=0;$('#uploadStatus').textContent='Uploading 0%';try{await upload(e.target);e.target.reset();progress.value=100;$('#uploadStatus').textContent='Upload complete';await load()}catch(error){$('#uploadStatus').textContent='Upload failed: '+error.message}finally{button.disabled=false}};load()</script>'''
@app.get('/api/status',dependencies=[Depends(auth)])
def status(): return {'enabled':PLAYBACK.read_text().strip()=='on','mode':MODE.read_text().strip()}
@app.get('/api/media',dependencies=[Depends(auth)])
def media(): return {'files':sorted(x.name for x in VIDEOS.iterdir() if x.is_file() and x.suffix.lower() in ALLOWED),'playlist':items()}
@app.post('/api/upload',dependencies=[Depends(auth)])
async def upload(file:UploadFile=File(...)):
 n=name(file.filename or ''); t=VIDEOS/n; tmp=t.with_suffix(t.suffix+'.uploading')
 with tmp.open('wb') as o:
  while c:=await file.read(1048576): o.write(c)
 tmp.replace(t); clear_normalized(n); return {'file':n}
@app.put('/api/playlist',dependencies=[Depends(auth)])
def playlist(u:ListUpdate):
 x=[item(a) for a in u.files]
 if any(not a.startswith(('http://','https://')) and not(VIDEOS/a).is_file() for a in x): raise HTTPException(400,'Missing file.')
 save(x); return {'files':x}
@app.post('/api/playlist/remote',dependencies=[Depends(auth)])
def remote(u:RemoteSource):
 url=item(u.url.strip())
 if not url.startswith(('http://','https://')): raise HTTPException(400,'Use an HTTP(S) URL.')
 x=items()
 if url not in x: save(x+[url])
 return {'files':items()}
@app.put('/api/playback',dependencies=[Depends(auth)])
def playback(u:State): PLAYBACK.write_text('on\n' if u.enabled else 'off\n'); return {'enabled':u.enabled}
@app.put('/api/playlist/mode',dependencies=[Depends(auth)])
def mode(u:ModeUpdate):
 if u.mode not in {'loop','once'}: raise HTTPException(400,'Mode must be loop or once.')
 MODE.write_text(u.mode+'\n'); return {'mode':u.mode}
@app.delete('/api/media/{filename}',dependencies=[Depends(auth)])
def delete(filename:str):
 n=name(filename); t=VIDEOS/n
 if not t.is_file(): raise HTTPException(404,'File not found.')
 t.unlink(); clear_normalized(n); save([x for x in items() if x!=n]); return {'deleted':n}
