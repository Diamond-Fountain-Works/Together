package com.together.android.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.together.android.R
import com.together.android.data.NativeAppStatus

/** Native pairing in the existing App workspace, with no second business store. */
@Composable
internal fun NativePartnerPanel(state: NativeAppStatus, paired: Boolean, onCreate: () -> Unit,
    onJoin: (String) -> Unit, onConfirm: (Boolean) -> Unit, onOffline: (Boolean) -> Unit,
    onCancel: () -> Unit) {
    var input by rememberSaveable { mutableStateOf("") }
    var checked by rememberSaveable { mutableStateOf(false) }
    val clipboard = LocalClipboardManager.current
    LaunchedEffect(state.verificationCode) { checked = false }
    Column(Modifier.fillMaxWidth().padding(24.dp).testTag("native.pairing"),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(stringResource(R.string.partner_title), style = MaterialTheme.typography.titleLarge)
        if (!paired) {
            val code = state.verificationCode
            if (code != null && state.peer != null) {
                Text(state.peerDisplayName ?: state.peer.displayName, style = MaterialTheme.typography.titleMedium)
                Text(code, style = MaterialTheme.typography.headlineLarge, fontFamily = FontFamily.Monospace,
                    modifier = Modifier.testTag("partner.verificationCode"))
                SelectionContainer { Text(state.peer.fingerprint, style = MaterialTheme.typography.bodySmall,
                    fontFamily = FontFamily.Monospace) }
                Row {
                    Checkbox(checked, { checked = it }, enabled = state.stage == "verifying",
                        modifier = Modifier.testTag("partner.verify"))
                    Text(stringResource(R.string.partner_verify), Modifier.weight(1f).padding(top = 12.dp))
                }
                Button({ onConfirm(checked) }, enabled = checked && state.stage == "verifying",
                    modifier = Modifier.testTag("partner.confirm")) { Text(stringResource(R.string.partner_confirm)) }
                if (state.stage == "confirming") Text(stringResource(R.string.partner_wait_confirmation))
            } else {
                val busy = state.stage in setOf("creating", "connecting", "authenticating", "syncing", "waiting")
                Button(onCreate, enabled = !busy && !state.offline,
                    modifier = Modifier.testTag("partner.create")) { Text(stringResource(R.string.partner_create)) }
                state.invitation?.let { invitation ->
                    OutlinedTextField(invitation, {}, readOnly = true, maxLines = 5,
                        label = { Text(stringResource(R.string.partner_code)) },
                        modifier = Modifier.fillMaxWidth().testTag("partner.invitationCode"))
                    TextButton({ clipboard.setText(AnnotatedString(invitation)) },
                        modifier = Modifier.testTag("partner.copy")) { Text(stringResource(R.string.partner_copy)) }
                    if (state.stage == "waiting") TextButton(onCancel,
                        modifier = Modifier.testTag("partner.cancel")) { Text(stringResource(R.string.action_cancel)) }
                    Text(stringResource(R.string.partner_wait_join), style = MaterialTheme.typography.bodySmall)
                }
                HorizontalDivider()
                OutlinedTextField(input, { if (it.toByteArray().size <= 32_768) input = it },
                    label = { Text(stringResource(R.string.partner_code)) }, minLines = 3, maxLines = 7,
                    modifier = Modifier.fillMaxWidth().testTag("partner.codeInput"), enabled = !busy && !state.offline)
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    TextButton({ clipboard.getText()?.text?.takeIf { it.toByteArray().size <= 32_768 }?.let { input = it } },
                        enabled = !busy && !state.offline, modifier = Modifier.testTag("partner.paste")) {
                        Text(stringResource(R.string.native_paste_invitation))
                    }
                    Button({ onJoin(input) }, enabled = input.isNotBlank() && !busy && !state.offline,
                        modifier = Modifier.testTag("partner.join")) { Text(stringResource(R.string.partner_join)) }
                }
            }
        }
        if (state.stage in setOf("creating", "connecting", "authenticating", "syncing"))
            LinearProgressIndicator(Modifier.fillMaxWidth())
        state.path?.let { path ->
            Text(stringResource(if (path == "direct") R.string.native_path_direct else R.string.native_path_relay),
                style = MaterialTheme.typography.bodySmall, modifier = Modifier.testTag("native.path"))
        }
        Row {
            Text(stringResource(R.string.native_work_offline), modifier = Modifier.weight(1f).padding(top = 12.dp))
            Switch(state.offline, onOffline, modifier = Modifier.testTag("native.offline"))
        }
    }
}
