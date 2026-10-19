package com.together.android

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.together.android.ui.PartnerPairingPanel
import com.together.protocol.PartnerPairingState
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

/** No production repository/identity and no system file picker. */
class PartnerPairingUiTest {
    @get:Rule val compose = createAndroidComposeRule<com.together.android.qa.BusinessQaActivity>()
    @Test fun partnerCodeIsTypedAndJoinUsesThatText() {
        var created=0;var joined:String?=null
        compose.setContent { MaterialTheme { PartnerPairingPanel(PartnerPairingState(),{created++},{joined=it},{}) } }
        compose.onNodeWithTag("partner.create").assertIsDisplayed().performClick()
        assertEquals(1,created)
        compose.onNodeWithTag("partner.join").assertIsNotEnabled()
        compose.onNodeWithTag("partner.codeInput").performTextInput("ABCD23456789")
        androidx.test.espresso.Espresso.closeSoftKeyboard();compose.waitForIdle()
        compose.onNodeWithTag("partner.join").assertIsDisplayed().assertIsEnabled().performClick()
        assertEquals("ABCD23456789",joined)
    }
    @Test fun unavailableServiceIsAnErrorAndNotASuccessfulPairing() {
        compose.setContent { MaterialTheme { PartnerPairingPanel(PartnerPairingState("error",error="PARTNER_SERVICE_UPGRADE_REQUIRED"),{},{},{}) } }
        compose.onNodeWithTag("partner.serviceUnavailable").assertIsDisplayed()
        compose.onNodeWithTag("partner.confirm").assertDoesNotExist()
        compose.onNodeWithTag("partner.codeInput").assertExists()
    }
}
