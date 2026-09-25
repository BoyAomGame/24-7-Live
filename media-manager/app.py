import os
import secrets
from pathlib import Path
from typing import Annotated

from fastapi import Depends, FastAPI, File, HTTPException, UploadFile
from fastapi.responses import HTMLResponse
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from pydantic import BaseModel

ROOT = Path("/media")
VIDEOS = ROOT / "videos"
PLAYLIST = ROOT / "playlist.txt"
PLAYBACK = ROOT / "playback.enabled"
ALLOWED = {".mp4", ".m4v", ".mov", ".mkv", ".webm"}
USER = os.getenv("MEDIA_ADMIN_USERNAME", "admin")
PASSWORD = os.getenv("MEDIA_ADMIN_PASSWORD", "")
security = HTTPBasic()
app = FastAPI(title="Local Media Library", docs_url=None, redoc_url=None)

def auth(credentials: Annotated[HTTPBasicCredentials, Depends(security)]):
    if not PASSWORD or not (secrets.compare_digest(credentials.username, USER) and secrets.compare_digest(credentials.password, PASSWORD)):
        raise HTTPException(status_code=401, detail="Invalid credentials", headers={"WWW-Authenticate": "Basic"})

def safe_name(name: str) -> str:
    name = Path(name).name
    if not name or Path(name).suffix.lower() not in ALLOWED:
        raise HTTPException(400, "Use MP4, M4V, MOV, MKV, or WebM files.")
    return name

def playlist() -> list[str]:
    if not PLAYLIST.exists(): return []
    return [line.strip() for line in PLAYLIST.read_text(encoding="utf-8").splitlines() if line.strip()]

class PlaylistUpdate(BaseModel):
    files: list[str]

class PlaybackUpdate(BaseModel):
    enabled: bool

@app.on_event("startup")
def setup():
    if not PASSWORD: raise RuntimeError("Set MEDIA_ADMIN_PASSWORD in .env before starting the media profile")
    VIDEOS.mkdir(parents=True, exist_ok=True)
    PLAYLIST.touch(exist_ok=True)
    if not PLAYBACK.exists(): PLAYBACK.write_text("on\n", encoding="utf-8")

@app.get("/", response_class=HTMLResponse, dependencies=[Depends(auth)])
def home():
    return '''<!doctype html><title>Local Media Library</title><style>body{font:16px system-ui;max-width:760px;margin:3rem auto;padding:0 1rem}li{margin:.5rem 0}button{margin-left:.5rem}#status{color:#175d28}</style><h1>Local Media Library</h1><p>Uploads play in playlist order whenever no live input is active.</p><form id=f><input type=file name=file accept="video/*" required><button>Upload</button></form><p id=status></p><ol id=list></ol><button onclick=save()>Save playlist</button><button onclick=setPlayback(true)>Play playlist</button><button onclick=setPlayback(false)>Show color bars</button><script>let files=[],order=[];const l=document.querySelector('#list'),s=document.querySelector('#status');async function load(){let x=await fetch('/api/media');({files,playlist:order}=await x.json());render()}function render(){l.innerHTML='';files.forEach(n=>{let i=document.createElement('li'),c=document.createElement('input');c.type='checkbox';c.checked=order.includes(n);c.onchange=()=>{order=c.checked?[...order,n]:order.filter(x=>x!=n);render()};i.append(c,' ',n);if(c.checked){let u=document.createElement('button');u.textContent='Up';u.onclick=()=>{let p=order.indexOf(n);if(p){[order[p-1],order[p]]=[order[p],order[p-1]];render()}};let d=document.createElement('button');d.textContent='Down';d.onclick=()=>{let p=order.indexOf(n);if(p<order.length-1){[order[p+1],order[p]]=[order[p],order[p+1]];render()}};i.append(u,d)}l.append(i)})}document.querySelector('#f').onsubmit=async e=>{e.preventDefault();s.textContent='Uploading…';let r=await fetch('/api/upload',{method:'POST',body:new FormData(e.target)});s.textContent=r.ok?'Uploaded. Add it to the playlist and save.':await r.text();if(r.ok){e.target.reset();load()}};async function save(){let r=await fetch('/api/playlist',{method:'PUT',headers:{'content-type':'application/json'},body:JSON.stringify({files:order})});s.textContent=r.ok?'Playlist saved.':'Could not save playlist.'}async function setPlayback(enabled){let r=await fetch('/api/playback',{method:'PUT',headers:{'content-type':'application/json'},body:JSON.stringify({enabled})});s.textContent=r.ok?(enabled?'Playlist will play when idle.':'Color bars will show when idle.'):'Could not change fallback.'}load()</script>'''

@app.get("/api/media", dependencies=[Depends(auth)])
def list_media():
    items = sorted(p.name for p in VIDEOS.iterdir() if p.is_file() and p.suffix.lower() in ALLOWED)
    return {"files": items, "playlist": playlist()}

@app.post("/api/upload", dependencies=[Depends(auth)])
async def upload(file: UploadFile = File(...)):
    name = safe_name(file.filename or "")
    target = VIDEOS / name
    temporary = target.with_suffix(target.suffix + ".uploading")
    with temporary.open("wb") as out:
        while chunk := await file.read(1024 * 1024): out.write(chunk)
    temporary.replace(target)
    return {"file": name}

@app.put("/api/playlist", dependencies=[Depends(auth)])
def save_playlist(update: PlaylistUpdate):
    names = [safe_name(name) for name in update.files]
    if any(not (VIDEOS / name).is_file() for name in names): raise HTTPException(400, "Playlist contains a missing file.")
    temporary = PLAYLIST.with_suffix(".tmp")
    temporary.write_text("\n".join(names) + ("\n" if names else ""), encoding="utf-8")
    temporary.replace(PLAYLIST)
    return {"files": names}

@app.delete("/api/media/{name}", dependencies=[Depends(auth)])
def delete_media(name: str):
    name = safe_name(name)
    target = VIDEOS / name
    if not target.is_file(): raise HTTPException(404, "File not found.")
    target.unlink()
    remaining = [item for item in playlist() if item != name]
    temporary = PLAYLIST.with_suffix(".tmp")
    temporary.write_text("\n".join(remaining) + ("\n" if remaining else ""), encoding="utf-8")
    temporary.replace(PLAYLIST)
    return {"deleted": name}

@app.put("/api/playback", dependencies=[Depends(auth)])
def set_playback(update: PlaybackUpdate):
    temporary = PLAYBACK.with_suffix(".tmp")
    temporary.write_text("on\n" if update.enabled else "off\n", encoding="utf-8")
    temporary.replace(PLAYBACK)
    return {"enabled": update.enabled}
