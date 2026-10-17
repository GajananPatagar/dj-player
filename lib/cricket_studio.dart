import 'entry_music_data.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import 'main.dart';
import 'voice_and_pro_hub.dart';

class CricketCommentaryScreen extends StatefulWidget {
  const CricketCommentaryScreen({super.key});

  @override
  State<CricketCommentaryScreen> createState() => _CricketCommentaryScreenState();
}

class _CricketCommentaryScreenState extends State<CricketCommentaryScreen> {
  final Random _rng = Random();

  final TextEditingController _teamACtrl = TextEditingController(text: 'Karnataka Lions');
  final TextEditingController _teamBCtrl = TextEditingController(text: 'Mumbai Warriors');
  final TextEditingController _targetCtrl = TextEditingController(text: '0');
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
  String _shotZone = 'Long-On';

  int _runs = 0;
  int _wickets = 0;
  int _legalBalls = 0;
  int _partnershipRuns = 0;
  int _partnershipBalls = 0;
  bool _freeHit = false;
  final Map<String, int> _batterRuns = {};
  final Map<String, int> _batterBalls = {};
  final Map<String, int> _bowlerWickets = {};
  final Map<String, int> _bowlerRuns = {};
  final List<String> _thisOver = [];
  final List<String> _fallOfWickets = [];
  final List<String> _feed = [];
  final Set<String> _usedTournamentLines = {};

  final List<String> _zones = [
    'Cover Drive',
    'Long-On',
    'Long-Off',
    'Deep Mid-Wicket',
    'Square Leg',
    'Third Man',
    'Fine Leg',
    'Straight Down Ground'
  ];

  @override
  void initState() {
    super.initState();
    _loadSquads();
  }

  void _loadSquads() {
    final parsedA = _squadACtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    final parsedB = _squadBCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toSet().toList();
    _squadA = parsedA.isEmpty ? ['Player 1', 'Player 2'] : parsedA;
    _squadB = parsedB.isEmpty ? ['Bowler 1', 'Keeper 1', 'Fielder 1'] : parsedB;

    if (!_squadA.contains(_striker)) _striker = _squadA[0];
    if (!_squadA.contains(_nonStriker)) _nonStriker = _squadA.length > 1 ? _squadA[1] : _squadA[0];
    if (!_squadB.contains(_wk)) _wk = _squadB[0];
    if (!_squadB.contains(_bowler)) _bowler = _squadB.length > 1 ? _squadB[1] : _squadB[0];
    if (!_squadB.contains(_fielder)) _fielder = _squadB.length > 2 ? _squadB[2] : _squadB[0];
    if (mounted) setState(() {});
  }

  void _swapStrike() {
    setState(() {
      final tmp = _striker;
      _striker = _nonStriker;
      _nonStriker = tmp;
    });
  }

  String _oversText() => (_legalBalls ~/ 6).toString() + '.' + (_legalBalls % 6).toString();

