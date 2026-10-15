/* ============================================================================
   SECTION 2: PRO CRICKET SCORER & REAL-VOICE NON-REPEATING AUTO-COMMENTARY
   Includes Stadium Crowd/Bat/Stump SFX + 300-Hash Anti-Repetition Memory
   ============================================================================ */

var cricketState = {
  teamA: "Royal Challengers",
  teamB: "Super Kings",
  squadA: [],
  squadB: [],
  runs: 0,
  wickets: 0,
  legalBalls: 0,
  freeHitActive: false,
  thisOver: [],
  striker: "Virat Kohli",
  nonStriker: "Faf du Plessis",
  bowler: "Jasprit Bumrah",
  wk: "MS Dhoni",
  fielder: "Ravindra Jadeja",
  batStats: {},
  bowlStats: {},
  usedCommentaryHashes: []
};

// Load tournament anti-repetition memory from localStorage
try {
  var savedHashes = localStorage.getItem("dj_cricket_used_hashes_v19");
  if (savedHashes) {
    cricketState.usedCommentaryHashes = JSON.parse(savedHashes);
  }
} catch (e) {}

function recordCommentaryHash(text) {
  cricketState.usedCommentaryHashes.push(text);
  if (cricketState.usedCommentaryHashes.length > 350) {
    cricketState.usedCommentaryHashes.shift();
  }
  try {
    localStorage.setItem("dj_cricket_used_hashes_v19", JSON.stringify(cricketState.usedCommentaryHashes));
  } catch (e) {}
  var badge = document.getElementById("uniqueHashCounter");
  if (badge) badge.textContent = "Unique Lines Used: " + cricketState.usedCommentaryHashes.length;
}

/* ==================== STADIUM CROWD, BAT CRACK & STUMP CRASH SFX ==================== */
var sfxCtx = null;

function getSfxContext() {
  if (!sfxCtx) {
    var AC = window.AudioContext || window.webkitAudioContext;
    sfxCtx = new AC();
  }
  if (sfxCtx.state === "suspended") sfxCtx.resume();
  return sfxCtx;
}

function playStadiumSfx(effectType) {
  var chk = document.getElementById("chkCrowdSfx");
  if (chk && !chk.checked) return;

  try {
    var ctx = getSfxContext();
    var now = ctx.currentTime;

    // 1. Bat Crack or Wooden Stump Crash (“Battery Bold”)
    if (effectType === "FOUR" || effectType === "SIX" || effectType === "BOWLED") {
      var osc = ctx.createOscillator();
      var gain = ctx.createGain();
      osc.type = (effectType === "BOWLED") ? "sawtooth" : "triangle";
      osc.frequency.setValueAtTime((effectType === "BOWLED") ? 190 : 520, now);
      osc.frequency.exponentialRampToValueAtTime(45, now + 0.18);
      gain.gain.setValueAtTime(0.6, now);
      gain.gain.exponentialRampToValueAtTime(0.01, now + 0.19);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(now);
      osc.stop(now + 0.2);
    }

    // 2. No-Ball Siren
    if (effectType === "NO_BALL" || effectType === "NO_BALL_SIX") {
      var sOsc = ctx.createOscillator();
      var sGain = ctx.createGain();
      sOsc.type = "sawtooth";
      sOsc.frequency.setValueAtTime(440, now);
      sOsc.frequency.linearRampToValueAtTime(880, now + 0.35);
      sOsc.frequency.linearRampToValueAtTime(440, now + 0.7);
      sGain.gain.setValueAtTime(0.35, now);
      sGain.gain.exponentialRampToValueAtTime(0.01, now + 0.75);
      sOsc.connect(sGain);
      sGain.connect(ctx.destination);
      sOsc.start(now);
      sOsc.stop(now + 0.76);
    }

    // 3. Stadium Crowd Roar on Boundaries & Wickets
    if (effectType === "SIX" || effectType === "FOUR" || effectType.indexOf("CAUGHT") !== -1 ||
        effectType === "BOWLED" || effectType === "RUN_OUT" || effectType === "STUMPED" || effectType === "LBW") {
      var duration = (effectType === "SIX" || effectType === "BOWLED") ? 2.4 : 1.6;
      var bufferSize = ctx.sampleRate * duration;
      var noiseBuffer = ctx.createBuffer(1, bufferSize, ctx.sampleRate);
      var output = noiseBuffer.getChannelData(0);
      for (var i = 0; i < bufferSize; i++) {
        output[i] = Math.random() * 2 - 1;
      }

      var whiteNoise = ctx.createBufferSource();
      whiteNoise.buffer = noiseBuffer;

      var filter = ctx.createBiquadFilter();
      filter.type = "bandpass";
      filter.frequency.value = 950;
      filter.Q.value = 0.7;

      var crowdGain = ctx.createGain();
      crowdGain.gain.setValueAtTime(0.02, now);
      crowdGain.gain.linearRampToValueAtTime(0.28, now + 0.25);
      crowdGain.gain.exponentialRampToValueAtTime(0.01, now + duration);

      whiteNoise.connect(filter);
      filter.connect(crowdGain);
      crowdGain.connect(ctx.destination);
      whiteNoise.start(now);
      whiteNoise.stop(now + duration);
    }
  } catch (e) {
    console.warn("SFX warning:", e);
  }
}

