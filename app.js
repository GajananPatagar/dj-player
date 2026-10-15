const AudioCtx = window.AudioContext || window.webkitAudioContext;
const ctx = new AudioCtx();

function createDeck(suffix) {
  const audio = new Audio();
  audio.crossOrigin = "anonymous";
  const source = ctx.createMediaElementSource(audio);
  const bass = ctx.createBiquadFilter();
  bass.type = "lowshelf";
  bass.frequency.value = 200;

  const gainNode = ctx.createGain();
  source.connect(bass);
  bass.connect(gainNode);
  gainNode.connect(ctx.destination);

  const fileInput = document.getElementById("file" + suffix);
  const playBtn = document.getElementById("play" + suffix);
  const cueBtn = document.getElementById("cue" + suffix);
  const rateSlider = document.getElementById("rate" + suffix);
  const gainSlider = document.getElementById("gain" + suffix);
  const bassSlider = document.getElementById("bass" + suffix);
  const platter = document.getElementById("platter" + suffix);
  const status = document.getElementById("status" + suffix);

  fileInput.addEventListener("change", (e) => {
    const file = e.target.files[0];
    if (!file) return;
    audio.src = URL.createObjectURL(file);
    status.textContent = "LOADED";
  });

  playBtn.addEventListener("click", async () => {
    if (ctx.state === "suspended") {
      await ctx.resume(); // Auto-heal suspended audio context
    }
    if (audio.paused) {
      await audio.play();
      platter.classList.add("spinning");
      status.textContent = "PLAYING";
    } else {
      audio.pause();
      platter.classList.remove("spinning");
      status.textContent = "PAUSED";
    }
  });

  cueBtn.addEventListener("click", () => {
    audio.pause();
    audio.currentTime = 0;
    platter.classList.remove("spinning");
    status.textContent = "CUE 0:00";
  });

  rateSlider.addEventListener("input", (e) => {
    audio.playbackRate = parseFloat(e.target.value);
  });

  gainSlider.addEventListener("input", (e) => {
    gainNode.gain.value = parseFloat(e.target.value);
  });

  bassSlider.addEventListener("input", (e) => {
    bass.gain.value = parseFloat(e.target.value);
  });

  return { audio, gainNode, gainSlider };
}

const deckA = createDeck("A");
const deckB = createDeck("B");

const crossfader = document.getElementById("crossfader");
crossfader.addEventListener("input", (e) => {
  const val = parseFloat(e.target.value);
  const baseA = parseFloat(deckA.gainSlider.value);
  const baseB = parseFloat(deckB.gainSlider.value);
  deckA.gainNode.gain.value = Math.cos(val * 0.5 * Math.PI) * baseA;
  deckB.gainNode.gain.value = Math.cos((1.0 - val) * 0.5 * Math.PI) * baseB;
});
