import processing.sound.*;

// Color Palettes (16 hex palettes converted to Processing color integers)
color[][] palettes = {
  {#564787, #DBCBD8, #F2FDFF, #9AD4D6, #101935},
  {#E55934, #5BC0EB, #404E4D, #C3BF6D, #B7B868},
  {#26547C, #FFF8E8, #FCD581, #D52941, #990D35},
  {#0E131F, #38405F, #59546C, #8B939C, #FF0035},
  {#080708, #3772FF, #DF2935, #FDCA40, #E6E8E6},
  {#0C0F0A, #FF206E, #FBFF12, #41EAD4, #FFFFFF},
  {#E8AEB7, #B8E1FF, #A9FFF7, #94FBAB, #82ABA1},
  {#ACBEA3, #40476D, #826754, #AD5D4E, #EB6534},
  {#313628, #595358, #857F74, #A4AC96, #CADF9E},
  {#EDD4B2, #D0A98F, #4D243D, #CAC2B5, #E0C9C9},
  {#FABC3C, #463F3A, #F19143, #37505C, #F55536},
  {#1A1F16, #1E3F20, #75B8C8, #53FF45, #CDD3D5},
  {#000000, #3D2645, #832161, #DA4167, #F0EFF4},
  {#161032, #FAFF81, #FFC53A, #E06D06, #B26700},
  {#3A4F41, #B9314F, #D5A18E, #DEC3BE, #E1DEE3},
  {#2B303A, #92DCE5, #EEEE59, #7C7C7C, #D64933}
};

// Canvas & Grid Parameters
int margin = 50;
int cols, rows;
float cellSize;
int num1, num2, num3, num4;

// Textures (6 textures: 1, 2, 3, 4, 7, 8)
PImage[] textures = new PImage[6];
PImage chosenTexture;
color[] currentPalette;
color[] targetPalette;
color[] activePaletteColors = new color[5];
float paletteLerp = 0;

// Visual Inertia / Lag Stage & Layout Morphing Variables
float smoothNum1 = 1, smoothNum2 = 1, smoothNum3 = 1, smoothNum4 = 1;
PGraphics bufferA, bufferB;
int currentMode = 0;
int targetMode = 0;
int prevMode = 0;
float modeTransition = 1.0; // 1.0 = fully settled into currentMode, < 1.0 = cross-fading
int pendingMode = -1; // desired next mode while Autonomous holds it back for a mutation tick

// Per-run seed: randomized on every launch so the same audio density state maps to a
// different palette/texture/mode than it did last run, instead of always lining up the
// same way (the mapping is otherwise a fixed formula on smoothNum1-4).
int visualSeed;
int paletteOffset, textureOffset, modeOffset;

// Sequencer Parameters
int steps = 16;
int globalStep = 0; // 0 to 31 (32 drum steps = 2 drum cycles = 1 chord cycle)
boolean[][] drumSequence = new boolean[16][4];  // Kick, Clap, HiHat, Snare
boolean[][] chordSequence = new boolean[16][5]; // Dm, Am, F, Gm, E7

// Sound Samples
SoundFile[] drumSounds = new SoundFile[4];
SoundFile[] chordSounds = new SoundFile[5];

// Playback & Mode State
boolean isPlaying = false;
boolean isAutonomous = false;
boolean showUI = true;
int activeBank = 0; // 0 = Drums, 1 = Chords
int bpm = 360;
int lastStepTime = 0;
int lastDrumMutationTime = 0;
int lastChordMutationTime = 0;
int currentChordVoice = -1; // which chord sample is currently ringing (mono chord bus)

// Autonomous "breathing" cycle: mostly net-additive, with occasional randomized dips
// toward near-silence before building back up. Durations are randomized (not on a
// fixed period) so the cadence doesn't read as mechanical to a casual observer.
final int PHASE_BUILD = 0;
final int PHASE_RELEASE = 1;
int mutationPhase = PHASE_BUILD;
int phaseEndTime = -1;
float globalRotation = 0;

void setup() {
  // size()/fullScreen() must be a single, literal, unconditional call — Processing's
  // preprocessor won't accept it behind a variable or an if/else. To switch modes,
  // comment/uncomment the pair below (and the noCursor() line with it).
  fullScreen(P2D);         // Fullscreen, installation mode (default)
  // size(1000, 800, P2D); // Windowed dev canvas — swap the comment with the line above

  noCursor(); // comment this out too when running windowed, to keep the cursor visible

  smooth(4);

  // Reseed explicitly so this run's palette/texture/mode mapping is independent of
  // last run's, rather than relying on default PRNG behavior.
  visualSeed = (int) (System.nanoTime() % 1000000);
  randomSeed(visualSeed);
  noiseSeed(visualSeed);
  paletteOffset = (int) random(palettes.length);
  textureOffset = (int) random(textures.length);
  modeOffset = (int) random(6);
  println("Visual seed: " + visualSeed);

  // Initialize off-screen graphics buffers for smooth layout cross-fading stage
  bufferA = createGraphics(width, height, P2D);
  bufferB = createGraphics(width, height, P2D);

  // Load & Pre-Scale Textures (Textures 1, 2, 3, 4, 7, 8)
  int[] texIndices = {1, 2, 3, 4, 7, 8};
  for (int i = 0; i < 6; i++) {
    textures[i] = loadImage("textures/Texture" + texIndices[i] + "-8K.jpg");
    if (textures[i] != null) {
      textures[i].resize(width, height); // Pre-scale to canvas size to eliminate 8K GPU rendering overhead
    }
  }
  // Load Sound Samples
  try {
    drumSounds[0] = new SoundFile(this, "samples/Kick.wav");
    drumSounds[1] = new SoundFile(this, "samples/Clap.wav");
    drumSounds[2] = new SoundFile(this, "samples/HiHat.wav");
    drumSounds[3] = new SoundFile(this, "samples/Snare.wav");

    chordSounds[0] = new SoundFile(this, "samples/Dm.wav");
    chordSounds[1] = new SoundFile(this, "samples/Am.wav");
    chordSounds[2] = new SoundFile(this, "samples/F.wav");
    chordSounds[3] = new SoundFile(this, "samples/Gm.wav");
    chordSounds[4] = new SoundFile(this, "samples/E7.wav");
  } catch (Exception e) {
    println("Audio files loaded with fallback handling: " + e.getMessage());
  }

  // Pre-fill a subtle default drum pattern
  drumSequence[0][0] = true; // Kick on 1
  drumSequence[4][1] = true; // Clap on 5
  drumSequence[8][0] = true; // Kick on 9
  drumSequence[12][3] = true; // Snare on 13
  chordSequence[0][0] = true; // Dm on 1
  chordSequence[8][2] = true; // F on 9

  snapVisualState();

  textFont(createFont("SansSerif", 14));
}

void draw() {
  background(0);

  // Calculate parameters based on sequences
  updateSequenceParameters();

  // Always draw generative art so shapes are visible
  drawGenerativeArt();

  if (isPlaying) {
    // Autonomous music evolution logic
    if (isAutonomous) {
      handleAutonomousMutation();
    }

    // Step Timing (32 global steps: 2 drum cycles of 16 steps, 1 chord cycle of 16 steps)
    int stepDuration = 60000 / bpm;
    int currentTime = millis();
    if (currentTime - lastStepTime >= stepDuration) {
      playStep();
      globalStep = (globalStep + 1) % 32;
      lastStepTime = currentTime;
    }
  }

  // Draw Drum Machine / Sequencer UI overlay if showUI is active
  if (showUI) {
    drawSequencerUI();
    drawHUD();
  }
}

void updateSequenceParameters() {
  num1 = countActiveSounds(drumSequence, 0) + countActiveSounds(chordSequence, 0) + countActiveSounds(chordSequence, 4) + 1;
  num2 = countActiveSounds(drumSequence, 1) + countActiveSounds(chordSequence, 1) + 1;
  num3 = countActiveSounds(drumSequence, 2) + countActiveSounds(chordSequence, 2) + 1;
  num4 = countActiveSounds(drumSequence, 3) + countActiveSounds(chordSequence, 3) + 1;

  // Visual Inertia / Parameter Lag Stage: smooth exponential lerping
  smoothNum1 += (num1 - smoothNum1) * 0.03;
  smoothNum2 += (num2 - smoothNum2) * 0.03;
  smoothNum3 += (num3 - smoothNum3) * 0.03;
  smoothNum4 += (num4 - smoothNum4) * 0.03;

  calculateGridParameters();

  // Pick target palette & texture (from 6 textures)
  targetPalette = palettes[computePaletteIndex()];
  chosenTexture = textures[computeTextureIndex()];

  // Smooth palette transition wave
  paletteLerp += 0.015;
  if (paletteLerp > 1.0) paletteLerp = 1.0;

  // Precompute 5 active palette colors
  for (int k = 0; k < 5; k++) {
    activePaletteColors[k] = lerpColor(currentPalette[k], targetPalette[k], paletteLerp);
  }

  // Detect desired mode layout from current density
  int newMode = computeModeIndex();
  if (isAutonomous && isPlaying) {
    // In Auto mode, hold the desired layout back and only commit it at the next
    // mutation tick (see handleAutonomousMutation) so background changes read as
    // part of the piece evolving, not a side effect of density noise.
    if (newMode != currentMode) pendingMode = newMode;
  } else if (newMode != targetMode && modeTransition >= 1.0) {
    prevMode = currentMode;
    targetMode = newMode;
    modeTransition = 0.0;
  }
}

int computePaletteIndex() {
  int raw = (int) (abs(smoothNum1 * 1.1 + smoothNum2 * 1.2 + smoothNum3 * 0.9 + smoothNum4 * 1.3));
  return (raw + paletteOffset) % palettes.length;
}

int computeTextureIndex() {
  int raw = (int) (abs(smoothNum1 * 0.8 + smoothNum2 * 1.1 + smoothNum3 * 1.0 + smoothNum4 * 0.9));
  return (raw + textureOffset) % textures.length;
}

int computeModeIndex() {
  return (((int) smoothNum4) + modeOffset) % 6;
}

// Instantly settles the visual state to match the current sequence — used on startup and
// after Clear so the sketch opens/resets already "arrived" instead of animating through
// several intermediate shapes/colors/textures while the lag stage catches up from scratch.
void snapVisualState() {
  num1 = countActiveSounds(drumSequence, 0) + countActiveSounds(chordSequence, 0) + countActiveSounds(chordSequence, 4) + 1;
  num2 = countActiveSounds(drumSequence, 1) + countActiveSounds(chordSequence, 1) + 1;
  num3 = countActiveSounds(drumSequence, 2) + countActiveSounds(chordSequence, 2) + 1;
  num4 = countActiveSounds(drumSequence, 3) + countActiveSounds(chordSequence, 3) + 1;

  smoothNum1 = num1;
  smoothNum2 = num2;
  smoothNum3 = num3;
  smoothNum4 = num4;

  calculateGridParameters();

  currentPalette = palettes[computePaletteIndex()];
  targetPalette = currentPalette;
  chosenTexture = textures[computeTextureIndex()];
  paletteLerp = 1.0;
  for (int k = 0; k < 5; k++) activePaletteColors[k] = currentPalette[k];

  int settledMode = computeModeIndex();
  prevMode = settledMode;
  currentMode = settledMode;
  targetMode = settledMode;
  modeTransition = 1.0;
  pendingMode = -1;
}

void calculateGridParameters() {
  float maxCells = max(8, min(20, smoothNum1 * 3));
  cellSize = min(width / maxCells, height / maxCells);
  cols = floor(width / cellSize);
  rows = floor(height / cellSize);
}

void drawGenerativeArt() {
  background(activePaletteColors[0]);

  // Advance layout mode transition stage progress
  if (modeTransition < 1.0) {
    modeTransition += 0.012; // ~2.5 second morph stage
    if (modeTransition >= 1.0) {
      modeTransition = 1.0;
      currentMode = targetMode;
    }
  }

  globalRotation += 0.002 * (smoothNum2 / 4.0);

  if (modeTransition >= 1.0) {
    // Direct rendering to main canvas
    pushMatrix();
    translate(width / 2, height / 2);
    rotate(globalRotation);
    translate(-width / 2, -height / 2);
    renderModePattern(this.g, currentMode);
    popMatrix();
  } else if (isParticleMode(prevMode) && isParticleMode(targetMode)) {
    // True geometric morph: grid/radial/checkerboard/multi-radial share one particle
    // system, so each particle can slide/scale/rotate directly toward its position
    // in the new layout instead of dissolving between two flat renders.
    pushMatrix();
    translate(width / 2, height / 2);
    rotate(globalRotation);
    translate(-width / 2, -height / 2);
    drawMorphedParticles(this.g, prevMode, targetMode, modeTransition);
    popMatrix();
  } else {
    // One endpoint is Waves or Kaleidoscope (not particle-based) — fall back to a
    // cross-fade between the two rendered layouts.
    renderModePattern(bufferA, prevMode);
    renderModePattern(bufferB, targetMode);

    // Composite outgoing layout buffer with fade-out
    tint(255, (1.0 - modeTransition) * 255);
    image(bufferA, 0, 0);

    // Composite incoming layout buffer with fade-in
    tint(255, modeTransition * 255);
    image(bufferB, 0, 0);
    noTint();
  }

  // Blend Texture Overlay
  if (chosenTexture != null) {
    tint(255, 120);
    blendMode(BLEND);
    image(chosenTexture, 0, 0);
    noTint();
  }
}

void renderModePattern(PGraphics target, int mode) {
  boolean isOffscreen = (target != this.g);
  if (isOffscreen) {
    target.beginDraw();
    target.background(activePaletteColors[0]);
    target.pushMatrix();
    target.translate(width / 2, height / 2);
    target.rotate(globalRotation);
    target.translate(-width / 2, -height / 2);
  }

  if (isParticleMode(mode)) {
    drawParticleMode(target, mode);
  } else {
    switch(mode) {
      case 4: drawOscillatingWaves(target); break;
      case 5: drawKaleidoscope(target); break;
    }
  }

  if (isOffscreen) {
    target.popMatrix();
    target.endDraw();
  }
}

color getInterpolatedColor(int index) {
  return activePaletteColors[index % 5];
}

void drawShape(PGraphics g, int index, float size) {
  switch(index % 6) {
    case 0:
      g.rectMode(CENTER);
      g.rect(0, 0, size, size);
      break;
    case 1:
      g.ellipse(0, 0, size, size);
      break;
    case 2:
      g.triangle(-size / 2, size / 2, 0, -size / 2, size / 2, size / 2);
      break;
    case 3:
      drawStar(g, 0, 0, size / 3, size / 2, 5);
      break;
    case 4:
      drawRegularPolygon(g, 0, 0, size / 2, 6);
      break;
    case 5:
      drawRegularPolygon(g, 0, 0, size / 2, 5);
      break;
  }
}

void drawStar(PGraphics g, float x, float y, float radius1, float radius2, int npoints) {
  float angle = TWO_PI / npoints;
  float halfAngle = angle / 2.0;
  g.beginShape();
  for (float a = 0; a < TWO_PI; a += angle) {
    float sx = x + cos(a) * radius2;
    float sy = y + sin(a) * radius2;
    g.vertex(sx, sy);
    sx = x + cos(a + halfAngle) * radius1;
    sy = y + sin(a + halfAngle) * radius1;
    g.vertex(sx, sy);
  }
  g.endShape(CLOSE);
}

void drawRegularPolygon(PGraphics g, float x, float y, float radius, int npoints) {
  float angle = TWO_PI / npoints;
  g.beginShape();
  for (float a = 0; a < TWO_PI; a += angle) {
    float sx = x + cos(a) * radius;
    float sy = y + sin(a) * radius;
    g.vertex(sx, sy);
  }
  g.endShape(CLOSE);
}

// --- Particle-based layout system (modes 0-3) -------------------------------
// Grid, Radial, Checkerboard, and Multi-Radial are all expressed as the same
// number of "particles" (see particleN), each placed by a mode-specific formula
// that is a pure function of (index, total, time). Because every mode produces
// the same particle count in the same index order, two modes' particles can be
// paired up 1:1 and lerped directly (see drawMorphedParticles) for a true
// geometric morph instead of an image dissolve.

class ShapeInst {
  float x, y, size, rot;
  int colorIdx, shapeIdx;
  ShapeInst(float x, float y, float size, float rot, int colorIdx, int shapeIdx) {
    this.x = x;
    this.y = y;
    this.size = size;
    this.rot = rot;
    this.colorIdx = colorIdx;
    this.shapeIdx = shapeIdx;
  }
}

boolean isParticleMode(int mode) {
  return mode >= 0 && mode <= 3;
}

int particleN() {
  return constrain(cols * rows, 30, 280);
}

float lerpAngle(float a, float b, float amt) {
  float diff = b - a;
  while (diff > PI) diff -= TWO_PI;
  while (diff < -PI) diff += TWO_PI;
  return a + diff * amt;
}

ShapeInst buildInstance(int mode, int i, int N, float t) {
  switch(mode) {
    case 1: return radialInstance(i, N, t);
    case 2: return checkerInstance(i, N, t);
    case 3: return multiRadialInstance(i, N, t);
    default: return gridInstance(i, N, t);
  }
}

ShapeInst gridInstance(int i, int N, float t) {
  int gcols = max(1, round(sqrt(N * (float) width / height)));
  int grows = max(1, ceil((float) N / gcols));
  int col = i % gcols;
  int row = i / gcols;
  float cw = width / (float) gcols;
  float ch = height / (float) grows;
  float xPos = col * cw + cw / 2;
  float yPos = row * ch + ch / 2;
  float nVal = noise(col * 0.3, row * 0.3, t);
  float localCell = min(cw, ch);
  float offset = (nVal - 0.5) * localCell * (smoothNum3 / 10.0);
  float size = localCell * max(0.4, smoothNum2 / 12.0);
  return new ShapeInst(xPos + offset, yPos + offset, size, nVal * TWO_PI, (col + row) % 5, (col + row) % 6);
}

ShapeInst radialInstance(int i, int N, float t) {
  float goldenAngle = 137.50776 * PI / 180.0;
  float centerX = width / 2, centerY = height / 2;
  float maxRadius = min(centerX, centerY);
  float rNorm = sqrt((i + 0.5) / N);
  float r = rNorm * maxRadius;
  float angle = i * goldenAngle;
  float spacing = maxRadius / sqrt(N);
  float size = spacing * max(0.5, smoothNum2 / 10.0);
  float nVal = noise(r * 0.02, i * 0.02, t);
  float offR = (nVal - 0.5) * size * (smoothNum3 / 8.0);
  float xPos = centerX + cos(angle) * (r + offR);
  float yPos = centerY + sin(angle) * (r + offR);
  return new ShapeInst(xPos, yPos, size, angle, i % 5, i % 6);
}

ShapeInst checkerInstance(int i, int N, float t) {
  int gcols = max(1, round(sqrt(N * (float) width / height)));
  int grows = max(1, ceil((float) N / gcols));
  int col = i % gcols;
  int row = i / gcols;
  float cw = width / (float) gcols;
  float ch = height / (float) grows;
  float brickOffset = (row % 2 == 1) ? cw / 2 : 0;
  float xPos = col * cw + cw / 2 + brickOffset;
  float yPos = row * ch + ch / 2;
  float size = min(cw, ch) * max(0.35, smoothNum2 / 14.0) * 0.9;
  return new ShapeInst(xPos, yPos, size, 0, (col + row) % 5, (col + row) % 6);
}

ShapeInst multiRadialInstance(int i, int N, float t) {
  int numCenters = max(2, min(8, (int) smoothNum4));
  int perCenter = max(1, N / numCenters);
  int centerIdx = i % numCenters;
  int localIdx = i / numCenters;
  float clusterAngle = centerIdx * TWO_PI / numCenters;
  float centerRadius = min(width, height) / (2.5 * sqrt(numCenters));
  float cx = width / 2 + cos(clusterAngle) * centerRadius;
  float cy = height / 2 + sin(clusterAngle) * centerRadius;
  float goldenAngle = 137.50776 * PI / 180.0;
  float rNorm = sqrt((localIdx + 0.5) / (float) perCenter);
  float maxR = min(width, height) * 0.22;
  float r = rNorm * maxR;
  float angle = localIdx * goldenAngle;
  float xPos = cx + cos(angle) * r;
  float yPos = cy + sin(angle) * r;
  float size = cellSize * 0.8 * max(0.4, smoothNum2 / 12.0);
  return new ShapeInst(xPos, yPos, size, angle, (centerIdx + localIdx) % 5, (centerIdx + localIdx) % 6);
}

void drawInstance(PGraphics g, ShapeInst s) {
  color c = activePaletteColors[s.colorIdx];
  g.stroke(c);
  g.strokeWeight(1.5);
  g.fill(c, 180);
  g.pushMatrix();
  g.translate(s.x, s.y);
  g.rotate(s.rot);
  drawShape(g, s.shapeIdx, s.size);
  g.popMatrix();
}

void drawParticleMode(PGraphics g, int mode) {
  float t = millis() * 0.0003;
  int N = particleN();
  for (int i = 0; i < N; i++) {
    drawInstance(g, buildInstance(mode, i, N, t));
  }
}

void drawMorphedParticles(PGraphics g, int modeA, int modeB, float amt) {
  float t = millis() * 0.0003;
  int N = particleN();
  for (int i = 0; i < N; i++) {
    ShapeInst a = buildInstance(modeA, i, N, t);
    ShapeInst b = buildInstance(modeB, i, N, t);
    float x = lerp(a.x, b.x, amt);
    float y = lerp(a.y, b.y, amt);
    float sz = lerp(a.size, b.size, amt);
    float rot = lerpAngle(a.rot, b.rot, amt);
    color colA = activePaletteColors[a.colorIdx];
    color colB = activePaletteColors[b.colorIdx];

    g.pushMatrix();
    g.translate(x, y);
    g.rotate(rot);
    g.strokeWeight(1.5);

    // Outgoing silhouette fades out while sliding to the shared (x, y)
    g.stroke(colA, (1.0 - amt) * 255);
    g.fill(colA, (1.0 - amt) * 180);
    drawShape(g, a.shapeIdx, sz);

    // Incoming silhouette fades in over the same moving position
    g.stroke(colB, amt * 255);
    g.fill(colB, amt * 180);
    drawShape(g, b.shapeIdx, sz);

    g.popMatrix();
  }
}

void drawOscillatingWaves(PGraphics g) {
  float centerX = width / 2;
  float centerY = height / 2;
  float t = millis() * 0.002;

  for (int r = 20; r < min(width, height) / 2; r += 20) {
    g.noFill();
    color c = activePaletteColors[(r / 20) % 5];
    g.stroke(c, 200);
    g.strokeWeight(2);

    g.beginShape();
    for (float a = 0; a < TWO_PI; a += 0.1) {
      float wave = sin(a * smoothNum3 + t + r * 0.05) * (smoothNum2 * 3.0);
      float x = centerX + cos(a) * (r + wave);
      float y = centerY + sin(a) * (r + wave);
      g.vertex(x, y);
    }
    g.endShape(CLOSE);
  }
}

void drawKaleidoscope(PGraphics g) {
  int segments = max(4, (int) smoothNum1 * 2);
  float angleStep = TWO_PI / segments;
  float centerX = width / 2;
  float centerY = height / 2;

  g.pushMatrix();
  g.translate(centerX, centerY);
  for (int i = 0; i < segments; i++) {
    g.rotate(angleStep);
    color c = activePaletteColors[i % 5];
    g.stroke(c);
    g.fill(c, 140);

    float d = sin(millis() * 0.001 + i) * 100 + 150;
    g.ellipse(d, 0, 30 + smoothNum2 * 2, 30 + smoothNum3 * 2);
  }
  g.popMatrix();
}

void drawSequencerUI() {
  float centerX = width / 2;
  float centerY = height / 2;
  float radiusOuter = min(width, height) * 0.38;
  float radiusInner = min(width, height) * 0.28;

  // Outer Ring Guide
  noFill();
  stroke(255, 30);
  strokeWeight(2);
  ellipse(centerX, centerY, radiusOuter * 2, radiusOuter * 2);
  ellipse(centerX, centerY, radiusInner * 2, radiusInner * 2);

  color[] drumColors = {#3232C8, #C8C832, #C83232, #32C832};
  color[] chordColors = {#9B51E0, #2F80ED, #F2994A, #EB5757, #6FCF97}; // Dm, Am, F, Gm, E7

  for (int i = 0; i < steps; i++) {
    float angle = map(i, 0, steps, 0, TWO_PI) - HALF_PI;

    // Outer Ring (Drums)
    float xOuter = centerX + cos(angle) * radiusOuter;
    float yOuter = centerY + sin(angle) * radiusOuter;

    for (int j = 0; j < 4; j++) {
      if (drumSequence[i][j]) {
        fill(drumColors[j], 220);
        noStroke();
        ellipse(xOuter + (j - 1.5) * 8, yOuter, 10, 10);
      }
    }

    // Inner Ring (Chords)
    float xInner = centerX + cos(angle) * radiusInner;
    float yInner = centerY + sin(angle) * radiusInner;

    for (int j = 0; j < 5; j++) {
      if (chordSequence[i][j]) {
        fill(chordColors[j], 220);
        noStroke();
        ellipse(xInner + (j - 2.0) * 8, yInner, 10, 10);
      }
    }

    // Step Numbers / Highlights
    noStroke();
    int currentDrumStep = globalStep % 16;
    int currentChordStep = (globalStep / 2) % 16;

    if (i == currentDrumStep || i == currentChordStep) {
      fill(255);
      textSize(16);
      if (i == currentDrumStep && i == currentChordStep) {
        text("[" + (i + 1) + "]", xOuter, yOuter);
      } else if (i == currentDrumStep) {
        text("<" + (i + 1) + ">", xOuter, yOuter); // Drum step indicator
      } else {
        text("(" + (i + 1) + ")", xInner, yInner); // Chord step indicator
      }
    } else {
      fill(160);
      textSize(13);
      text(i + 1, xOuter, yOuter);
    }
  }
}

void drawHUD() {
  fill(0, 180);
  noStroke();
  rect(15, 15, 380, 150, 10);

  fill(255);
  textAlign(LEFT, TOP);
  textSize(14);
  text("CONTROL PANEL", 25, 25);
  
  textSize(12);
  fill(isPlaying ? color(80, 255, 120) : color(255, 100, 100));
  text("Status: " + (isPlaying ? "PLAYING" : "PAUSED (Press SPACE)"), 25, 45);

  fill(activeBank == 0 ? color(100, 200, 255) : color(255, 180, 100));
  text("Active Bank [TAB]: " + (activeBank == 0 ? "DRUMS (1:1 Speed)" : "CHORDS (1/2 Speed across 2 Drum Cycles)"), 25, 65);

  fill(isAutonomous ? color(255, 215, 0) : color(180));
  text("Autonomous Mode [A]: " + (isAutonomous ? "ON (Drums: fast | Chords: slow rate)" : "OFF"), 25, 85);

  fill(200);
  text("Key Commands: [H] Hide UI | [Space] Play/Pause | [TAB] Bank", 25, 105);
  text("              [A] Auto Mode | [C] Clear | [T/Y] Prev/Next", 25, 125);

  textAlign(CENTER, CENTER);
}

// Advances the Build/Release breathing cycle. Release doesn't fire every time a Build
// stretch ends (only ~55% of the time), and both phase lengths are randomized ranges,
// so dips arrive at irregular, unpredictable intervals rather than a fixed period.
void updateMutationPhase() {
  int now = millis();
  if (phaseEndTime < 0) {
    phaseEndTime = now + (int) random(70000, 160000);
    return;
  }
  if (now < phaseEndTime) return;

  if (mutationPhase == PHASE_BUILD) {
    if (random(1.0) < 0.55) {
      mutationPhase = PHASE_RELEASE;
      phaseEndTime = now + (int) random(18000, 42000);
    } else {
      phaseEndTime = now + (int) random(70000, 160000);
    }
  } else {
    mutationPhase = PHASE_BUILD;
    phaseEndTime = now + (int) random(70000, 160000);
  }
}

void handleAutonomousMutation() {
  updateMutationPhase();
  boolean releasing = (mutationPhase == PHASE_RELEASE);
  int currentTime = millis();
  int stepMs = 60000 / bpm;

  // 1. DRUM MUTATION (Evaluated every 8 drum steps ~1.3s)
  if (currentTime - lastDrumMutationTime > stepMs * 8) {
    lastDrumMutationTime = currentTime;
    if (random(1.0) < (releasing ? 0.9 : 0.8)) {
      int randVoice = (int) random(4);
      int activeCount = countActiveSounds(drumSequence, randVoice);

      if (releasing) {
        // Thin this voice toward near-silence; leave a rare spark so it never goes fully dead
        if (activeCount > 0) {
          for (int attempts = 0; attempts < 10; attempts++) {
            int s = (int) random(16);
            if (drumSequence[s][randVoice]) {
              drumSequence[s][randVoice] = false;
              break;
            }
          }
        } else if (random(1.0) < 0.1) {
          int s = (int) random(16);
          drumSequence[s][randVoice] = true;
        }
      } else if (activeCount < 3) {
        // Prefer adding a note to an empty step
        for (int attempts = 0; attempts < 10; attempts++) {
          int s = (int) random(16);
          if (!drumSequence[s][randVoice]) {
            drumSequence[s][randVoice] = true;
            break;
          }
        }
      } else if (activeCount > 7) {
        // Prefer removing a note from an active step
        for (int attempts = 0; attempts < 10; attempts++) {
          int s = (int) random(16);
          if (drumSequence[s][randVoice]) {
            drumSequence[s][randVoice] = false;
            break;
          }
        }
      } else {
        // Toggle random step
        int randStep = (int) random(16);
        drumSequence[randStep][randVoice] = !drumSequence[randStep][randVoice];
      }
    }
  }

  // 2. CHORD MUTATION (Evaluated at REDUCED RATE: every 32 drum steps = 2 full drum cycles ~5.3s)
  if (currentTime - lastChordMutationTime > stepMs * 32) {
    lastChordMutationTime = currentTime;
    if (random(1.0) < (releasing ? 0.75 : 0.4)) {
      int randVoice = (int) random(5);
      int activeCount = countActiveSounds(chordSequence, randVoice);

      if (releasing) {
        if (activeCount > 0) {
          for (int attempts = 0; attempts < 10; attempts++) {
            int s = (int) random(16);
            if (chordSequence[s][randVoice]) {
              chordSequence[s][randVoice] = false;
              break;
            }
          }
        } else if (random(1.0) < 0.1) {
          for (int attempts = 0; attempts < 10; attempts++) {
            int s = (int) random(16);
            if (!chordSequence[s][randVoice]) {
              setChordStep(s, randVoice);
              break;
            }
          }
        }
      } else if (activeCount < 2) {
        // Prefer adding a chord note (only one chord voice may occupy a step)
        for (int attempts = 0; attempts < 10; attempts++) {
          int s = (int) random(16);
          if (!chordSequence[s][randVoice]) {
            setChordStep(s, randVoice);
            break;
          }
        }
      } else if (activeCount > 6) {
        // Prefer removing a chord note
        for (int attempts = 0; attempts < 10; attempts++) {
          int s = (int) random(16);
          if (chordSequence[s][randVoice]) {
            chordSequence[s][randVoice] = false;
            break;
          }
        }
      } else {
        int randStep = (int) random(16);
        if (chordSequence[randStep][randVoice]) {
          chordSequence[randStep][randVoice] = false;
        } else {
          setChordStep(randStep, randVoice);
        }
      }

      // Trigger palette morph on chord progression shift
      paletteLerp = 0;
      currentPalette = targetPalette;

      // Commit any pending background layout change at this same mutation tick
      if (pendingMode != -1 && pendingMode != currentMode && modeTransition >= 1.0) {
        prevMode = currentMode;
        targetMode = pendingMode;
        modeTransition = 0.0;
        pendingMode = -1;
      }
    }
  }
}

void playStep() {
  int currentDrumStep = globalStep % 16;
  int currentChordStep = (globalStep / 2) % 16;

  // Play active drum sounds on every step (1:1 speed, loops every 16 steps)
  for (int i = 0; i < 4; i++) {
    if (drumSequence[currentDrumStep][i] && drumSounds[i] != null) {
      drumSounds[i].play();
    }
  }

  // Play the chord on HALF-TIME (every 2 drum steps, 16 steps total across 2 drum cycles).
  // Chord samples are ~12s and sustain past their step, so at most one plays at a time:
  // triggering a new one cuts off whatever chord was still ringing.
  if (globalStep % 2 == 0) {
    int activeVoice = -1;
    for (int i = 0; i < 5; i++) {
      if (chordSequence[currentChordStep][i]) {
        activeVoice = i;
        break;
      }
    }
    if (activeVoice != -1 && chordSounds[activeVoice] != null) {
      if (currentChordVoice != -1 && currentChordVoice != activeVoice && chordSounds[currentChordVoice] != null) {
        chordSounds[currentChordVoice].stop();
      }
      chordSounds[activeVoice].play();
      currentChordVoice = activeVoice;
    }
  }
}

int countActiveSounds(boolean[][] seq, int voiceIndex) {
  int count = 0;
  for (int i = 0; i < steps; i++) {
    if (seq[i][voiceIndex]) count++;
  }
  return count;
}

// Only one chord voice may occupy a given step; activating one clears any other on that step.
void setChordStep(int step, int voice) {
  for (int k = 0; k < 5; k++) chordSequence[step][k] = false;
  chordSequence[step][voice] = true;
}

void keyPressed() {
  int currentDrumStep = globalStep % 16;
  int currentChordStep = (globalStep / 2) % 16;

  if (key == ' ') {
    isPlaying = !isPlaying;
    if (isPlaying) {
      lastStepTime = millis();
      globalStep = 0;
      playStep();
    }
  } else if (key == '\t' || key == TAB || keyCode == TAB) {
    activeBank = (activeBank == 0) ? 1 : 0;
  } else if (key == 'h' || key == 'H') {
    showUI = !showUI;
  } else if (key == 'a' || key == 'A') {
    isAutonomous = !isAutonomous;
  } else if (key == 'c' || key == 'C') {
    for (int i = 0; i < steps; i++) {
      for (int j = 0; j < 4; j++) drumSequence[i][j] = false;
      for (int j = 0; j < 5; j++) chordSequence[i][j] = false;
    }
    if (currentChordVoice != -1 && chordSounds[currentChordVoice] != null) {
      chordSounds[currentChordVoice].stop();
    }
    currentChordVoice = -1;
    snapVisualState();
  } else if (key == 'y' || key == 'Y') {
    globalStep = (globalStep + 1) % 32;
  } else if (key == 't' || key == 'T') {
    globalStep = (globalStep - 1 + 32) % 32;
  }

  // Sound triggers based on active bank
  if (activeBank == 0) { // Drums
    char[] drumKeys = {'q', 'w', 'e', 'r'};
    for (int j = 0; j < 4; j++) {
      if (key == drumKeys[j] || key == Character.toUpperCase(drumKeys[j])) {
        drumSequence[currentDrumStep][j] = !drumSequence[currentDrumStep][j];
        if (drumSounds[j] != null) drumSounds[j].play();
      }
    }
  } else { // Chords (16 steps across 2 drum cycles) — one chord voice per step
    char[] chordKeys = {'1', '2', '3', '4', '5'};
    for (int j = 0; j < 5; j++) {
      if (key == chordKeys[j]) {
        boolean turningOn = !chordSequence[currentChordStep][j];
        if (turningOn) {
          setChordStep(currentChordStep, j);
          if (chordSounds[j] != null) chordSounds[j].play();
        } else {
          chordSequence[currentChordStep][j] = false;
        }
      }
    }
  }
}
