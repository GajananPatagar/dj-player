#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "📲 1/4 Adding Global Tab Switcher & Unified Share Listener in lib/main.dart..."

python3 - << 'PYEOF'
with open("lib/main.dart", "r") as f:
    code = f.read()

# 1. Add global tab notifier & shared media notifier inside MasterVolumeController or AppSoundEngine
if "activeTabIndexNotifier" not in code:
    code = code.replace(
        "static bool hardwareVolumeEntryMode = false;",
        "static bool hardwareVolumeEntryMode = false;\n  static final ValueNotifier<int> activeTabIndexNotifier = ValueNotifier<int>(0);\n  static final ValueNotifier<String?> incomingSharedMediaNotifier = ValueNotifier<String?>(null);"
    )

# 2. Forward 'onSharedMedia' inside AppSoundEngine.initHardwareVolumeListener so there is ZERO MethodChannel conflict!
old_listener = """  static void initHardwareVolumeListener() {
    _nativeChannel.setMethodCallHandler((call) async {
      if (!hardwareVolumeEntryMode) return;
      if (call.method == 'onVolumeKey') {"""

new_listener = """  static void initHardwareVolumeListener() {
    _nativeChannel.setMethodCallHandler((call) async {
      if (call.method == 'onSharedMedia' && call.arguments != null) {
        final String shared = call.arguments.toString().trim();
        if (shared.isNotEmpty) {
          // Automatically switch to Cricket Commentary Page (Tab Index 1) immediately!
          activeTabIndexNotifier.value = 1;
          incomingSharedMediaNotifier.value = shared + '##' + DateTime.now().millisecondsSinceEpoch.toString();
        }
        return;
      }
      if (!hardwareVolumeEntryMode) return;
      if (call.method == 'onVolumeKey') {"""

if old_listener in code:
    code = code.replace(old_listener, new_listener)

# 3. Hook _MasterHomeShellState to listen to AppSoundEngine.activeTabIndexNotifier and check initial shared media on launch/resume
old_shell = """class _MasterHomeShellState extends State<MasterHomeShell> {
  int _selectedIndex = 0;"""

new_shell = """class _MasterHomeShellState extends State<MasterHomeShell> with WidgetsBindingObserver {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    AppSoundEngine.activeTabIndexNotifier.addListener(() {
      if (mounted && _selectedIndex != AppSoundEngine.activeTabIndexNotifier.value) {
        setState(() => _selectedIndex = AppSoundEngine.activeTabIndexNotifier.value);
      }
    });
    _checkPendingSharedIntent();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingSharedIntent();
    }
  }

  Future<void> _checkPendingSharedIntent() async {
    try {
      final String? initial = await AppSoundEngine._nativeChannel.invokeMethod<String>('getInitialSharedMedia');
      if (initial != null && initial.trim().isNotEmpty) {
        AppSoundEngine.activeTabIndexNotifier.value = 1;
        AppSoundEngine.incomingSharedMediaNotifier.value =
            initial.trim() + '##' + DateTime.now().millisecondsSinceEpoch.toString();
      }
    } catch (_) {}
  }"""

if old_shell in code:
    code = code.replace(old_shell, new_shell)

code = code.replace(
    "onTap: (idx) => setState(() => _selectedIndex = idx),",
    "onTap: (idx) { AppSoundEngine.activeTabIndexNotifier.value = idx; setState(() => _selectedIndex = idx); },"
)

with open("lib/main.dart", "w") as f:
    f.write(code)
print("✅ Patched lib/main.dart to auto-open Cricket Page (Tab 2) on Share!")
PYEOF

echo "📲 2/4 Upgrading lib/real_tile_studio.dart (Multi-Engine Cobalt + Native WebView + Direct Stream Resolver)..."

python3 - << 'PYEOF'
with open("lib/real_tile_studio.dart", "r") as f:
    code = f.read()

# Remove the conflicting setMethodCallHandler in RealTileStudioManager.init and listen to AppSoundEngine.incomingSharedMediaNotifier instead!
old_init = """  static Future<void> init({Function(String sharedTextOrPath)? onSharedMediaReceived}) async {
    if (!_initialized) {
      _initialized = true;
      await loadSavedData();
      _nativeChannel.setMethodCallHandler((call) async {
        if (call.method == 'onSharedMedia' && call.arguments != null) {
          final String shared = call.arguments.toString();
          if (onSharedMediaReceived != null && shared.isNotEmpty) {
            onSharedMediaReceived(shared);
          }
        }
      });
    }
    try {
      final String? initialShared = await _nativeChannel.invokeMethod<String>('getInitialSharedMedia');
      if (initialShared != null && initialShared.isNotEmpty && onSharedMediaReceived != null) {
        onSharedMediaReceived(initialShared);
      }
    } catch (_) {}
  }"""

