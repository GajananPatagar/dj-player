#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "🛠 Fixing Kotlin Syntax Errors in MainActivity.kt..."

# Ensure the correct package directory structure exists
mkdir -p android/app/src/main/kotlin/com/gajanan/djplaycommentry/dj_player

cat << 'KT_EOF' > android/app/src/main/kotlin/com/gajanan/djplaycommentry/dj_player/MainActivity.kt
package com.gajanan.djplaycommentry.dj_player

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaRecorder
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.Voice
import android.view.KeyEvent
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.nio.ByteBuffer
import java.util.Locale

class MainActivity: FlutterActivity(), TextToSpeech.OnInitListener {
    private var tts: TextToSpeech? = null
    private var ttsReady: Boolean = false
    private var recorder: MediaRecorder? = null
    private var currentRecordPath: String? = null
    private var methodChannel: MethodChannel? = null
    private var pendingFileResult: MethodChannel.Result? = null
    private var pendingIsVideo: Boolean = false
    private var initialSharedMedia: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        tts = TextToSpeech(this, this)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
            if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO, Manifest.permission.READ_EXTERNAL_STORAGE), 200)
            }
        }
        handleIncomingShareIntent(intent)
    }

    override fun onInit(status: Int) {
        ttsReady = (status == TextToSpeech.SUCCESS)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIncomingShareIntent(intent)
    }

    private fun handleIncomingShareIntent(intent: Intent?) {
        if (intent == null) return
        if (Intent.ACTION_SEND == intent.action) {
            val sharedText = intent.getStringExtra(Intent.EXTRA_TEXT)
            val sharedStream = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
            if (!sharedText.isNullOrEmpty()) {
                initialSharedMedia = sharedText
                Handler(Looper.getMainLooper()).postDelayed({
                    methodChannel?.invokeMethod("onSharedMedia", sharedText)
                }, 500)
            } else if (sharedStream != null) {
                val extracted = copyUriAndExtractAudio(sharedStream, true)
                if (extracted != null) {
                    initialSharedMedia = extracted
                    Handler(Looper.getMainLooper()).postDelayed({
                        methodChannel?.invokeMethod("onSharedMedia", extracted)
                    }, 500)
                }
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            methodChannel?.invokeMethod("onVolumeKey", "UP")
        } else if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            methodChannel?.invokeMethod("onVolumeKey", "DOWN")
        }
        return super.onKeyDown(keyCode, event)
    }

    private fun selectBestNaturalVoice(locale: Locale) {
        try {
            val voices = tts?.voices ?: return
            var bestVoice: Voice? = null
            var bestScore = -1000
            for (v in voices) {
                if (v.locale.language == locale.language) {
                    val n = v.name.lowercase()
                    var score = v.quality
                    if (n.contains("knm") || n.contains("knd") || n.contains("him") || n.contains("hid") ||
                        n.contains("enm") || n.contains("end") || n.contains("gbm") || n.contains("aub") ||
                        n.contains("male") || n.contains("-b") || n.contains("-d")) {
                        score += 600
                    }
                    if (n.contains("knf") || n.contains("hif") || n.contains("enf") || n.contains("female") || n.contains("-a") || n.contains("-c")) {
                        score -= 500
                    }
                    if (n.contains("network") || n.contains("wavenet")) {
                        score += 300
                    }
                    if (score > bestScore) {
                        bestScore = score
                        bestVoice = v
                    }
                }
            }
            if (bestVoice != null) {
                tts?.voice = bestVoice
            } else {
                tts?.language = locale
            }
        } catch (_: Exception) {
            tts?.language = locale
        }
    }

    private fun resolveAndExtractUrlNative(rawShareText: String, result: MethodChannel.Result) {
        val urlRegex = Regex("https?://[^\\s\"<>]+")
        val match = urlRegex.find(rawShareText)
        val targetUrl = match?.value ?: rawShareText.trim()
        var completed = false
        val mainHandler = Handler(Looper.getMainLooper())

        fun finishWithUrl(mediaUrl: String?) {
            if (completed) return
            completed = true
            if (mediaUrl == null) {
                mainHandler.post { result.success(null) }
                return
            }
            Thread {
                try {
                    val conn = URL(mediaUrl).openConnection() as HttpURLConnection
                    conn.setRequestProperty("User-Agent", "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124.0 Mobile Safari/537.36")
                    conn.connectTimeout = 12000
                    conn.readTimeout = 20000
                    conn.instanceFollowRedirects = true
                    val tempVid = File(filesDir, "native_reel_${System.currentTimeMillis()}.mp4")
                    conn.inputStream.use { inp ->
                        FileOutputStream(tempVid).use { out ->
                            inp.copyTo(out)
                        }
                    }
                    if (tempVid.exists() && tempVid.length() > 10000) {
                        val audioPath = extractAudioTrackHardware(tempVid.absolutePath) ?: tempVid.absolutePath
                        mainHandler.post { result.success(audioPath) }
                    } else {
                        mainHandler.post { result.success(null) }
                    }
                } catch (_: Exception) {
                    mainHandler.post { result.success(null) }
                }
            }.start()
        }

        mainHandler.post {
            try {
                val wv = WebView(applicationContext)
                wv.settings.javaScriptEnabled = true
                wv.settings.domStorageEnabled = true
                wv.settings.mediaPlaybackRequiresUserGesture = false
                wv.settings.userAgentString = "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36"

                wv.webViewClient = object : WebViewClient() {
                    override fun shouldInterceptRequest(view: WebView?, request: WebResourceRequest?): WebResourceResponse? {
                        val reqUrl = request?.url?.toString() ?: ""
                        if (!completed && (reqUrl.contains(".mp4") || reqUrl.contains(".m4a") || reqUrl.contains("googlevideo.com/videoplayback") || reqUrl.contains("cdninstagram.com") || reqUrl.contains("fbcdn.net")) && !reqUrl.contains(".jpg") && !reqUrl.contains(".png") && !reqUrl.contains(".webp")) {
                            if (reqUrl.contains("mp4") || reqUrl.contains("videoplayback") || reqUrl.contains("audio")) {
                                mainHandler.post {
                                    try { wv.destroy() } catch (_: Exception) {}
                                }
                                finishWithUrl(reqUrl)
                            }
                        }
                        return super.shouldInterceptRequest(view, request)
                    }

                    override fun onPageFinished(view: WebView?, url: String?) {
                        super.onPageFinished(view, url)
                        view?.evaluateJavascript(
                            "(function(){ var v = document.querySelector('video'); if(v && v.src) return v.src; var m = document.querySelector('meta[property=\"og:video\"]'); if(m) return m.content; return ''; })()"
                        ) { resStr ->
                            val clean = resStr?.replace("\"", "")?.trim() ?: ""
                            if (!completed && clean.startsWith("http")) {
                                try { wv.destroy() } catch (_: Exception) {}
                                finishWithUrl(clean)
                            }
                        }
                    }
                }

                val loadUrl = if (targetUrl.contains("instagram.com")) {
                    val sc = Regex("(?:reel|reels|p)/([A-Za-z0-9_-]+)").find(targetUrl)?.groupValues?.get(1)
                    if (sc != null) "https://www.instagram.com/p/$sc/embed/captioned/" else targetUrl
                } else {
                    targetUrl
                }
                wv.loadUrl(loadUrl)

                mainHandler.postDelayed({
                    if (!completed) {
                        try { wv.destroy() } catch (_: Exception) {}
                        finishWithUrl(null)
                    }
                }, 9500)
            } catch (_: Exception) {
                finishWithUrl(null)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == 701) {
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val path = copyUriAndExtractAudio(data.data!!, pendingIsVideo)
                pendingFileResult?.success(path)
            } else {
                pendingFileResult?.success(null)
            }
            pendingFileResult = null
        }
    }

    private fun copyUriAndExtractAudio(uri: Uri, extractIfVideo: Boolean): String? {
        return try {
            val mime = contentResolver.getType(uri) ?: ""
            val isVid = extractIfVideo || mime.startsWith("video")
            val ext = if (isVid) ".mp4" else ".m4a"
            val tempIn = File(filesDir, "picked_${System.currentTimeMillis()}$ext")
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(tempIn).use { output ->
                    input.copyTo(output)
                }
            }
            if (isVid) {
                extractAudioTrackHardware(tempIn.absolutePath) ?: tempIn.absolutePath
            } else {
                tempIn.absolutePath
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun extractAudioTrackHardware(videoPath: String): String? {
        return try {
            val outAudioFile = File(filesDir, "extracted_audio_${System.currentTimeMillis()}.m4a")
            val extractor = MediaExtractor()
            extractor.setDataSource(videoPath)
            var audioTrackIndex = -1
            for (i in 0 until extractor.trackCount) {
                val format = extractor.getTrackFormat(i)
                val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("audio/")) {
                    audioTrackIndex = i
                    break
                }
            }
            if (audioTrackIndex < 0) {
                extractor.release()
                return videoPath
            }
            extractor.selectTrack(audioTrackIndex)
            val format = extractor.getTrackFormat(audioTrackIndex)
            val muxer = MediaMuxer(outAudioFile.absolutePath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            val dstIndex = muxer.addTrack(format)
            muxer.start()
            val buffer = ByteBuffer.allocate(256 * 1024)
            val bufferInfo = MediaCodec.BufferInfo()
            while (true) {
                val sampleSize = extractor.readSampleData(buffer, 0)
                if (sampleSize < 0) break
                bufferInfo.offset = 0
                bufferInfo.size = sampleSize
                bufferInfo.presentationTimeUs = extractor.sampleTime
                bufferInfo.flags = extractor.sampleFlags
                muxer.writeSampleData(dstIndex, buffer, bufferInfo)
                extractor.advance()
            }
            muxer.stop()
            muxer.release()
            extractor.release()
            outAudioFile.absolutePath
        } catch (_: Exception) {
            videoPath
        }
    }

    private fun startIsolatedVoiceRecorder(fileName: String, useEchoCancelledSource: Boolean): String? {
        try {
            recorder?.release()
            val outFile = File(filesDir, "$fileName.m4a")
            currentRecordPath = outFile.absolutePath
            recorder = MediaRecorder().apply {
                if (useEchoCancelledSource) {
                    setAudioSource(MediaRecorder.AudioSource.VOICE_COMMUNICATION)
                } else {
                    setAudioSource(MediaRecorder.AudioSource.MIC)
                }
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioEncodingBitRate(192000)
                setAudioSamplingRate(44100)
                setOutputFile(currentRecordPath)
                prepare()
                start()
            }
            return currentRecordPath
        } catch (_: Exception) {
            return try {
                recorder?.release()
                val outFile = File(filesDir, "$fileName.m4a")
                currentRecordPath = outFile.absolutePath
                recorder = MediaRecorder().apply {
                    setAudioSource(MediaRecorder.AudioSource.MIC)
                    setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                    setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                    setAudioEncodingBitRate(192000)
                    setAudioSamplingRate(44100)
                    setOutputFile(currentRecordPath)
                    prepare()
                    start()
                }
                currentRecordPath
            } catch (_: Exception) {
                null
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dj_native_tts")
        methodChannel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "speak" -> {
                    if (!ttsReady || tts == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val text = call.argument<String>("text") ?: ""
                    val lang = call.argument<String>("lang") ?: "kn-IN"
                    val basePitch = (call.argument<Double>("pitch") ?: 0.92).toFloat()
                    val baseRate = (call.argument<Double>("rate") ?: 1.20).toFloat()
                    val locale = Locale.forLanguageTag(lang)
                    val avail = tts?.isLanguageAvailable(locale) ?: TextToSpeech.LANG_NOT_SUPPORTED
                    if (avail < TextToSpeech.LANG_AVAILABLE) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    tts?.stop()
                    selectBestNaturalVoice(locale)

                    val parts = text.split(" | ")
                    if (parts.size >= 3) {
                        tts?.setPitch((basePitch * 1.10f).coerceIn(0.75f, 1.35f))
                        tts?.setSpeechRate((baseRate * 1.06f).coerceIn(0.95f, 1.45f))
                        tts?.speak(parts[0], TextToSpeech.QUEUE_FLUSH, null, "utt_w1")

                        tts?.setPitch((basePitch * 0.94f).coerceIn(0.72f, 1.25f))
                        tts?.setSpeechRate((baseRate * 1.03f).coerceIn(0.95f, 1.40f))
                        tts?.speak(parts[1], TextToSpeech.QUEUE_ADD, null, "utt_w2")

                        tts?.setPitch((basePitch * 1.03f).coerceIn(0.75f, 1.30f))
                        tts?.setSpeechRate((baseRate * 0.98f).coerceIn(0.90f, 1.35f))
                        val speakRes = tts?.speak(parts.subList(2, parts.size).joinToString(" "), TextToSpeech.QUEUE_ADD, null, "utt_w3")
                        result.success(speakRes == TextToSpeech.SUCCESS)
                    } else {
                        tts?.setPitch(basePitch)
                        tts?.setSpeechRate(baseRate)
                        val speakRes = tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "dj_single_utt")
                        result.success(speakRes == TextToSpeech.SUCCESS)
                    }
                }
                "stopSpeak" -> {
                    tts?.stop()
                    result.success(true)
                }
                "setKaraokeVocalCut" -> {
                    result.success(true)
                }
                "startCleanVocalRecord" -> {
                    val name = call.argument<String>("name") ?: "karaoke_vocal"
                    val path = startIsolatedVoiceRecorder(name, true)
                    result.success(path)
                }
                "stopCleanVocalRecord" -> {
                    try {
                        recorder?.stop()
                    } catch (_: Exception) {}
                    recorder?.release()
                    recorder = null
                    try {
                        val src = currentRecordPath?.let { File(it) }
                        if (src != null && src.exists() && src.length() > 500) {
                            val dlDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                            dlDir.mkdirs()
                            val publicFile = File(dlDir, "DJ_Karaoke_" + src.name)
                            src.copyTo(publicFile, overwrite = true)
                            MediaScannerConnection.scanFile(this, arrayOf(publicFile.absolutePath), arrayOf("audio/mp4"), null)
                        }
                    } catch (_: Exception) {}
                    result.success(currentRecordPath)
                }
                "startRecord" -> {
                    val name = call.argument<String>("name") ?: "voice_clip"
                    val path = startIsolatedVoiceRecorder(name, false)
                    result.success(path)
                }
                "stopRecord" -> {
                    try {
                        recorder?.stop()
                        recorder?.release()
                        recorder = null
                        result.success(currentRecordPath)
                    } catch (_: Exception) {
                        recorder?.release()
                        recorder = null
                        result.success(currentRecordPath)
                    }
                }
                "pickMediaAndExtractAudio" -> {
                    pendingFileResult = result
                    pendingIsVideo = call.argument<Boolean>("isVideo") ?: false
                    val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                        type = if (pendingIsVideo) "video/*" else "audio/*"
                        addCategory(Intent.CATEGORY_OPENABLE)
                    }
                    startActivityForResult(Intent.createChooser(intent, "Select Media"), 701)
                }
                "extractAudioFromUri" -> {
                    val u = call.argument<String>("uri") ?: ""
                    if (u.startsWith("content://")) {
                        result.success(copyUriAndExtractAudio(Uri.parse(u), true))
                    } else {
                        result.success(extractAudioTrackHardware(u))
                    }
                }
                "getInitialSharedMedia" -> {
                    val s = initialSharedMedia
                    initialSharedMedia = null
                    result.success(s)
                }
                "resolveAndExtractUrlNative" -> {
                    val u = call.argument<String>("url") ?: ""
                    resolveAndExtractUrlNative(u, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        tts?.stop()
        tts?.shutdown()
        recorder?.release()
        super.onDestroy()
    }
}
KT_EOF

echo "✅ Created clean standalone MainActivity.kt!"
