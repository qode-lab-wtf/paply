import unittest
from bench import score,assign
class MetricsTests(unittest.TestCase):
 def test_permutation_and_missing(self):
  words=[dict(start=1,end=2,speaker='A',text='ja',sentence='a'),dict(start=3,end=4,speaker='B',text='nein',sentence='b')]
  self.assertEqual(score(words,[dict(start=1,end=2,speaker='9'),dict(start=3,end=4,speaker='8')],5)['WDER'],0)
  self.assertEqual(score(words,[dict(start=1,end=2,speaker='9')],5)['WDER'],.5)
 def test_merged_cluster_intervals_are_not_double_counted(self):
  ws=[dict(start=1,end=2,text="ja")]
  segs=[dict(start=1,end=1.6,speaker="a"),dict(start=1,end=1.6,speaker="a"),dict(start=1,end=1.9,speaker="b")]
  self.assertEqual(assign(ws,segs),["b"])
 def test_overlap_tie_abstains(self):
  self.assertEqual(assign([dict(start=1,end=2,text="ja")],[dict(start=1,end=2,speaker="a"),dict(start=1,end=2,speaker="b")]),["?"])
 def test_adjacent_words_merge_for_collar(self):
  from bench import annotation
  a=annotation([dict(start=0,end=1,speaker="a"),dict(start=1,end=2,speaker="a")])
  self.assertEqual(len(a),1)
 def test_smoothing_does_not_use_truth(self):
  words=[dict(start=1,end=2,speaker='A',text='ja',sentence='a')]
  segments=[dict(start=1,end=2,speaker='9')]
  before=assign(words,segments,True);words[0].update(speaker='Z',sentence='random')
  self.assertEqual(before,assign(words,segments,True))
 def test_confident_interjection_survives(self):
  words=[dict(start=i,end=i+.5,text='ja') for i in range(5)]
  segments=[dict(start=i,end=i+.5,speaker='B' if i==2 else 'A') for i in range(5)]
  self.assertEqual(assign(words,segments,True)[2],'B')
if __name__=='__main__':unittest.main()
