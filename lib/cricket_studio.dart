import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'voice_and_pro_hub.dart';

class CricketCommentaryScreen extends StatefulWidget {
  const CricketCommentaryScreen({super.key});

  @override
  State<CricketCommentaryScreen> createState() => _CricketCommentaryScreenState();
}

class _CricketCommentaryScreenState extends State<CricketCommentaryScreen> {
  final FlutterTts _tts = FlutterTts();
  final AudioPlayer _cloudVoicePlayer = AudioPlayer();
  final Random _rng = Random();

  final TextEditingController _teamACtrl = TextEditingController(text: 'Karnataka Lions');
  final TextEditingController _teamBCtrl = TextEditingController(text: 'Mumbai Warriors');
  final TextEditingController _squadACtrl = TextEditingController(
      text: 'Virat Kohli, KL Rahul, Rajat Patidar, Glenn Maxwell, Devdutt Padikkal, Dinesh Karthik, Mayank Agarwal, Shreyas Gopal, Prasidh Krishna, Mohammed Siraj, Vyshak Vijaykumar');
  final TextEditingController _squadBCtrl = TextEditingController(
      text: 'Rohit Sharma, Jasprit Bumrah, Hardik Pandya, Suryakumar Yadav, Ishan Kishan, Ravindra Jadeja, Kuldeep Yadav, Mohammed Shami, Axar Patel, Arshdeep Singh, Yuzvendra Chahal');

  List<String> _squadA = [];
  List<String> _squadB = [];

  String _striker = 'Virat Kohli';
  String _nonStriker = 'KL Rahul';
  String _bowler = 'Jasprit Bumrah';
  String _wk = 'Ishan Kishan';
  String _fielder = 'Ravindra Jadeja';
  String _commLanguage = 'KANNADA'; // KANNADA, HINDI, ENGLISH

  int _runs = 0;
  int _wickets = 0;
  int _legalBalls = 0;
  bool _freeHit = false;
  List<String> _thisOver = [];
  final List<String> _feed = [];
  final Set<String> _usedTournamentLines = {};

  @override
  void initState() {
    super.initState();
    _loadSquads();
  }

  void _loadSquads() {
    _squadA = _squadACtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    _squadB = _squadBCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (_squadA.isNotEmpty && !_squadA.contains(_striker)) _striker = _squadA[0];
    if (_squadA.length > 1 && !_squadA.contains(_nonStriker)) _nonStriker = _squadA[1];
    if (_squadB.isNotEmpty && !_squadB.contains(_wk)) _wk = _squadB[0];
    if (_squadB.length > 1 && !_squadB.contains(_bowler)) _bowler = _squadB[1];
    if (_squadB.length > 2 && !_squadB.contains(_fielder)) _fielder = _squadB[2];
    setState(() {});
  }

  void _swapStrike() {
    setState(() {
      final tmp = _striker;
      _striker = _nonStriker;
      _nonStriker = tmp;
    });
  }

  String _oversText() {
    return (_legalBalls ~/ 6).toString() + '.' + (_legalBalls % 6).toString();
  }

