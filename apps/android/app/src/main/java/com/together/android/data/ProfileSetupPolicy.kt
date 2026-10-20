package com.together.android.data

import com.together.domain.Relationship
import com.together.protocol.graphemeCount

internal object ProfileSetupPolicy {
    fun required(native: Boolean, debug: Boolean, hasProfile: Boolean) = native && !debug && !hasProfile

    fun canSave(name: String, relationship: String, initial: Boolean) =
        name.isNotBlank() && name.graphemeCount() <= 80 &&
            (!initial || Relationship.parse(relationship) != Relationship.UNKNOWN)
}
