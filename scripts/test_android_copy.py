#!/usr/bin/env python3
"""Negative publication-gate checks using temporary synthetic source, never user data."""
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from audit_android_copy import ROOT, audit

class AndroidCopyGateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        shutil.copytree(ROOT/'apps/android/app/src/main/res', self.root/'apps/android/app/src/main/res')
        (self.root/'qa').mkdir()
        shutil.copy(ROOT/'qa/android_copy_review.json', self.root/'qa/android_copy_review.json')
    def tearDown(self): self.temp.cleanup()
    def test_unreviewed_replacement_and_placeholder_fail(self):
        p=self.root/'apps/android/app/src/main/res/values/strings.xml'
        p.write_text(p.read_text().replace('>Together<','>Sample Data<',1))
        report=audit(self.root)
        self.assertEqual('FAIL',report['status'])
        self.assertIn('unreviewed_copy',{x['type'] for x in report['issues']})
        self.assertIn('placeholder',{x['type'] for x in report['issues']})
    def test_new_visible_kotlin_literal_fails(self):
        p=self.root/'apps/android/app/src/main/java/Test.kt';p.parent.mkdir(parents=True)
        p.write_text('Text("Unreviewed product sentence")')
        self.assertTrue(any(x['type']=='visible_literal' for x in audit(self.root)['issues']))
    def test_user_content_is_not_a_static_copy_input(self):
        (self.root/'private-user-content.txt').write_text('Sample Data '+ '❤️'*2000)
        self.assertEqual('PASS',audit(self.root)['status'])
    def test_long_copy_warns_without_disabling_rule(self):
        index_path=self.root/'qa/android_copy_review.json';index=json.loads(index_path.read_text())
        p=self.root/'apps/android/app/src/main/res/values-zh-rCN/strings.xml'
        original='在受信任的 Mac 创建“添加我的设备”邀请，导入后核对双方校验码。'
        replacement='甲'*40
        self.assertIn(original,p.read_text());p.write_text(p.read_text().replace(original,replacement))
        index['values-zh-rCN/guidance_add_device']['sha256']=hashlib.sha256(replacement.encode()).hexdigest()
        index_path.write_text(json.dumps(index))
        report=audit(self.root);self.assertEqual('WARN',report['status']);self.assertTrue(any(x['type']=='copy_budget' for x in report['issues']))
if __name__=='__main__': unittest.main()