  String _generateNonRepeatingLine(String eventType) {
    final teamA = _teamACtrl.text.trim();
    List<String> pool = [];

    if (_commLanguage == 'KANNADA') {
      switch (eventType) {
        case 'SIX':
          pool = [
            'ಅದ್ಭುತವಾದ ಸಿಕ್ಸರ್! ' + _bowler + ' ಎಸೆದ ಚೆಂಡನ್ನು ' + _striker + ' ಸ್ಟೇಡಿಯಂ ಆಚೆಗಟ್ಟಿದ್ದಾರೆ! ಪ್ರೇಕ್ಷಕರಲ್ಲಿ ಭಾರೀ ಸಂಭ್ರಮ!',
            'ಬೃಹತ್ ಸಿಕ್ಸರ್! ' + _striker + ' ಅವರ ಬ್ಯಾಟ್‌ನಿಂದ ಸಿಡಿದ ಚೆಂಡು ನೇರವಾಗಿ ಗ್ಯಾಲರಿಗೆ ಹೋಗಿ ಬಿದ್ದಿದೆ! ಆರು ರನ್‌ಗಳು!',
            'ಎಂತಹ ಹೊಡೆತ! ' + _bowler + ' ಅವರ ಬೌಲಿಂಗ್‌ನಲ್ಲಿ ' + _striker + ' ಭರ್ಜರಿ ಸಿಕ್ಸರ್ ಬಾರಿಸಿದ್ದಾರೆ! ' + teamA + ' ತಂಡಕ್ಕೆ ಆರು ರನ್!'
          ];
          break;
        case 'FOUR':
          pool = [
            'ಮನೋಹರವಾದ ಬೌಂಡರಿ! ' + _striker + ' ಹೊಡೆದ ಚೆಂಡನ್ನು ತಡೆಯಲು ಫೀಲ್ಡರ್ ' + _fielder + ' ಡೈವ್ ಮಾಡಿದರೂ ಸಾಧ್ಯವಾಗಲಿಲ್ಲ! ನಾಲ್ಕು ರನ್‌ಗಳು!',
            'ಸೂಪರ್ ಕವರ್ ಡ್ರೈವ್! ' + _bowler + ' ಎಸೆತಕ್ಕೆ ' + _striker + ' ಬ್ಯಾಟ್‌ನಿಂದ ಮಿಂಚಿನ ವೇಗದ ಬೌಂಡರಿ!',
            'ಗ್ಯಾಪ್‌ನಲ್ಲಿ ಅದ್ಭುತ ಹೊಡೆತ! ' + _fielder + ' ಚೆಂಡನ್ನು ಬೆನ್ನಟ್ಟಿದರೂ ಚೆಂಡು ಬೌಂಡರಿ ಗೆರೆ ದಾಟಿದೆ! ನಾಲ್ಕು ರನ್!'
          ];
          break;
        case 'BOWLED':
          pool = [
            'ಬ್ಯಾಟರಿ ಬೋಲ್ಡ್! ಕ್ಲೀನ್ ಬೌಲ್ಡ್! ' + _bowler + ' ಎಸೆದ ವೇಗದ ಯಾರ್ಕರ್‌ಗೆ ' + _striker + ' ಅವರ ಸ್ಟಂಪ್ಸ್ ಹಾರಿಹೋಗಿದೆ! ವಿಕೆಟ್ ಕೀಪರ್ ' + _wk + ' ಸಂಭ್ರಮಿಸುತ್ತಿದ್ದಾರೆ!',
            'ಕ್ಲೀನ್ ಬೌಲ್ಡ್! ಎಂತಹ ಅದ್ಭುತ ಎಸೆತ! ' + _bowler + ' ಅವರ ಬೆಂಕಿಯಂತಹ ಚೆಂಡು ನೇರವಾಗಿ ವಿಕೆಟ್‌ಗೆ ಬಡಿದಿದೆ! ' + _striker + ' ಪೆವಿಲಿಯನ್ ಕಡೆಗೆ ನಡೆಯುತ್ತಿದ್ದಾರೆ!',
            'ಬ್ಯಾಟರಿ ಬೋಲ್ಡ್! ಮಿಡಲ್ ಸ್ಟಂಪ್ ಉರುಳಿಬಿದ್ದಿದೆ! ' + _bowler + ' ಅವರಿಗೆ ಭರ್ಜರಿ ವಿಕೆಟ್!'
          ];
          break;
        case 'CAUGHT':
          pool = [
            'ಗಾಳಿಯಲ್ಲಿ ಚೆಂಡು ಮತ್ತು ಅದ್ಭುತ ಕ್ಯಾಚ್! ' + _striker + ' ಹೊಡೆದ ಚೆಂಡನ್ನು ಫೀಲ್ಡರ್ ' + _fielder + ' ಯಾವುದೇ ತಪ್ಪಿಲ್ಲದೆ ಹಿಡಿದಿದ್ದಾರೆ! ' + _bowler + 'ಗೆ ವಿಕೆಟ್!',
            'ಸೂಪರ್ ಡೈವಿಂಗ್ ಕ್ಯಾಚ್! ' + _fielder + ' ಹಾರಿ ಹಿಡಿದ ಅದ್ಭುತ ಕ್ಯಾಚ್‌ಗೆ ' + _striker + ' ಔಟ್ ಆಗಿದ್ದಾರೆ!'
          ];
          break;
        case 'CAUGHT_WK':
          pool = [
            'ಬ್ಯಾಟ್‌ನ ಅಂಚಿಗೆ ತಗುಲಿ ವಿಕೆಟ್ ಕೀಪರ್ ಕೈ ಸೇರಿದೆ! ' + _bowler + ' ಎಸೆತದಲ್ಲಿ ವಿಕೆಟ್ ಕೀಪರ್ ' + _wk + ' ಅದ್ಭುತ ಕ್ಯಾಚ್ ಹಿಡಿದಿದ್ದಾರೆ! ' + _striker + ' ಔಟ್!',
            'ಕಾಟ್ ಬಿಹೈಂಡ್! ವಿಕೆಟ್ ಹಿಂದೆ ' + _wk + ' ಮಿಂಚಿನ ವೇಗದಲ್ಲಿ ಕ್ಯಾಚ್ ಹಿಡಿದಿದ್ದಾರೆ!'
          ];
          break;
        case 'RUN_OUT':
          pool = [
            'ಡೈರೆಕ್ಟ್ ಹಿಟ್ ರನ್ ಔಟ್! ' + _striker + ' ಮತ್ತು ' + _nonStriker + ' ನಡುವೆ ಗೊಂದಲ! ಫೀಲ್ಡರ್ ' + _fielder + ' ಎಸೆದ ಚೆಂಡು ನೇರವಾಗಿ ವಿಕೆಟ್‌ಗೆ ಬಡಿದಿದೆ!',
            'ರನ್ ಔಟ್! ' + _fielder + ' ವೇಗವಾಗಿ ಚೆಂಡನ್ನು ವಿಕೆಟ್ ಕೀಪರ್ ' + _wk + ' ಕೈಗೆ ನೀಡಿದ್ದಾರೆ, ' + _striker + ' ಕ್ರೀಸ್ ತಲುಪುವ ಮುನ್ನವೇ ಔಟ್!'
          ];
          break;
        case 'STUMPED':
          pool = [
            'ಮಿಂಚಿನ ಸ್ಟಂಪಿಂಗ್! ' + _striker + ' ಮುಂದೆ ಬಂದು ಹೊಡೆಯಲು ಪ್ರಯತ್ನಿಸಿದರು, ಆದರೆ ವಿಕೆಟ್ ಕೀಪರ್ ' + _wk + ' ಕ್ಷಣಮಾತ್ರದಲ್ಲಿ ಬೇಲ್ಸ್ ಹಾರಿಸಿದ್ದಾರೆ!',
          ];
          break;
        case 'LBW':
          pool = [
            'ಜೋರಾದ ಅಪೀಲ್ ಮತ್ತು ಅಂಪೈರ್ ಬೆರಳು ಎತ್ತಿದ್ದಾರೆ! ಎಲ್‌ಬಿಡಬ್ಲ್ಯೂ ಔಟ್! ' + _bowler + ' ಎಸೆತ ನೇರವಾಗಿ ' + _striker + ' ಪ್ಯಾಡ್‌ಗೆ ಬಡಿದಿದೆ!'
          ];
          break;
        case 'NO_BALL':
          pool = [
            'ನೋ ಬಾಲ್ ಸೈರನ್ ಮೊಳಗಿದೆ! ' + _bowler + ' ಕ್ರೀಸ್ ಗೆರೆ ದಾಟಿದ್ದಾರೆ! ಒಂದು ಹೆಚ್ಚುವರಿ ರನ್ ಮತ್ತು ಮುಂದಿನ ಎಸೆತ ಫ್ರೀ ಹಿಟ್ ಆಗಿರುತ್ತದೆ!'
          ];
          break;
        case 'WIDE':
          pool = [
            'ವೈಡ್ ಬಾಲ್! ' + _bowler + ' ಲೆಗ್ ಸೈಡ್ ಆಚೆ ಎಸೆದಿದ್ದಾರೆ, ವಿಕೆಟ್ ಕೀಪರ್ ' + _wk + ' ಡೈವ್ ಮಾಡಿ ಚೆಂಡನ್ನು ತಡೆದಿದ್ದಾರೆ! ಒಂದು ಹೆಚ್ಚುವರಿ ರನ್!'
          ];
          break;
        case 'RUN_1':
          pool = [
            'ಚುರುಕಾದ ಒಂದು ರನ್! ' + _striker + ' ಚೆಂಡನ್ನು ಗ್ಯಾಪ್‌ನಲ್ಲಿ ತಳ್ಳಿ ' + _nonStriker + ' ಜೊತೆ ವೇಗವಾಗಿ ಸ್ಟ್ರೈಕ್ ಬದಲಾಯಿಸಿದ್ದಾರೆ!'
          ];
          break;
        case 'RUN_2':
          pool = [
            'ಅದ್ಭುತ ಓಟ! ' + _striker + ' ಮತ್ತು ' + _nonStriker + ' ಫೀಲ್ಡರ್ ' + _fielder + ' ಚೆಂಡನ್ನು ಎಸೆಯುವಷ್ಟರಲ್ಲಿ ಎರಡು ರನ್ ಪೂರೈಸಿದ್ದಾರೆ!'
          ];
          break;
        default:
          pool = [
            'ಡಾಟ್ ಬಾಲ್! ' + _bowler + ' ಅವರ ನಿಖರವಾದ ಎಸೆತವನ್ನು ' + _striker + ' ರಕ್ಷಣಾತ್ಮಕವಾಗಿ ಆಡಿದ್ದಾರೆ. ಯಾವುದೇ ರನ್ ಇಲ್ಲ!'
          ];
      }
    } else if (_commLanguage == 'HINDI') {
      switch (eventType) {
        case 'SIX':
          pool = [
            'शानदार छक्का! ' + _bowler + ' की गेंद पर ' + _striker + ' का गगनचुंबी प्रहार! गेंद सीधा स्टेडियम के बाहर छह रनों के लिए!',
            'धमाकेदार सिक्सर! ' + _striker + ' ने फ्रंट फुट हटाया और गेंद को दर्शकों के बीच पहुंचा दिया! कमाल की बल्लेबाज़ी!',
            'बल्ले के बीचो-बीच लगी गेंद! ' + _fielder + ' सिर्फ दर्शक बनकर देखते रह गए और गेंद सीमा रेखा के पार छह रन!'
          ];
          break;
        case 'FOUR':
          pool = [
            'कड़क चौका! ' + _striker + ' का लाजवाब कवर ड्राइव, फील्डर ' + _fielder + ' ने डाइव लगाई लेकिन गेंद गोली की रफ़्तार से बाउंड्री के पार!',
            'शानदार टाइमिंग! ' + _bowler + ' की गेंद को ' + _striker + ' ने गैप में पिरोया और चार रन बटोरे!'
          ];
          break;
        case 'BOWLED':
          pool = [
            'बैटरी बोल्ड! क्लीन बोल्ड! ' + _bowler + ' की सटीक यॉर्कर ने ' + _striker + ' के स्टंप्स हवा में उड़ा दिए! गिल्लियां विकेटकीपर ' + _wk + ' के पास जा गिरीं!',
            'डंडे बिखर गए! बैटरी बोल्ड! ' + _bowler + ' की रफ़्तार का ' + _striker + ' के पास कोई जवाब नहीं था! बोल्ड होकर पवेलियन लौटते हुए!'
          ];
          break;
        case 'CAUGHT':
          pool = [
            'हवा में गेंद और शानदार कैच! ' + _striker + ' ने बड़ा शॉट खेलने की कोशिश की लेकिन फील्डर ' + _fielder + ' ने बाउंड्री पर बेहतरीन कैच लपका!',
            'क्या कैच पकड़ा है ' + _fielder + ' ने! ' + _bowler + ' को मिली बड़ी सफलता, ' + _striker + ' आउट!'
          ];
          break;
        case 'CAUGHT_WK':
          pool = [
            'बल्ले का बाहरी किनारा और विकेटकीपर ' + _wk + ' के दस्तानों में सुरक्षित कैच! ' + _bowler + ' की शानदार गेंद पर ' + _striker + ' आउट!'
          ];
          break;
        case 'RUN_OUT':
          pool = [
            'डायरेक्ट हिट और रन आउट! ' + _striker + ' और ' + _nonStriker + ' के बीच तालमेल की कमी, फील्डर ' + _fielder + ' का सीधा थ्रो स्टंप्स पर लगा!'
          ];
          break;
        case 'STUMPED':
          pool = [
            'बिजली की रफ़्तार से स्टंपिंग! ' + _striker + ' क्रीज़ से बाहर निकले और विकेटकीपर ' + _wk + ' ने पलक झपकते ही गिल्लियां बिखेर दीं!'
          ];
          break;
        case 'LBW':
          pool = [
            'ज़ोरदार अपील और अंपायर की उंगली हवा में! एलबीडब्ल्यू आउट! ' + _bowler + ' ने ' + _striker + ' को सीधा स्टंप्स के सामने फंसाया!'
          ];
          break;
        case 'NO_BALL':
          pool = [
            'नो बॉल का सायरन बजा! ' + _bowler + ' का पैर क्रीज़ से बाहर! एक अतिरिक्त रन और अगली गेंद होगी फ्री हिट!'
          ];
          break;
        case 'WIDE':
          pool = [
            'वाइड बॉल! ' + _bowler + ' ने दिशा भटकी, विकेटकीपर ' + _wk + ' ने शानदार बचाव किया! एक अतिरिक्त रन!'
          ];
          break;
        case 'RUN_1':
          pool = [
            'हल्के हाथों से खेला ' + _striker + ' ने और ' + _nonStriker + ' के साथ तेज़ी से दौड़कर एक रन पूरा किया!'
          ];
          break;
        case 'RUN_2':
          pool = [
            'गैप में शॉट और तेज़ दौड़! ' + _fielder + ' के थ्रो से पहले ' + _striker + ' और ' + _nonStriker + ' ने दो रन पूरे किए!'
          ];
          break;
        default:
          pool = [
            'डॉट बॉल! ' + _bowler + ' की सटीक लाइन और लेंथ, ' + _striker + ' ने सम्मान दिया। कोई रन नहीं!'
          ];
      }
    } else {
      switch (eventType) {
        case 'SIX':
          pool = [
            'MONSTER MAXIMUM! ' + _striker + ' picks up the length from ' + _bowler + ' and launches it high into the upper tier for SIX!',
            'OUT OF THE PARK! ' + _striker + ' clears the front leg and smashes ' + _bowler + ' over ' + _fielder + ' for a massive SIX!'
          ];
          break;
        case 'FOUR':
          pool = [
            'CRACKING FOUR! ' + _striker + ' threads the cover drive past a diving ' + _fielder + ' for a scorching boundary!'
          ];
          break;
        case 'BOWLED':
          pool = [
            'BATTERY BOLD! CLEAN BOWLED! TIMBER! ' + _bowler + ' fires an unplayable yorker that shatters ' + _striker + 's stumps right in front of keeper ' + _wk + '!',
            'CASTLED HIM! BATTERY BOLD! ' + _bowler + ' uproots the middle stump! What a sensational delivery!'
          ];
          break;
        case 'CAUGHT':
          pool = [
            'TAKEN IN THE DEEP! ' + _striker + ' mistimes the lofted drive and ' + _fielder + ' pouches a clinical catch off ' + _bowler + '!'
          ];
          break;
        case 'CAUGHT_WK':
          pool = [
            'EDGED AND TAKEN! ' + _bowler + ' finds the outside edge of ' + _striker + ' and wicketkeeper ' + _wk + ' takes a flying catch!'
          ];
          break;
        case 'RUN_OUT':
          pool = [
            'DIRECT HIT RUN OUT! Brilliant throw from ' + _fielder + ' to keeper ' + _wk + ' catches ' + _striker + ' short of the crease!'
          ];
          break;
        case 'STUMPED':
          pool = [
            'LIGHTNING STUMPING BY ' + _wk + '! ' + _striker + ' danced down the track to ' + _bowler + ' and missed completely!'
          ];
          break;
        case 'LBW':
          pool = [
            'PLUMB IN FRONT! LBW! ' + _bowler + ' traps ' + _striker + ' dead in front of middle stump!'
          ];
          break;
        case 'NO_BALL':
          pool = [
            'SIREN BLARES! NO BALL! ' + _bowler + ' oversteps the crease! Free Hit coming up next ball for ' + _striker + '!'
          ];
          break;
        case 'WIDE':
          pool = [
            'WIDE SIGNALED! ' + _bowler + ' sprays it past ' + _striker + ' and keeper ' + _wk + ' dives to stop it!'
          ];
          break;
        case 'RUN_1':
          pool = [
            'Smart single by ' + _striker + ' into the gap! ' + _nonStriker + ' rotates onto strike.'
          ];
          break;
        case 'RUN_2':
          pool = [
            'Punched into the pocket by ' + _striker + '! They sprint back hard for two runs before ' + _fielder + ' can relay the throw!'
          ];
          break;
        default:
          pool = [
            'Solid front-foot defense by ' + _striker + ' back to ' + _bowler + '. Dot ball pressure building!'
          ];
      }
    }

    String chosen = pool[_rng.nextInt(pool.length)];
    if (_usedTournamentLines.contains(chosen)) {
      chosen = chosen + ' (' + _oversText() + ' ಓವರ್ / Over)';
    }
    _usedTournamentLines.add(chosen);
    return chosen;
  }

