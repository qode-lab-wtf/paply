"""AMI manual-word evaluation; reference units are punctuation/pause-defined, not oracle smoothing."""
import argparse,json,time,resource,zipfile,xml.etree.ElementTree as ET
from pathlib import Path
from collections import Counter,defaultdict
import numpy as np
import soundfile as sf
from scipy.optimize import linear_sum_assignment
from pyannote.core import Annotation,Segment,Timeline
from pyannote.metrics.diarization import DiarizationErrorRate,JaccardErrorRate
from fetch import ROOT

def words(meeting):
    out=[]
    with zipfile.ZipFile(ROOT/'data/annotations.zip') as z:
        for name in z.namelist():
            if '/'+meeting+'.' not in '/'+name or not name.endswith('.words.xml'): continue
            speaker=Path(name).name.split('.')[1]
            sentence=0; last=0
            for w in ET.fromstring(z.read(name)):
                if w.tag!='w' or 'starttime' not in w.attrib or 'endtime' not in w.attrib: continue
                a,b=float(w.attrib['starttime']),float(w.attrib['endtime'])
                if b<=a: continue
                if a-last>0.8: sentence+=1
                out.append(dict(start=a,end=b,speaker=speaker,text=w.text or '',sentence=f'{speaker}-{sentence}'))
                if (w.text or '').endswith(('.', '?', '!')): sentence+=1
                last=b
    return sorted(out,key=lambda x:x['start'])
def annotation(rows):
    a=Annotation()
    for i,r in enumerate(rows): a[Segment(r['start'],r['end']),i]=str(r['speaker'])
    return a.support()

def assign(ws,segs,smooth=False):
    # After cluster merging, overlapping intervals of the SAME speaker count only once.
    by_speaker=defaultdict(list)
    for segment in segs: by_speaker[str(segment['speaker'])].append(segment)
    merged=[]
    for speaker, segments in by_speaker.items():
        intervals=[]
        for segment in sorted(segments,key=lambda x:x['start']):
            if intervals and segment['start']<=intervals[-1]['end']:
                intervals[-1]['end']=max(intervals[-1]['end'],segment['end'])
            else: intervals.append(dict(start=segment['start'],end=segment['end'],speaker=speaker))
        merged.extend(intervals)
    segs=merged
    labels=[]; confidence=[]
    for w in ws:
        score=Counter()
        for s in segs:
            overlap=max(0,min(w['end'],s['end'])-max(w['start'],s['start']))
            if overlap: score[str(s['speaker'])]+=overlap
        ranked=score.most_common()
        labels.append(ranked[0][0] if ranked and (len(ranked)==1 or ranked[0][1]-ranked[1][1]>1e-6) else '?')
        confidence.append((ranked[0][1]-(ranked[1][1] if len(ranked)>1 else 0))/(w['end']-w['start']) if ranked else 0)
    if smooth:
        # Observable punctuation/pause only: NEVER use ground-truth sentence or speaker IDs here.
        groups=[]; group=[]
        for i,w in enumerate(ws):
            if group and w['start']-ws[group[-1]]['end']>0.8: groups.append(group);group=[]
            group.append(i)
            if w.get('text','').endswith(('.', '?', '!')): groups.append(group);group=[]
        if group: groups.append(group)
        for group in groups:
            majority,n=Counter(labels[i] for i in group if labels[i]!='?').most_common(1)[0] if any(labels[i]!='?' for i in group) else ('?',0)
            if n/max(1,len(group))<0.7: continue
            for i in group:
                if confidence[i]<0.6: labels[i]=majority
    return labels

def score(ws,segs,duration,smooth=False):
    ref,hyp=annotation(ws),annotation(segs)
    uem=Timeline([Segment(0,duration)])
    der=DiarizationErrorRate(collar=.25,skip_overlap=False)(ref,hyp,uem=uem)
    jer=JaccardErrorRate(collar=.25,skip_overlap=False)(ref,hyp,uem=uem)
    labels=assign(ws,segs,smooth)
    truth=sorted(set(w['speaker'] for w in ws)); clusters=sorted(set(labels)-{'?'})
    mat=np.zeros((len(clusters),len(truth)),dtype=int)
    for w,l in zip(ws,labels):
        if l!='?': mat[clusters.index(l),truth.index(w['speaker'])]+=1
    ii,jj=linear_sum_assignment(-mat)
    mapping={clusters[i]:truth[j] for i,j in zip(ii,jj)}
    errors=[mapping.get(l)!=w['speaker'] for w,l in zip(ws,labels)]
    units=defaultdict(list)
    for w,e in zip(ws,errors): units[w['sentence']].append(e)
    return dict(scorer_version=4,DER=der,JER=jer,WDER=sum(errors)/len(ws),sentence_any_error=sum(any(v) for v in units.values())/len(units),sentence_majority_error=sum(sum(v)>len(v)/2 for v in units.values())/len(units),words=len(ws),sentences=len(units),count_error=len(set(str(s['speaker']) for s in segs))-len(truth),unknown_rate=labels.count('?')/len(labels))
def sherpa(audio,model,n,threshold):
    import sherpa_onnx as sh
    config=sh.OfflineSpeakerDiarizationConfig(segmentation=sh.OfflineSpeakerSegmentationModelConfig(pyannote=sh.OfflineSpeakerSegmentationPyannoteModelConfig(model=str(ROOT/'models/sherpa-onnx-pyannote-segmentation-3-0/model.onnx'),window_shift_ratio=.1),num_threads=2),embedding=sh.SpeakerEmbeddingExtractorConfig(model=str(model),num_threads=2),clustering=sh.FastClusteringConfig(num_clusters=n,threshold=threshold),min_duration_on=.0,min_duration_off=.0)
    start=time.perf_counter(); d=sh.OfflineSpeakerDiarization(config)
    segs=[dict(start=s.start,end=s.end,speaker=str(s.speaker)) for s in d.process(audio).sort_by_start_time()]
    return dict(segments=segs,seconds=time.perf_counter()-start,peak_rss_bytes=resource.getrusage(resource.RUSAGE_SELF).ru_maxrss)
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('meeting');p.add_argument('--model');p.add_argument('--hyp');p.add_argument('--speakers',type=int,default=-1);p.add_argument('--threshold',type=float,default=.7);a=p.parse_args()
    audio,sr=sf.read(ROOT/f'data/{a.meeting}.wav',dtype='float32');assert sr==16000 and audio.ndim==1
    if a.hyp: result=json.loads(Path(a.hyp).read_text());name=Path(a.hyp).stem
    else:
        name=f'{a.meeting}-{Path(a.model).stem}-n{a.speakers}-t{a.threshold}'
        dest=ROOT/f'results/{name}.json'
        if dest.exists(): result=json.loads(dest.read_text())
        else:
            result=sherpa(audio,a.model,a.speakers,a.threshold);dest.write_text(json.dumps(result))
    ws=words(a.meeting);assert ws
    for smooth in [False,True]:
        metrics=score(ws,result['segments'],len(audio)/sr,smooth)
        metrics.update(meeting=a.meeting,engine=name,smooth=smooth,seconds=result['seconds'],rtf=result['seconds']/(len(audio)/sr),duration=len(audio)/sr,peak_rss_bytes=result.get('peak_rss_bytes'))
        (ROOT/f'results/{name}-smooth{smooth}-metrics.json').write_text(json.dumps(metrics,indent=2));print(json.dumps(metrics),flush=True)