/* ==================== SQUAD & PLAYER DROPDOWN MANAGER ==================== */
function parsePlayerList(rawText) {
  var parts = rawText.split(/[\n,]+/);
  var cleaned = [];
  for (var i = 0; i < parts.length; i++) {
    var p = parts[i].trim();
    if (p) cleaned.push(p);
  }
  return cleaned;
}

function ensurePlayerStats(name) {
  if (!cricketState.batStats[name]) {
    cricketState.batStats[name] = { runs: 0, balls: 0, fours: 0, sixes: 0, out: false };
  }
  if (!cricketState.bowlStats[name]) {
    cricketState.bowlStats[name] = { runs: 0, wickets: 0, balls: 0 };
  }
}

function populateSelectOptions(selectId, list, defaultIdx) {
  var sel = document.getElementById(selectId);
  if (!sel) return;
  var prevVal = sel.value;
  sel.innerHTML = "";
  for (var i = 0; i < list.length; i++) {
    ensurePlayerStats(list[i]);
    var opt = document.createElement("option");
    opt.value = list[i];
    opt.textContent = list[i];
    sel.appendChild(opt);
  }
  if (prevVal && list.indexOf(prevVal) !== -1) {
    sel.value = prevVal;
  } else if (list[defaultIdx]) {
    sel.value = list[defaultIdx];
  } else if (list[0]) {
    sel.value = list[0];
  }
}

function applySquadsAndPopulateDropdowns() {
  cricketState.teamA = document.getElementById("teamAName").value.trim() || "Team A";
  cricketState.teamB = document.getElementById("teamBName").value.trim() || "Team B";
  cricketState.squadA = parsePlayerList(document.getElementById("teamAPlayers").value);
  cricketState.squadB = parsePlayerList(document.getElementById("teamBPlayers").value);

  populateSelectOptions("selStriker", cricketState.squadA, 0);
  populateSelectOptions("selNonStriker", cricketState.squadA, 1);
  populateSelectOptions("selWk", cricketState.squadB, 0);
  populateSelectOptions("selBowler", cricketState.squadB, 3);
  populateSelectOptions("selFielder", cricketState.squadB, 2);

  syncSelectedRoles();
  updateScoreboardUi();
}

function syncSelectedRoles() {
  cricketState.striker = document.getElementById("selStriker").value;
  cricketState.nonStriker = document.getElementById("selNonStriker").value;
  cricketState.bowler = document.getElementById("selBowler").value;
  cricketState.wk = document.getElementById("selWk").value;
  cricketState.fielder = document.getElementById("selFielder").value;

  ensurePlayerStats(cricketState.striker);
  ensurePlayerStats(cricketState.nonStriker);
  ensurePlayerStats(cricketState.bowler);
  updateScoreboardUi();
}

function swapStrikeManual() {
  var s = document.getElementById("selStriker").value;
  var ns = document.getElementById("selNonStriker").value;
  document.getElementById("selStriker").value = ns;
  document.getElementById("selNonStriker").value = s;
  syncSelectedRoles();
}

function swapInningsTeams() {
  var tmpName = document.getElementById("teamAName").value;
  var tmpSquad = document.getElementById("teamAPlayers").value;
  document.getElementById("teamAName").value = document.getElementById("teamBName").value;
  document.getElementById("teamAPlayers").value = document.getElementById("teamBPlayers").value;
  document.getElementById("teamBName").value = tmpName;
  document.getElementById("teamBPlayers").value = tmpSquad;
  resetMatchScoreboard();
}

