package com.together.android.ui

import android.Manifest
import android.media.MediaPlayer
import android.media.MediaRecorder
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.*
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Favorite
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.*
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.*
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.*
import androidx.lifecycle.*
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.together.android.R
import com.together.android.data.*
import com.together.domain.*
import com.together.protocol.*
import java.io.File
import java.time.*
import kotlinx.coroutines.*

@Composable
internal fun AssetPreview(asset: Asset, repository: TogetherRepository, avatar: Boolean = false) {
    var bitmap by remember(asset.sha256) { mutableStateOf<android.graphics.Bitmap?>(null) }
    LaunchedEffect(asset.sha256) {
        bitmap =
            withContext(Dispatchers.IO) {
                runCatching {
                        android.graphics.BitmapFactory.decodeFile(
                            AndroidMedia.preview(repository.mediaFiles, asset).absolutePath
                        )
                    }
                    .getOrNull()
            }
    }
    bitmap?.let {
        Image(
            it.asImageBitmap(),
            contentDescription =
                stringResource(if (avatar) R.string.label_avatar else R.string.label_photo),
            contentScale = if (avatar) ContentScale.Crop else ContentScale.Fit,
            modifier =
                if (avatar) Modifier.size(64.dp).clip(CircleShape)
                else Modifier.fillMaxWidth().heightIn(max = 360.dp),
        )
    }
}

@Composable
internal fun ProfileAvatar(
    user: String,
    state: TogetherRepository.State,
    repository: TogetherRepository,
) {
    val profile = state.snapshot.entities[user]
    val asset =
        profile?.fields?.id("avatarAssetId")?.let { state.snapshot.entities[it]?.let(Asset::from) }
    if (asset != null && repository.mediaFiles.verified(asset)) {
        AssetPreview(asset, repository, true)
        return
    }
    // Protocol 3 cached thumbnails are bounded by the legacy domain validator.
    val legacy = profile?.fields?.get("avatarData")?.let(LogValue::bytes)
    var bitmap by remember { mutableStateOf<android.graphics.Bitmap?>(null) }
    LaunchedEffect(profile?.fields?.get("avatarData")) {
        bitmap = withContext(Dispatchers.IO) { legacy?.let(AndroidMedia::legacyAvatar) }
    }
    val renderedBitmap = bitmap
    if (renderedBitmap != null)
        Image(
            renderedBitmap.asImageBitmap(),
            stringResource(R.string.label_avatar),
            contentScale = ContentScale.Crop,
            modifier = Modifier.size(64.dp).clip(CircleShape),
        )
    else
        Surface(
            shape = CircleShape,
            color = MaterialTheme.colorScheme.secondaryContainer,
            modifier = Modifier.size(64.dp),
        ) {
            Box(contentAlignment = Alignment.Center) {
                Icon(
                    Icons.Outlined.Person,
                    stringResource(R.string.label_avatar),
                    tint = MaterialTheme.colorScheme.onSecondaryContainer,
                )
            }
        }
}

