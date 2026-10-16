"""Public enrollment file contract, no private keys or server credentials."""
from pathlib import Path
import base64,hashlib,json,unittest
from jsonschema import Draft202012Validator,ValidationError
from referencing import Registry,Resource
ROOT=Path(__file__).resolve().parents[2]
def digest(value):return hashlib.sha256(json.dumps(value,sort_keys=True,ensure_ascii=False,separators=(',',':')).encode()).hexdigest()
class DeviceEnrollmentConformance(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.v=json.loads((ROOT/'protocol/fixtures/device-enrollment-v1.json').read_text())
        cls.s=json.loads((ROOT/'protocol/schemas/device-enrollment-v1.schema.json').read_text())
        schemas=[cls.s]+[json.loads((ROOT/'protocol/schemas'/name).read_text()) for name in ['replication-v4.schema.json','domain-v3.schema.json']]
        cls.registry=Registry().with_resources([(s['$id'],Resource.from_contents(s)) for s in schemas])
    def validate(self,name,obj):Draft202012Validator({'$ref':self.s['$id']+'#/$defs/'+name},registry=self.registry).validate(obj)
    def test_signed_public_shapes_and_independent_device(self):
        v=self.v;self.assertTrue(v['synthetic']);self.assertEqual(v['version'],1)
        for k,n in [('offer','Offer'),('request','Request'),('completion','Completion')]:
            self.validate(n,v[k]);self.assertEqual(len(base64.b64decode(v[k]['signature'],validate=True)),64)
        a=v['offer']['body'];d=v['request']['body']['device'];self.assertEqual(a['ownerId'],d['userId'])
        self.assertNotEqual(a['issuerDeviceId'],d['deviceId']);self.assertEqual(d['protocolVersion'],4)
        self.assertNotIn('privateKey',json.dumps(v));self.assertNotIn('pairingSecret',json.dumps(v))
    def test_digest_and_verification_code_binding(self):
        v=self.v
        for k in ['offer','request']:
            self.assertEqual(digest(v[k]),v[k+'Digest'])
            self.assertEqual(' '.join(v[k+'Digest'][i:i+4].upper() for i in range(0,24,4)),v[k+'Code'])
        self.assertEqual(v['request']['body']['offerDigest'],v['offerDigest'])
        self.assertEqual(v['completion']['body']['requestDigest'],v['requestDigest'])
    def test_unknown_kinds_and_private_key_fields_rejected(self):
        from copy import deepcopy
        x=deepcopy(self.v['request']);x['body']['kind']='InvitePartner'
        with self.assertRaises(ValidationError):self.validate('Request',x)
        x=deepcopy(self.v['request']);x['body']['device']['privateKey']='forbidden'
        with self.assertRaises(ValidationError):self.validate('Request',x)
if __name__=='__main__':unittest.main()