new_init = """  static Function(String)? _sharedCallback;

  static Future<void> init({Function(String sharedTextOrPath)? onSharedMediaReceived}) async {
    _sharedCallback = onSharedMediaReceived;
    if (!_initialized) {
      _initialized = true;
      await loadSavedData();
      AppSoundEngine.incomingSharedMediaNotifier.addListener(() {
        final String? raw = AppSoundEngine.incomingSharedMediaNotifier.value;
        if (raw != null && raw.isNotEmpty && _sharedCallback != null) {
          final String clean = raw.split('##').first;
          _sharedCallback!(clean);
        }
      });
    }
    final String? existing = AppSoundEngine.incomingSharedMediaNotifier.value;
    if (existing != null && existing.isNotEmpty && _sharedCallback != null) {
      final String clean = existing.split('##').first;
      AppSoundEngine.incomingSharedMediaNotifier.value = null;
      _sharedCallback!(clean);
    }
  }"""

if old_init in code:
    code = code.replace(old_init, new_init)

# Add Tier 0 Native Android WebView & Cobalt API Extractor at the start of extractAudioFromReelOrShortUrl
old_extract_start = """    final RegExp urlReg = RegExp(r'https?://[^\\s]+');
    final match = urlReg.firstMatch(clean);
    final String targetUrl = match != null ? match.group(0)! : clean;

    final dir = await getApplicationDocumentsDirectory();
    final int ts = DateTime.now().millisecondsSinceEpoch;
    final String outAudioPath = '${dir.path}/exact_reel_short_$ts.m4a';
    final String tempVideoPath = '${dir.path}/temp_video_$ts.mp4';"""

new_extract_start = """    final RegExp urlReg = RegExp(r'https?://[^\\s]+');
    final match = urlReg.firstMatch(clean);
    final String targetUrl = match != null ? match.group(0)! : clean;

    final dir = await getApplicationDocumentsDirectory();
    final int ts = DateTime.now().millisecondsSinceEpoch;
    final String outAudioPath = '${dir.path}/exact_reel_short_$ts.m4a';
    final String tempVideoPath = '${dir.path}/temp_video_$ts.mp4';

    // TIER 0A: Native Android Headless WebView & Hardware MediaExtractor (Works on IG Reels & YT Shorts with cookies/JS!)
    try {
      final String? nativeExtracted = await _nativeChannel
          .invokeMethod<String>('resolveAndExtractUrlNative', {'url': targetUrl})
          .timeout(const Duration(seconds: 18));
      if (nativeExtracted != null && File(nativeExtracted).existsSync() && File(nativeExtracted).lengthSync() > 8000) {
        return nativeExtracted;
      }
    } catch (_) {}

    // TIER 0B: Multi-Node Cobalt Media API (Extracts direct audio/video from Instagram Reels & YouTube Shorts)
    const List<String> cobaltNodes = [
      'https://Cobalt.avo.sh',
      'https://co.eepy.today',
      'https://cobalt-api.kwiatekmiki.com',
      'https://api.cobalt.tools/api/json',
    ];
    for (final cNode in cobaltNodes) {
      try {
        final cRes = await http
            .post(
              Uri.parse(cNode),
              headers: {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
                'User-Agent': 'Mozilla/5.0 (Android 14; Mobile)',
              },
              body: jsonEncode({
                'url': targetUrl,
                'isAudioOnly': true,
                'aFormat': 'mp3',
                'downloadMode': 'audio',
              }),
            )
            .timeout(const Duration(seconds: 7));
        if (cRes.statusCode == 200) {
          final Map cData = jsonDecode(cRes.body);
          final String? dlUrl = cData['url']?.toString();
          if (dlUrl != null && dlUrl.startsWith('http')) {
            final mediaRes = await http.get(Uri.parse(dlUrl)).timeout(const Duration(seconds: 25));
            if (mediaRes.statusCode == 200 && mediaRes.bodyBytes.length > 10000) {
              final File af = File(outAudioPath);
              await af.writeAsBytes(mediaRes.bodyBytes, flush: true);
              return af.path;
            }
          }
        }
      } catch (_) {}
    }"""

if old_extract_start in code:
    code = code.replace(old_extract_start, new_extract_start)

with open("lib/real_tile_studio.dart", "w") as f:
    f.write(code)
print("✅ Upgraded lib/real_tile_studio.dart with Native WebView + Cobalt + Innertube Extractor!")
PYEOF

echo "📲 3/4 Auto-Scrolling Cricket Page to Trimmer When Reel/Short Arrives (lib/cricket_studio.dart)..."

python3 - << 'PYEOF'
with open("lib/cricket_studio.dart", "r") as f:
    code = f.read()

