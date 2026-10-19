package com.together.android.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.together.android.R
import com.together.protocol.PartnerPairingState
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Composable
internal fun PartnerPairingPanel(state: PartnerPairingState,
    onCreate: () -> Unit, onJoin: (String) -> Unit, onConfirm: (Boolean) -> Unit) {
    var input by rememberSaveable { mutableStateOf("") }
    var verified by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(state.verificationCode) { verified = false }
    val busy = state.stage in setOf("creating", "joining", "confirming", "syncing")
    val clipboard = LocalClipboardManager.current
    val peer = state.peer
    val verificationCode = state.verificationCode
    Column(Modifier.fillMaxWidth().padding(24.dp).testTag("partner.pairing"),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(stringResource(R.string.partner_title), style = MaterialTheme.typography.titleLarge)
        if (peer != null && verificationCode != null) {
            Text(peer.profileName, style = MaterialTheme.typography.titleMedium)
            Text(verificationCode, style = MaterialTheme.typography.headlineLarge,
                fontFamily = FontFamily.Monospace, modifier = Modifier.testTag("partner.verificationCode"))
            Text(peer.descriptor.fingerprint, style = MaterialTheme.typography.bodySmall,
                fontFamily = FontFamily.Monospace)
            Row {
                Checkbox(verified, { verified = it }, enabled = state.stage == "verifying",
                    modifier = Modifier.testTag("partner.verify"))
                Text(stringResource(R.string.partner_verify), modifier = Modifier.padding(top = 12.dp))
            }
            Button({ onConfirm(verified) }, enabled = verified && state.stage == "verifying",
                modifier = Modifier.testTag("partner.confirm")) { Text(stringResource(R.string.partner_confirm)) }
            if (state.stage == "confirming") Text(stringResource(R.string.partner_wait_confirmation))
            if (state.stage == "syncing") Text(stringResource(R.string.partner_finishing))
        } else {
            Button(onCreate, enabled = !busy && state.stage != "waiting",
                modifier = Modifier.testTag("partner.create")) { Text(stringResource(R.string.partner_create)) }
            state.invitation?.let { invitation ->
                Text(invitation.code, style = MaterialTheme.typography.headlineMedium,
                    fontFamily = FontFamily.Monospace, modifier = Modifier.testTag("partner.invitationCode"))
                TextButton({ clipboard.setText(AnnotatedString(invitation.code)) },
                    modifier = Modifier.testTag("partner.copy")) { Text(stringResource(R.string.partner_copy)) }
                val expires = DateTimeFormatter.ofPattern("MM-dd HH:mm").withZone(ZoneId.systemDefault())
                    .format(Instant.ofEpochMilli(invitation.expiresAt))
                Text(stringResource(R.string.partner_expiry, expires), style = MaterialTheme.typography.bodySmall)
                Text(stringResource(R.string.partner_wait_join), style = MaterialTheme.typography.bodySmall)
            }
            HorizontalDivider()
            OutlinedTextField(input, { if (it.length <= 64) input = it },
                label = { Text(stringResource(R.string.partner_code)) }, singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, keyboardType = KeyboardType.Ascii),
                enabled = !busy && state.stage != "waiting", modifier = Modifier.fillMaxWidth().testTag("partner.codeInput"))
            Button({ onJoin(input) }, enabled = !busy && state.stage != "waiting" && input.isNotBlank(),
                modifier = Modifier.testTag("partner.join")) { Text(stringResource(R.string.partner_join)) }
        }
        if (busy) LinearProgressIndicator(Modifier.fillMaxWidth())
        if (state.error == "PARTNER_SERVICE_UPGRADE_REQUIRED")
            Text(stringResource(R.string.partner_service_upgrade), color = MaterialTheme.colorScheme.error,
                modifier = Modifier.testTag("partner.serviceUnavailable"))
        else state.error?.let { Text(stringResource(errorCopy(it)), color = MaterialTheme.colorScheme.error,
            modifier = Modifier.testTag("partner.error")) }
    }
}