function resetMatchScoreboard() {
  cricketState.runs = 0;
  cricketState.wickets = 0;
  cricketState.legalBalls = 0;
  cricketState.freeHitActive = false;
  cricketState.thisOver = [];
  cricketState.batStats = {};
  cricketState.bowlStats = {};
  applySquadsAndPopulateDropdowns();
  document.getElementById("commentaryFeedList").innerHTML = "";
  speakLiveCommentary("Match scoreboard reset. " + cricketState.teamA + " vs " + cricketState.teamB + ". Players taking their positions on the field!", "MILESTONE");
}

/* ==================== COMBINATORIAL TOURNAMENT COMMENTARY MATRIX ==================== */
var PHRASE_BANKS = {
  runup: [
    "{bowler} steams in from the broadcast end,",
    "{bowler} charges in with a tight grip on the seam,",
    "{bowler} sprints past the umpire and releases a thunderbolt,",
    "{bowler} comes around the wicket looking for swing,",
    "Crowds on their feet as {bowler} bowls at full tilt,",
    "{bowler} hits the deck hard with serious pace,",
    "{bowler} measures the run-up carefully and fires it in,",
    "Tension in the stadium as {bowler} charges toward the crease,"
  ],

  DOT: [
    "and {striker} punches it solidly back down the pitch. No run, dot ball pressure building!",
    "beaten on the outside edge! {wk} collects cleanly behind the stumps. Superb bowling from {bowler}!",
    "defended right under the eyes by {striker}. {fielder} swoops in quickly to prevent the single.",
    "crisp block off the front foot by {striker}. {bowler} is asking serious questions here!",
    "driven straight to {fielder} inside the circle! {nonStriker} shouts NO from the other end!"
  ],

  RUN_1: [
    "dropped into the gap with soft hands by {striker}! {striker} and {nonStriker} scamper through for a lightning single before {fielder} can release the throw!",
    "worked neatly off the hips by {striker} toward {fielder} for a smart single to rotate the strike.",
    "guided down to third man by {striker}. Easy single taken, {nonStriker} is now on strike!",
    "pushed into the pockets at mid-on! {striker} calls early and makes the crease comfortably for one."
  ],

  RUN_2: [
    "pierced into the deep pocket by {striker}! They sprint the first one hard and turn back for the second! Great running between {striker} and {nonStriker}!",
    "clipped firmly off the pads into the vacant square boundary! {fielder} chases it down, keeping {striker} to a brace of runs!",
    "punched into the gap at extra cover! {striker} pushes {nonStriker} hard for two and beats {fielder}'s throw back to {wk}!"
  ],

  RUN_3: [
    "timed exquisitely by {striker} through the outfield! {fielder} puts in a desperate diving stop inches inside the rope, saving a boundary as {striker} and {nonStriker} run three!",
    "sweetly driven into the vast pockets of the ground! Brilliant relay throw from {fielder}, but the batters cross for three!"
  ],

  FOUR: [
    "CRACK! {striker} leans into a glorious cover drive! {fielder} dives full length but cannot stop it! Racing away to the fence for FOUR!",
    "SHOT OF AN EMPEROR! {striker} rocks onto the back foot and pulls {bowler} fiercely past {fielder} for a scorching boundary!",
    "threaded like a surgeon by {striker}! Splits the gap and leaves {fielder} chasing shadows! Four runs added to {teamA}'s total!",
    "crunched down the ground by {striker}! Not even two fielders could have stopped that tracer bullet! FOUR RUNS!",
    "late cut of the highest class by {striker}! Beats {wk} and rockets to the third-man boundary for FOUR!"
  ],

  SIX: [
    "BOOM! OUT OF THE STADIUM! {striker} clears the front leg and launches {bowler} high into the night sky for a MASSIVE SIX!",
    "MONSTER MAXIMUM! {striker} picks the length in a flash and deposits {bowler} ten rows back into the cheering crowd!",
    "MAGNIFICENT HIT! {striker} dances down the track and lofts {bowler} effortlessly over long-on for a gigantic SIX!",
    "SWEET SOUND OFF THE WILLOW! {striker} muscles that delivery way over {fielder}'s head into the second tier for SIX!",
    "UNBELIEVABLE POWER FROM {striker}! Flicked off the wrists with ridiculous timing, sailing over the ropes for a maximum!"
  ],

  BOWLED: [
    "BATTERY BOLD! CLEAN BOWLED! TIMBER! {bowler} unleashes an unplayable toe-crushing yorker that shatters {striker}'s stumps! The middle stump is cartwheeling toward {wk}!",
    "CASTLED HIM! {bowler} gets the ball to nip back sharply through the gate and crashes straight into the woodwork! {striker} is Clean Bowled and walks back stunned!",
    "KNOCKED HIM OVER! BATTERY BOLD! What a peach of a delivery from {bowler}! The bails fly past {wk} and the off-stump is uprooted out of the turf!",
    "SHATTERED STUMPS! {striker} swings hard across the line and misses completely as {bowler} hits the bullseye! Clean bowled of the highest order!"
  ],

  CAUGHT_FIELDER: [
    "UP IN THE AIR AND TAKEN! {striker} mistimes the lofted shot and {fielder} judges it to perfection under the high ball! Huge wicket for {bowler}!",
    "WHAT A SCREAMER BY {fielder}! {striker} slashed hard, and {fielder} flew horizontally through the air to pluck a one-handed stunner! {bowler} is ecstatic!",
    "CAUGHT IN THE DEEP! {striker} tried to clear the ropes, didn't get the elevation, and {fielder} makes zero mistake near the boundary cushion!"
  ],

  CAUGHT_WK: [
    "EDGED AND TAKEN BEHIND! {bowler} shapes it away late, kisses the outside edge of {striker}'s bat, and wicketkeeper {wk} pouches a clinical catch!",
    "GOT HIM! Feather touch off the glove from {striker}, and {wk} dives full stretch in front of first slip to complete a breathtaking catch!",
    "NICKED TO THE KEEPER! {bowler} extracts extra bounce, {striker} pokes at it, and {wk} swallows it safely in the gloves!"
  ],

  RUN_OUT: [
    "DIRECT HIT! RUN OUT! Terrible mix-up between {striker} and {nonStriker}! {fielder} picks up cleanly and throws down the stumps in a single motion! {striker} is short of the ground!",
    "LIGHTNING RELAY RUN OUT! {fielder} fires a bullet throw to wicketkeeper {wk}, who whips the bails off before {striker}'s bat can cross the line!",
    "CHAOS IN THE MIDDLE! {striker} called for a risky run, {fielder} pounced like a panther and caught {striker} miles out of the crease! Run out!"
  ],

  STUMPED: [
    "STUMPED IN A FLASH! {striker} charged down the pitch, beaten completely by the flight from {bowler}, and wicketkeeper {wk} takes the bails off at lightning speed!",
    "BRILLIANT GLOVEWORK BY {wk}! {bowler} drags {striker} out of the crease with a deceptive delivery and {wk} completes a textbook stumping!"
  ],

  LBW: [
    "HUGE APPEAL AND THE FINGER GOES UP! LBW! {bowler} traps {striker} plumb in front of middle and leg! Dead inline, three reds all day long!",
    "PINNED ON THE BACK PAD! {bowler} swings it back into the pads, {striker} misses the flick, and the umpire raises the finger immediately for LBW!"
  ],

  NO_BALL: [
    "SIREN BLARES! NO BALL! {bowler} has overstepped the popping crease! That is an extra run for {teamA} and the next delivery to {striker} will be a FREE HIT!",
    "OVERSTEPPED BY {bowler}! The third umpire triggers the hooter! Free Hit coming up now for {striker}—time to swing for the fences!"
  ],

  NO_BALL_SIX: [
    "PUNISHED TO THE MAXIMUM ON A NO BALL! {bowler} oversteps the line AND {striker} launches it into the stands for SIX! Seven runs off one delivery AND a Free Hit next ball!",
    "DOUBLE DISASTER FOR {bowler}! Siren goes off for a No Ball while the ball is still sailing into the upper deck off {striker}'s bat for SIX!"
  ],

  WIDE: [
    "WIDE BALL! {bowler} loses radar and sprays that way down the leg side! Wicketkeeper {wk} puts in a full-length dive to save four byes!",
    "Umpire stretches both arms horizontally! {bowler} pushes that delivery too far outside the tramline to {striker}. Extra run added to {teamA}!"
  ],

  BYE_1: [
    "Beats both {striker}'s bat and {wk}'s gloves! {striker} and {nonStriker} steal a quick bye while {fielder} chases it back!",
    "Deflected off the thigh pad of {striker} into the gap! Leg bye signaled by the umpire as the batters cross over!"
  ],

  OVERTHROW_4: [
    "OVERTHROWS! WILD THROW FROM {fielder} backs up past {wk} and races all the way to the boundary rope! Four bonus runs gifted to {striker} and {teamA}!"
  ]
};

