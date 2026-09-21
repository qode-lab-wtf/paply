"""Lossless merging and report reference contracts, independent of model quality."""
import importlib.util
from pathlib import Path
import unittest

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
    def test_long_report_chunks_cover_every_segment(self):
        sources=[{'id':str(i),'tStart':i,'speaker':'Sprecher 1','text':'content '*100} for i in range(100)]
        groups=list(reporter.chunks(sources))
        self.assertGreater(len(groups),1)
        self.assertEqual([s['id'] for group in groups for s in group],[s['id'] for s in sources])
    def test_unknown_report_references_rejected(self):
        report={k:[] for k in reporter.schema(['s1'])['required']}
        report['tasks']=[{'text':'unsupported','sourceIds':['made-up']}]
        with self.assertRaises(ValueError):reporter.validate(report,[{'id':'s1'}])

if __name__=='__main__':unittest.main()