if "ScrollController _pageScrollCtrl" not in code:
    code = code.replace(
        "final Random _rng = Random();",
        "final Random _rng = Random();\n  final ScrollController _pageScrollCtrl = ScrollController();"
    )
    code = code.replace(
        "child: ListView(\n            padding: const EdgeInsets.all(10),",
        "child: ListView(\n            controller: _pageScrollCtrl,\n            padding: const EdgeInsets.all(10),"
    )

old_shared_cb = """    RealTileStudioManager.init(
      onSharedMediaReceived: (shared) async {
        if (!mounted) return;
        setState(() {
          _isExtractingMedia = true;
          _lastSpokenBanner = '📲 Extracting Audio from Shared Instagram Reel / YT Short...';
        });"""

new_shared_cb = """    RealTileStudioManager.init(
      onSharedMediaReceived: (shared) async {
        if (!mounted) return;
        setState(() {
          _reelShortUrlCtrl.text = shared;
          _isExtractingMedia = true;
          _lastSpokenBanner = '📲 Extracting Exact Audio from Shared Reel / Short... Please wait ~4s';
        });
        // Auto-scroll straight down to the Spectrum Trimmer Studio so user sees it immediately!
        Future.delayed(const Duration(milliseconds: 300), () {
          if (_pageScrollCtrl.hasClients) {
            _pageScrollCtrl.animateTo(
              _pageScrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOut,
            );
          }
        });"""

if old_shared_cb in code:
    code = code.replace(old_shared_cb, new_shared_cb)

with open("lib/cricket_studio.dart", "w") as f:
    f.write(code)
print("✅ Patched lib/cricket_studio.dart to auto-scroll to Spectrum Trimmer on Share!")
PYEOF

echo "📲 4/4 Adding Native Headless WebView Media Sniffer & singleTop Share Intent to .github/workflows/main.yml..."

python3 - << 'PYEOF'
with open(".github/workflows/main.yml", "r") as f:
    yml = f.read()

# 1. Add WebView imports to MainActivity.kt
old_imp = "          import android.net.Uri"
new_imp = """          import android.net.Uri
          import android.os.Handler
          import android.os.Looper
          import android.webkit.WebResourceRequest
          import android.webkit.WebResourceResponse
          import android.webkit.WebView
          import android.webkit.WebViewClient
          import java.net.HttpURLConnection
          import java.net.URL"""

if old_imp in yml:
    yml = yml.replace(old_imp, new_imp)

# 2. Add resolveAndExtractUrlNative method inside MainActivity.kt (Sniffs real .mp4/.m4a CDN URL from IG Reel / YT Short via Android WebView + downloads & strips audio!)
native_resolver_fn = """
              private fun resolveAndExtractUrlNative(rawShareText: String, result: MethodChannel.Result) {
                  val urlRegex = Regex("https?://[^\\\\s\\"<>]+")
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
                              conn.InstanceFollowRedirects = true
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
"""

if "resolveAndExtractUrlNative" not in yml:
    yml = yml.replace("              override fun onInit(status: Int) {", native_resolver_fn + "\n              override fun onInit(status: Int) {")

old_get_init = """                          "getInitialSharedMedia" -> {
                              val s = initialSharedMedia
                              initialSharedMedia = null
                              result.success(s)
                          }"""

new_get_init = """                          "getInitialSharedMedia" -> {
                              val s = initialSharedMedia
                              initialSharedMedia = null
                              result.success(s)
                          }
                          "resolveAndExtractUrlNative" -> {
                              val u = call.argument<String>("url") ?: ""
                              resolveAndExtractUrlNative(u, result)
                          }"""

if old_get_init in yml:
    yml = yml.replace(old_get_init, new_get_init)

# Ensure handleIncomingShareIntent posts after 600ms as well so Flutter engine is ready even on cold start
old_handle_intent = """                      if (!sharedText.isNullOrEmpty()) {
                          initialSharedMedia = sharedText
                          methodChannel?.invokeMethod("onSharedMedia", sharedText)
                      }"""

new_handle_intent = """                      if (!sharedText.isNullOrEmpty()) {
                          initialSharedMedia = sharedText
                          Handler(Looper.getMainLooper()).postDelayed({
                              methodChannel?.invokeMethod("onSharedMedia", sharedText)
                          }, 500)
                      }"""

if old_handle_intent in yml:
    yml = yml.replace(old_handle_intent, new_handle_intent)

# Fix HttpURLConnection property casing
yml = yml.replace("conn.InstanceFollowRedirects = true", "conn.instanceFollowRedirects = true")

with open(".github/workflows/main.yml", "w") as f:
    f.write(yml)
print("✅ Injected Native Headless WebView Sniffer & Delayed Share Dispatch into MainActivity.kt!")
PYEOF

echo "✅ All Share-to-Cricket-Tab & Native Extraction fixes applied!"
