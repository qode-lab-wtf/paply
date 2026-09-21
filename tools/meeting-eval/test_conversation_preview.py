import unittest
from conversation_preview import assign_words


class AssignmentTests(unittest.TestCase):
    def test_overlap_preserves_word_and_marks_uncertainty(self):
        asr={'segments':[{'text':' Hallo','start':0,'end':1,'words':[{'word':' Hallo','start':0,'end':1}]}]}
        result=assign_words(asr,[{'speaker':'A','start':0,'end':1},{'speaker':'B','start':0,'end':1}])
        self.assertEqual(result[0]['text'],' Hallo')
        self.assertIn('Überlappung',result[0]['speaker'])

    def test_missing_word_alignment_preserves_full_text(self):
        result=assign_words({'segments':[{'text':'eins zwei','start':0,'end':1,'words':[{'word':'eins','start':0,'end':.5}]}]},[])
        self.assertEqual(result[0]['text'],'eins zwei')
        self.assertIn('unvollständig',result[0]['speaker'])

    def test_duplicate_intervals_do_not_inflate_confidence(self):
        asr={'segments':[{'text':'Hallo','start':0,'end':1,'words':[{'word':'Hallo','start':0,'end':1}]}]}
        result=assign_words(asr,[{'speaker':'A','start':0,'end':.4}]*3)
        self.assertEqual(result[0]['speaker'],'Zuordnung unklar')