var AFTERMATH_TAGS = [
  "The dugout is on its feet applauding!",
  "Look at the intensity on the field right now!",
  "Every single ball in this contest is pure box-office entertainment!",
  "The captain is immediately adjusting the field placements after that!",
  "What an atmosphere inside this packed stadium tonight!",
  "Broadcast cameras zooming straight in on the reaction!",
  "Championship-level cricket unfolding right before our eyes!",
  "That changes the momentum of this over completely!"
];

function fillTemplate(str, map) {
  return str
    .replace(/\{striker\}/g, map.striker)
    .replace(/\{nonStriker\}/g, map.nonStriker)
    .replace(/\{bowler\}/g, map.bowler)
    .replace(/\{wk\}/g, map.wk)
    .replace(/\{fielder\}/g, map.fielder)
    .replace(/\{teamA\}/g, map.teamA)
    .replace(/\{teamB\}/g, map.teamB);
}

function buildUniqueCommentary(eventCode, extraNote) {
  var runups = PHRASE_BANKS.runup;
  var outcomes = PHRASE_BANKS[eventCode] || PHRASE_BANKS.DOT;
  var candidate = "";

  for (var attempt = 0; attempt < 25; attempt++) {
    var rPhrase = runups[Math.floor(Math.random() * runups.length)];
    var oPhrase = outcomes[Math.floor(Math.random() * outcomes.length)];
    var aPhrase = AFTERMATH_TAGS[Math.floor(Math.random() * AFTERMATH_TAGS.length)];

    var raw = rPhrase + " " + oPhrase + " " + (extraNote ? extraNote + " " : "") + aPhrase;
    candidate = fillTemplate(raw, cricketState);

    if (cricketState.usedCommentaryHashes.indexOf(candidate) === -1) {
      break;
    }
  }

  recordCommentaryHash(candidate);
  return candidate;
}