  String _generateNonRepeatingLine(String eventType) {
    final teamA = _teamACtrl.text.trim();
    final sRuns = _batterRuns[_striker] ?? 0;
    List<String> pool = [];

    if (_commLanguage == 'KANNADA') {
      switch (eventType) {
        case 'SIX':
          pool = [
            'ಅದ್ಭುತವಾದ ಸಿಕ್ಸರ್! ' + _bowler + ' ಎಸೆದ ಚೆಂಡನ್ನು ' + _striker + ' ' + _shotZone + ' ಮೇಲಿಂದ ಸ್ಟೇಡಿಯಂ ಆಚೆಗಟ್ಟಿದ್ದಾರೆ! ಆರು ರನ್‌ಗಳು!',
            'ಬೃಹತ್ ಸಿಕ್ಸರ್! ' + _striker + ' ಅವರ ಬ್ಯಾಟ್‌ನಿಂದ ಸಿಡಿದ ಚೆಂಡು ನೇರವಾಗಿ ಪ್ರೇಕ್ಷಕರ ಗ್ಯಾಲರಿಗೆ ಹೋಗಿ ಬಿದ್ದಿದೆ! ಈಗ ' + _striker + ' ಅವರ ಮೊತ್ತ ' + sRuns.toString() + ' ರನ್!',
            'ಎಂತಹ ಭರ್ಜರಿ ಹೊಡೆತ! ' + _bowler + ' ಅವರ ಬೌಲಿಂಗ್‌ನಲ್ಲಿ ' + _striker + ' ಆಕರ್ಷಕ ಸಿಕ್ಸರ್ ಬಾರಿಸಿದ್ದಾರೆ! ' + teamA + ' ತಂಡದ ಮೊತ್ತ ' + _runs.toString() + ' ಕ್ಕೆ ಏರಿದೆ!'
          ];
          break;
        case 'FOUR':
          pool = [
            'ಮನೋಹರವಾದ ಬೌಂಡರಿ! ' + _striker + ' ಹೊಡೆದ ಚೆಂಡನ್ನು ತಡೆಯಲು ಫೀಲ್ಡರ್ ' + _fielder + ' ಡೈವ್ ಮಾಡಿದರೂ ಸಾಧ್ಯವಾಗಲಿಲ್ಲ! ನಾಲ್ಕು ರನ್‌ಗಳು!',
            'ಸೂಪರ್ ಶಾಟ್! ' + _bowler + ' ಎಸೆತಕ್ಕೆ ' + _striker + ' ಬ್ಯಾಟ್‌ನಿಂದ ' + _shotZone + ' ದಿಕ್ಕಿನಲ್ಲಿ ಮಿಂಚಿನ ವೇಗದ ಬೌಂಡರಿ!',
            'ಗ್ಯಾಪ್‌ನಲ್ಲಿ ಅದ್ಭುತ ಹೊಡೆತ! ಫೀಲ್ಡರ್ ' + _fielder + ' ಚೆಂಡನ್ನು ಬೆನ್ನಟ್ಟಿದರೂ ಚೆಂಡು ಬೌಂಡರಿ ಗೆರೆ ದಾಟಿದೆ! ನಾಲ್ಕು ರನ್!'
          ];
          break;
        case 'BOWLED':
          pool = [
            'ಬ್ಯಾಟರಿ ಬೋಲ್ಡ್! ಕ್ಲೀನ್ ಬೌಲ್ಡ್! ' + _bowler + ' ಎಸೆದ ವೇಗದ ಯಾರ್ಕರ್‌ಗೆ ' + _striker + ' ಅವರ ಸ್ಟಂಪ್ಸ್ ಹಾರಿಹೋಗಿದೆ! ವಿಕೆಟ್ ಕೀಪರ್ ' + _wk + ' ಸಂಭ್ರಮಿಸುತ್ತಿದ್ದಾರೆ!',
            'ಕ್ಲೀನ್ ಬೌಲ್ಡ್! ಎಂತಹ ಅದ್ಭುತ ಎಸೆತ! ' + _bowler + ' ಅವರ ಬೆಂಕಿಯಂತಹ ಚೆಂಡು ನೇರವಾಗಿ ವಿಕೆಟ್‌ಗೆ ಬಡಿದಿದೆ! ' + _striker + ' ಔಟ್ ಆಗಿ ಪೆವಿಲಿಯನ್ ಕಡೆಗೆ ನಡೆಯುತ್ತಿದ್ದಾರೆ!',
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
            'ಬ್ಯಾಟ್‌ನ ಅಂಚಿಗೆ ತಗುಲಿ ವಿಕೆಟ್ ಕೀಪರ್ ಕೈ ಸೇರಿದೆ! ' + _bowler + ' ಎಸೆತದಲ್ಲಿ ವಿಕೆಟ್ ಕೀಪರ್ ' + _wk + ' ಅದ್ಭುತ ಕ್ಯಾಚ್ ಹಿಡಿದಿದ್ದಾರೆ! ' + _striker + ' ಔಟ್!'
          ];
          break;
        case 'RUN_OUT':
          pool = [
            'ಡೈರೆಕ್ಟ್ ಹಿಟ್ ರನ್ ಔಟ್! ' + _striker + ' ಮತ್ತು ' + _nonStriker + ' ನಡುವೆ ಗೊಂದಲ! ಫೀಲ್ಡರ್ ' + _fielder + ' ಎಸೆದ ಚೆಂಡು ನೇರವಾಗಿ ವಿಕೆಟ್‌ಗೆ ಬಡಿದಿದೆ!'
          ];
          break;
        case 'STUMPED':
          pool = [
            'ಮಿಂಚಿನ ಸ್ಟಂಪಿಂಗ್! ' + _striker + ' ಮುಂದೆ ಬಂದು ಹೊಡೆಯಲು ಪ್ರಯತ್ನಿಸಿದರು, ಆದರೆ ವಿಕೆಟ್ ಕೀಪರ್ ' + _wk + ' ಕ್ಷಣಮಾತ್ರದಲ್ಲಿ ಬೇಲ್ಸ್ ಹಾರಿಸಿದ್ದಾರೆ!'
          ];
          break;
        case 'LBW':
          pool = [
            'ಜೋರಾದ ಅಪೀಲ್ ಮತ್ತು ಅಂಪೈರ್ ಬೆರಳು ಎತ್ತಿದ್ದಾರೆ! ಎಲ್‌ಬಿಡಬ್ಲ್ಯೂ ಔಟ್! ' + _bowler + ' ಎಸೆತ ನೇರವಾಗಿ ' + _striker + ' ಪ್ಯಾಡ್‌ಗೆ ಬಡಿದಿದೆ!'
          ];
          break;
        case 'NO_BALL':
          pool = [
            'ನೋ ಬಾಲ್! ' + _bowler + ' ಕ್ರೀಸ್ ಗೆರೆ ದಾಟಿದ್ದಾರೆ! ಒಂದು ಹೆಚ್ಚುವರಿ ರನ್ ಮತ್ತು ಮುಂದಿನ ಎಸೆತ ಫ್ರೀ ಹಿಟ್ ಆಗಿರುತ್ತದೆ!'
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
            'शानदार छक्का! ' + _bowler + ' की गेंद पर ' + _striker + ' का ' + _shotZone + ' के ऊपर से गगनचुंबी प्रहार! छह रन!',
            'धमाकेदार सिक्सर! ' + _striker + ' ने गेंद को दर्शकों के बीच पहुंचा दिया! ' + _striker + ' अब ' + sRuns.toString() + ' रन पर!'
          ];
          break;
        case 'FOUR':
          pool = [
            'कड़क चौका! ' + _striker + ' का लाजवाब शॉट, फील्डर ' + _fielder + ' ने डाइव लगाई लेकिन गेंद गोली की रफ़्तार से बाउंड्री के पार चार रन!'
          ];
          break;
        case 'BOWLED':
          pool = [
            'बैटरी बोल्ड! क्लीन बोल्ड! ' + _bowler + ' की सटीक यॉर्कर ने ' + _striker + ' के स्टंप्स हवा में उड़ा दिए! विकेटकीपर ' + _wk + ' जश्न मनाते हुए!'
          ];
          break;
        case 'CAUGHT':
          pool = [
            'हवा में गेंद और शानदार कैच! फील्डर ' + _fielder + ' ने बाउंड्री पर बेहतरीन कैच लपका! ' + _bowler + ' को मिली विकेट!'
          ];
          break;
        case 'CAUGHT_WK':
          pool = [
            'बल्ले का बाहरी किनारा और विकेटकीपर ' + _wk + ' के दस्तानों में सुरक्षित कैच! ' + _striker + ' आउट!'
          ];
          break;
        case 'RUN_OUT':
          pool = [
            'डायरेक्ट हिट और रन आउट! फील्डर ' + _fielder + ' का सीधा थ्रो स्टंप्स पर लगा और ' + _striker + ' क्रीज़ से बाहर!'
          ];
          break;
        case 'STUMPED':
          pool = [
            'बिजली की रफ़्तार से स्टंपिंग! विकेटकीपर ' + _wk + ' ने पलक झपकते ही गिल्लियां बिखेर दीं!'
          ];
          break;
        case 'LBW':
          pool = [
            'ज़ोरदार अपील और अंपायर की उंगली हवा में! एलबीडब्ल्यू आउट! ' + _bowler + ' ने ' + _striker + ' को फंसाया!'
          ];
          break;
        case 'NO_BALL':
          pool = [
            'नो बॉल! ' + _bowler + ' का पैर क्रीज़ से बाहर! अगली गेंद होगी फ्री हिट!'
          ];
          break;
        case 'WIDE':
          pool = [
            'वाइड बॉल! अंपायर ने दोनों हाथ फैलाए, टीम को मिला एक अतिरिक्त रन!'
          ];
          break;
        case 'RUN_1':
          pool = [
            'हल्के हाथों से खेला ' + _striker + ' ने और तेज़ी से दौड़कर एक रन पूरा किया!'
          ];
          break;
        case 'RUN_2':
          pool = [
            'गैप में शॉट और ' + _striker + ' तथा ' + _nonStriker + ' ने दौड़कर दो रन पूरे किए!'
          ];
          break;
        default:
          pool = [
            'डॉट बॉल! ' + _bowler + ' की सटीक गेंद, ' + _striker + ' ने सम्मान दिया।'
          ];
      }
    } else {
      switch (eventType) {
        case 'SIX':
          pool = [
            'MASSIVE SIX! ' + _striker + ' launches ' + _bowler + ' high over ' + _shotZone + ' into the crowd for six runs!'
          ];
          break;
        case 'FOUR':
          pool = [
            'CRACKING FOUR! ' + _striker + ' pierces the gap past ' + _fielder + ' at ' + _shotZone + ' for a boundary!'
          ];
          break;
        case 'BOWLED':
          pool = [
            'BATTERY BOLD! CLEAN BOWLED! ' + _bowler + ' shatters ' + _striker + 's stumps right in front of keeper ' + _wk + '!'
          ];
          break;
        default:
          pool = [
            _bowler + ' bowls to ' + _striker + ', fielded cleanly by ' + _fielder + '.'
          ];
      }
    }

    String chosen = pool[_rng.nextInt(pool.length)];
    final catchphrase = VoiceCloneProfileStore.activeProfile.catchphrase.trim();
    if (catchphrase.isNotEmpty) {
      chosen = catchphrase + '! ' + chosen;
    }
    if (_usedTournamentLines.contains(chosen)) {
      chosen = chosen + ' (' + _runs.toString() + ' ವಿಕೆಟ್ ' + _wickets.toString() + ')';
    }
    _usedTournamentLines.add(chosen);
    return chosen;
  }

