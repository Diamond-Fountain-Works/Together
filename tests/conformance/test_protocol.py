"""Language-neutral fixture checks; only synthetic files, never app storage."""
from pathlib import Path
from decimal import Decimal, ROUND_HALF_UP
from datetime import datetime
from zoneinfo import ZoneInfo
import base64, calendar, hashlib, json, unittest, uuid
from jsonschema import Draft202012Validator
ROOT=Path(__file__).resolve().parents[2]
V=json.loads((ROOT/'protocol/fixtures/conformance-v1.json').read_text())
SCHEMA=json.loads((ROOT/'protocol/schemas/domain-v3.schema.json').read_text())

class ProtocolConformance(unittest.TestCase):
    def test_actual_swift_dto_contracts(self):
        Draft202012Validator.check_schema(SCHEMA)
        samples=json.loads((ROOT/'protocol/fixtures/dto-snapshots-v3.json').read_text())
        self.assertTrue(samples['synthetic'])
        for name,value in samples['samples'].items():
            with self.subTest(dto=name):
                Draft202012Validator({**SCHEMA,'$ref':'#/$defs/'+name}).validate(value)
        self.assertTrue({'SharedSpace','UserProfile','DeviceIdentity','SyncOperation','TodoTask','WishGrant','WishItem','DailyLoveGift','FinanceAmount','ExpenseEntry','RecurringBill','MediaAsset'}<=set(samples['samples']))
    def test_private_material_is_not_a_device_contract_field(self):
        descriptor=dict(json.loads((ROOT/'protocol/fixtures/dto-snapshots-v3.json').read_text())['samples']['DeviceIdentity'])
        descriptor['privateKeyData']='SYNTHETIC_INVALID_FIELD'
        self.assertFalse(Draft202012Validator({**SCHEMA,'$ref':'#/$defs/DeviceIdentity'}).is_valid(descriptor))
    def test_uuid_epoch_and_shared_day(self):
        self.assertEqual(str(uuid.UUID(V['uuid']['input'])).upper(),V['uuid']['canonical'])
        t=V['time'];d=datetime.fromisoformat(t['instant'].replace('Z','+00:00'))
        self.assertEqual(int(d.timestamp()*1000),t['epochMilliseconds'])
        self.assertEqual(d.astimezone(ZoneInfo(t['sharedZone'])).strftime('%Y-%m-%d'),t['dayKey'])
    def test_money_decimal_and_aa(self):
        for v in V['money']:
            digits=0 if v['currency']=='JPY' else 2
            self.assertEqual(int(Decimal(v['original'])*(10**digits)),int(v['originalMinor']))
            self.assertEqual(int((Decimal(v.get('actualCNY',v['original']))*100).quantize(Decimal(1),rounding=ROUND_HALF_UP)),int(v['cnyMinor']))
        total=int(Decimal(V['aa']['totalCNY'])*100);a=total//2+total%2;b=total//2
        self.assertEqual([str(a),str(b)],V['aa']['sharesMinor']);self.assertEqual(a+b,total)
    def test_monthly31_cycle_and_next_month(self):
        for v in V['monthly31']:
            y,m=map(int,v['month'].split('-'));day=min(31,calendar.monthrange(y,m)[1])
            self.assertEqual(f'{y:04}-{m:02}-{day:02}',v['date'])
        v=V['cycle'];zone=ZoneInfo(v['zone']);start=datetime.fromisoformat(v['start'].replace('Z','+00:00')).astimezone(zone);end=datetime.fromisoformat(v['end'].replace('Z','+00:00')).astimezone(zone)
        self.assertEqual(start.day,29);self.assertEqual(end.day,31);self.assertLess(start,end)
        y,m=map(int,V['revision']['currentMonth'].split('-'));next_month=f'{y+int(m==12):04}-{1 if m==12 else m+1:02}'
        self.assertEqual(next_month,V['revision']['effectiveMonth'])
    def test_stable_uuid_and_media_hash(self):
        v=V['stableID'];data=bytearray(hashlib.sha256(v['seed'].encode()).digest()[:16]);data[6]=(data[6]&15)|80;data[8]=(data[8]&63)|128
        self.assertEqual(str(uuid.UUID(bytes=bytes(data))).upper(),v['uuid'])
        v=V['media'];data=base64.b64decode(v['base64'],validate=True)
        self.assertEqual(len(data),v['byteCount']);self.assertEqual(hashlib.sha256(data).hexdigest(),v['sha256'])
    def test_invitation_target_is_not_misreported_as_implemented(self):
        # This unchanged Protocol 3 fixture records the original v1 relay purpose;
        # it is not the normal native App's current first-partner contract.
        v=V['invitation'];self.assertEqual(v['implementedTTLms'],600000);self.assertEqual(v['requiredTTLms'],8*60*60*1000);self.assertEqual(v['targetStatus'],'PENDING_NETWORK_CHANGE');self.assertTrue(v['oneUse'])
        source=(ROOT/'services/relay/src/index.ts').read_text()
        # The new, separately versioned partner purpose has an 8-hour TTL;
        # the existing v1 invitation behavior remains unchanged pending PR #3.
        self.assertIn('nativePartner ? 28800000 : 600000',source)
        self.assertIn('path === "/v2/partner-invitations"',source)
    def test_current_invitation_metadata_separates_authorities_and_wire_encodings(self):
        v=json.loads((ROOT/'protocol/versions.json').read_text())['invitation']
        self.assertEqual(v['activeForFreshNormalApps'],'nativePeer')
        self.assertEqual(v['requiredPartnerLifetimeMilliseconds'],8*60*60*1000)
        self.assertEqual(v['legacyRelay']['lifetimeMilliseconds'],600000)
        self.assertEqual(v['legacyRelay']['endpoint'],'/v1/invitations')
        self.assertEqual(v['partnerRelay']['lifetimeMilliseconds'],28800000)
        self.assertEqual(v['partnerRelay']['endpoint'],'/v2/partner-invitations')
        self.assertTrue(v['legacyRelay']['oneUse'] and v['partnerRelay']['oneUse'])
        native=v['nativePeer']
        fixture=json.loads((ROOT/'protocol/fixtures/native-partner-contact-v1.json').read_text())
        contact=fixture['contact'] if 'contact' in fixture else fixture
        self.assertEqual(contact['body']['expiresAt']-contact['body']['issuedAt'],native['lifetimeMilliseconds'])
        self.assertEqual(native['encoding'],'signed-canonical-json-native-partner-contact-v1')
        self.assertEqual(native['timestampUnit'],'unix-milliseconds')
        self.assertNotEqual(native['authority'],v['partnerRelay']['authority'])
        self.assertIn('receiver local system clock',native['authority'])
        self.assertIn('does not revoke',native['pinnedReconnect'])
    def test_version_dimensions(self):
        versions=json.loads((ROOT/'protocol/versions.json').read_text());app=json.loads((ROOT/versions['appVersionSource']).read_text())
        self.assertEqual(app['deviceProtocolVersion'],versions['syncProtocolVersion']);self.assertEqual(versions['databaseSchemaVersion'],1);self.assertEqual(versions['relayServiceProtocolVersion'],1)
    def test_signed_log_schema_and_reference_replay(self):
        # CryptoKit verifies signatures in Swift; here independently exercise
        # the same portable ordering/deduplication/tombstone vector.
        v=json.loads((ROOT/'protocol/fixtures/signed-log-v3.json').read_text())
        self.assertTrue(v['synthetic'])
        operations=v['operations']
        for signed in operations:
            Draft202012Validator({**SCHEMA,'$ref':'#/$defs/SignedOperation'}).validate(signed)
            self.assertEqual(len(base64.b64decode(signed['signature'],validate=True)),64)
        projections=[]
        for inputs in [operations,list(reversed(operations)),operations+operations]:
            unique={s['operation']['operationId']:s['operation'] for s in inputs}
            self.assertEqual(len(unique),v['expectedDistinctOperations'])
            fields={};deleted=False;before=None
            for op in sorted(unique.values(),key=lambda o:(o['lamportClock'],o['deviceId'],o['operationId'])):
                if op['operationType']=='delete':
                    before=dict(fields);deleted=True
                elif not deleted:
                    fields.update(op['payload'])
            self.assertEqual(before['title']['string']['_0'],v['expectedTitleBeforeDeletion'])
            self.assertEqual(before['notes']['string']['_0'],v['expectedIndependentNotes'])
            self.assertEqual(deleted,v['expectedDeleted']);projections.append((fields,deleted))
        self.assertEqual(projections[0],projections[1]);self.assertEqual(projections[1],projections[2])

if __name__=='__main__':unittest.main()
