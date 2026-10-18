import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'main.dart';
import 'voice_and_pro_hub.dart';
import 'entry_music_data.dart';

class CricketCommentaryScreen extends StatefulWidget {
  const CricketCommentaryScreen({super.key});

  @override
  State<CricketCommentaryScreen> createState() => _CricketCommentaryScreenState();
}

class _CricketCommentaryScreenState extends State<CricketCommentaryScreen> {
  final Random _rng = Random();

  final TextEditingController _teamACtrl = TextEditingController(text: 'Karnataka Lions');
  final TextEditingController _teamBCtrl = TextEditingController(text: 'Mumbai Warriors');
  final TextEditingController _targetCtrl = TextEditingController(text: '180');
  final TextEditingController _maxOversCtrl = TextEditingController(text: '20');
  final TextEditingController _squadACtrl = TextEditingController(
      text: 'Gajanan Patagar, Virat Kohli, KL Rahul, Rajat Patidar, Darshan, Glenn Maxwell, Devdutt Padikkal, Dinesh Karthik, Manjunath, Mohammed Siraj, Prashanth');
  final TextEditingController _squadBCtrl = TextEditingController(
      text: 'Rohit Sharma, Jasprit Bumrah, Hardik Pandya, Suryakumar Yadav, Ishan Kishan, Ravindra Jadeja, Kuldeep Yadav, Mohammed Shami, Axar Patel, Arshdeep Singh, Yuzvendra Chahal');

  List<String> _squadA = [];
  List<String> _squadB = [];

  String _striker = 'Gajanan Patagar';
  String _nonStriker = 'Virat Kohli';
  String _bowler = 'Jasprit Bumrah';
  String _wk = 'Ishan Kishan';
  String _fielder = 'Ravindra Jadeja';
  String _commLanguage = 'KANNADA'; // KANNADA, HINDI, ENGLISH
  String _shotZone = 'Long-On';
  bool _dualCommentatorBanter = true;
  bool _autoWalkoutBgmOnWicket = true;

  int _runs = 0;
  int _wickets = 0;
  int _legalBalls = 0;
  int _consecutiveWickets = 0;
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
  final List<Map<String, dynamic>> _undoHistoryStack = [];
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

  void _saveUndoSnapshot() {
    _undoHistoryStack.add({
      'runs': _runs,
      'wickets': _wickets,
      'legalBalls': _legalBalls,
      'consecutiveWickets': _consecutiveWickets,
      'partnershipRuns': _partnershipRuns,
      'partnershipBalls': _partnershipBalls,
      'freeHit': _freeHit,
      'striker': _striker,
      'nonStriker': _nonStriker,
      'bowler': _bowler,
      'batterRuns': Map<String, int>.from(_batterRuns),
      'batterBalls': Map<String, int>.from(_batterBalls),
      'bowlerWickets': Map<String, int>.from(_bowlerWickets),
      'bowlerRuns': Map<String, int>.from(_bowlerRuns),
      'thisOver': List<String>.from(_thisOver),
      'fallOfWickets': List<String>.from(_fallOfWickets),
      'feed': List<String>.from(_feed),
    });
    if (_undoHistoryStack.length > 30) {
      _undoHistoryStack.removeAt(0);
    }
  }