  Future<void> _speakWithClonedVoice(String text) async {
    final profile = VoiceCloneProfileStore.activeProfile;
    String langCode = 'kn-IN';
    String tlParam = 'kn';
    if (_commLanguage == 'HINDI') {
      langCode = 'hi-IN';
      tlParam = 'hi';
    } else if (_commLanguage == 'ENGLISH') {
      langCode = 'en-IN';
      tlParam = 'en';
    }

    try {
      await _tts.setLanguage(langCode);
      await _tts.setPitch(profile.pitch);
      await _tts.setSpeechRate(profile.speed);
      await _tts.speak(text);
    } catch (_) {}

    // Cloud Neural Voice Fallback so Kannada/Hindi works even if local TTS voice pack is missing
    if (profile.useCloudNeuralBackup) {
      try {
        final safeQuery = Uri.encodeComponent(text.length > 180 ? text.substring(0, 180) : text);
        final url = 'https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=' + tlParam + '&q=' + safeQuery;
        await _cloudVoicePlayer.play(UrlSource(url));
        await _cloudVoicePlayer.setPlaybackRate(profile.speed.clamp(0.7, 1.4));
      } catch (_) {}
    }
  }

  void _triggerBall(String eventType) {
    bool legal = true;
    bool rotate = false;
    bool isWicket = false;
    String badge = '0';

    if (_freeHit &&
        (eventType == 'BOWLED' || eventType == 'CAUGHT' || eventType == 'CAUGHT_WK' || eventType == 'STUMPED' || eventType == 'LBW')) {
      eventType = 'DOT';
    }

    switch (eventType) {
      case 'DOT':
        badge = '0';
        break;
      case 'RUN_1':
        _runs += 1;
        rotate = true;
        badge = '1';
        break;
      case 'RUN_2':
        _runs += 2;
        badge = '2';
        break;
      case 'FOUR':
        _runs += 4;
        badge = '4';
        break;
      case 'SIX':
        _runs += 6;
        badge = '6';
        break;
      case 'BOWLED':
      case 'CAUGHT':
      case 'CAUGHT_WK':
      case 'RUN_OUT':
      case 'STUMPED':
      case 'LBW':
        _wickets += 1;
        isWicket = true;
        badge = 'W';
        break;
      case 'NO_BALL':
        _runs += 1;
        legal = false;
        _freeHit = true;
        badge = 'NB';
        break;
      case 'WIDE':
        _runs += 1;
        legal = false;
        badge = 'WD';
        break;
    }

    if (legal) {
      _legalBalls += 1;
      if (eventType != 'NO_BALL') _freeHit = false;
    }

    final line = _generateNonRepeatingLine(eventType);

    setState(() {
      _thisOver.add(badge);
      _feed.insert(0, '[' + _oversText() + '] ' + line);
      if (rotate) {
        final t = _striker;
        _striker = _nonStriker;
        _nonStriker = t;
      }
      if (isWicket && _squadA.isNotEmpty) {
        final nextIdx = (_wickets + 1) % _squadA.length;
        _striker = _squadA[nextIdx];
      }
      if (legal && _legalBalls % 6 == 0) {
        _thisOver.clear();
        final t = _striker;
        _striker = _nonStriker;
        _nonStriker = t;
      }
    });

    _speakWithClonedVoice(line);
  }

