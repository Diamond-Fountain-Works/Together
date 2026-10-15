"""Portable hashing/shape vectors; signatures are tested by CryptoKit/WebCrypto."""
from pathlib import Path
import base64, hashlib, json, unittest
from jsonschema import Draft202012Validator
from referencing import Registry, Resource
ROOT=Path(__file__).resolve().parents[2]
def canonical(value):return json.dumps(value,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode()
def digest(value):return hashlib.sha256(canonical(value)).hexdigest()
class ReplicationV4Conformance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture=json.loads((ROOT/'protocol/fixtures/replication-v4.json').read_text())
        cls.schema=json.loads((ROOT/'protocol/schemas/replication-v4.schema.json').read_text())
        legacy=json.loads((ROOT/'protocol/schemas/domain-v3.schema.json').read_text())
        cls.registry=Registry().with_resources([(s['$id'],Resource.from_contents(s)) for s in [legacy,cls.schema]])
    def validate(self,name,value):
        Draft202012Validator({'$ref':self.schema['$id']+'#/$defs/'+name},registry=self.registry).validate(value)
    def test_public_synthetic_metadata_and_explicit_frames(self):
        v=self.fixture;self.assertTrue(v['synthetic']);self.assertEqual(v['protocolVersion'],4)
        self.validate('AuthorizationArchive',v['authorization']);self.validate('ReplicationRecord',v['record']);self.validate('SignedAcknowledgement',v['receipt'])
        for frame in v['frames']:self.validate('ReplicationFrame',frame)
        self.assertEqual(len(v['frames']),8)
    def test_authorization_operation_and_certificate_digests(self):
        v=self.fixture;self.assertEqual(digest(v['authorization']),v['authorizationDigest'])
        record=v['record']['authorized'];self.assertEqual(digest(record),v['inventory']['certificationDigest'])
        self.assertEqual(digest(record['body']['signedOperation']),v['inventory']['contentDigest'])
        self.assertEqual(digest(v['record']),v['recordDigest'])
        self.assertEqual(len(base64.b64decode(record['signature'],validate=True)),64)
    def test_inventory_includes_certificate_not_only_operation_id(self):
        v=self.fixture;e=v['inventory'];line=f"{e['operationId']}:{e['contentDigest']}:{e['certificationDigest']}\n".encode()
        self.assertEqual(hashlib.sha256(b'Together-Inventory-4\n'+line).hexdigest(),v['checkpoint']['digest'])
        self.assertEqual(v['checkpoint']['count'],1)
    def test_oversized_inventory_and_unknown_frame_are_rejected(self):
        from copy import deepcopy
        from jsonschema import ValidationError
        frame=deepcopy(self.fixture['frames'][2]);frame['page']['entries']*=129
        with self.assertRaises(ValidationError):self.validate('ReplicationFrame',frame)
        with self.assertRaises(ValidationError):self.validate('ReplicationFrame',{'kind':'databaseSnapshot','passId':self.fixture['frames'][1]['passId']})
if __name__=='__main__':unittest.main()
