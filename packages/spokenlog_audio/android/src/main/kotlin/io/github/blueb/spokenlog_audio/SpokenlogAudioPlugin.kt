package io.github.blueb.spokenlog_audio

import android.app.Activity
import android.content.Intent
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

class SpokenlogAudioPlugin :
    FlutterPlugin,
    ActivityAware,
    MethodChannel.MethodCallHandler,
    PluginRegistry.ActivityResultListener {
    private lateinit var channel: MethodChannel
    private var binding: ActivityPluginBinding? = null
    private var pendingResult: MethodChannel.Result? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "spokenlog_audio")
        channel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        binding.addActivityResultListener(this)
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)

    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

    override fun onDetachedFromActivity() {
        binding?.removeActivityResultListener(this)
        binding = null
    }

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "convertToWav" -> {
                val source = call.argument<String>("source")!!
                val target = call.argument<String>("target")!!
                Thread {
                    try {
                        decodeToWav(source, target)
                        main.post { result.success(null) }
                    } catch (e: Exception) {
                        File(target).delete()
                        main.post { result.error("convert_failed", e.message, null) }
                    }
                }.start()
            }

            "pickAudio" -> {
                pickAudio(result)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    private fun pickAudio(result: MethodChannel.Result) {
        val activity = binding?.activity ?: return result.error("no_activity", "No foreground activity", null)
        if (pendingResult != null) return result.error("busy", "Picker already open", null)
        pendingResult = result
        val intent =
            Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                putExtra(Intent.EXTRA_MIME_TYPES, arrayOf("audio/*", "video/*"))
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    // Samsung Voice Recorder default folder; the picker falls back to its default if missing.
                    putExtra(
                        DocumentsContract.EXTRA_INITIAL_URI,
                        DocumentsContract.buildDocumentUri(
                            "com.android.externalstorage.documents",
                            "primary:Recordings/Voice Recorder",
                        ),
                    )
                }
            }
        activity.startActivityForResult(intent, PICK_AUDIO_REQUEST)
    }

    override fun onActivityResult(
        requestCode: Int,
        resultCode: Int,
        data: Intent?,
    ): Boolean {
        if (requestCode != PICK_AUDIO_REQUEST) return false
        val result = pendingResult ?: return true
        pendingResult = null
        val activity = binding?.activity
        if (resultCode != Activity.RESULT_OK || data == null || activity == null) {
            result.success(emptyList<String>())
            return true
        }

        val uris =
            data.clipData?.let { clip -> (0 until clip.itemCount).map { clip.getItemAt(it).uri } }
                ?: listOfNotNull(data.data)
        Thread {
            try {
                val dir =
                    File(activity.cacheDir, "audio_import").apply {
                        deleteRecursively()
                        mkdirs()
                    }
                val paths =
                    uris.mapIndexed { index, uri ->
                        val target = File(File(dir, index.toString()).apply { mkdirs() }, displayName(activity, uri))
                        activity.contentResolver.openInputStream(uri)!!.use { input ->
                            target.outputStream().use { input.copyTo(it) }
                        }
                        target.path
                    }
                main.post { result.success(paths) }
            } catch (e: Exception) {
                main.post { result.error("copy_failed", e.message, null) }
            }
        }.start()
        return true
    }

    private fun displayName(
        activity: Activity,
        uri: Uri,
    ): String =
        activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
            if (it.moveToFirst()) it.getString(0) else null
        } ?: uri.lastPathSegment?.substringAfterLast('/') ?: "audio"

    /** Decodes the first audio track of [source] to 16 kHz mono PCM16 WAV, the format local engines read. */
    private fun decodeToWav(
        source: String,
        target: String,
    ) {
        val extractor = MediaExtractor()
        try {
            extractor.setDataSource(source)
            val track =
                (0 until extractor.trackCount).firstOrNull {
                    extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
                } ?: throw IllegalArgumentException("No audio track")
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            val codec = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
            try {
                codec.configure(format, null, null, 0)
                codec.start()
                RandomAccessFile(target, "rw").use { out -> decodeLoop(extractor, codec, format, out) }
            } finally {
                codec.release()
            }
        } finally {
            extractor.release()
        }
    }

    private fun decodeLoop(
        extractor: MediaExtractor,
        codec: MediaCodec,
        format: MediaFormat,
        out: RandomAccessFile,
    ) {
        val resampler = MonoResampler(format.getInteger(MediaFormat.KEY_SAMPLE_RATE))
        var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        var isFloat = false
        out.setLength(0)
        out.write(ByteArray(44))
        val info = MediaCodec.BufferInfo()
        var inputDone = false
        var outputDone = false
        while (!outputDone) {
            if (!inputDone) {
                val i = codec.dequeueInputBuffer(10_000)
                if (i >= 0) {
                    val size = extractor.readSampleData(codec.getInputBuffer(i)!!, 0)
                    if (size < 0) {
                        codec.queueInputBuffer(i, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputDone = true
                    } else {
                        codec.queueInputBuffer(i, 0, size, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
            }
            val o = codec.dequeueOutputBuffer(info, 10_000)
            if (o == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                val f = codec.outputFormat
                resampler.sourceRate = f.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                channels = f.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                isFloat = f.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                    f.getInteger(MediaFormat.KEY_PCM_ENCODING) == AudioFormat.ENCODING_PCM_FLOAT
            } else if (o >= 0) {
                val buf = codec.getOutputBuffer(o)!!.order(ByteOrder.nativeOrder())
                buf.position(info.offset)
                buf.limit(info.offset + info.size)
                while (buf.remaining() >= channels * (if (isFloat) 4 else 2)) {
                    var sum = 0f
                    repeat(channels) { sum += if (isFloat) buf.float else buf.short / 32768f }
                    resampler.push(sum / channels)
                }
                codec.releaseOutputBuffer(o, false)
                resampler.flushTo(out, minBytes = 1 shl 16)
                if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) outputDone = true
            }
        }
        resampler.flushTo(out, minBytes = 0)
        if (resampler.dataBytes == 0L) throw IllegalStateException("No audio decoded")
        out.seek(0)
        out.write(wavHeader(resampler.dataBytes))
    }

    /** Streaming linear resampler: output sample k sits at source position k * sourceRate / 16000. */
    // shortcut: no low-pass before downsampling, fine for speech; add a filter if music imports sound harsh.
    private class MonoResampler(
        var sourceRate: Int,
    ) {
        private var sourceIndex = -1L
        private var previous = 0f
        private var outIndex = 0L
        private val pending = ByteArrayOutputStream()
        var dataBytes = 0L
            private set

        fun push(sample: Float) {
            sourceIndex++
            if (sourceIndex == 0L) previous = sample
            val step = sourceRate / 16000.0
            while (outIndex * step <= sourceIndex) {
                val v = previous + (sample - previous) * (1 - (sourceIndex - outIndex * step)).toFloat()
                val s = (v.coerceIn(-1f, 1f) * 32767).toInt()
                pending.write(s and 0xff)
                pending.write((s shr 8) and 0xff)
                outIndex++
            }
            previous = sample
        }

        fun flushTo(
            out: RandomAccessFile,
            minBytes: Int,
        ) {
            if (pending.size() == 0 || pending.size() < minBytes) return
            out.write(pending.toByteArray())
            dataBytes += pending.size()
            pending.reset()
        }
    }

    companion object {
        private const val PICK_AUDIO_REQUEST = 4721

        fun wavHeader(dataBytes: Long): ByteArray =
            ByteBuffer
                .allocate(44)
                .order(ByteOrder.LITTLE_ENDIAN)
                .put("RIFF".toByteArray())
                .putInt((36 + dataBytes).toInt())
                .put("WAVEfmt ".toByteArray())
                .putInt(16)
                .putShort(1)
                .putShort(1)
                .putInt(16000)
                .putInt(32000)
                .putShort(2)
                .putShort(16)
                .put("data".toByteArray())
                .putInt(dataBytes.toInt())
                .array()
    }
}
