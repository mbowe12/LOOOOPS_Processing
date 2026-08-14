# Processing Loops

A generative audio-visual instrument built in Processing. A step sequencer drives drum
and chord samples, and the same sequence data drives a generative background — shape
density, color palette, texture, and layout all react to what's currently playing, with
a lag/mutation system that keeps everything drifting and morphing smoothly instead of
snapping.

## Requirements

- [Processing](https://processing.org/download) 4.x
- The **Sound** library (Processing IDE → Sketch → Import Library → Add Library → search
  "Sound" → Install)

## Running it

Open `Processing_Loops.pde` in the Processing IDE and press Run (▶). By default the
sketch launches fullscreen (mouse cursor hidden) at your display's native resolution,
with the sequencer paused and the background already settled into its starting layout —
press Space to start playback. Press `Esc` to quit.

To run windowed instead (useful during development), open `setup()` at the top of
`Processing_Loops.pde` and swap which line is commented out — use `size(1000, 800, P2D)`
instead of `fullScreen(P2D)`, and comment out the `noCursor()` line too so the cursor
stays visible. (Processing requires `size()`/`fullScreen()` to be a single literal call,
so this has to be a source edit rather than a runtime toggle.)

## Controls

| Key | Action |
|---|---|
| `Space` | Play / pause the sequencer |
| `TAB` | Switch the editing bank between Drums and Chords |
| `A` | Toggle Autonomous mode (the sequencer mutates its own pattern over time) |
| `H` | Show / hide the sequencer UI overlay |
| `C` | Clear both sequences and reset the visuals to their settled starting state |
| `T` / `Y` | Step the playhead back / forward one step |

**Drums bank** (`TAB` to select) — toggles a step at the current drum playhead position:

| Key | Voice |
|---|---|
| `Q` | Kick |
| `W` | Clap |
| `E` | Hi-Hat |
| `R` | Snare |

**Chords bank** (`TAB` to select) — toggles a step at the current chord playhead
position. Only one chord can occupy a given step; activating a new one replaces
whatever was there:

| Key | Chord |
|---|---|
| `1` | Dm |
| `2` | Am |
| `3` | F |
| `4` | Gm |
| `5` | E7 |

Drums run at 1:1 speed (16 steps, one drum cycle). Chords run at half-time across 32
global steps (16 chord steps spanning 2 drum cycles), and only one chord sample rings
at a time — triggering a new one cuts off whatever was still playing.

## Automated visuals mode

To run the piece as an unattended, self-generating audio-visual loop (installation,
screensaver, ambient background):

1. Press **Space** to start playback.
2. Press **A** to turn on Autonomous mode — the sequencer will add, remove, and swap
   drum and chord notes on its own timer from here on, no input needed.
3. Press **H** to hide the sequencer UI overlay, leaving just the generative
   background.

In this state the piece runs indefinitely: the drum pattern mutates every ~1.3s, the
chord progression mutates every ~5.3s, and the background layout, color palette, and
texture morph in step with those chord mutations — so the whole thing evolves as one
coherent, continuously-changing piece with no further interaction required. Press `H`
again at any point to bring the sequencer UI back and check on / take manual control of
the pattern.

The piece also breathes over longer timescales: it spends most of its time net-additive
(building up the pattern), then occasionally — not on any fixed schedule — dips into a
short release phase that thins the pattern back down toward near-silence before
building again. Both how long a build stretch lasts and whether it's followed by a dip
are randomized, so there's no predictable cadence to notice; it never goes fully silent
and never hard-resets, it just periodically exhales.

## How the background system works (brief)

- **Density → look**: the number of active drum/chord steps per voice drives four
  smoothed parameters (`smoothNum1-4`) that control shape size, spacing, rotation
  noise, and which of the 16 color palettes / 6 textures / 6 layout modes is selected.
- **Lag stage**: those parameters ease toward their target rather than jumping, so
  edits (manual or autonomous) feel like the piece drifting rather than snapping.
- **Layout modes**: Grid, Radial, Checkerboard, and Multi-Radial share one particle
  system, so transitions between them are a true geometric morph — shapes slide,
  scale, and rotate directly from one layout into the next. Waves and Kaleidoscope
  aren't particle-based, so transitions touching those two cross-fade instead.
- **Mutation-tied transitions**: while Autonomous is on, a new background layout is
  held back and only committed at the same moment a chord mutation fires, so visual
  changes read as part of the piece evolving rather than as noise.
