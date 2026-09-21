"""Lossless merging and report reference contracts, independent of model quality."""
import importlib.util
from pathlib import Path
import unittest
import tempfile
import json

ROOT=Path(__file__).resolve().parents[2]
def load(name):
    spec=importlib.util.spec_from_file_location(name, ROOT/'electron-menubar/meeting/local'/f'{name}.py')
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
worker=load('worker');reporter=load('reporter')

class ProductContracts(unittest.TestCase):
    def test_incomplete_word_alignment_preserves_original_text(self):
        asr={'segments':[{'text':'one two three','start':0,'end':3,'words':[{'word':'one','start':0,'end':1}]}]}
        rows=worker.assign(asr,[{'start':0,'end':3,'speaker':'a'}],'mic','hash')
        self.assertEqual(rows[0]['text'],'one two three');self.assertTrue(rows[0]['uncertain'])
    def test_overlap_keeps_text_and_marks_uncertainty(self):
        asr={'segments':[{'text':' hi','start':0,'end':1,'words':[{'word':' hi','start':0,'end':1}]}]}
        rows=worker.assign(asr,[{'start':0,'end':1,'speaker':'a'},{'start':0,'end':1,'speaker':'b'}],'mic','hash')
        self.assertEqual(rows[0]['text'],' hi');self.assertTrue(rows[0]['uncertain'])
    def test_detected_untranscribed_voice_is_visible(self):
        rows=worker.assign({'segments':[]},[{'start':1,'end':2,'speaker':'a'}],'mic','hash')
        self.assertEqual(rows[0]['kind'],'audio-gap')
    def test_equal_word_timestamps_preserve_original_text_order(self):
        asr={'segments':[{'text':'first second','start':0,'end':1,'words':[{'word':'first','start':0,'end':0},{'word':' second','start':0,'end':1}]}]}
        with tempfile.TemporaryDirectory() as temp:
            directory=Path(temp);(directory/'processing').mkdir()
            (directory/'processing/mic-asr.json').write_text(json.dumps(asr))
            (directory/'processing/mic-diarization.json').write_text(json.dumps([{'start':0,'end':1,'speaker':'a'}]))
            result=worker.merge(directory,{'tracks':{'mic':{'sha256':'source-order'}},'models':{}})
            self.assertEqual(''.join(s['text'] for s in result['segments']),'first second')
    def test_long_report_chunks_cover_every_segment(self):
        sources=[{'id':str(i),'tStart':i,'speaker':'Sprecher 1','text':'content '*100} for i in range(100)]
        groups=list(reporter.chunks(sources))
        self.assertGreater(len(groups),1)
        self.assertEqual([s['id'] for group in groups for s in group],[s['id'] for s in sources])
    def test_rejected_claim_becomes_exact_source_not_a_decision(self):
        source={'id':'s','text':'If yes, I know I was deceived.','speaker':'S1'}
        report={'decisions':[{'text':'Matter is closed.','sourceIds':['s'],'sources':[source]}]}
        approved,fallback=reporter.apply_review(report,{'checks':[{'id':0,'supported':False}]})
        self.assertEqual(approved['decisions'],[])
        self.assertIn(source['text'],fallback[0]['text'])
        self.assertNotIn('Matter is closed.',fallback[0]['text'])
    def test_incomplete_or_duplicate_review_cannot_approve_claims(self):
        report={'topics':[{'text':'one'},{'text':'two'}]}
        for checks in [[],[{'id':0,'supported':True}]*2,[{'id':0,'supported':'yes'},{'id':1,'supported':True}]]:
            with self.assertRaises(ValueError):reporter.apply_review(report,{'checks':checks})
    def test_unknown_report_references_rejected(self):
        report={k:[] for k in reporter.schema(['s1'])['required']}
        report['tasks']=[{'text':'unsupported','sourceIds':['made-up']}]
        with self.assertRaises(ValueError):reporter.validate(report,[{'id':'s1'}])

if __name__=='__main__':unittest.main()
