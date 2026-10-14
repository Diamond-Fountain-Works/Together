"""Local reviewer safety: immutable inputs, explicit evidence, no approval writes."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from PIL import Image
import build_visual_review as review


class VisualReviewTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.addCleanup(patch.stopall)
        patch.object(review, 'ROOT', self.root).start()
        patch.object(review, 'expected_cases', return_value=['home-empty-light.png']).start()
        self.base = self.root/'qa/visual/approved'
        self.run = self.root/'qa/results/frozen'
        (self.run/'images').mkdir(parents=True)
        self.base.mkdir(parents=True)
        (self.root/'qa/project.json').write_text('{}')
        self.name = 'home-empty-light.png'
        for folder in (self.base, self.run/'images'):
            Image.new('RGB', (100, 100), 'white').save(folder/self.name)
        baseline = {'images': {self.name: {'sha256': review.sha(self.base/self.name),
                                         'sourceResultBundle': 'qa/results/ui-old.xcresult'}}}
        (self.base/'manifest.json').write_text(json.dumps(baseline))
        self.manifest = self.run/'manifest.json'
        self.frozen = {'sourceResultBundle': 'qa/results/ui-new.xcresult',
                       'uiPassed': 1, 'uiFailed': 0, 'uiSkipped': 0,
                       'images': [{'case': self.name, 'sha256': review.sha(self.run/'images'/self.name),
                                   'comparison': review.compare(self.base/self.name, self.run/'images'/self.name)}]}
        self.write_manifest()
        self.output = self.run/'browser'

    def write_manifest(self):
        self.manifest.write_text(json.dumps(self.frozen))

    def test_generation_preserves_inputs_and_does_not_approve_pixel_pass(self):
        inputs = [self.base/'manifest.json', self.base/self.name, self.manifest, self.run/'images'/self.name]
        before = {path: review.sha(path) for path in inputs}
        data = review.build(self.manifest, self.output)
        self.assertEqual(data['rawCounts'], {'PASS': 1})
        self.assertEqual(data['humanApprovalCount'], 0)
        self.assertFalse(data['baselineMutated'])
        self.assertFalse(data['remoteWrites'])
        self.assertEqual(before, {path: review.sha(path) for path in inputs})
        self.assertIn('未获得 Build 5 人工批准', data['screenshots'][0]['analysis']['assessment'])
        self.assertTrue((self.output/'index.html').is_file())

    def test_rejects_modified_frozen_and_approved_bytes(self):
        for path in (self.base/self.name, self.run/'images'/self.name):
            original = path.read_bytes()
            Image.new('RGB', (100, 100), 'black').save(path)
            with self.assertRaisesRegex(ValueError, 'hash changed'):
                review.build(self.manifest, self.output)
            path.write_bytes(original)

    def test_rejects_duplicate_matrix_and_modified_comparison(self):
        self.frozen['images'].append(dict(self.frozen['images'][0]))
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, 'duplicated'):
            review.build(self.manifest, self.output)
        self.frozen['images'].pop()
        self.frozen['images'][0]['comparison']['severity'] = 'REVIEW REQUIRED'
        self.write_manifest()
        with self.assertRaisesRegex(ValueError, 'disagrees'):
            review.build(self.manifest, self.output)

    def test_output_cannot_target_approved_baseline_or_outside_repository(self):
        for folder in (self.base, self.root.parent/'outside-review'):
            with self.assertRaises(ValueError):
                review.build(self.manifest, folder)
        self.assertFalse((self.base/'index.html').exists())

    def test_inline_metadata_cannot_close_script_element(self):
        self.frozen['sourceResultBundle'] = 'qa/results/ui-</script><script>bad()</script>.xcresult'
        self.write_manifest()
        review.build(self.manifest, self.output)
        html = (self.output/'index.html').read_text()
        self.assertNotIn('</script><script>bad()', html)
        self.assertIn('\\u003c/script>', html)

    def test_edge_evidence_does_not_exempt_comparison_or_decide_fix(self):
        original = self.base/self.name
        candidate = self.run/'images'/self.name
        image = Image.open(candidate).convert('RGB'); image.putpixel((1, 2), (0, 0, 0)); image.save(candidate)
        metrics = review.measure(original, candidate, self.run/'mask.png')
        raw = review.compare(original, candidate)
        scope = {'frame': [0, 0, 50, 50], 'window': [0, 0, 50, 50]}
        result = review.classify(self.name, raw, metrics, scope, scope)
        self.assertEqual(raw['severity'], 'REVIEW REQUIRED')
        self.assertEqual(metrics['centerStrongPixels'], 0)
        self.assertEqual(result['group'], '窗口外缘与背景')
        self.assertIn('尚未确认需要', result['assessment'])
        image.putpixel((50, 50), (0, 0, 0)); image.save(candidate)
        metrics = review.measure(original, candidate, self.run/'mask.png')
        self.assertEqual(metrics['centerStrongPixels'], 1)
        self.assertEqual(review.classify(self.name, raw, metrics, scope, scope)['group'], '人工布局复核')

    def test_native_frame_metadata_is_explicit_and_traceable(self):
        folder = self.root/'qa/results/attachments-old'; folder.mkdir(parents=True)
        filename = 'frame.txt'
        (folder/filename).write_text('Native XCTest scope: popover; frame: (593.0, 72.0, 356.0, 280.0); fixture window: (80.0, 182.0, 900.0, 672.0)')
        (folder/'manifest.json').write_text(json.dumps([{'attachments': [
            {'suggestedHumanReadableName': 'home-empty-light-capture-scope_0', 'exportedFileName': filename,
             'timestamp': 1791985812.91}], 'testIdentifier': 'TogetherUITests/testSnapshotMatrix()'}]))
        scope = review.scope_metadata('qa/results/ui-old.xcresult')[self.name]
        self.assertEqual(scope['frame'], [593, 72, 356, 280])
        self.assertEqual(scope['window'], [80, 182, 900, 672])
        self.assertEqual(Path(scope['sourcePath']), (folder/filename).resolve())
        self.assertEqual(scope['frameRecordedAt'], '2026-10-14T13:50:12.910000+00:00')
        self.assertEqual(scope['testIdentifier'], 'TogetherUITests/testSnapshotMatrix()')


if __name__ == '__main__':
    unittest.main()
