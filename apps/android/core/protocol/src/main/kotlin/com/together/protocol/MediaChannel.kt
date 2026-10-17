package com.together.protocol

import kotlinx.serialization.json.JsonObject

/** Authenticated existing WirePayload channel. Operation replication remains independent. */
interface MediaChannel {
    fun synchronize(remote: DeviceDescriptor): List<JsonObject>

    fun receive(remote: DeviceDescriptor, payload: JsonObject): List<JsonObject>

    fun disconnected(deviceId: String)
}
