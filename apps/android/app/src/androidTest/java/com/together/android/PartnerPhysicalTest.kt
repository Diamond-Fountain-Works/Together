package com.together.android

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.together.android.data.*
import com.together.android.ui.TogetherApp
import com.together.domain.*
import com.together.protocol.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import kotlinx.serialization.json.*
import org.junit.*
import org.junit.Assert.*
import java.io.File
import java.time.Instant

/** Real device UI + Room + independent Keystore, never the default workspace. */
class PartnerPhysicalTest {
    @get:Rule val compose=createAndroidComposeRule<com.together.android.qa.BusinessQaActivity>()
    private val instrumentation get()=InstrumentationRegistry.getInstrumentation()
    private val context get()=instrumentation.targetContext
    private val args get()=InstrumentationRegistry.getArguments()
    private val at=Instant.parse("2026-10-09T04:00:00Z")
    private fun directory():File {
        val id=args.getString("partnerBridgeId")
        Assume.assumeTrue("Separately authorized cross-network driver required",id!=null)
        check(id!!.matches(Regex("[A-F0-9]{32}")))
        return File(context.filesDir,"partner-bridge/$id").also{check(it.isDirectory)}
    }
    private fun read(dir:File,name:String)=Canonical.parse(File(dir,name).readBytes()).jsonObject
    private fun write(dir:File,name:String,value:JsonObject=buildJsonObject{put("status","PASS")}) {
        val atomic=android.util.AtomicFile(File(dir,name));val output=atomic.startWrite()
        try{output.write(Canonical.bytes(value));atomic.finishWrite(output)}catch(e:Exception){atomic.failWrite(output);throw e}
    }
    private suspend fun waitFor(label:String,block:()->Boolean) {
        val start=android.os.SystemClock.elapsedRealtime()
        try{withTimeout(90_000){while(!block())delay(100)}}
        finally{android.util.Log.i("TogetherPartnerQa","stage=$label elapsedMs=${android.os.SystemClock.elapsedRealtime()-start}")}
    }
    private fun capture(name:String) {
        check(name.matches(Regex("[a-z-]+")))
        compose.waitForIdle()
        val id=args.getString("partnerBridgeId")!!
        val path="/data/local/tmp/together-partner-$id-$name.png"
        val fd=instrumentation.uiAutomation.executeShellCommand("screencap -p $path")
        android.os.ParcelFileDescriptor.AutoCloseInputStream(fd).use{it.readBytes()}
    }
    @Test fun partnerInvitationUiHistoryLiveSyncMediaAndReconnect()=runBlocking {
        val dir=directory();val config=read(dir,"launch.json")
        val origin=config.getValue("base").jsonPrimitive.content
        check(origin=="https://together-pairing-staging.together-connection-service.workers.dev")
        val androidInvites=config.getValue("androidInvites").jsonPrimitive.boolean
        val namespace=uid();val scope=CoroutineScope(SupervisorJob()+Dispatchers.IO)
        val repo=TogetherRepository(context,scope,namespace,DateProvider{at},origin)
        try{
            withTimeout(15_000){repo.state.first{it.loaded}}
            assertNull(repo.state.value.error)
            val original=repo.state.value.descriptor!!
            repo.saveProfile("Synthetic QA Android","girlfriend",null)
            repo.saveTask(title="Synthetic Android before pairing")
            repo.foreground(true);repo.noteInteraction()
            compose.setContent{TogetherApp(repo)}
            if(compose.onAllNodesWithTag("navigation.open").fetchSemanticsNodes().isNotEmpty())compose.onNodeWithTag("navigation.open").performClick()
            compose.onNodeWithTag("nav.connection").performClick()
            if(androidInvites){
                compose.onNodeWithTag("partner.create").performScrollTo().performClick()
                waitFor("Android creates invitation"){repo.state.value.partnerPairing.invitation!=null}
                write(dir,"phone-invitation.json",buildJsonObject{put("code",repo.state.value.partnerPairing.invitation!!.code)})
            }else{
                waitFor("Mac invitation"){File(dir,"mac-invitation.json").isFile}
                val code=read(dir,"mac-invitation.json").getValue("code").jsonPrimitive.content
                android.util.Log.i("TogetherPartnerQa","ui=enter-partner-code")
                compose.onNodeWithTag("partner.codeInput").performScrollTo().performTextInput(code)
                android.util.Log.i("TogetherPartnerQa","ui=dismiss-keyboard")
                // Espresso's OEM IME idling path can wait on the candidate
                // window. Dismiss via the native Back key without changing
                // the user's keyboard, then click the actual Compose action.
                val dismissed=instrumentation.uiAutomation.executeShellCommand("input keyevent 111")
                android.os.ParcelFileDescriptor.AutoCloseInputStream(dismissed).use{it.readBytes()}
                android.util.Log.i("TogetherPartnerQa","ui=join-partner")
                compose.onNodeWithTag("partner.join").performScrollTo().performClick()
            }
            waitFor("same verification code"){repo.state.value.partnerPairing.stage=="verifying"}
            val proposal=repo.state.value.partnerPairing
            compose.waitUntil(10_000){compose.onAllNodesWithTag("partner.verificationCode").fetchSemanticsNodes().isNotEmpty()}
            assertNotEquals(original.userId,proposal.peer!!.descriptor.userId)
            write(dir,"phone-verification.json",buildJsonObject{put("code",proposal.verificationCode!!);put("fingerprint",proposal.peer!!.descriptor.fingerprint)})
            capture("verification-candidate")
            waitFor("driver verifies codes"){File(dir,"approved").isFile}
            assertNull(repo.state.value.authorization)
            compose.onNodeWithTag("partner.verify").performScrollTo().performClick()
            compose.onNodeWithTag("partner.confirm").performScrollTo().performClick()
            waitFor("co-signed genesis and Protocol 4"){repo.state.value.authorization!=null&&repo.state.value.connection=="connected"&&repo.state.value.historyReady}
            assertEquals(original,repo.state.value.descriptor)
            assertEquals(2,repo.state.value.authorization!!.members.size)
            assertTrue(repo.state.value.snapshot.of("task").any{it.fields.text("title")=="Synthetic Mac before pairing"})
            capture("connected-candidate")
            waitFor("Mac business"){File(dir,"mac-created.json").isFile}
            val native=read(dir,"mac-created.json");val grant=native.getValue("grant").jsonPrimitive.content;val nativeGift=native.getValue("gift").jsonPrimitive.content
            waitFor("Mac operations"){repo.state.value.snapshot.entities[grant]!=null&&repo.state.value.snapshot.gifts[nativeGift]!=null}
            assertNotNull(repo.state.value.snapshot.entities[native.getValue("deleted").jsonPrimitive.content]?.deletedAt)
            repo.execute{
                task(null,"Synthetic Android live task","",null,null,null)+listOf(
                    wish(grant,"Synthetic cross-network wish",""),
                    expense(null,"Synthetic AA",Amount.create("9.99"),Payment("equalSplit",context.members.toList()),CivilDate(2026,10,9),"food","",null),
                    expense(null,"Synthetic shared",Amount.create("12.34"),Payment("reserves",emptyList()),CivilDate(2026,10,9),"food","",null))
            }
            val task=repo.state.value.snapshot.of("task").single{it.fields.text("title")=="Synthetic Android live task"}.id
            val wish=repo.state.value.snapshot.wishes.values.single{it.title=="Synthetic cross-network wish"}.id
            val photo=repo.importOwnedMedia(File(dir,"synthetic.png").copyTo(File(context.cacheDir,"partner-$namespace.png")),"photo")
            val audio=repo.importOwnedMedia(File(dir,"synthetic.wav").copyTo(File(context.cacheDir,"partner-$namespace.wav")),"audio")
            repo.sendGift(GiftDraft("Synthetic Android sealed gift",audio.assetId,photo.assetId))
            val gift=repo.state.value.snapshot.gifts.values.single{it.entity.fields.id("senderId")==original.userId}.id
            write(dir,"phone-created.json",buildJsonObject{put("device",original.json());put("task",task);put("wish",wish);put("gift",gift)})
            waitFor("wish request"){repo.state.value.snapshot.wishes[wish]?.status=="completionRequested"}
            repo.execute{listOf(wishAction(wish,"confirmFulfillment"))}
            waitFor("signed persistence and verified originals"){
                val s=repo.state.value;gift in s.giftSynced&&s.snapshot.gifts[nativeGift]?.let{giftAssets(it).all{id->s.snapshot.entities[id]?.let(Asset::from)?.let(repo.mediaFiles::verified)==true}}==true&&s.operationStates.values.any{it=="converged"}
            }
            val stats=FinanceProjection.statistics(repo.state.value.snapshot)
            assertEquals(1967,stats.bookBalance);assertEquals(999,stats.personal.values.sum());assertEquals(2,repo.state.value.snapshot.remaining(grant))
            assertEquals(1,repo.state.value.snapshot.of("expense").count{it.fields.id("billId")!=null})
            val reviewed=repo.state.value.snapshot.changes.map{it.operationId}.toSet();repo.markReviewed(reviewed);repo.markNotified(reviewed)
            repo.foreground(false);waitFor("foreground disconnect"){repo.state.value.connection=="offline"}
            repo.localWrite(task,"task","patch",mapOf("notes" to LogValue.string("Synthetic Android offline notes")))
            write(dir,"phone-offline.json")
            waitFor("Mac offline writes"){File(dir,"mac-offline-written").isFile}
            repeat(6){repo.foreground(true);repo.reconnect();delay(20)}
            waitFor("catch-up after repeated connect"){
                val s=repo.state.value;s.connection=="connected"&&s.snapshot.entities[task]?.fields?.text("title")=="Synthetic Mac offline title"&&s.snapshot.of("task").any{it.fields.text("title")=="Synthetic Mac catch-up"}
            }
            write(dir,"phone-reconnected.json",buildJsonObject{put("namespace",namespace);put("descriptor",original.json());put("space",repo.state.value.authorization!!.spaceId);put("reviewed",buildJsonArray{reviewed.sorted().forEach{add(it)}})})
            waitFor("Mac checkpoint"){File(dir,"mac-checkpoint.json").isFile}
            val db=TogetherDatabase.open(context,"qa-$namespace-together-local.db")
            try{val store=RoomReplicaStore(db);val id=AndroidIdentityStore(context,namespace).load("LOCAL");val trust=SpaceAuthorization.restore(Canonical.parse(store.local("authorization")!!).model());val replica=Replica(store,id,trust).also{it.restore()};assertEquals(read(dir,"mac-checkpoint.json").model<Checkpoint>(),replica.inventoryCheckpoint())}finally{db.close()}
        }finally{
            write(dir,"phone-diagnostic.json",buildJsonObject{put("connection",repo.state.value.connection);put("pairing",repo.state.value.partnerPairing.stage);put("error",repo.state.value.partnerPairing.error?:repo.state.value.error?:repo.state.value.connectionError?:"");put("diagnostic",repo.state.value.partnerPairing.diagnostic?:"")})
            repo.close();scope.cancel()
        }
    }
    @Test fun pairedPartnerIdentityAndHistorySurviveActualProcessRestart()=runBlocking {
        val dir=directory();val plan=read(dir,"phone-reconnected.json");val namespace=plan.getValue("namespace").jsonPrimitive.content
        val scope=CoroutineScope(SupervisorJob()+Dispatchers.IO)
        val repo=TogetherRepository(context,scope,namespace,DateProvider{at},read(dir,"launch.json").getValue("base").jsonPrimitive.content)
        try{
            withTimeout(15_000){repo.state.first{it.loaded}}
            assertNull(repo.state.value.error);assertEquals(plan.getValue("descriptor").model<DeviceDescriptor>(),repo.state.value.descriptor)
            assertEquals(plan.getValue("space").jsonPrimitive.content,repo.state.value.authorization!!.spaceId)
            assertTrue(repo.state.value.reviewed.containsAll(plan.getValue("reviewed").jsonArray.map{it.jsonPrimitive.content}))
            repo.foreground(true);waitFor("WSS after force-stop"){repo.state.value.connection=="connected"}
            compose.setContent{TogetherApp(repo)};capture("restarted-candidate")
            assertTrue(repo.state.value.snapshot.of("mediaAsset").map(Asset::from).all{repo.mediaFiles.verified(it)&&MediaFiles.digest(repo.mediaFiles.original(it))==it.sha256})
            write(dir,"phone-restarted.json")
        }finally{repo.close();scope.cancel()}
    }
}
