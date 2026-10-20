package com.together.android.p2p

import android.content.Context
import android.net.ConnectivityManager
import android.net.LinkAddress
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import com.together.protocol.*
import kotlinx.serialization.json.*
import java.net.Inet6Address
import java.net.InetAddress

/**
 * Test-process routing only. Never requests a network, changes a radio/default/VPN, adopts
 * shell permissions, or changes another process. A missing/inaccessible local network fails closed.
 */
class QaNetworkScope(context: Context, val scope: String, bindAddress: String?) {
    private val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val prior = cm.boundNetworkForProcess
    private val mobile = cm.activeNetwork ?: throw ProtocolException("QA_MOBILE_DEFAULT_REQUIRED")
    private val bindIp = bindAddress?.let(::ipv6SocketAddress)
    private var selected: Network? = null
    private var selectedAddress: LinkAddress? = null
    private var attempted = false

    init {
        requireProtocol(scope in setOf("independent-public", "shared-hotspot", "shared-uplink-public-relay"), "QA_INVALID_NETWORK_SCOPE")
        requireProtocol(prior == null, "QA_UNEXPECTED_PRIOR_PROCESS_BINDING")
        checkMobile()
    }

    private fun checkMobile() {
        val caps = cm.getNetworkCapabilities(mobile) ?: throw ProtocolException("QA_MOBILE_DISCONNECTED")
        requireProtocol(caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) &&
            !caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
            !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN) &&
            caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET), "PUBLIC_CELLULAR_WITHOUT_VPN_REQUIRED")
        requireProtocol(cm.allNetworks.none { cm.getNetworkCapabilities(it)?.hasTransport(NetworkCapabilities.TRANSPORT_VPN) == true }, "QA_ACTIVE_VPN_REJECTED")
        requireProtocol(cm.allNetworks.none { network -> cm.getNetworkCapabilities(network)?.let {
            it.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) && it.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        } == true }, "QA_INTERNET_WIFI_REJECTED")
        val visibleDefault = cm.activeNetwork
        requireProtocol(visibleDefault == mobile || (selected != null && visibleDefault == selected), "QA_MOBILE_DEFAULT_CHANGED")
    }

    fun bindForIroh(): JsonObject {
        checkMobile()
        if (scope == "shared-hotspot") {
            requireProtocol(Build.VERSION.SDK_INT >= 35 && bindIp != null, "QA_LOCAL_NETWORK_UNSUPPORTED")
            val candidates = cm.allNetworks.mapNotNull { network ->
                val caps = cm.getNetworkCapabilities(network) ?: return@mapNotNull null
                val lp = cm.getLinkProperties(network) ?: return@mapNotNull null
                val owned = lp.linkAddresses.singleOrNull { it.address == bindIp } ?: return@mapNotNull null
                if (network != mobile && caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
                    !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                    caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN) &&
                    caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_LOCAL_NETWORK) &&
                    !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) Triple(network, owned, lp) else null
            }
            requireProtocol(candidates.size == 1, "QA_EXACT_LOCAL_NETWORK_NOT_VISIBLE")
            val (network, owned, _) = candidates.single()
            selected = network; selectedAddress = owned; attempted = true
            requireProtocol(cm.bindProcessToNetwork(network), "QA_LOCAL_NETWORK_BIND_DENIED")
            requireProtocol(cm.boundNetworkForProcess == network, "QA_PROCESS_BIND_NOT_APPLIED")
        }
        return proof()
    }

    fun validatePeer(address: P2PAddress) {
        if (scope != "shared-hotspot") return
        val local = selectedAddress ?: throw ProtocolException("QA_LOCAL_NETWORK_NOT_SELECTED")
        requireProtocol(address.directAddresses.any { raw ->
            runCatching {
                val peer = ipv6SocketAddress(raw)
                peer != local.address && samePrefix(local.address.address, peer.address, local.prefixLength)
            }.getOrDefault(false)
        }, "QA_PEER_NOT_ON_SELECTED_LOCAL_PREFIX")
    }

    fun proof(): JsonObject {
        checkMobile()
        val current = cm.boundNetworkForProcess
        requireProtocol(current == selected, "QA_PROCESS_BINDING_CHANGED")
        val local = selected
        if (local != null) {
            val caps = cm.getNetworkCapabilities(local) ?: throw ProtocolException("QA_LOCAL_NETWORK_LOST")
            val lp = cm.getLinkProperties(local) ?: throw ProtocolException("QA_LOCAL_NETWORK_LOST")
            requireProtocol(caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_LOCAL_NETWORK) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN) &&
                !caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                lp.linkAddresses.any { it.address == bindIp }, "QA_SELECTED_LOCAL_NETWORK_CHANGED")
        }
        return buildJsonObject {
            put("scope", scope); put("mobileDefaultNetworkHandle", mobile.networkHandle)
            put("mobileDefaultCellular", true); put("vpn", false)
            put("testSocketTransport", if (local == null) "CELLULAR" else "WIFI_LOCAL_NETWORK")
            put("processBound", local != null)
            local?.let { n ->
                put("selectedNetworkHandle", n.networkHandle)
                val lp = cm.getLinkProperties(n)!!
                put("interfaceName", lp.interfaceName ?: "")
                put("selectedLinkAddress", selectedAddress.toString())
            }
        }
    }

    /** Must run after the native endpoint is closed, on every success/failure/abort path. */
    fun restore(): JsonObject {
        val before = cm.boundNetworkForProcess
        val returned = if (attempted) cm.bindProcessToNetwork(prior) else true
        val after = cm.boundNetworkForProcess
        val restored = returned && after == prior
        return buildJsonObject {
            put("scope", scope); put("attempted", attempted); put("restored", restored)
            put("previouslyBound", prior != null); put("currentBindingMatchesPrevious", after == prior)
            prior?.let { put("priorNetworkHandle", it.networkHandle) }
            before?.let { put("beforeRestoreNetworkHandle", it.networkHandle) }
            after?.let { put("afterRestoreNetworkHandle", it.networkHandle) }
        }
    }

    private fun ipv6SocketAddress(raw: String): Inet6Address {
        val match = Regex("^\\[([0-9A-Fa-f:]+)\\]:([0-9]{1,5})$").matchEntire(raw)
            ?: throw ProtocolException("QA_NUMERIC_IPV6_SOCKET_REQUIRED")
        requireProtocol(match.groupValues[2].toInt() in 0..65535, "QA_INVALID_PORT")
        return InetAddress.getByName(match.groupValues[1]) as? Inet6Address
            ?: throw ProtocolException("QA_IPV6_REQUIRED")
    }

    private fun samePrefix(a: ByteArray, b: ByteArray, bits: Int): Boolean {
        if (a.size != 16 || b.size != 16 || bits !in 1..128) return false
        val whole = bits / 8; val remainder = bits % 8
        if ((0 until whole).any { a[it] != b[it] }) return false
        return remainder == 0 || ((a[whole].toInt() xor b[whole].toInt()) and (0xff shl (8 - remainder))) == 0
    }
}