@Composable
internal fun AudioPlayer(file: File, onError: (String) -> Unit) {
    var player by remember(file.absolutePath) { mutableStateOf<MediaPlayer?>(null) }
    var ready by remember { mutableStateOf(false) }
    var playing by remember { mutableStateOf(false) }
    var position by remember { mutableIntStateOf(0) }
    var duration by remember { mutableIntStateOf(0) }
    val owner = LocalLifecycleOwner.current
    DisposableEffect(file.absolutePath, owner) {
        ready = false
        playing = false
        position = 0
        duration = 0
        val p = MediaPlayer()
        player = p
        p.setOnPreparedListener {
            ready = true
            duration = it.duration
        }
        p.setOnCompletionListener {
            playing = false
            position = duration
        }
        p.setOnErrorListener { _, _, _ ->
            ready = false
            playing = false
            onError("UNSUPPORTED_MEDIA")
            true
        }
        try {
            p.setDataSource(file.absolutePath)
            p.prepareAsync()
        } catch (e: Exception) {
            onError("UNSUPPORTED_MEDIA")
        }
        val observer = LifecycleEventObserver { _, event ->
            if (
                event == Lifecycle.Event.ON_STOP &&
                    ready &&
                    runCatching { p.isPlaying }.getOrDefault(false)
            ) {
                runCatching { p.pause() }
                playing = false
            }
        }
        owner.lifecycle.addObserver(observer)
        onDispose {
            owner.lifecycle.removeObserver(observer)
            p.release()
            player = null
        }
    }
    LaunchedEffect(playing) {
        while (playing) {
            delay(250)
            position = runCatching { player?.currentPosition ?: 0 }.getOrDefault(0)
        }
    }
    Column {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Button(
                enabled = ready,
                onClick = {
                    player?.let {
                        if (playing) it.pause() else it.start()
                        playing = !playing
                    }
                },
                modifier = Modifier.testTag("audio.play"),
            ) {
                Text(stringResource(if (playing) R.string.action_pause else R.string.action_play))
            }
            Text(audioTime(position) + " / " + audioTime(duration), Modifier.padding(start = 12.dp))
        }
        Slider(
            value = position.toFloat().coerceIn(0f, maxOf(duration, 1).toFloat()),
            onValueChange = {
                position = it.toInt()
                player?.seekTo(position)
            },
            enabled = ready,
            valueRange = 0f..maxOf(duration, 1).toFloat(),
        )
    }
}

private fun audioTime(ms: Int) =
    java.lang.String.format(java.util.Locale.ROOT, "%d:%02d", ms / 60000, ms / 1000 % 60)

@Suppress("DEPRECATION")
private class Recorder(private val context: android.content.Context) {
    var recorder: MediaRecorder? = null
    var file: File? = null

    fun start() {
        val f = File(context.cacheDir, "record-${uid()}.m4a")
        val r = MediaRecorder()
        try {
            r.setAudioSource(MediaRecorder.AudioSource.MIC)
            r.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
            r.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
            r.setOutputFile(f.absolutePath)
            r.prepare()
            r.start()
            recorder = r
            file = f
        } catch (e: Exception) {
            r.release()
            f.delete()
            throw e
        }
    }

    fun stop(): File {
        val r = recorder ?: throw ProtocolException("RECORDING_NOT_STARTED")
        try {
            r.stop()
            return file!!
        } finally {
            r.release()
            recorder = null
        }
    }

    fun dispose() {
        recorder?.let {
            runCatching { it.stop() }
            it.release()
        }
        recorder = null
    }
}

