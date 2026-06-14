package com.mobstudios.hermes

import android.annotation.SuppressLint
import android.content.Context
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

/**
 * 6r-d faz1 — eş zamanlı (concurrent) çift mikrofon yakalama köprüsü.
 *
 * İki ayrı [AudioRecord] instance'ı eş zamanlı açar:
 * - **primary** = kulaklık mikrofonu (BT SCO / kablolu / USB) — Voice Translator'da sağ taraf
 * - **secondary** = telefon dahili mikrofonu — Voice Translator'da sol taraf
 *
 * Her mic kendi reader thread'inde okunur, ham **PCM16 / 16kHz / mono** chunk'ları
 * kendi [EventChannel]'ına yayar. Bu faz **VAD içermez** — amacı Poco X3 Pro'da
 * (MIUI) iki mic'in gerçekten eş zamanlı stream verebildiğini kanıtlamak.
 * Faz2'de Dart tarafı her stream'e ayrı `VadHandler.startListening(audioStream:)`
 * bağlayacak (roadmap 6r-d-faz2).
 *
 * Bu bir pub paketi değil; [MainActivity.configureFlutterEngine] içinde manuel
 * register edilir.
 */
class HermesDualMicPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    companion object {
        private const val METHOD_CHANNEL = "hermes/dual_mic"
        private const val EVENT_PRIMARY = "hermes/dual_mic/primary"
        private const val EVENT_SECONDARY = "hermes/dual_mic/secondary"

        private const val SAMPLE_RATE = 16000
        private const val CHANNEL_CONFIG = AudioFormat.CHANNEL_IN_MONO
        private const val AUDIO_FORMAT = AudioFormat.ENCODING_PCM_16BIT

