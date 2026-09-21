import base64
import contextlib
import io
import json
from pathlib import Path
import re
import sys
import tempfile
import unittest
from unittest.mock import patch
import review


class ReviewTests(unittest.TestCase):
    def test_audio_bytes_and_script_escaping_survive_embedding(self):
        # Regression: generic DATA replacement corrupted real WAV base64 once.
        with tempfile.TemporaryDirectory() as folder:
            p = Path(folder)
            audio = base64.b64decode('DATA')
            (p/'audio.wav').write_bytes(audio)
            manifest = {'audio': str(p/'audio.wav'), 'audioSha256': 'a', 'id': 'test',
                        'durationSeconds': 1, 'reference': {'reviewed': False}}
            asr = {'audioSha256': 'a', 'status': 'completed', 'candidate': 'test', 'text': '</script><script>bad()</script>'}
            diar = {'audioSha256': 'a', 'status': 'completed', 'candidate': 'test', 'segments': []}
            for name, data in [('m', manifest), ('asr', asr), ('diar', diar)]:
                (p/(name+'.json')).write_text(json.dumps(data))
            args = ['review.py', str(p/'m.json'), '--asr', str(p/'asr.json'), '--diarization', str(p/'diar.json'), '--output', str(p/'review.html')]
            with patch.object(sys, 'argv', args), contextlib.redirect_stdout(io.StringIO()):
                review.main()
            output = (p/'review.html').read_text()
            encoded = re.search('base64,([^"<>]*)', output)[1]
            self.assertEqual(base64.b64decode(encoded), audio)
            self.assertNotIn('</script><script>bad()', output)
            self.assertIn('id="text"', output)


if __name__ == '__main__':
    unittest.main()
