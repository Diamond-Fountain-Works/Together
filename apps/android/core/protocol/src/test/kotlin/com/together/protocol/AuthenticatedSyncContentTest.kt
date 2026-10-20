package com.together.protocol

import java.io.File
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class AuthenticatedSyncContentTest {
    @Test fun existingC1EnvelopeFixturesRoundTripExactlyAndDoNotAcceptRawReplication() {
        val fixture = Canonical.parse(File(System.getProperty("together.fixtures"), "authenticated-content-v1.json").readBytes()).jsonObject
        assertEquals("together/p4/c1-content/1", fixture.getValue("nativeAppALPN").jsonPrimitive.content)
        assertEquals("together/p4/1", fixture.getValue("legacyTransportALPN").jsonPrimitive.content)
        val values = fixture.getValue("canonicalEnvelopes").jsonArray.map { it.jsonPrimitive.content }
        assertEquals(7, values.size)
        values.forEach { text ->
            val content = AuthenticatedSyncContent.decode(text.toByteArray())
            assertEquals(text, Canonical.encode(content).toString(Charsets.UTF_8))
        }
        val frame = ReplicationFrame("syncHint", hintId = "00000000-0000-0000-0000-0000000000A2")
        assertEquals(values.first(), Canonical.encode(AuthenticatedSyncContent.replication(frame)).toString(Charsets.UTF_8))
        assertThrows(Exception::class.java) { AuthenticatedSyncContent.decode(Canonical.encode(frame)) }
        assertThrows(Exception::class.java) { AuthenticatedSyncContent("media").validate() }
        assertThrows(Exception::class.java) { AuthenticatedSyncContent("replication", frame, JsonObject(emptyMap())).validate() }
    }
}