/* ==================== BALL OUTCOME STATE MACHINE ==================== */
function getNextAvailableBatsman() {
  for (var i = 0; i < cricketState.squadA.length; i++) {
    var p = cricketState.squadA[i];
    ensurePlayerStats(p);
    if (p !== cricketState.striker && p !== cricketState.nonStriker && !cricketState.batStats[p].out) {
      return p;
    }
  }
  return cricketState.squadA[0] || "New Batter";
}

function triggerCricketBall(eventCode) {
  syncSelectedRoles();
  ensurePlayerStats(cricketState.striker);
  ensurePlayerStats(cricketState.nonStriker);
  ensurePlayerStats(cricketState.bowler);

  var sStat = cricketState.batStats[cricketState.striker];
  var bStat = cricketState.bowlStats[cricketState.bowler];
  var extraNote = "";
  var rotateStrike = false;
  var isLegalDelivery = true;
  var badgeText = "0";

  // Check if Free Hit prevents dismissal (except Run Out)
  if (cricketState.freeHitActive &&
      (eventCode === "BOWLED" || eventCode === "CAUGHT_FIELDER" || eventCode === "CAUGHT_WK" || eventCode === "STUMPED" || eventCode === "LBW")) {
    eventCode = "DOT";
    extraNote = "Wait! That was a FREE HIT delivery, so " + cricketState.striker + " cannot be given out!";
  }

  switch (eventCode) {
    case "DOT":
      sStat.balls++;
      bStat.balls++;
      badgeText = "0";
      break;
    case "RUN_1":
      cricketState.runs += 1;
      sStat.runs += 1; sStat.balls++;
      bStat.runs += 1; bStat.balls++;
      rotateStrike = true;
      badgeText = "1";
      break;
    case "RUN_2":
      cricketState.runs += 2;
      sStat.runs += 2; sStat.balls++;
      bStat.runs += 2; bStat.balls++;
      badgeText = "2";
      break;
    case "RUN_3":
      cricketState.runs += 3;
      sStat.runs += 3; sStat.balls++;
      bStat.runs += 3; bStat.balls++;
      rotateStrike = true;
      badgeText = "3";
      break;
    case "FOUR":
      cricketState.runs += 4;
      sStat.runs += 4; sStat.balls++; sStat.fours++;
      bStat.runs += 4; bStat.balls++;
      badgeText = "4";
      break;
    case "SIX":
      cricketState.runs += 6;
      sStat.runs += 6; sStat.balls++; sStat.sixes++;
      bStat.runs += 6; bStat.balls++;
      badgeText = "6";
      break;
    case "BOWLED":
    case "CAUGHT_FIELDER":
    case "CAUGHT_WK":
    case "RUN_OUT":
    case "STUMPED":
    case "LBW":
      cricketState.wickets += 1;
      sStat.balls++;
      sStat.out = true;
      bStat.balls++;
      if (eventCode !== "RUN_OUT") bStat.wickets++;
      badgeText = "W";
      break;
    case "NO_BALL":
      cricketState.runs += 1;
      bStat.runs += 1;
      isLegalDelivery = false;
      cricketState.freeHitActive = true;
      badgeText = "NB";
      break;
    case "NO_BALL_SIX":
      cricketState.runs += 7;
      sStat.runs += 6; sStat.balls++; sStat.sixes++;
      bStat.runs += 7;
      isLegalDelivery = false;
      cricketState.freeHitActive = true;
      badgeText = "NB+6";
      break;
    case "WIDE":
      cricketState.runs += 1;
      bStat.runs += 1;
      isLegalDelivery = false;
      badgeText = "WD";
      break;
    case "BYE_1":
      cricketState.runs += 1;
      sStat.balls++;
      bStat.balls++;
      rotateStrike = true;
      badgeText = "1B";
      break;
    case "OVERTHROW_4":
      cricketState.runs += 4;
      sStat.runs += 4; sStat.balls++;
      bStat.runs += 4; bStat.balls++;
      badgeText = "4-OT";
      break;
  }

  // Milestone detection (50 or 100)
  if (sStat.runs >= 50 && sStat.runs - 6 < 50 && sStat.runs < 56) {
    extraNote += "FIFTY UP FOR " + cricketState.striker + "! Raises the bat to all corners of the ground!";
  } else if (sStat.runs >= 100 && sStat.runs - 6 < 100 && sStat.runs < 106) {
    extraNote += "CENTURY FOR " + cricketState.striker + "! Take a bow, what a sensational hundred!";
  }

  // Generate commentary before replacing out batter so the dismissed batter's name is spoken
  var commentaryLine = buildUniqueCommentary(eventCode, extraNote);

  if (isLegalDelivery) {
    cricketState.legalBalls++;
    if (eventCode !== "NO_BALL" && eventCode !== "NO_BALL_SIX") {
      cricketState.freeHitActive = false;
    }
  }

  cricketState.thisOver.push(badgeText);

  // Handle new batsman coming in on wicket
  if (badgeText === "W") {
    var nextBat = getNextAvailableBatsman();
    document.getElementById("selStriker").value = nextBat;
    cricketState.striker = nextBat;
    commentaryLine += " " + nextBat + " walks out to the middle at number " + (cricketState.wickets + 2) + "!";
  } else if (rotateStrike) {
    swapStrikeManual();
  }

  // Handle End of Over (6 legal balls)
  if (isLegalDelivery && cricketState.legalBalls > 0 && cricketState.legalBalls % 6 === 0) {
    swapStrikeManual();
    var completedOvers = cricketState.legalBalls / 6;
    commentaryLine += " End of Over " + completedOvers + ". Score is " + cricketState.runs + " for " + cricketState.wickets + ".";
    cricketState.thisOver = [];
  }

  updateScoreboardUi();
  playStadiumSfx(eventCode);
  speakLiveCommentary(commentaryLine, eventCode);
}

