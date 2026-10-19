import unittest, tempfile, json, sys, hashlib
from pathlib import Path
from PIL import Image
sys.path.insert(0,str(Path(__file__).parent))
import audit_ui_copy as audit
import compare_visuals as visuals
from compare_visuals import compare, expected_cases
class QualityToolTests(unittest.TestCase):
    def test_capture_run_rejects_replaced_or_escaped_images(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);directory=root/'qa/visual/candidates/run-a';directory.mkdir(parents=True)
            image=directory/'case.png';Image.new('RGB',(10,10),'white').save(image)
            saved=visuals.ROOT,visuals.CANDIDATES
            visuals.ROOT=root;visuals.CANDIDATES=root/'qa/visual/candidates'
            try:
                report={'captureDirectory':'qa/visual/candidates/run-a','screenshotSHA256':{'case.png':visuals.sha(image)}}
                self.assertEqual(visuals.capture_file('case.png',report),image.resolve())
                Image.new('RGB',(10,10),'black').save(image)
                with self.assertRaisesRegex(ValueError,'hash'):visuals.capture_file('case.png',report)
                with self.assertRaisesRegex(ValueError,'escaped'):visuals.capture_file('../case.png',report)
                report['captureDirectory']='qa/results'
                with self.assertRaisesRegex(ValueError,'outside'):visuals.capture_file('case.png',report)
            finally:visuals.ROOT,visuals.CANDIDATES=saved
    def test_copy_catalog_and_raw_unreviewed_error(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);src=root/'0.0.1/Sources/TogetherApp';src.mkdir(parents=True)
            cat=root/'UI.xcstrings';review=root/'review.json'
            cat.write_text(json.dumps({'strings':{'ok':{'localizations':{'zh-Hans':{'stringUnit':{'value':'保存'}}}}}}))
            review.write_text(json.dumps({'entries':{'ok':{'category':'Action','review':'approved','textSHA256':hashlib.sha256('保存'.encode()).hexdigest()}}}))
            (src/'View.swift').write_text('Text("Unreviewed visible copy")')
            saved=audit.ROOT,audit.PROJECT,audit.CATALOG,audit.REVIEW,audit.CORE
            audit.ROOT=root;audit.PROJECT=root/'0.0.1';audit.CATALOG=cat;audit.REVIEW=review;audit.CORE=root/'core'
            try:self.assertTrue(any(i['severity']=='Error' and i['type']=='visible_literal' for i in audit.scan()))
            finally:audit.ROOT,audit.PROJECT,audit.CATALOG,audit.REVIEW,audit.CORE=saved
    def test_changed_copy_cannot_reuse_old_approval(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);cat=root/'UI.xcstrings';review=root/'review.json'
            cat.write_text(json.dumps({'strings':{'ok':{'localizations':{'zh-Hans':{'stringUnit':{'value':'新的文案'}}}}}}))
            review.write_text(json.dumps({'entries':{'ok':{'category':'Action','review':'approved','textSHA256':hashlib.sha256('保存'.encode()).hexdigest()}}}))
            saved=audit.ROOT,audit.PROJECT,audit.CATALOG,audit.REVIEW,audit.CORE
            audit.ROOT=root;audit.PROJECT=root/'0.0.1';audit.CATALOG=cat;audit.REVIEW=review;audit.CORE=root/'core'
            try:self.assertTrue(any(i['type']=='changed_since_review' and i['severity']=='Error' for i in audit.scan()))
            finally:audit.ROOT,audit.PROJECT,audit.CATALOG,audit.REVIEW,audit.CORE=saved
    def test_visual_matrix_requires_all_current_cases(self):
        config=json.loads((Path(__file__).resolve().parents[1]/'qa/project.json').read_text())
        cases=expected_cases(config)
        # Upcoming was merged into Pending on both clients. Its four obsolete
        # page/state captures are historical baselines, not current destinations.
        self.assertEqual(len(cases),64);self.assertEqual(len(set(cases)),64)
        self.assertFalse(any(name.startswith('upcoming-') for name in cases))
        self.assertIn('reveal-dark-reduced-sealed.png',cases)
        self.assertNotIn('upcoming-empty-light-disconnected.png',cases)
        self.assertIn('completed-populated-dark-disconnected.png',cases)
        self.assertIn('wishes-populated-dark-compact-reduced.png',cases)
        self.assertIn('reserves-empty-light-disconnected.png',cases)
        self.assertIn('bills-populated-dark-disconnected.png',cases)
        self.assertIn('finance-settings-populated-light-disconnected.png',cases)
        self.assertIn('expenses-populated-dark-compact-reduced.png',cases)
    def test_native_input_placeholder_is_not_mock_data(self):
        source='TextField("标题", text: $userTitle)'
        self.assertTrue(audit.visible(Path('View.swift'),source,source.index('"'),'标题'))
    def test_user_data_excluded_and_templates_supported(self):
        source='Text(user.giftContent)\n// Text("Sample Data")\nText("有 \\(count) 项")'
        found=audit.literals(source);self.assertEqual(len(found),1);self.assertEqual(found[0][2],'有 \\(count) 项')
        indirect='person(user.profile, fallback: "等待资料同步")'
        self.assertTrue(audit.visible(Path('Sources/TogetherApp/Home.swift'),indirect,indirect.index('"'),'等待资料同步'))
        icon='HStack { Text(role.name); Image(systemName: role == .unknown ? "circle" : "checkmark.circle.fill") }'
        self.assertFalse(audit.visible(Path('View.swift'),icon,icon.index('"'),'circle'))
    def test_visual_identical_minor_major_and_dimensions(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);a=root/'a.png';b=root/'b.png'
            image=Image.new('RGB',(100,100),'white');image.save(a);image.save(b)
            self.assertEqual(compare(a,b)['severity'],'PASS')
            image.putpixel((20,30),(0,0,0));image.save(b);result=compare(a,b)
            self.assertEqual(result['severity'],'REVIEW REQUIRED');self.assertEqual(result['bbox'],(20,30,21,31))
            Image.new('RGB',(100,100),'black').save(b);self.assertEqual(compare(a,b)['severity'],'FAIL')
            Image.new('RGB',(101,100),'white').save(b);self.assertEqual(compare(a,b)['severity'],'FAIL')
if __name__=='__main__':unittest.main()
