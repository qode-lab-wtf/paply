"""Copy existing evaluation audio/results into the isolated app; never read API keys."""
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
DEST=Path.home()/'Library/Application Support/Paply Gespräch Test'
DEST.mkdir(parents=True,exist_ok=True)
config_file=DEST/'config.json'
config=json.loads(config_file.read_text()) if config_file.exists() else {}
entries=config.get('meetings',[])
for letter in ['a','b','c','d','e']:
    session_id=f'eval-{letter}'
    if any(s['id']==session_id for s in entries):continue
    directory=DEST/'meetings'/session_id
    (directory/'processing').mkdir(parents=True,exist_ok=True)
    tracks={};duration=0
    for channel in ['mic','system']:
        manifest=ROOT/f'work/samples/conversation-{letter}-{channel}.json'
        if not manifest.exists():continue
        m=json.loads(manifest.read_text());audio=Path(m['audio'])
        # Historical evaluation output names have two conventions.
        if letter=='a' and channel=='mic':asr='whisper-a-mic';diar='pyannote-a-mic-offline'
        elif letter=='b':asr='whisper-b-offline';diar='pyannote-b-offline'
        else:asr=f'whisper-{letter}-{channel}-offline';diar=f'pyannote-{letter}-{channel}-offline'
        a=json.loads((ROOT/f'work/results/{asr}.json').read_text());d=json.loads((ROOT/f'work/results/{diar}.json').read_text())
        actual=hashlib.sha256(audio.read_bytes()).hexdigest()
        if a['status']!='completed' or d['status']!='completed' or not actual==a['audioSha256']==d['audioSha256']==m['audioSha256']:raise ValueError('Incomplete or mismatched evaluation')
        shutil.copy2(audio,directory/f'audio_{channel}.wav')
        (directory/'processing'/f'{channel}-asr.json').write_text(json.dumps(a,ensure_ascii=False))
        (directory/'processing'/f'{channel}-diarization.json').write_text(json.dumps(d['segments']))
        tracks[channel]={'sha256':actual,'offsetSeconds':0,'timing':'historical-offset-unverified'}
        duration=max(duration,m['durationSeconds'])
    runtime=json.loads((ROOT/'work/local-runtime.json').read_text())
    state={'schemaVersion':2,'status':'processing','retentionPolicy':'historical-copy-preserve','audioExpiresAt':None,'tracks':tracks,'completed':{},'models':runtime['models'],'importedEvaluation':True}
    (directory/'local-state.json').write_text(json.dumps(state,indent=2))
    worker=ROOT/'electron-menubar/meeting/local/worker.py'
    def run(stage):
        subprocess.run(['/usr/bin/sandbox-exec','-p','(version 1)(allow default)(deny network*)',runtime['diarizationPython'],str(worker),stage,str(directory),str(ROOT/'work/local-runtime.json')],check=True)
    run('merge');shutil.copy2(directory/'transcript.json',directory/'report-input.json');run('report')
    state['status']='ready';(directory/'local-state.json').write_text(json.dumps(state,indent=2))
    transcript=json.loads((directory/'transcript.json').read_text());speakers=list(dict.fromkeys(s['speaker'] for s in transcript['segments']))
    entries.append({'id':session_id,'startTime':'2026-09-21T10:00:00.000Z','durationMs':duration*1000,'title':f'Vorhandenes Gespräch {letter.upper()} · Testkopie','speakerCount':len(speakers),'speakerNames':speakers,'preview':'Lokal ausgewertete Testkopie','hasSummary':True,'favorite':False,'diarizationUsed':True,'diarizationSpeakers':len(speakers)})
config.update(meetings=entries,meetingHotkey='Command+Option+Shift+X',autoStart=False)
config_file.write_text(json.dumps(config,ensure_ascii=False,indent=2))
print(f'Imported {len(entries)} isolated test conversations')