function triggerCustomMilestoneCommentary() {
  syncSelectedRoles();
  var text = "Welcome back to the live broadcast! " + cricketState.teamA + " are currently " +
    cricketState.runs + " for " + cricketState.wickets + ". " + cricketState.striker +
    " and " + cricketState.nonStriker + " are at the crease facing " + cricketState.bowler +
    ", with " + cricketState.wk + " behind the stumps!";
  playStadiumSfx("FOUR");
  speakLiveCommentary(text, "MILESTONE");
}

function formatOvers(balls) {
  var o = Math.floor(balls / 6);
  var b = balls % 6;
  return o + "." + b;
}

function updateScoreboardUi() {
  document.getElementById("liveBattingTeamTitle").textContent = cricketState.teamA;
  document.getElementById("scoreRuns").textContent = cricketState.runs;
  document.getElementById("scoreWickets").textContent = cricketState.wickets;
  document.getElementById("scoreOvers").textContent = formatOvers(cricketState.legalBalls);

  var oversDecimal = cricketState.legalBalls > 0 ? (cricketState.legalBalls / 6) : 0;
  var crr = oversDecimal > 0 ? (cricketState.runs / oversDecimal).toFixed(2) : "0.00";
  document.getElementById("scoreCrr").textContent = crr;

  document.getElementById("thisOverBalls").textContent =
    cricketState.thisOver.length > 0 ? cricketState.thisOver.join(" • ") : "-";

  var fhBanner = document.getElementById("freeHitBanner");
  if (cricketState.freeHitActive) {
    fhBanner.classList.remove("hidden");
  } else {
    fhBanner.classList.add("hidden");
  }

  var sStat = cricketState.batStats[cricketState.striker] || { runs: 0, balls: 0 };
  var nsStat = cricketState.batStats[cricketState.nonStriker] || { runs: 0, balls: 0 };
  var bStat = cricketState.bowlStats[cricketState.bowler] || { runs: 0, wickets: 0, balls: 0 };

  document.getElementById("liveStrikerTxt").textContent = cricketState.striker;
  document.getElementById("strikerStatsTxt").textContent = sStat.runs + " (" + sStat.balls + ")";

  document.getElementById("liveNonStrikerTxt").textContent = cricketState.nonStriker;
  document.getElementById("nonStrikerStatsTxt").textContent = nsStat.runs + " (" + nsStat.balls + ")";

  document.getElementById("liveBowlerTxt").textContent = cricketState.bowler;
  document.getElementById("bowlerStatsTxt").textContent =
    bStat.wickets + "-" + bStat.runs + " (" + formatOvers(bStat.balls) + ")";
}