@Composable
internal fun GiftEditor(
    state: TogetherRepository.State,
    repository: TogetherRepository,
    onClose: () -> Unit,
    onError: (String) -> Unit,
    reply: String? = null,
) {
    var text by rememberSaveable { mutableStateOf(state.draft.text) }
    var photo by rememberSaveable { mutableStateOf(state.draft.photoAssetId) }
    var audio by rememberSaveable { mutableStateOf(state.draft.audioAssetId) }
    var sent by remember { mutableStateOf(false) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val recorder = remember { Recorder(context) }
    var recording by remember { mutableStateOf(false) }
    var paused by remember { mutableStateOf(false) }
    fun draft() = GiftDraft(text, audio, photo, reply ?: state.draft.replyToGiftId)
    fun run(block: suspend () -> Unit) {
        scope.launch {
            try {
                block()
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                onError((e as? ProtocolException)?.code ?: "MEDIA_IO_ERROR")
            }
        }
    }
    fun stop() {
        if (!recording) return
        recording = false
        run {
            val file = recorder.stop()
            try {
                val a = repository.importRecorded(file)
                audio = a.assetId
                repository.saveDraft(draft())
            } finally {
                file.delete()
            }
        }
    }
    val latestStop by rememberUpdatedState(newValue = { stop() })
    val lifecycle = LocalLifecycleOwner.current
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) latestStop()
        }
        lifecycle.lifecycle.addObserver(observer)
        onDispose {
            lifecycle.lifecycle.removeObserver(observer)
            recorder.dispose()
        }
    }
    val permission =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { allowed ->
            if (allowed) {
                try {
                    recorder.start()
                    recording = true
                    paused = false
                } catch (e: Exception) {
                    onError("MICROPHONE_UNAVAILABLE")
                }
            } else onError("MICROPHONE_DENIED")
        }
    val photoPicker =
        rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            if (uri != null)
                run {
                    photo = repository.importMedia(uri, "photo").assetId
                    repository.saveDraft(draft())
                }
        }
    val audioPicker =
        rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            if (uri != null)
                run {
                    audio = repository.importMedia(uri, "audio").assetId
                    repository.saveDraft(draft())
                }
        }
    val me = state.descriptor!!.userId
    val zone =
        state.authorization?.archive?.genesis?.body?.sharedTimeZoneIdentifier
            ?: ZoneId.systemDefault().id
    val used = state.snapshot.giftUsed(me, dayKey(state.now, zone))
    val partner = members(state).firstOrNull { it != me }
    LaunchedEffect(text, audio, photo) {
        delay(350)
        runCatching { repository.saveDraft(draft()) }
    }
    fun close() {
        if (sent) {
            onClose()
            return
        }
        if (recording) stop()
        run {
            repository.saveDraft(draft())
            onClose()
        }
    }
    FormSheet(
        R.string.action_send_gift,
        ::close,
        "gift.editor",
        onSave = {
            repository.sendGift(draft())
            sent = true
        },
        onError = onError,
        enabled =
            partner != null &&
                !used &&
                !recording &&
                (text.isNotBlank() || photo != null || audio != null),
        saveLabel = R.string.action_send_with_love,
    ) {
        val relation =
            Relationship.parse(
                partner?.let { state.snapshot.entities[it]?.fields?.text("relationshipLabel") }
            )
        Text(
            stringResource(
                when (relation) {
                    Relationship.BOYFRIEND -> R.string.gift_prompt_boy
                    Relationship.GIRLFRIEND -> R.string.gift_prompt_girl
                    else -> R.string.gift_prompt_unknown
                }
            )
        )
        if (used) Text(stringResource(R.string.gift_quota_used))
        if (partner == null) Text(stringResource(R.string.guidance_partner_needed))
        OutlinedTextField(
            value = text,
            onValueChange = { text = it },
            placeholder = { Text(stringResource(R.string.gift_input_hint)) },
            modifier = Modifier.fillMaxWidth().testTag("gift.text"),
            minLines = 4,
            maxLines = 10,
            isError = text.graphemeCount() > 4000 || text.toByteArray().size > 16000,
        )
        Row {
            OutlinedButton(
                onClick = { photoPicker.launch(arrayOf("image/*")) },
                enabled = !recording,
            ) {
                Text(stringResource(R.string.action_add_photo))
            }
            TextButton(onClick = { audioPicker.launch(arrayOf("audio/*")) }, enabled = !recording) {
                Text(stringResource(R.string.action_import_audio))
            }
        }
        if (!recording)
            OutlinedButton(onClick = { permission.launch(Manifest.permission.RECORD_AUDIO) }) {
                Text(stringResource(R.string.action_record_audio))
            }
        else
            Row {
                Button(onClick = { stop() }) {
                    Text(stringResource(R.string.action_stop_recording))
                }
                TextButton(
                    onClick = {
                        try {
                            if (paused) recorder.recorder?.resume() else recorder.recorder?.pause()
                            paused = !paused
                        } catch (e: Exception) {
                            onError("MICROPHONE_UNAVAILABLE")
                        }
                    }
                ) {
                    Text(
                        stringResource(
                            if (paused) R.string.action_resume else R.string.action_pause
                        )
                    )
                }
            }
        photo?.let { id ->
            (state.staged[id] ?: state.snapshot.entities[id]?.let(Asset::from))?.let { asset ->
                AssetPreview(asset, repository)
                Text(
                    stringResource(R.string.guidance_photo_metadata),
                    style = MaterialTheme.typography.bodySmall,
                )
                TextButton(onClick = { photo = null }) {
                    Text(stringResource(R.string.action_remove_photo))
                }
            }
        }
        audio?.let { id ->
            (state.staged[id] ?: state.snapshot.entities[id]?.let(Asset::from))?.let { asset ->
                AudioPlayer(repository.mediaFiles.original(asset), onError)
                TextButton(onClick = { audio = null }) {
                    Text(stringResource(R.string.action_remove_audio))
                }
            }
        }
    }
}

