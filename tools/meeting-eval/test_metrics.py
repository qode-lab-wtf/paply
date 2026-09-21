import unittest
from metrics import score, speaker_accuracy, word_error_rate
from run_model import normalize_turns


def seg(a, b, who):
    return {'start': a, 'end': b, 'speaker': who}


class MetricsTests(unittest.TestCase):
    def test_model_padding_clipped_to_audio(self):
        self.assertEqual(normalize_turns([{'startTimeSeconds': 20, 'endTimeSeconds': 21.07, 'speakerId': 's'}], 21),
                         [seg(20, 21, 's')])

    def test_renumbering_does_not_penalize(self):
        m = speaker_accuracy([seg(0, 1, 'A'), seg(1, 2, 'B')], [seg(0, 1, '9'), seg(1, 2, '7')], 2)
        self.assertEqual(m['accuracy'], 1)

    def test_one_speaker_collapse_fails(self):
        m = speaker_accuracy([seg(0, 1, 'A'), seg(1, 2, 'B')], [seg(0, 2, '0')], 2)
        self.assertEqual(m['accuracy'], .5)

    def test_overlap_excluded_not_declared_correct(self):
        m = speaker_accuracy([seg(0, 2, 'A'), seg(1, 2, 'B')], [seg(0, 2, '0')], 2)
        self.assertEqual(m['evaluatedSeconds'], 1)
        self.assertEqual(m['overlapSeconds'], 1)

    def test_missing_audio_is_wrong(self):
        m = speaker_accuracy([seg(0, 2, 'A')], [], 2)
        self.assertEqual(m['accuracy'], 0)

    def test_extra_simultaneous_speaker_is_wrong(self):
        m = speaker_accuracy([seg(0, 2, 'A')], [seg(0, 2, '0'), seg(1, 2, '1')], 2)
        self.assertEqual(m['accuracy'], .5)

    def test_invalid_times_rejected(self):
        with self.assertRaises(ValueError):
            speaker_accuracy([seg(0, float('nan'), 'A')], [], 2)

    def test_word_errors_and_normalization(self):
        self.assertEqual(word_error_rate('Ja, möglich!', 'ja möglich')['wer'], 0)
        self.assertEqual(word_error_rate('Wir kaufen zwei Teile', 'Wir kaufen drei Teile')['wer'], .25)

    def test_unreviewed_never_passes(self):
        self.assertFalse(score({'reference': {'reviewed': False}}, {})['passed'])

    def test_different_audio_rejected(self):
        with self.assertRaises(ValueError):
            score({'reference': {'reviewed': True, 'reviewer': 'human'}, 'audioSha256': 'a'}, {'audioSha256': 'b'})

    def test_empty_reference_never_passes(self):
        m = score({'reference': {'reviewed': True, 'reviewer': 'human', 'text': ''}, 'audioSha256': 'a'},
                  {'task': 'asr', 'text': '', 'audioSha256': 'a'})
        self.assertFalse(m['passed'])


if __name__ == '__main__':
    unittest.main()
