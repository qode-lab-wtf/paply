"""Offline meeting worker. One stage per process; no cloud or model download fallback."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import time

os.environ.update(HF_HUB_OFFLINE='1', TRANSFORMERS_OFFLINE='1', PYANNOTE_METRICS_ENABLED='false', HF_HUB_DISABLE_TELEMETRY='1')


def save(path, value):
    path=Path(path)
    with tempfile.NamedTemporaryFile(mode='w',dir=path.parent,prefix=path.name+'.',suffix='.tmp',delete=False) as f:
        json.dump(value,f,ensure_ascii=False,indent=2);f.flush();os.fsync(f.fileno());temp=f.name
    os.replace(temp,path)


def digest(path):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        while data:=f.read(1024*1024):h.update(data)
    return h.hexdigest()


def transcribe(audio, config):
    import soundfile as sf
    import numpy as np
    with sf.SoundFile(audio) as f:
        if f.frames==0:return {'text':'','segments':[]}
        # Only digital near-silence can be skipped. Never gate quiet voices by a coarse RMS.
        peak=0
        for block in f.blocks(blocksize=16000):peak=max(peak,float(np.max(np.abs(block))))
    if peak<1/32768:return {'text':'','segments':[]}
    if config.get('asrBackend', 'mlx-whisper') == 'faster-whisper':
        from dataclasses import asdict
        from faster_whisper import WhisperModel
        model=WhisperModel(config['fasterWhisperModel'],device='cpu',compute_type='int8',cpu_threads=8,local_files_only=True)
        segments,_=model.transcribe(str(audio),language='de',beam_size=5,vad_filter=True,
                                   word_timestamps=True,condition_on_previous_text=False)
        segments=[asdict(s) for s in segments]
        return {'text':''.join(s['text'] for s in segments),'segments':segments}
    if config.get('asrBackend', 'mlx-whisper') != 'mlx-whisper':raise ValueError('Unsupported ASR backend')
    import mlx_whisper
    return mlx_whisper.transcribe(str(audio),path_or_hf_repo=config['whisperModel'],language='de',
                                 word_timestamps=True,condition_on_previous_text=False,temperature=0,verbose=False)


def diarize(audio, config):
    import soundfile as sf
    import torch
    from pyannote.audio import Pipeline
    signal,rate=sf.read(audio,dtype='float32',always_2d=True)
    duration=len(signal)/rate
    if not len(signal):return []
    pipeline=Pipeline.from_pretrained(config['pyannoteModel'])
    device=config.get('diarizationDevice','cpu')
    if device not in ('cpu','mps'):raise ValueError('Unsupported diarization device')
    if device=='mps' and not torch.backends.mps.is_available():raise RuntimeError('Apple GPU nicht verfügbar; CPU kann ausdrücklich konfiguriert werden')
    pipeline.to(torch.device(device))
    output=pipeline({'waveform':torch.from_numpy(signal.T.copy()),'sample_rate':rate})
    return [{'start':max(0,t.start),'end':min(duration,t.end),'speaker':speaker}
            for t,speaker in output.speaker_diarization if min(duration,t.end)>max(0,t.start)]


def assign(asr, turns, channel, audio_hash, offset=0):
    labels=list(dict.fromkeys(t['speaker'] for t in sorted(turns,key=lambda t:t['start'])))
    names={s:channel+'-speaker-'+hashlib.sha256(json.dumps([audio_hash, [(round(t['start'],3),round(t['end'],3)) for t in turns if t['speaker']==s]]).encode()).hexdigest()[:16] for s in labels}
    rows=[]
    for segment in asr['segments']:
        words=segment.get('words',[])
        complete=''.join(w['word'] for w in words).split()==segment['text'].split()
        if not complete:words=[{'word':segment['text'],'start':segment['start'],'end':segment['end']}]
        for w in words:
            a,b=w['start'],w['end'];span=max(.001,b-a)
            coverage={}
            for label in labels:
                intervals=sorted((max(a,t['start']),min(b,t['end'])) for t in turns if t['speaker']==label and t['start']<b and t['end']>a)
                total=0;previous=a
                for lo,hi in intervals:total+=max(0,hi-max(lo,previous));previous=max(previous,hi)
                if total:coverage[label]=total/span
            ranked=sorted(coverage,key=coverage.get,reverse=True)
            uncertain=not complete or not ranked or coverage[ranked[0]]<.6 or (len(ranked)>1 and coverage[ranked[1]]>=.2)
            speaker_id=names[ranked[0]] if not uncertain else channel+'-unclear'
            row={'tStart':a+offset,'tEnd':b+offset,'text':w['word'],'channel':channel,'speakerId':speaker_id,
                 'uncertain':uncertain,'candidateSpeakerIds':[names[k] for k in ranked]}
            row['id']=hashlib.sha256(json.dumps([audio_hash,channel,a,b,w['word']],ensure_ascii=False).encode()).hexdigest()[:24]
            rows.append(row)
    grouped=[]
    for row in rows:
        if grouped and grouped[-1]['speakerId']==row['speakerId'] and grouped[-1]['uncertain']==row['uncertain'] and row['tStart']-grouped[-1]['tEnd']<.7 and len(grouped[-1]['text'])<280:
            grouped[-1]['text']+=row['text'];grouped[-1]['tEnd']=row['tEnd'];grouped[-1]['wordIds'].append(row['id'])
        else:grouped.append({**row,'wordIds':[row['id']]})
    # A changed segment boundary must not silently inherit a whole-text correction.
    for group in grouped:
        group['id']=hashlib.sha256(json.dumps(group['wordIds']).encode()).hexdigest()[:24]
    # Preserve acoustic evidence even if ASR missed a short response.
    for t in turns:
        if not any(w['tStart']<t['end']+offset and w['tEnd']>t['start']+offset for w in rows):
            grouped.append({'id':hashlib.sha256(f'{audio_hash}:{channel}:gap:{t["start"]}'.encode()).hexdigest()[:24],
                'tStart':t['start']+offset,'tEnd':t['end']+offset,'text':'[Sprache erkannt – Text unklar]',
                'channel':channel,'speakerId':names[t['speaker']],'uncertain':True,'kind':'audio-gap','wordIds':[]})
    return grouped


def merge(directory,state):
    segments=[]
    for channel,track in state['tracks'].items():
        asr=json.loads((directory/'processing'/f'{channel}-asr.json').read_text())
        turns=json.loads((directory/'processing'/f'{channel}-diarization.json').read_text())
        rows=assign(asr,turns,channel,track['sha256'],track.get('offsetSeconds',0))
        for row in rows:row['timingUncertain']=track.get('timingUncertain',False)
        segments.extend(rows)
    segments.sort(key=lambda s:(s['tStart'],s['channel']))
    labels=list(dict.fromkeys(s['speakerId'] for s in segments if not s['speakerId'].endswith('-unclear')))
    for s in segments:
        s['speaker']='Zuordnung unklar' if s['speakerId'].endswith('-unclear') else f'Sprecher {labels.index(s["speakerId"])+1}'
    # Acoustic echo evidence is advisory: never delete concurrent contributions.
    if {'mic','system'} <= set(state['tracks']):
        import numpy as np
        import soundfile as sf
        from scipy.signal import correlate
        from difflib import SequenceMatcher
        signals={ch:sf.read(directory/f'audio_{ch}.wav',dtype='float32')[0] for ch in ['mic','system']}
        rates={ch:sf.info(directory/f'audio_{ch}.wav').samplerate for ch in signals}
        if rates['mic']==rates['system']:
            rate=rates['mic']
            for m in [s for s in segments if s['channel']=='mic' and s.get('kind')!='audio-gap']:
                for remote in [s for s in segments if s['channel']=='system' and abs(s['tStart']-m['tStart'])<1.5]:
                    if SequenceMatcher(None,m['text'].casefold(),remote['text'].casefold()).ratio()<.8:continue
                    a=max(m['tStart'],remote['tStart']);b=min(m['tEnd'],remote['tEnd'],a+3)
                    if b-a<.4:continue
                    clips=[]
                    for ch in ['mic','system']:
                        off=state['tracks'][ch].get('offsetSeconds',0)
                        x=signals[ch][max(0,int((a-off)*rate)):max(0,int((b-off)*rate)):4];x=x-x.mean() if len(x) else x;clips.append(x)
                    if min(map(len,clips))<100:continue
                    score=float(np.max(np.abs(correlate(*clips,mode='full',method='fft')))/(np.linalg.norm(clips[0])*np.linalg.norm(clips[1])+1e-9))
                    if score>=.85:m['possibleEchoOf']=remote['id'];m['echoCorrelation']=score;m['uncertain']=True
    return {'schemaVersion':2,'language':'de','segments':segments,'provisional':False,
            'qualityApproved':False,'models':state['models'],'alignment':'word-overlap-with-visible-uncertainty'}


def source_report(transcript):
    # Safe source overview while no generative report model has passed factuality evaluation.
    sections=[]
    for s in transcript['segments']:
        block=int(s['tStart']//180)
        if not sections or sections[-1]['block']!=block:sections.append({'block':block,'title':f'Gespräch ab {block*3:02d}:00','sources':[]})
        sections[-1]['sources'].append({'id':s['id'],'tStart':s['tStart'],'speaker':s['speaker'],'text':s['text']})
    return {'schemaVersion':2,'kurzzusammenfassung':'Quellenübersicht des Gesprächs. Eine inhaltlich geprüfte automatische Zusammenfassung steht noch aus.',
        'kernpunkte':[],'todos':[],'offeneFragen':[],'sections':sections,'reportStatus':'source-overview',
        'model':'deterministic-source-overview','generatedAt':__import__('datetime').datetime.now(__import__('datetime').timezone.utc).isoformat()}


def untranscribed_seconds(transcript):
    total=0
    for channel in {s.get('channel') for s in transcript['segments']}:
        end=0
        for row in sorted((s for s in transcript['segments'] if s.get('channel')==channel and s.get('kind')=='audio-gap'),key=lambda s:s['tStart']):
            total+=max(0,row['tEnd']-max(end,row['tStart']))
            end=max(end,row['tEnd'])
    return total


def main():
    p=argparse.ArgumentParser();p.add_argument('stage',choices=['enhancement','asr','diarization','merge','report']);p.add_argument('directory',type=Path);p.add_argument('config',type=Path);p.add_argument('--channel',choices=['mic','system']);a=p.parse_args()
    config=json.loads(a.config.read_text());state=json.loads((a.directory/'local-state.json').read_text())
    if state['schemaVersion']!=2:raise ValueError('Unsupported session version')
    if a.stage in ['enhancement','asr','diarization']:
        if state.get('audioExpiresAt') and time.time()*1000>=state['audioExpiresAt']:raise ValueError('Audio-Aufbewahrungszeit abgelaufen')
        audio=a.directory/f'audio_{a.channel}.wav'
        if digest(audio)!=state['tracks'][a.channel]['sha256']:raise ValueError('Audio changed since capture')
        if a.stage=='enhancement':
            from enhancer import enhance
            output=a.directory/'processing'/f'{a.channel}-enhanced.wav'
            enhance(audio,output,config,state)
            out={'sourceSha256':digest(audio),'sha256':digest(output),'model':config['models']['enhancementRevision']}
        else:
            # Enhancement improves clustering here but can distort recognized words.
            # Transcription therefore always uses the untouched original recording.
            if config.get('enhancementModel') and a.channel=='mic' and a.stage=='diarization':
                evidence=json.loads((a.directory/'processing'/'mic-enhancement.json').read_text())
                if evidence['sourceSha256']!=digest(audio):raise ValueError('Enhancement source mismatch')
                audio=a.directory/'processing'/'mic-enhanced.wav'
                if evidence['sha256']!=digest(audio):raise ValueError('Enhanced audio changed')
            out=transcribe(audio,config) if a.stage=='asr' else diarize(audio,config)
        target=a.directory/'processing'/f'{a.channel}-{a.stage}.json'
    elif a.stage=='merge':out=merge(a.directory,state);target=a.directory/'transcript.json'
    else:
        transcript=json.loads((a.directory/'report-input.json').read_text())
        if untranscribed_seconds(transcript)>=10:
            out=source_report(transcript)
            out.update(reportStatus='needs-transcript-review',qualityApproved=False,kurzzusammenfassung='Bericht zurückgestellt: Mindestens zehn Sekunden erkannte Sprache fehlen im Transkript. Zuerst die gekennzeichneten Tonstellen prüfen; daraus wird keine scheinbar vollständige Zusammenfassung erzeugt.')
        elif config.get('reporter'):
            from reporter import generate
            out=generate(transcript,config,a.directory/'processing')
        else:out=source_report(transcript)
        target=a.directory/'summary.json'
    save(target,out)

if __name__=='__main__':
    try:main()
    except Exception as error:
        print(f'{type(error).__name__}: {error}',file=sys.stderr);sys.exit(1)