        // BT SCO bağlantısının kurulmasını beklerken üst sınır (MIUI'de async).
        private const val SCO_TIMEOUT_MS = 2500L
        private const val SCO_POLL_MS = 100L
    }

    private lateinit var appContext: Context
    private lateinit var audioManager: AudioManager
    private lateinit var methodChannel: MethodChannel
    private lateinit var primaryChannel: EventChannel
    private lateinit var secondaryChannel: EventChannel

    private val mainHandler = Handler(Looper.getMainLooper())

    private var primarySink: EventChannel.EventSink? = null
    private var secondarySink: EventChannel.EventSink? = null

    private var primaryRecorder: MicRecorder? = null
    private var secondaryRecorder: MicRecorder? = null

    private var startedBluetoothSco = false

    // ---------- FlutterPlugin ----------

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        appContext = binding.applicationContext
        audioManager = appContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)

        primaryChannel = EventChannel(binding.binaryMessenger, EVENT_PRIMARY)
        primaryChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                primarySink = events
            }

            override fun onCancel(arguments: Any?) {
                primarySink = null
            }
        })

        secondaryChannel = EventChannel(binding.binaryMessenger, EVENT_SECONDARY)
        secondaryChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                secondarySink = events
            }

            override fun onCancel(arguments: Any?) {
                secondarySink = null
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        stopCapture()
        methodChannel.setMethodCallHandler(null)
        primaryChannel.setStreamHandler(null)
        secondaryChannel.setStreamHandler(null)
    }

    // ---------- MethodChannel ----------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isDualCaptureSupported" -> result.success(isDualCaptureSupported())

            "start" -> {
                val preferBluetooth = call.argument<Boolean>("preferBluetooth") ?: false
                val primarySource =
                    call.argument<Int>("primarySource") ?: MediaRecorder.AudioSource.MIC
                val secondarySource =
                    call.argument<Int>("secondarySource") ?: MediaRecorder.AudioSource.MIC
                try {
                    val info = startCapture(preferBluetooth, primarySource, secondarySource)
                    result.success(info)
                } catch (e: Exception) {
                    stopCapture()
                    result.error("START_FAILED", e.message, null)
                }
            }

            "stop" -> {
                stopCapture()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    // ---------- Capture lifecycle ----------

    /**
     * Concurrent capture API 29+'da resmî olarak destekli; daha eski sürümlerde
     * cihaza/OEM'e bağlı. Bu sadece bir gösterge — gerçek kanıt cihaz smoke'u.
     */
    private fun isDualCaptureSupported(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
    }

    private fun startCapture(
        preferBluetooth: Boolean,
        primarySource: Int,
        secondarySource: Int,
    ): Map<String, Any?> {
        if (primaryRecorder != null || secondaryRecorder != null) {
            stopCapture()
        }

        val builtin = findInputDevice(AudioDeviceInfo.TYPE_BUILTIN_MIC)
        val headset = selectHeadsetDevice(preferBluetooth)

        primaryRecorder = MicRecorder("primary", headset, primarySource) { data ->
            mainHandler.post { primarySink?.success(data) }
        }.also { it.start() }

        secondaryRecorder = MicRecorder("secondary", builtin, secondarySource) { data ->
            mainHandler.post { secondarySink?.success(data) }
        }.also { it.start() }

        return mapOf(
            "dualCaptureSupported" to isDualCaptureSupported(),
            "primaryDevice" to (headset?.let { describeDevice(it) } ?: "varsayılan (kulaklık yok)"),
            "secondaryDevice" to (builtin?.let { describeDevice(it) } ?: "varsayılan"),
            "scoStarted" to startedBluetoothSco,
            "primarySource" to sourceLabel(primarySource),
            "secondarySource" to sourceLabel(secondarySource),
        )
    }

    private fun sourceLabel(source: Int): String = when (source) {
        MediaRecorder.AudioSource.MIC -> "MIC"
        MediaRecorder.AudioSource.VOICE_RECOGNITION -> "VOICE_RECOGNITION"
        MediaRecorder.AudioSource.VOICE_COMMUNICATION -> "VOICE_COMMUNICATION"
        MediaRecorder.AudioSource.CAMCORDER -> "CAMCORDER"
        MediaRecorder.AudioSource.UNPROCESSED -> "UNPROCESSED"
        else -> "source $source"
    }

    private fun stopCapture() {
        primaryRecorder?.stop()
        primaryRecorder = null
        secondaryRecorder?.stop()
        secondaryRecorder = null
        stopBluetoothScoIfNeeded()
    }

    // ---------- Device selection ----------

    /**
     * Kulaklık mic'i seç. Mehmet tercihi: BT çok daha iyi ama kablolu daha güvenilir
     * (MIUI SCO riski). [preferBluetooth] true ise BT SCO öne alınır; aksi halde
     * USB → kablolu → BT SCO sırası denenir. Kulaklık yoksa null döner
     * (primary varsayılan mic'e düşer; cihaz testinde bu durum belli olur).
     */
    private fun selectHeadsetDevice(preferBluetooth: Boolean): AudioDeviceInfo? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null

        val sco = findInputDevice(AudioDeviceInfo.TYPE_BLUETOOTH_SCO)
        val usb = findInputDevice(AudioDeviceInfo.TYPE_USB_HEADSET)
        val wired = findInputDevice(AudioDeviceInfo.TYPE_WIRED_HEADSET)

        val order = if (preferBluetooth) {
            listOf(sco, usb, wired)
        } else {
            listOf(usb, wired, sco)
        }
        val chosen = order.firstOrNull { it != null } ?: return null

        // SCO kulaklık seçildiyse mic yönlendirmesini etkinleştir (async).
        if (chosen.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO) {
            ensureBluetoothSco()
        }
        return chosen
    }

    private fun findInputDevice(type: Int): AudioDeviceInfo? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return null
        return audioManager
            .getDevices(AudioManager.GET_DEVICES_INPUTS)
            .firstOrNull { it.type == type }
    }

    private fun ensureBluetoothSco() {
        if (startedBluetoothSco) return
        @Suppress("DEPRECATION")
        audioManager.startBluetoothSco()
        @Suppress("DEPRECATION")
        audioManager.isBluetoothScoOn = true
        startedBluetoothSco = true

        // SCO bağlantısı asenkron kurulur; setPreferredDevice'in tutması için
        // kısa süre bekle (üst sınırlı, MIUI takılmasın diye).
        val deadline = System.currentTimeMillis() + SCO_TIMEOUT_MS
        while (System.currentTimeMillis() < deadline && !audioManager.isBluetoothScoOn) {
            try {
                Thread.sleep(SCO_POLL_MS)
            } catch (_: InterruptedException) {
                break
            }
        }
    }

    private fun stopBluetoothScoIfNeeded() {
        if (!startedBluetoothSco) return
        @Suppress("DEPRECATION")
        audioManager.isBluetoothScoOn = false
        @Suppress("DEPRECATION")
        audioManager.stopBluetoothSco()
        startedBluetoothSco = false
    }

    private fun describeDevice(device: AudioDeviceInfo): String {
        val typeLabel = when (device.type) {
            AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "Bluetooth SCO"
            AudioDeviceInfo.TYPE_USB_HEADSET -> "USB kulaklık"
            AudioDeviceInfo.TYPE_WIRED_HEADSET -> "Kablolu kulaklık"
            AudioDeviceInfo.TYPE_BUILTIN_MIC -> "Dahili mic"
            else -> "tip ${device.type}"
        }
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            "$typeLabel (${device.productName})"
        } else {
            typeLabel
        }
    }

    // ---------- Tek mic reader ----------

    /**
     * Tek bir [AudioRecord]'u kendi thread'inde okuyup ham PCM byte'larını
     * [onChunk]'a iletir. [onChunk] ana thread'e post etmekle yükümlü
     * (EventSink ana thread'de çağrılmalı).
     */
    private inner class MicRecorder(
        private val label: String,
        private val preferredDevice: AudioDeviceInfo?,
        private val audioSource: Int,
        private val onChunk: (ByteArray) -> Unit,
    ) {
        private var record: AudioRecord? = null
        @Volatile
        private var running = false
        private var readerThread: Thread? = null

        @SuppressLint("MissingPermission")
        fun start() {
            val minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE, CHANNEL_CONFIG, AUDIO_FORMAT)
            if (minBuf <= 0) {
                throw IllegalStateException("$label: getMinBufferSize döndü $minBuf")
            }
            val bufferSize = minBuf * 2

            val rec = AudioRecord(
                audioSource,
                SAMPLE_RATE,
                CHANNEL_CONFIG,
                AUDIO_FORMAT,
                bufferSize,
            )
            if (rec.state != AudioRecord.STATE_INITIALIZED) {
                rec.release()
                throw IllegalStateException("$label: AudioRecord init başarısız")
            }
            if (preferredDevice != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                rec.setPreferredDevice(preferredDevice)
            }

            record = rec
            rec.startRecording()
            running = true

            readerThread = thread(name = "hermes-mic-$label", isDaemon = true) {
                val chunk = ByteArray(bufferSize)
                while (running) {
                    val read = rec.read(chunk, 0, chunk.size)
                    if (read > 0) {
                        onChunk(chunk.copyOf(read))
                    } else if (read < 0) {
                        running = false
                        break
                    }
                }
            }
        }

        fun stop() {
            running = false
            readerThread?.join(500)
            readerThread = null
            record?.let { rec ->
                try {
                    if (rec.recordingState == AudioRecord.RECORDSTATE_RECORDING) {
                        rec.stop()
                    }
                } catch (_: Exception) {
                    // best effort
                }
                rec.release()
            }
            record = null
        }
    }
}
