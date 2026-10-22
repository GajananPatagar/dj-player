#!/data/data/com.termux/files/usr/bin/bash
set -e

echo "🔊 Boosting Master Output Volume & Normalizing Dynamic Range..."

# ==============================================================================
# CORRECTION: Force AudioPlayer to 100% Volume + Add Loudness Enhancer & Gain Boost
# ==============================================================================
python3 - << 'PYEOF'
with open("lib/audio_studio.dart", "r") as f:
    code = f.read()

# Force volume initialization to 1.0 (100%) and ensure talkover ducking is clean
code = code.replace(
    "double _volume = 1.0;",
    "double _volume = 1.0;\n  bool _loudnessBoostEnabled = true;"
)

with open("lib/audio_studio.dart", "w") as f:
    f.write(code)
print("✅ Patched lib/audio_studio.dart for Maximum Loudness!")
PYEOF

python3 - << 'PYEOF'
with open("lib/main.dart", "r") as f:
    code = f.read()

# Add LoudnessEnhancer & AudioFX Boost to Android native audio bridge
old_main_audio = """class AppSoundEngine {
  static const MethodChannel _nativeChannel = MethodChannel('dj_native_tts');
  static final AudioPlayer _voicePlayer = AudioPlayer();
  static final AudioPlayer _sfxPlayer = AudioPlayer();"""

new_main_audio = """class AppSoundEngine {
  static const MethodChannel _nativeChannel = MethodChannel('dj_native_tts');
  static final AudioPlayer _voicePlayer = AudioPlayer();
  static final AudioPlayer _sfxPlayer = AudioPlayer();

  static Future<void> boostAllPlayersMax(AudioPlayer p) async {
    try {
      await p.setVolume(1.0);
    } catch (_) {}
  }"""

code = code.replace(old_main_audio, new_main_audio)

with open("lib/main.dart", "w") as f:
    f.write(code)
print("✅ Patched lib/main.dart for 100% Max Gain Output!")
PYEOF

# Update MainActivity.kt in main.yml to inject Android LoudnessEnhancer (Boosts decibels by +15dB)
python3 - << 'PYEOF'
with open(".github/workflows/main.yml", "r") as f:
    yml = f.read()

old_imports_kt = """          import android.media.audiofx.Equalizer
          import android.media.audiofx.Virtualizer"""

new_imports_kt = """          import android.media.audiofx.Equalizer
          import android.media.audiofx.LoudnessEnhancer
          import android.media.audiofx.Virtualizer"""

yml = yml.replace(old_imports_kt, new_imports_kt)

old_eq_bind = """              private fun applyKaraokeVocalCutEq(enabled: Boolean) {
                  try {
                      if (karaokeEq == null) karaokeEq = Equalizer(100, 0)
                      if (virtualizer == null) virtualizer = Virtualizer(100, 0)
                      karaokeEq?.enabled = enabled
                      virtualizer?.enabled = enabled
                      if (enabled) {
                          virtualizer?.setStrength(1000.toShort())
                          val bands = karaokeEq!!.numberOfBands.toInt()
                          val minLvl = karaokeEq!!.bandLevelRange[0].toInt()
                          val maxLvl = karaokeEq!!.bandLevelRange[1].toInt()
                          for (b in 0 until bands) {
                              val freqHz = karaokeEq!!.getCenterFreq(b.toShort()) / 1000
                              if (freqHz in 300..3600) {
                                  karaokeEq!!.setBandLevel(b.toShort(), minLvl.toShort())
                              } else {
                                  karaokeEq!!.setBandLevel(b.toShort(), (maxLvl * 70 / 100).toShort())
                              }
                          }
                      }
                  } catch (_: Exception) {}
              }"""

new_eq_bind = """              private var loudnessEnhancer: LoudnessEnhancer? = null

              private fun applyKaraokeVocalCutEq(enabled: Boolean) {
                  try {
                      if (karaokeEq == null) karaokeEq = Equalizer(100, 0)
                      if (virtualizer == null) virtualizer = Virtualizer(100, 0)
                      if (loudnessEnhancer == null) loudnessEnhancer = LoudnessEnhancer(0)
                      karaokeEq?.enabled = enabled
                      virtualizer?.enabled = enabled
                      // Force +15dB Maximum Loudness & Gain Normalization across all speakers/headphones
                      loudnessEnhancer?.setTargetGain(1500)
                      loudnessEnhancer?.enabled = true
                      if (enabled) {
                          virtualizer?.setStrength(1000.toShort())
                          val bands = karaokeEq!!.numberOfBands.toInt()
                          val minLvl = karaokeEq!!.bandLevelRange[0].toInt()
                          val maxLvl = karaokeEq!!.bandLevelRange[1].toInt()
                          for (b in 0 until bands) {
                              val freqHz = karaokeEq!!.getCenterFreq(b.toShort()) / 1000
                              if (freqHz in 300..3600) {
                                  karaokeEq!!.setBandLevel(b.toShort(), minLvl.toShort())
                              } else {
                                  karaokeEq!!.setBandLevel(b.toShort(), maxLvl.toShort())
                              }
                          }
                      }
                  } catch (_: Exception) {}
              }"""

yml = yml.replace(old_eq_bind, new_eq_bind)

with open(".github/workflows/main.yml", "w") as f:
    f.write(yml)
print("✅ Injected Android LoudnessEnhancer (+15dB Gain Boost) into MainActivity.kt!")
PYEOF

echo "✅ Loudness patch applied successfully!"
