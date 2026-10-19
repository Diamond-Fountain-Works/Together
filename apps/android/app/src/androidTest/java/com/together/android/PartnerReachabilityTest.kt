package com.together.android

import androidx.test.platform.app.InstrumentationRegistry
import com.together.protocol.*
import kotlinx.serialization.json.*
import okhttp3.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Proxy
import java.util.concurrent.TimeUnit

/** Read-only health probes. No identity, pairing, business payload or TLS bypass. */
class PartnerReachabilityTest {
    @Test fun recordDirectHttpsStagesAndAddressFamilies() {
        val id=InstrumentationRegistry.getArguments().getString("probeRunId")
        assumeTrue("Separately orchestrated reachability diagnostics",id!=null)
        require(id!!.matches(Regex("[A-F0-9]{32}")))
        val results=mutableListOf<JsonObject>()
        for((label,url) in listOf("staging" to "https://together-pairing-staging.together-connection-service.workers.dev/health",
            "production-health-only" to "https://together-connection.together-connection-service.workers.dev/health",
            "https-control" to "https://www.apple.com/library/test/success.html", "domestic-https-control" to "https://www.baidu.com")){
            for(family in if(label=="staging")listOf("default","ipv4","ipv6")else listOf("default")){
                val stages=mutableListOf<String>();val start=android.os.SystemClock.elapsedRealtime()
                val client=OkHttpClient.Builder().followRedirects(false).proxy(Proxy.NO_PROXY)
                    .callTimeout(10,TimeUnit.SECONDS).connectTimeout(5,TimeUnit.SECONDS).readTimeout(5,TimeUnit.SECONDS)
                    .dns(object:Dns { override fun lookup(hostname:String):List<InetAddress> = Dns.SYSTEM.lookup(hostname).filter { family=="default"||(family=="ipv4"&&it is Inet4Address)||(family=="ipv6"&&it is Inet6Address) } })
                    .eventListener(object:EventListener(){
                        override fun dnsStart(call:Call,domainName:String){stages.add("dns")}
                        override fun connectStart(call:Call,inetSocketAddress:InetSocketAddress,proxy:Proxy){stages.add("connect-"+if(inetSocketAddress.address is Inet6Address)"v6"else"v4")}
                        override fun secureConnectStart(call:Call){stages.add("tls")}
                        override fun responseHeadersStart(call:Call){stages.add("response")}
                    }).build()
                var status:Int?=null;var error:String?=null
                try{client.newCall(Request.Builder().url(url).build()).execute().use{status=it.code}}
                catch(e:Exception){error=generateSequence<Throwable>(e){it.cause}.take(4).joinToString("/"){it.javaClass.simpleName}}
                finally{client.connectionPool.evictAll();client.dispatcher.executorService.shutdown()}
                results.add(buildJsonObject{put("target",label);put("family",family);status?.let{put("httpStatus",it)};error?.let{put("errorClasses",it)};put("elapsedMs",android.os.SystemClock.elapsedRealtime()-start);put("stages",buildJsonArray{stages.forEach{add(it)}})})
            }
        }
        val file=File(InstrumentationRegistry.getInstrumentation().targetContext.filesDir,"partner-reachability-$id.json")
        file.writeBytes(Canonical.bytes(buildJsonObject{put("diagnosticOnly",true);put("results",JsonArray(results))}))
    }
}