  void _triggerBall(String eventType) {
    bool legal = true;
    bool rotate = false;
    bool isWicket = false;
    int addedRuns = 0;
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
        addedRuns = 1;
        rotate = true;
        badge = '1';
        break;
      case 'RUN_2':
        addedRuns = 2;
        badge = '2';
        break;
      case 'RUN_3':
        addedRuns = 3;
        rotate = true;
        badge = '3';
        break;
      case 'FOUR':
        addedRuns = 4;
        badge = '4';
        break;
      case 'SIX':
        addedRuns = 6;
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
        _bowlerRuns[_bowler] = (_bowlerRuns[_bowler] ?? 0) + 1;
        legal = false;
        _freeHit = true;
        badge = 'NB';
        break;
      case 'WIDE':
        _runs += 1;
        _bowlerRuns[_bowler] = (_bowlerRuns[_bowler] ?? 0) + 1;
        legal = false;
        badge = 'WD';
        break;
    }

    if (addedRuns > 0) {
      _runs += addedRuns;
      _partnershipRuns += addedRuns;
      _batterRuns[_striker] = (_batterRuns[_striker] ?? 0) + addedRuns;
      _bowlerRuns[_bowler] = (_bowlerRuns[_bowler] ?? 0) + addedRuns;
    }

    if (legal) {
      _legalBalls += 1;
      _partnershipBalls += 1;
      _batterBalls[_striker] = (_batterBalls[_striker] ?? 0) + 1;
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
        _bowlerWickets[_bowler] = (_bowlerWickets[_bowler] ?? 0) + 1;
        _fallOfWickets.add(_runs.toString() + '/' + _wickets.toString() + ' (' + _striker + ')');
        _partnershipRuns = 0;
        _partnershipBalls = 0;
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

    // Play balanced SFX and single natural voice
    AppSoundEngine.playSynthesizedSfx(eventType);
    if (eventType == 'SIX' || eventType == 'FOUR' || eventType == 'BOWLED' || eventType == 'CAUGHT') {
      MasterVolumeController.autoCricketStingerTrigger.value = eventType + '_' + DateTime.now().millisecondsSinceEpoch.toString();
    }
    AppSoundEngine.speakRealVoice(line, _commLanguage, eventKey: eventType);
  }