  void _undoLastBall() {
    if (_undoHistoryStack.isEmpty) return;
    final snap = _undoHistoryStack.removeLast();
    setState(() {
      _runs = snap['runs'] as int;
      _wickets = snap['wickets'] as int;
      _legalBalls = snap['legalBalls'] as int;
      _consecutiveWickets = snap['consecutiveWickets'] as int;
      _partnershipRuns = snap['partnershipRuns'] as int;
      _partnershipBalls = snap['partnershipBalls'] as int;
      _freeHit = snap['freeHit'] as bool;
      _striker = snap['striker'] as String;
      _nonStriker = snap['nonStriker'] as String;
      _bowler = snap['bowler'] as String;
      _batterRuns
        ..clear()
        ..addAll(snap['batterRuns'] as Map<String, int>);
      _batterBalls
        ..clear()
        ..addAll(snap['batterBalls'] as Map<String, int>);
      _bowlerWickets
        ..clear()
        ..addAll(snap['bowlerWickets'] as Map<String, int>);
      _bowlerRuns
        ..clear()
        ..addAll(snap['bowlerRuns'] as Map<String, int>);
      _thisOver
        ..clear()
        ..addAll(snap['thisOver'] as List<String>);
      _fallOfWickets
        ..clear()
        ..addAll(snap['fallOfWickets'] as List<String>);
      _feed
        ..clear()
        ..addAll(snap['feed'] as List<String>);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(duration: Duration(seconds: 1), content: Text('⏪ Last ball undone! Score restored.')),
    );
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

  String _oversText() => '${_legalBalls ~/ 6}.${_legalBalls % 6}';

  String _buildCoCommentatorBanter(String eventType, String? incomingBatter) {
    if (!_dualCommentatorBanter) return '';
    final int target = int.tryParse(_targetCtrl.text) ?? 0;
    final int maxOvers = int.tryParse(_maxOversCtrl.text) ?? 20;
    final int ballsLeft = (maxOvers * 6) - _legalBalls;
    final int runsNeeded = target > _runs ? (target - _runs) : 0;

    if (_commLanguage == 'KANNADA') {
      if (incomingBatter != null) {
        return 'ಹೌದು! ಈಗ ಹೊಸ ಬ್ಯಾಟ್ಸ್‌ಮನ್ $incomingBatter ಕ್ರೀಸ್‌ಗೆ ಎಂಟ್ರಿ ಕೊಡುತ್ತಿದ್ದಾರೆ! ಸ್ಟೇಡಿಯಂನಲ್ಲಿ ಎಂಟ್ರಿ ಮ್ಯೂಸಿಕ್ ಮೊಳಗುತ್ತಿದೆ!';
      }
      if (_consecutiveWickets == 2) {
        return 'ಗಮನಿಸಿ! $_bowler ಈಗ ಹ್ಯಾಟ್ರಿಕ್ ವಿಕೆಟ್ ಅವಕಾಶದಲ್ಲಿದ್ದಾರೆ!';
      }
      if (target > 0 && ballsLeft > 0 && runsNeeded > 0 && (eventType == 'SIX' || eventType == 'FOUR')) {
        return 'ಪಂದ್ಯ ರೋಚಕವಾಗಿದೆ! ಗೆಲ್ಲಲು ಇನ್ನು $ballsLeft ಎಸೆತಗಳಲ್ಲಿ $runsNeeded ರನ್ ಬೇಕಾಗಿದೆ!';
      }
      if (eventType == 'SIX') {
        return 'ಎಂತಹ ಪವರ್ ಹಿಟ್ಟಿಂಗ್! $_shotZone ಮೇಲೆ ಚೆಂಡು ರಾಕೆಟ್ ವೇಗದಲ್ಲಿ ಹಾರಿಹೋಗಿದೆ!';
      }
    } else if (_commLanguage == 'HINDI') {
      if (incomingBatter != null) {
        return 'जी हाँ! अब नए बल्लेबाज़ $incomingBatter मैदान में उतर रहे हैं और धमाकेदार एंट्री म्यूज़िक बज रहा है!';
      }
      if (target > 0 && ballsLeft > 0 && runsNeeded > 0 && (eventType == 'SIX' || eventType == 'FOUR')) {
        return 'मुकाबला रोमांचक मोड़ पर! अब $ballsLeft गेंदों में $runsNeeded रनों की ज़रूरत है!';
      }
    } else {
      if (incomingBatter != null) {
        return 'And here walks out $incomingBatter to the crease as the stadium entry music blasts!';
      }
    }
    return '';
  }

  String _generateNonRepeatingLine(String eventType) {
    final teamA = _teamACtrl.text.trim();
    final sRuns = _batterRuns[_striker] ?? 0;
    List<String> pool = [];

    if (_commLanguage == 'KANNADA') {
      switch (eventType) {
        case 'SIX':
          pool = [
            'ಅದ್ಭುತವಾದ ಸಿಕ್ಸರ್! $_bowler ಎಸೆದ ಚೆಂಡನ್ನು $_striker $_shotZone ಮೇಲಿಂದ ಸ್ಟೇಡಿಯಂ ಆಚೆಗಟ್ಟಿದ್ದಾರೆ! ಆರು ರನ್‌ಗಳು!',
            'ಬೃಹತ್ ಸಿಕ್ಸರ್! $_striker ಅವರ ಬ್ಯಾಟ್‌ನಿಂದ ಸಿಡಿದ ಚೆಂಡು ನೇರವಾಗಿ ಪ್ರೇಕ್ಷಕರ ಗ್ಯಾಲರಿಗೆ ಹೋಗಿ ಬಿದ್ದಿದೆ! ಈಗ $_striker ಮೊತ್ತ $sRuns ರನ್!',
            'ಬೆಂಕಿ ಹೊಡೆತ! $_bowler ಬೌಲಿಂಗ್‌ನಲ್ಲಿ $_striker ಭರ್ಜರಿ ಸಿಕ್ಸರ್ ಬಾರಿಸಿದ್ದಾರೆ! $teamA ಮೊತ್ತ $_runs ಕ್ಕೆ ಏರಿದೆ!'
          ];
          break;
        case 'FOUR':
          pool = [
            'ಮನೋಹರವಾದ ಬೌಂಡರಿ! $_striker ಹೊಡೆದ ಚೆಂಡನ್ನು ತಡೆಯಲು ಫೀಲ್ಡರ್ $_fielder ಡೈವ್ ಮಾಡಿದರೂ ಸಾಧ್ಯವಾಗಲಿಲ್ಲ! ನಾಲ್ಕು ರನ್!',
            'ಸೂಪರ್ ಶಾಟ್! $_bowler ಎಸೆತಕ್ಕೆ $_striker ಬ್ಯಾಟ್‌ನಿಂದ $_shotZone ದಿಕ್ಕಿನಲ್ಲಿ ಮಿಂಚಿನ ವೇಗದ ಬೌಂಡರಿ!'
          ];
          break;
        case 'BOWLED':
          pool = [
            'ಬ್ಯಾಟರಿ ಬೋಲ್ಡ್! ಕ್ಲೀನ್ ಬೌಲ್ಡ್! $_bowler ಎಸೆದ ವೇಗದ ಯಾರ್ಕರ್‌ಗೆ $_striker ಅವರ ಸ್ಟಂಪ್ಸ್ ಹಾರಿಹೋಗಿದೆ! ವಿಕೆಟ್ ಕೀಪರ್ $_wk ಸಂಭ್ರಮಿಸುತ್ತಿದ್ದಾರೆ!',
            'ಕ್ಲೀನ್ ಬೌಲ್ಡ್! ಎಂತಹ ಅದ್ಭುತ ಎಸೆತ! $_bowler ಅವರ ಬೆಂಕಿಯಂತಹ ಚೆಂಡು ನೇರವಾಗಿ ವಿಕೆಟ್‌ಗೆ ಬಡಿದಿದೆ!'
          ];
          break;
        case 'CAUGHT':
          pool = [
            'ಗಾಳಿಯಲ್ಲಿ ಚೆಂಡು ಮತ್ತು ಅದ್ಭುತ ಕ್ಯಾಚ್! $_striker ಹೊಡೆದ ಚೆಂಡನ್ನು ಫೀಲ್ಡರ್ $_fielder ಯಾವುದೇ ತಪ್ಪಿಲ್ಲದೆ ಹಿಡಿದಿದ್ದಾರೆ! $_bowler ಗೆ ವಿಕೆಟ್!'
          ];
          break;
        case 'CAUGHT_WK':
          pool = [
            'ಬ್ಯಾಟ್‌ನ ಅಂಚಿಗೆ ತಗುಲಿ ವಿಕೆಟ್ ಕೀಪರ್ ಕೈ ಸೇರಿದೆ! $_bowler ಎಸೆತದಲ್ಲಿ ವಿಕೆಟ್ ಕೀಪರ್ $_wk ಅದ್ಭುತ ಕ್ಯಾಚ್ ಹಿಡಿದಿದ್ದಾರೆ!'
          ];
          break;
        case 'RUN_OUT':
          pool = [
            'ಡೈರೆಕ್ಟ್ ಹಿಟ್ ರನ್ ಔಟ್! $_striker ಮತ್ತು $_nonStriker ನಡುವೆ ಗೊಂದಲ! ಫೀಲ್ಡರ್ $_fielder ಎಸೆದ ಚೆಂಡು ನೇರವಾಗಿ ವಿಕೆಟ್‌ಗೆ ಬಡಿದಿದೆ!'
          ];
          break;
        case 'STUMPED':
          pool = [
            'ಮಿಂಚಿನ ಸ್ಟಂಪಿಂಗ್! $_striker ಮುಂದೆ ಬಂದು ಹೊಡೆಯಲು ಪ್ರಯತ್ನಿಸಿದರು, ಆದರೆ ವಿಕೆಟ್ ಕೀಪರ್ $_wk ಕ್ಷಣಮಾತ್ರದಲ್ಲಿ ಬೇಲ್ಸ್ ಹಾರಿಸಿದ್ದಾರೆ!'
          ];
          break;
        case 'LBW':
          pool = [
            'ಜೋರಾದ ಅಪೀಲ್ ಮತ್ತು ಅಂಪೈರ್ ಬೆರಳು ಎತ್ತಿದ್ದಾರೆ! ಎಲ್‌ಬಿಡಬ್ಲ್ಯೂ ಔಟ್! $_bowler ಎಸೆತ ನೇರವಾಗಿ $_striker ಪ್ಯಾಡ್‌ಗೆ ಬಡಿದಿದೆ!'
          ];
          break;
        case 'NO_BALL':
          pool = [
            'ನೋ ಬಾಲ್! $_bowler ಕ್ರೀಸ್ ಗೆರೆ ದಾಟಿದ್ದಾರೆ! ಒಂದು ಹೆಚ್ಚುವರಿ ರನ್ ಮತ್ತು ಮುಂದಿನ ಎಸೆತ ಫ್ರೀ ಹಿಟ್ ಆಗಿರುತ್ತದೆ!'
          ];
          break;
        case 'WIDE':
          pool = [
            'ವೈಡ್ ಬಾಲ್! $_bowler ಲೆಗ್ ಸೈಡ್ ಆಚೆ ಎಸೆದಿದ್ದಾರೆ, ವಿಕೆಟ್ ಕೀಪರ್ $_wk ಡೈವ್ ಮಾಡಿ ಚೆಂಡನ್ನು ತಡೆದಿದ್ದಾರೆ!'
          ];
          break;
        case 'RUN_1':
          pool = [
            'ಚುರುಕಾದ ಒಂದು ರನ್! $_striker ಚೆಂಡನ್ನು $_shotZone ಕಡೆಗೆ ತಳ್ಳಿ $_nonStriker ಜೊತೆ ಸ್ಟ್ರೈಕ್ ಬದಲಾಯಿಸಿದ್ದಾರೆ!'
          ];
          break;
        case 'RUN_2':
          pool = [
            'ಅದ್ಭುತ ಓಟ! $_striker ಮತ್ತು $_nonStriker ಫೀಲ್ಡರ್ $_fielder ಚೆಂಡನ್ನು ಎಸೆಯುವಷ್ಟರಲ್ಲಿ ಎರಡು ರನ್ ಪೂರೈಸಿದ್ದಾರೆ!'
          ];
          break;
        default:
          pool = [
            'ಡಾಟ್ ಬಾಲ್! $_bowler ಅವರ ನಿಖರವಾದ ಎಸೆತವನ್ನು $_striker ರಕ್ಷಣಾತ್ಮಕವಾಗಿ ಆಡಿದ್ದಾರೆ.'
          ];
      }
    } else if (_commLanguage == 'HINDI') {
      switch (eventType) {
        case 'SIX':
          pool = [
            'शानदार छक्का! $_bowler की गेंद पर $_striker का $_shotZone के ऊपर से गगनचुंबी प्रहार! छह रन!'
          ];
          break;
        case 'FOUR':
          pool = [
            'कड़क चौका! $_striker का लाजवाब शॉट, फील्डर $_fielder ने डाइव लगाई लेकिन गेंद गोली की रफ़्तार से बाउंड्री के पार!'
          ];
          break;
        case 'BOWLED':
          pool = [
            'बैटरी बोल्ड! क्लीन बोल्ड! $_bowler की सटीक यॉर्कर ने $_striker के स्टंप्स हवा में उड़ा दिए!'
          ];
          break;
        default:
          pool = [
            '$_bowler की शानदार गेंद $_striker को, फील्डर $_fielder ने तेज़ी से गेंद को रोका!'
          ];
      }
    } else {
      pool = [
        '$eventType! $_bowler bowls to $_striker towards $_shotZone, fielded by $_fielder with $_wk behind the stumps!'
      ];
    }

    String chosen = pool[_rng.nextInt(pool.length)];
    final catchphrase = VoiceCloneProfileStore.activeProfile.catchphrase.trim();
    if (catchphrase.isNotEmpty) {
      chosen = '$catchphrase! $chosen';
    }
    if (_usedTournamentLines.contains(chosen)) {
      chosen = '$chosen ($_runs/$_wickets)';
    }
    _usedTournamentLines.add(chosen);
    return chosen;
  }

  void _triggerBall(String eventType) {
    _saveUndoSnapshot();

    bool legal = true;
    bool rotate = false;
    bool isWicket = false;
    int addedRuns = 0;
    String badge = '0';
    String? incomingBatterName;

    if (_freeHit &&
        (eventType == 'BOWLED' || eventType == 'CAUGHT' || eventType == 'CAUGHT_WK' || eventType == 'STUMPED' || eventType == 'LBW')) {
      eventType = 'DOT';
    }

    switch (eventType) {
      case 'DOT':
        badge = '0';
        _consecutiveWickets = 0;
        break;
      case 'RUN_1':
        addedRuns = 1;
        rotate = true;
        badge = '1';
        _consecutiveWickets = 0;
        break;
      case 'RUN_2':
        addedRuns = 2;
        badge = '2';
        _consecutiveWickets = 0;
        break;
      case 'RUN_3':
        addedRuns = 3;
        rotate = true;
        badge = '3';
        _consecutiveWickets = 0;
        break;
      case 'FOUR':
        addedRuns = 4;
        badge = '4';
        _consecutiveWickets = 0;
        break;
      case 'SIX':
        addedRuns = 6;
        badge = '6';
        _consecutiveWickets = 0;
        break;
      case 'BOWLED':
      case 'CAUGHT':
      case 'CAUGHT_WK':
      case 'RUN_OUT':
      case 'STUMPED':
      case 'LBW':
        _wickets += 1;
        _consecutiveWickets += 1;
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
      if (rotate) {
        final t = _striker;
        _striker = _nonStriker;
        _nonStriker = t;
      }
      if (isWicket && _squadA.isNotEmpty) {
        _bowlerWickets[_bowler] = (_bowlerWickets[_bowler] ?? 0) + 1;
        _fallOfWickets.add('$_runs/$_wickets ($_striker)');
        _partnershipRuns = 0;
        _partnershipBalls = 0;
        final nextIdx = (_wickets + 1) % _squadA.length;
        incomingBatterName = _squadA[nextIdx];
        _striker = incomingBatterName!;
      }
      if (legal && _legalBalls % 6 == 0) {
        _thisOver.clear();
        final t = _striker;
        _striker = _nonStriker;
        _nonStriker = t;
      }
    });

    final String banter = _buildCoCommentatorBanter(eventType, incomingBatterName);
    setState(() {
      _feed.insert(0, '[${_oversText()}] $line ${banter.isNotEmpty ? "\n🎙 Co-Comm: $banter" : ""}');
    });

    AppSoundEngine.playSynthesizedSfx(eventType);
    if ((isWicket && _autoWalkoutBgmOnWicket) || eventType == 'SIX' || eventType == 'FOUR') {
      MasterVolumeController.autoCricketStingerTrigger.value = '${eventType}_${DateTime.now().millisecondsSinceEpoch}';
    }
    AppSoundEngine.speakRealVoice(line, _commLanguage, eventKey: eventType, coCommentatorText: banter);
  }

  void _copyWhatsAppScorecard() {
    final String summary = '🏏 *${_teamACtrl.text} vs ${_teamBCtrl.text}*\n'
        '📊 Score: *$_runs/$_wickets (${_oversText()} Overs)*\n'
        '🏏 *$Striker: ${_batterRuns[_striker] ?? 0}(${_batterBalls[_striker] ?? 0})\n'
        '🏏 $_nonStriker: ${_batterRuns[_nonStriker] ?? 0}(${_batterBalls[_nonStriker] ?? 0})\n'
        '⚾ $_bowler: ${_bowlerWickets[_bowler] ?? 0}-${_bowlerRuns[_bowler] ?? 0}\n'
        '🔥 Powered by DJ Play and Commentry App v100';
    Clipboard.setData(ClipboardData(text: summary));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('📋 WhatsApp Scorecard copied to clipboard!')),
    );
  }

  String get $Striker => _striker;

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
                .map((p) => DropdownMenuItem(value: p, child: Text('$label: $p', overflow: TextOverflow.ellipsis)))
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
        // Live Scoreboard Card + Undo + WhatsApp Share
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
                      Text('${_teamACtrl.text} vs ${_teamBCtrl.text}',
                          style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                      Text(
                        '$_runs/$_wickets (${_oversText()} Ov)',
                        style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade800,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        ),
                        icon: const Icon(Icons.undo, size: 15),
                        label: const Text('UNDO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900)),
                        onPressed: _undoLastBall,
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Copy WhatsApp Scorecard',
                        icon: const Icon(Icons.share, color: Colors.greenAccent, size: 20),
                        onPressed: _copyWhatsAppScorecard,
                      ),
                    ],
                  ),
                ],
              ),
              if (target > 0 || _freeHit || _consecutiveWickets >= 2)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (target > 0)
                        Text('Target $target • Need $runsNeeded runs',
                            style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                      if (_consecutiveWickets >= 2)
                        const Text('🔥 HAT-TRICK BALL!',
                            style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.w900)),
                      if (_freeHit)
                        const Text('🚨 FREE HIT!',
                            style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              const Divider(color: Colors.white24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('🏏 *$_striker ${_batterRuns[_striker] ?? 0}(${_batterBalls[_striker] ?? 0})',
                      style: const TextStyle(fontSize: 11, color: Color(0xFF00E676), fontWeight: FontWeight.bold)),
                  Text('🏃 $_nonStriker ${_batterRuns[_nonStriker] ?? 0}(${_batterBalls[_nonStriker] ?? 0})',
                      style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  Text('⚾ $_bowler ${_bowlerWickets[_bowler] ?? 0}-${_bowlerRuns[_bowler] ?? 0}',
                      style: const TextStyle(fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Language & Dual-Banter Toggles
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
                  child: Text('🎙 $lang', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),

        // Step 1: Team & Squad Editor
        ExpansionTile(
          collapsedBackgroundColor: const Color(0xFF11192B),
          backgroundColor: const Color(0xFF11192B),
          title: const Text('📋 Step 1: Teams, Target, Dual-Commentator & Walkout Settings',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF))),
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: TextField(controller: _teamACtrl, decoration: const InputDecoration(labelText: 'Batting Team'))),
                      const SizedBox(width: 6),
                      Expanded(child: TextField(controller: _teamBCtrl, decoration: const InputDecoration(labelText: 'Bowling Team'))),
                      const SizedBox(width: 6),
                      Expanded(child: TextField(controller: _targetCtrl, decoration: const InputDecoration(labelText: 'Target'))),
                    ],
                  ),
                  TextField(controller: _squadACtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Batting Squad (comma separated)')),
                  TextField(controller: _squadBCtrl, maxLines: 2, decoration: const InputDecoration(labelText: 'Bowling Squad (comma separated)')),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('🎙 Dual-Commentator Banter (Lead + Co-Commentator)', style: TextStyle(fontSize: 11)),
                    value: _dualCommentatorBanter,
                    onChanged: (v) => setState(() => _dualCommentatorBanter = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('👑 Auto-Blast Incoming Batter Walkout BGM on Wicket', style: TextStyle(fontSize: 11)),
                    value: _autoWalkoutBgmOnWicket,
                    onChanged: (v) => setState(() => _autoWalkoutBgmOnWicket = v),
                  ),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle),
                    label: const Text('Save Squads & Update Players'),
                    onPressed: _loadSquads,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // Step 2: Pre-Ball Role & 360 Wagon Wheel Zone Selector
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: const Color(0xFF11192B), borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('🎯 Step 2: Active Players & 360° Wagon Wheel Zone',
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
                  _buildRoleDropdown('🧭 360° Zone', _shotZone, _zones, (v) => setState(() => _shotZone = v!)),
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
            _actionButton('🔄 RESET MATCH', Colors.grey.shade800, () {
              _saveUndoSnapshot();
              setState(() {
                _runs = 0;
                _wickets = 0;
                _legalBalls = 0;
                _consecutiveWickets = 0;
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
                '🔊 Kannada/Hindi Phonetic AI + Dual Banter ($_commLanguage)',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF00E676)),
              ),
              if (_fallOfWickets.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Fall of Wickets: ${_fallOfWickets.join(" | ")}',
                      style: const TextStyle(fontSize: 10, color: Colors.orangeAccent)),
                ),
              const SizedBox(height: 6),
              if (_feed.isEmpty)
                const Text('Tap any run or wicket button above to hear live commentary!',
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