/* ==================== REAL VOICE COMMENTARY ENGINE ==================== */
function speakLiveCommentary(text, eventCode) {
  var banner = document.getElementById("liveSpeechBanner");
  if (banner) banner.textContent = "🎙 " + text;

  var feed = document.getElementById("commentaryFeedList");
  if (feed) {
    var item = document.createElement("div");
    item.className = "comm-item";
    item.innerHTML = "<strong>[" + formatOvers(cricketState.legalBalls) + " ov]</strong> " + text;
    feed.insertBefore(item, feed.firstChild);
  }

  var chkVoice = document.getElementById("chkRealVoice");
  if (chkVoice && !chkVoice.checked) return;

  var selectedLang = document.getElementById("selVoiceStyle").value || "en-IN";

  // Excitement modulation based on ball event
  var isHighExcitement = (eventCode === "SIX" || eventCode === "FOUR" || eventCode === "BOWLED" ||
    eventCode.indexOf("CAUGHT") !== -1 || eventCode === "RUN_OUT" || eventCode === "STUMPED" || eventCode === "LBW");

  if ("speechSynthesis" in window) {
    try {
      window.speechSynthesis.cancel();
      var utter = new SpeechSynthesisUtterance(text);
      utter.lang = selectedLang;
      utter.rate = isHighExcitement ? 1.12 : 1.02;
      utter.pitch = isHighExcitement ? 1.18 : 1.0;
      utter.volume = 1.0;

      var voices = window.speechSynthesis.getVoices() || [];
      for (var i = 0; i < voices.length; i++) {
        if (voices[i].lang && voices[i].lang.toLowerCase().indexOf(selectedLang.toLowerCase().slice(0, 2)) !== -1) {
          utter.voice = voices[i];
          if (voices[i].lang.toLowerCase() === selectedLang.toLowerCase()) break;
        }
      }
      window.speechSynthesis.speak(utter);
    } catch (e) {
      console.warn("SpeechSynthesis fallback:", e);
    }
  }
}

window.addEventListener("DOMContentLoaded", function() {
  if ("speechSynthesis" in window) {
    window.speechSynthesis.getVoices();
  }
  applySquadsAndPopulateDropdowns();
});