  Widget _buildRoleDropdown(String label, String currentValue, List<String> items, ValueChanged<String?> onChanged) {
    final safeItems = items.contains(currentValue) ? items : [currentValue, ...items];
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1120),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white24),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: currentValue,
            isExpanded: true,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
            items: safeItems
                .toSet()
                .map((p) => DropdownMenuItem(value: p, child: Text(label + ': ' + p, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        // Live Scoreboard Banner
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF0D274C), Color(0xFF091326)]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.amber, width: 1.5),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_teamACtrl.text + ' vs ' + _teamBCtrl.text,
                          style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                      Text(
                        _runs.toString() + '/' + _wickets.toString() + ' (' + _oversText() + ' Ov)',
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                    ],
                  ),
                  if (_freeHit)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(20)),
                      child: const Text('🚨 FREE HIT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                    ),
                ],
              ),
              const Divider(color: Colors.white24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('🏏 *' + _striker, style: const TextStyle(fontSize: 11, color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
                  Text('🏃 ' + _nonStriker, style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  Text('⚾ ' + _bowler, style: const TextStyle(fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Commentary Language Selector (Kannada / Hindi / English)
        Row(
          children: ['KANNADA', 'HINDI', 'ENGLISH'].map((lang) {
            final active = (_commLanguage == lang);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: active ? Colors.amber : const Color(0xFF162035),
                    foregroundColor: active ? Colors.black : Colors.white,
                  ),
                  onPressed: () => setState(() => _commLanguage = lang),
                  child: Text('🎙 ' + lang, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),

        // Step 1: Manual Team & Squad Entry
        ExpansionTile(
          collapsedBackgroundColor: const Color(0xFF11192B),
          backgroundColor: const Color(0xFF11192B),
          title: const Text('📋 Step 1: Edit Team Names & 11-Player Squads',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF))),
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  TextField(controller: _teamACtrl, decoration: const InputDecoration(labelText: 'Batting Team Name')),
                  TextField(controller: _squadACtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Batting Players (comma separated)')),
                  const SizedBox(height: 6),
                  TextField(controller: _teamBCtrl, decoration: const InputDecoration(labelText: 'Bowling Team Name')),
                  TextField(controller: _squadBCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Bowling Players (comma separated)')),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Save Teams & Update Player Dropdowns'),
                    onPressed: _loadSquads,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Step 2: Pre-Ball Role Selector
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFF11192B), borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('🎯 Step 2: Select Active Players Before Ball',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber)),
                  TextButton.icon(
                    icon: const Icon(Icons.swap_horiz, size: 16),
                    label: const Text('Swap Strike', style: TextStyle(fontSize: 11)),
                    onPressed: _swapStrike,
                  ),
                ],
              ),
              Row(
                children: [
                  _buildRoleDropdown('🏏 Striker', _striker, _squadA, (v) => setState(() => _striker = v!)),
                  _buildRoleDropdown('🏃 Non-Str', _nonStriker, _squadA, (v) => setState(() => _nonStriker = v!)),
                ],
              ),
              Row(
                children: [
                  _buildRoleDropdown('⚾ Bowler', _bowler, _squadB, (v) => setState(() => _bowler = v!)),
                  _buildRoleDropdown('🧤 WK', _wk, _squadB, (v) => setState(() => _wk = v!)),
                  _buildRoleDropdown('🤾 Fielder', _fielder, _squadB, (v) => setState(() => _fielder = v!)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Step 3: Post-Bowling Parameter Trigger Buttons
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 2.1,
          children: [
            _actionButton('0 • DOT', Colors.blueGrey, () => _triggerBall('DOT')),
            _actionButton('1 • SINGLE', Colors.teal, () => _triggerBall('RUN_1')),
            _actionButton('2 • DOUBLE', Colors.teal, () => _triggerBall('RUN_2')),
            _actionButton('4 • FOUR!', Colors.blueAccent, () => _triggerBall('FOUR')),
            _actionButton('6 • SIXER!', Colors.deepPurpleAccent, () => _triggerBall('SIX')),
            _actionButton('🔥 BATTERY BOLD', Colors.redAccent, () => _triggerBall('BOWLED')),
            _actionButton('🙌 CAUGHT', Colors.red, () => _triggerBall('CAUGHT')),
            _actionButton('🧤 WK CATCH', Colors.red, () => _triggerBall('CAUGHT_WK')),
            _actionButton('🎯 RUN OUT', Colors.deepOrange, () => _triggerBall('RUN_OUT')),
            _actionButton('⚡ STUMPED', Colors.pink, () => _triggerBall('STUMPED')),
            _actionButton('☝️ LBW OUT', Colors.brown, () => _triggerBall('LBW')),
            _actionButton('🚨 NO BALL', Colors.amber.shade800, () => _triggerBall('NO_BALL')),
            _actionButton('↔️ WIDE BALL', Colors.orange.shade800, () => _triggerBall('WIDE')),
            _actionButton('🔄 RESET', Colors.grey.shade800, () {
              setState(() {
                _runs = 0;
                _wickets = 0;
                _legalBalls = 0;
                _freeHit = false;
                _thisOver.clear();
                _feed.clear();
              });
            }),
          ],
        ),
        const SizedBox(height: 10),

        // Live Commentary Feed
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFF0E172A),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF00E5FF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '🔊 Active Voice Clone: ' + VoiceCloneProfileStore.activeProfile.name + ' (' + _commLanguage + ')',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF00E676)),
              ),
              const SizedBox(height: 6),
              if (_feed.isEmpty)
                const Text('Tap any run or wicket button above to hear live Kannada/Hindi/English commentary!',
                    style: TextStyle(fontSize: 12, color: Colors.white70))
              else
                ..._feed.take(8).map((line) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(line, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionButton(String label, Color bg, VoidCallback onTap) {
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: bg,
        foregroundColor: Colors.white,
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onTap,
      child: Text(label, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
    );
  }
}
