import unittest
from stability import agreement

def row(start,end,speaker):return {'start':start,'end':end,'speaker':speaker}

class StabilityContracts(unittest.TestCase):
    def test_labels_do_not_change_agreement(self):
        a=[row(0,1,'A'),row(1,2,'B')];b=[row(0,1,'Y'),row(1,2,'X')]
        x=agreement(a,b,2);self.assertEqual(x['mappedAgreement'],1);self.assertFalse(x['qualityApproved'])
    def test_collapsed_speakers_are_not_perfect_agreement(self):
        x=agreement([row(0,1,'A'),row(1,2,'B')],[row(0,2,'X')],2)
        self.assertEqual(x['mappedAgreement'],.5);self.assertEqual(len(x['disagreementIntervals']),1)
    def test_excluded_overlap_and_silence_do_not_inflate_score(self):
        x=agreement([row(0,2,'A')],[row(0,1,'X'),row(0,1,'Y')],2)
        self.assertIsNone(x['mappedAgreement']);self.assertEqual(x['comparableSeconds'],0)
        self.assertEqual(x['speechPresenceDisagreementSeconds'],1)
    def test_small_intervals_are_integrated_without_frame_rounding(self):
        x=agreement([row(0,.003,'A')],[row(0,.003,'B')],1)
        self.assertAlmostEqual(x['comparableSeconds'],.003)
if __name__=='__main__':unittest.main()
