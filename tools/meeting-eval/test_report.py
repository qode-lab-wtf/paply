import copy
import unittest
from report import validate_report


class ReportTests(unittest.TestCase):
    def setUp(self):
        self.text = 'Anna soll Ben anrufen.'
        self.report = {'overview': 'Ein Anruf steht an.', 'topics': [], 'decisions': [], 'openQuestions': [],
                       'tasks': [{'text': 'Ben anrufen', 'owner': 'Anna', 'sourceIds': ['segment-1'], 'sourceQuote': self.text}]}

    def test_valid_evidence(self):
        validate_report(self.report, self.text, 'stop')

    def test_fabricated_quotation_rejected(self):
        self.report['tasks'][0]['sourceQuote'] = 'Ben soll Anna anrufen.'
        with self.assertRaises(ValueError):
            validate_report(self.report, self.text, 'stop')

    def test_wrong_reference_rejected(self):
        self.report['tasks'][0]['sourceIds'] = ['invented']
        with self.assertRaises(ValueError):
            validate_report(self.report, self.text, 'stop')

    def test_truncation_rejected_even_for_parseable_json(self):
        with self.assertRaises(ValueError):
            validate_report(self.report, self.text, 'length')

    def test_missing_sections_rejected(self):
        del self.report['decisions']
        with self.assertRaises(ValueError):
            validate_report(self.report, self.text, 'stop')

    def test_empty_quote_rejected(self):
        self.report['tasks'][0]['sourceQuote'] = ''
        with self.assertRaises(ValueError):
            validate_report(self.report, self.text, 'stop')


if __name__ == '__main__':
    unittest.main()