@Composable
internal fun GiftHistory(
    state: TogetherRepository.State,
    onClose: () -> Unit,
    onOpen: (String) -> Unit,
    onDelete: (String) -> Unit,
) {
    FormSheet(R.string.action_gift_history, onClose, "gift.history") {
        val gifts =
            state.snapshot.gifts.values
                .filter { it.effective && it.entity.deletedAt == null }
                .sortedByDescending { it.entity.fields.date("sentAt") }
        if (gifts.isEmpty()) Text(stringResource(R.string.empty_gifts))
        gifts.forEach { gift ->
            OutlinedCard(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        memberName(state, gift.entity.fields.id("senderId")!!),
                        style = MaterialTheme.typography.titleMedium,
                    )
                    Text(
                        Instant.ofEpochMilli(gift.entity.fields.date("sentAt")!!)
                            .atZone(ZoneId.systemDefault())
                            .toLocalDateTime()
                            .toString()
                    )
                    if (gift.entity.fields.id("senderId") == state.descriptor!!.userId)
                        Text(
                            stringResource(
                                if (gift.id in state.giftSynced) R.string.status_gift_synced
                                else R.string.status_pending_sync
                            )
                        )
                    else
                        Text(
                            stringResource(
                                if (state.presentations[gift.id]?.openedAt == null)
                                    R.string.status_unopened
                                else R.string.status_opened
                            )
                        )
                    Row {
                        TextButton(
                            onClick = { onOpen(gift.id) },
                            modifier = Modifier.testTag("gift.history.open.${gift.id}"),
                        ) {
                            Text(stringResource(R.string.action_view_gift))
                        }
                        if (gift.entity.fields.id("senderId") == state.descriptor.userId)
                            TextButton(onClick = { onDelete(gift.id) }) {
                                Text(stringResource(R.string.action_delete))
                            }
                    }
                }
            }
        }
    }
}

