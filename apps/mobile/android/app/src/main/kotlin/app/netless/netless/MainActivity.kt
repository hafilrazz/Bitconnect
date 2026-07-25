package app.netless.netless

import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val methodChannelName = "app.netless/ble_mesh"
    private val eventChannelName = "app.netless/ble_mesh_events"

    private var meshServer: BleMeshServer? = null
    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventChannelName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startPeripheral" -> {
                        try {
                            if (meshServer == null) {
                                meshServer = BleMeshServer(
                                    context = this,
                                    onPacket = { from, payload ->
                                        mainHandler.post {
                                            eventSink?.success(
                                                mapOf(
                                                    "type" to "packet",
                                                    "from" to from,
                                                    "data" to payload,
                                                ),
                                            )
                                        }
                                    },
                                    onPeersChanged = { peers ->
                                        mainHandler.post {
                                            eventSink?.success(
                                                mapOf(
                                                    "type" to "peers",
                                                    "peers" to peers,
                                                ),
                                            )
                                        }
                                    },
                                )
                            }
                            val ok = meshServer?.start() == true
                            result.success(ok)
                        } catch (e: Exception) {
                            result.error("start_failed", e.message, null)
                        }
                    }
                    "stopPeripheral" -> {
                        meshServer?.stop()
                        meshServer = null
                        result.success(null)
                    }
                    "notifyCentrals" -> {
                        val data = call.argument<ByteArray>("data")
                        if (data == null) {
                            result.error("bad_args", "data required", null)
                        } else {
                            meshServer?.sendToConnectedCentrals(data)
                            result.success(null)
                        }
                    }
                    "connectedCentrals" -> {
                        result.success(meshServer?.connectedPeerIds() ?: emptyList<String>())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        meshServer?.stop()
        meshServer = null
        super.onDestroy()
    }
}
