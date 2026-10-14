import unittest,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent))
from audit_repository_safety import findings
class RepositorySafetyTests(unittest.TestCase):
    def test_private_data_and_keys_block_publication(self):
        for path in ['private/Together.store','old/device.key','config/.env','cert/signing.p12','photos/private.heic','audio/private.m4a','qa/results/runtime.log']:
            self.assertTrue(findings(path,b'','test'),path)
        self.assertTrue(findings('misnamed.dat',b'SQLite format 3\x00','test'))
    def test_detects_generated_credential_without_exposing_it(self):
        value=('gh'+'p_'+'a'*36).encode();issues=findings('config.txt',value,'test')
        self.assertTrue(any(x['rule']=='github_token' for x in issues));self.assertNotIn(value.decode(),str(issues))
    def test_icons_and_synthetic_baselines_have_declared_provenance(self):
        self.assertFalse(findings('apps/apple/macOS/Sources/TogetherApp/Resources/IconSource/preview-1024.png',b'','test'))
        self.assertFalse(findings('qa/visual/approved/home.png',b'','test'))
        self.assertTrue(findings('photos/unknown.png',b'','test'))
if __name__=='__main__':unittest.main()
