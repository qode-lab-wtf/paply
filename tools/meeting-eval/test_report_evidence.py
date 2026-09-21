import unittest
from jsonschema import ValidationError
from report_evidence import build_sources, validate_and_attach


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.sources = build_sources({'status':'completed','text':'Anna ruft Ben an.', 'segments':[
            {'start':0,'end':2,'text':'Anna ruft Ben an.'}]})
        self.report = {'overview':{'text':'Ein Anruf.', 'sourceIds':[self.sources[0]['id']]},
                       'topics':[], 'decisions':[], 'tasks':[], 'openQuestions':[]}

    def test_attaches_original_source_and_timestamps(self):
        result=validate_and_attach(self.report,self.sources,'stop')
        self.assertEqual(result['overview']['sources'][0]['text'],'Anna ruft Ben an.')
        self.assertEqual(result['overview']['sources'][0]['end'],2)
        self.assertNotIn('sources',self.report['overview'])

    def test_missing_transcript_portion_rejected(self):
        with self.assertRaises(ValueError):
            build_sources({'status':'completed','text':'eins zwei','segments':[{'text':'eins'}]})

    def test_unknown_reference_rejected(self):
        self.report['overview']['sourceIds']=['unknown']
        with self.assertRaises(ValidationError):
            validate_and_attach(self.report,self.sources,'stop')

    def test_truncation_rejected(self):
        with self.assertRaises(ValueError):
            validate_and_attach(self.report,self.sources,'length')

    def test_unreferenced_overview_rejected(self):
        self.report['overview']='Unbelegte Aussage'
        with self.assertRaises(ValidationError):
            validate_and_attach(self.report,self.sources,'stop')