  Widget _buildRoleDropdown(String label, String currentValue, List<String> items, ValueChanged<String?> onChanged) {
    final uniqueItems = <String>{currentValue, ...items}.toList();
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
            items: uniqueItems
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
    final int target = int.tryParse(_targetCtrl.text) ?? 0;
    final int runsNeeded = target > _runs ? (target - _runs) : 0;

    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        // Live Stadium Scoreboard
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (_freeHit)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(20)),
                          child: const Text('🚨 FREE HIT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 10)),
                        ),
                      Text('Partnership: ' + _partnershipRuns.toString() + ' (' + _partnershipBalls.toString() + ')',
                          style: const TextStyle(fontSize: 11, color: Colors.cyanAccent)),
                      if (target > 0)
                        Text('Need ' + runsNeeded.toString() + ' runs',
                            style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ],
              ),
              const Divider(color: Colors.white24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('🏏 *' + _striker + ' ' + (_batterRuns[_striker] ?? 0).toString() + '(' + (_batterBalls[_striker] ?? 0).toString() + ')',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
                  Text('🏃 ' + _nonStriker + ' ' + (_batterRuns[_nonStriker] ?? 0).toString() + '(' + (_batterBalls[_nonStriker] ?? 0).toString() + ')',
                      style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  Text('⚾ ' + _bowler + ' ' + (_bowlerWickets[_bowler] ?? 0).toString() + '-' + (_bowlerRuns[_bowler] ?? 0).toString(),
                      style: const TextStyle(fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Language Selector (Kannada / Hindi / English)
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

        // Step 1: Team & Squad Editor
        ExpansionTile(
          collapsedBackgroundColor: const Color(0xFF11192B),
          backgroundColor: const Color(0xFF11192B),
          title: const Text('📋 Step 1: Enter Team Names, Target & 11-Player Squads',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF))),
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: TextField(controller: _teamACtrl, decoration: const InputDecoration(labelText: 'Batting Team'))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: _teamBCtrl, decoration: const InputDecoration(labelText: 'Bowling Team'))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: _targetCtrl, decoration: const InputDecoration(labelText: 'Target (Opt)'))),
                    ],
                  ),
                  TextField(controller: _squadACtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Batting Players (comma separated)')),
                  TextField(controller: _squadBCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Bowling Players (comma separated)')),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Save Squads & Update Dropdowns'),
                    onPressed: _loadSquads,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Step 2: Pre-Ball Role & Shot Direction Selector
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
                ],
              ),
              Row(
                children: [
                  _buildRoleDropdown('🤾 Fielder', _fielder, _squadB, (v) => setState(() => _fielder = v!)),
                  _buildRoleDropdown('🧭 Shot Zone', _shotZone, _zones, (v) => setState(() => _shotZone = v!)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Step 3: Post-Bowling Parameter Trigger Pad
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 2.15,
          children: [
            _actionButton('0 • DOT', Colors.blueGrey, () => _triggerBall('DOT')),
            _actionButton('1 • SINGLE', Colors.teal, () => _triggerBall('RUN_1')),
            _actionButton('2 • DOUBLE', Colors.teal, () => _triggerBall('RUN_2')),
            _actionButton('3 • THREE', Colors.teal.shade700, () => _triggerBall('RUN_3')),
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
                _partnershipRuns = 0;
                _partnershipBalls = 0;
                _freeHit = false;
                _batterRuns.clear();
                _batterBalls.clear();
                _bowlerWickets.clear();
                _bowlerRuns.clear();
                _thisOver.clear();
                _fallOfWickets.clear();
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
                '🔊 Single-Channel Natural Voice: ' + VoiceCloneProfileStore.activeProfile.name + ' (' + _commLanguage + ')',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF00E676)),
              ),
              if (_fallOfWickets.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Fall of Wickets: ' + _fallOfWickets.join(' | '),
                      style: const TextStyle(fontSize: 10, color: Colors.orangeAccent)),
                ),
              const SizedBox(height: 6),
              if (_feed.isEmpty)
                const Text('Tap any run or wicket button above to hear natural Kannada/Hindi/English commentary!',
                    style: TextStyle(fontSize: 12, color: Colors.white70))
              else
                ..._feed.take(10).map((line) => Padding(
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