@Composable
internal fun GiftReveal(
    id: String,
    automatic: Boolean,
    state: TogetherRepository.State,
    repository: TogetherRepository,
    onClose: () -> Unit,
    onReply: (String) -> Unit,
    onError: (String) -> Unit,
) {
    val gift =
        state.snapshot.gifts[id]?.takeIf { it.effective && it.entity.deletedAt == null } ?: return
    val own = gift.entity.fields.id("senderId") == state.descriptor!!.userId
    var opened by rememberSaveable(id) { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val sender = gift.entity.fields.id("senderId")!!
    val label =
        Relationship.parse(state.snapshot.entities[sender]?.fields?.text("relationshipLabel"))
    val hasText = !gift.entity.fields.text("textContent").isNullOrBlank()
    val title =
        if (own) R.string.label_sent_gift
        else
            when (label) {
                Relationship.BOYFRIEND ->
                    if (hasText) R.string.gift_title_boy_text else R.string.gift_title_boy_media
                Relationship.GIRLFRIEND ->
                    if (hasText) R.string.gift_title_girl_text else R.string.gift_title_girl_media
                else ->
                    if (hasText) R.string.gift_title_unknown_text
                    else R.string.gift_title_unknown_media
            }
    fun run(block: suspend () -> Unit) {
        scope.launch {
            try {
                block()
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                onError((e as? ProtocolException)?.code ?: "MEDIA_IO_ERROR")
            }
        }
    }
    LaunchedEffect(id) {
        withFrameNanos {}
        if (!own)
            runCatching { repository.presentedGift(id, automatic) }
                .onFailure {
                    onError("INVALID_GIFT")
                    onClose()
                }
    }
    val photo =
        gift.entity.fields.id("photoAssetId")?.let { state.snapshot.entities[it]?.let(Asset::from) }
    val save =
        rememberLauncherForActivityResult(
            ActivityResultContracts.CreateDocument(
                photo?.let {
                    android.webkit.MimeTypeMap.getSingleton()
                        .getMimeTypeFromExtension(it.fileExtension)
                } ?: "application/octet-stream"
            )
        ) { uri ->
            if (uri != null && photo != null)
                run {
                    withContext(Dispatchers.IO) {
                        var name = ""
                        context.contentResolver
                            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                            ?.use { if (it.moveToFirst()) name = it.getString(0).orEmpty() }
                        requireProtocol(
                            name.endsWith("." + photo.fileExtension, true),
                            "EXPORT_FORMAT_MISMATCH",
                        )
                        val out =
                            context.contentResolver.openOutputStream(uri, "w")
                                ?: throw ProtocolException("MEDIA_IO_ERROR")
                        repository.mediaFiles.export(photo, out)
                    }
                }
        }
    Dialog(
        onDismissRequest = onClose,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Surface(
            shape = MaterialTheme.shapes.large,
            modifier =
                Modifier.widthIn(max = 720.dp)
                    .fillMaxWidth(.96f)
                    .fillMaxHeight(.92f)
                    .testTag("gift.reveal"),
        ) {
            Column(
                Modifier.padding(24.dp).animateContentSize(),
                verticalArrangement = Arrangement.spacedBy(20.dp),
            ) {
                Column(
                    Modifier.weight(1f).verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(20.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    if (!opened) {
                        Spacer(Modifier.height(40.dp))
                        Icon(
                            Icons.Outlined.Favorite,
                            stringResource(R.string.label_sealed_gift),
                            tint = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.size(96.dp),
                        )
                        Text(
                            stringResource(R.string.gift_sealed_title),
                            style = MaterialTheme.typography.headlineMedium,
                        )
                        Text(memberName(state, sender))
                    } else {
                        Text(stringResource(title), style = MaterialTheme.typography.headlineSmall)
                        ProfileAvatar(sender, state, repository)
                        Text(memberName(state, sender))
                        Text(
                            Instant.ofEpochMilli(gift.entity.fields.date("sentAt")!!)
                                .atZone(ZoneId.systemDefault())
                                .toLocalDateTime()
                                .toString(),
                            style = MaterialTheme.typography.labelMedium,
                        )
                        // Private content and its semantics are constructed only after explicit
                        // Open.
                        if (hasText)
                            Text(
                                gift.entity.fields.text("textContent").orEmpty(),
                                style = MaterialTheme.typography.bodyLarge,
                                modifier = Modifier.testTag("gift.privateText"),
                            )
                        gift.entity.fields
                            .id("audioAssetId")
                            ?.let { state.snapshot.entities[it]?.let(Asset::from) }
                            ?.let { asset ->
                                if (repository.mediaFiles.verified(asset))
                                    AudioPlayer(repository.mediaFiles.original(asset), onError)
                                else Text(stringResource(R.string.status_media_pending))
                            }
                        photo?.let { asset ->
                            if (repository.mediaFiles.verified(asset)) {
                                AssetPreview(asset, repository)
                                OutlinedButton(
                                    onClick = {
                                        val name =
                                            asset.originalFilename
                                                .substringAfterLast('/')
                                                .substringAfterLast('\\')
                                                .substringBeforeLast('.') +
                                                "." +
                                                asset.fileExtension
                                        save.launch(name)
                                    },
                                    modifier = Modifier.testTag("gift.savePhoto"),
                                ) {
                                    Text(stringResource(R.string.action_save_photo))
                                }
                            } else Text(stringResource(R.string.status_media_pending))
                        }
                        if (!own)
                            Text(
                                stringResource(
                                    when (label) {
                                        Relationship.BOYFRIEND -> R.string.gift_ending_boy
                                        Relationship.GIRLFRIEND -> R.string.gift_ending_girl
                                        else -> R.string.gift_ending_unknown
                                    }
                                ),
                                color = MaterialTheme.colorScheme.primary,
                                style = MaterialTheme.typography.bodyMedium,
                            )
                    }
                }
                Row(
                    Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.End,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (opened && !own)
                        TextButton(onClick = { onReply(id) }) {
                            Text(stringResource(R.string.action_reply_love))
                        }
                    if (!opened) {
                        TextButton(onClick = onClose) {
                            Text(stringResource(R.string.action_close))
                        }
                        Button(
                            onClick = {
                                run {
                                    repository.openedGift(id)
                                    opened = true
                                }
                            },
                            modifier = Modifier.testTag("gift.open"),
                        ) {
                            Text(stringResource(R.string.action_open_gift))
                        }
                    } else
                        Button(onClick = onClose, modifier = Modifier.testTag("gift.received")) {
                            Text(stringResource(R.string.action_gift_received))
                        }
                }
            }
        }
    }
}

@Composable
internal fun ProfileForm(
    state: TogetherRepository.State,
    repository: TogetherRepository,
    onClose: () -> Unit,
    onError: (String) -> Unit,
) {
    val profile = remember { state.snapshot.entities[state.descriptor!!.userId] }
    var name by rememberSaveable { mutableStateOf(profile?.fields?.text("displayName").orEmpty()) }
    var role by rememberSaveable {
        mutableStateOf(profile?.fields?.text("relationshipLabel") ?: "unknown")
    }
    var avatar by rememberSaveable { mutableStateOf(profile?.fields?.id("avatarAssetId")) }
    var clearLegacy by rememberSaveable { mutableStateOf(false) }
    val scope = rememberCoroutineScope()
    val picker =
        rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            if (uri != null)
                scope.launch {
                    try {
                        avatar = repository.importMedia(uri, "avatar").assetId
                    } catch (e: Exception) {
                        onError((e as? ProtocolException)?.code ?: "MEDIA_IO_ERROR")
                    }
                }
        }
    FormSheet(
        R.string.label_profile,
        onClose,
        "profile.editor",
        onSave = { repository.saveProfile(name, role, avatar, profile, clearLegacy) },
        onError = onError,
        enabled = name.isNotBlank() && name.graphemeCount() <= 80,
    ) {
        Input(name, { name = it }, R.string.label_nickname, "profile.name")
        Choice(
            R.string.label_relationship,
            role,
            listOf(
                "boyfriend" to stringResource(R.string.role_boyfriend),
                "girlfriend" to stringResource(R.string.role_girlfriend),
                "unknown" to stringResource(R.string.role_unknown),
            ),
            { role = it },
        )
        avatar?.let { id ->
            (state.staged[id] ?: state.snapshot.entities[id]?.let(Asset::from))?.let {
                AssetPreview(it, repository, true)
            }
        }
        if (avatar == null && !clearLegacy)
            ProfileAvatar(state.descriptor!!.userId, state, repository)
        OutlinedButton(onClick = { picker.launch(arrayOf("image/*")) }) {
            Text(stringResource(R.string.action_choose_avatar))
        }
        if (
            avatar != null ||
                (!clearLegacy && LogValue.bytes(profile?.fields?.get("avatarData")) != null)
        )
            TextButton(
                onClick = {
                    avatar = null
                    clearLegacy = true
                }
            ) {
                Text(stringResource(R.string.action_remove_photo))
            }
        Text(
            stringResource(R.string.guidance_photo_metadata),
            style = MaterialTheme.typography.bodySmall,
        )
    }
}
