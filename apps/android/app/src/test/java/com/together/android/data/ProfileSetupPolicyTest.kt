package com.together.android.data

import org.junit.Assert.*
import org.junit.Test

class ProfileSetupPolicyTest {
    @Test fun firstReleaseRequiresProfileButPersistedProfileCompletesSetup() {
        assertTrue(ProfileSetupPolicy.required(true, false, false))
        assertFalse(ProfileSetupPolicy.required(true, false, true))
        assertFalse(ProfileSetupPolicy.required(true, true, false))
        assertFalse(ProfileSetupPolicy.required(false, true, false))
    }

    @Test fun initialSetupRequiresAnExplicitSupportedRelationshipAndName() {
        assertFalse(ProfileSetupPolicy.canSave("Alice", "unknown", true))
        assertFalse(ProfileSetupPolicy.canSave("Alice", "future-family-role", true))
        assertFalse(ProfileSetupPolicy.canSave("   ", "boyfriend", true))
        assertFalse(ProfileSetupPolicy.canSave("a".repeat(81), "girlfriend", true))
        assertTrue(ProfileSetupPolicy.canSave("Alice", "boyfriend", true))
        assertTrue(ProfileSetupPolicy.canSave("Alice", "girlfriend", true))
    }

    @Test fun existingProfilesCanKeepNeutralLabelsWithoutRestartingSetup() {
        assertTrue(ProfileSetupPolicy.canSave("Alice", "unknown", false))
        assertFalse(ProfileSetupPolicy.required(true, false, true))
    }
}
