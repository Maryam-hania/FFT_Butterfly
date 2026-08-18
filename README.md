# Radix-2 DIT FFT Butterfly Unit

A SystemVerilog implementation of a Radix-2 Decimation-in-Time (DIT) FFT
butterfly, using Q4.12 fixed-point complex arithmetic.

```
Xtop = A + B*W
Xbot = A - B*W
```

## 1. File structure

| File               | Description                                                              |
|---------------------|---------------------------------------------------------------------------|
| `FFT_Butterfly.sv`  | Top-level module (`fft_butterfly`). Wires the controller and datapath together. This is the module the testbench instantiates. |
| `Controller.sv`     | FSM (`controller`) that sequences the multi-cycle operation: `IDLE -> MULT -> SCALE -> ADD -> DONE`. Drives 4 enable pulses into the datapath. |
| `Datapath.sv`       | `datapath` module. Holds the 4 real multipliers, the complex product accumulation, the rounding/saturation logic, and the final add/sub stage. |
| `testbench2.sv`     | Self-checking testbench (`fft_butterfly_tb`). Directed tests + a real-number golden model + 300 randomized vectors. |
| `wave.do`           | QuestaSim script: compiles everything, opens a waveform with the important signals grouped, and runs the simulation. |

## 2. Q4.12 fixed-point format

- 16-bit signed value, 4 integer bits (including sign) + 12 fractional bits.
- Value = `raw / 4096`.
- Range: **-8.0** to **+7.99975586** (`16'sh8000` to `16'sh7FFF`).
- Multiplying two Q4.12 numbers gives a Q8.24 result, so the product is
  shifted right by 12 (with round-to-nearest) to bring it back to Q4.12.

## 3. Architecture

```
                 ┌─────────────┐
   clk, rst ───▶ │             │
   start ──────▶ │ Controller  │──▶ load_inputs, en_mult, en_scale, en_add
                 │   (FSM)     │──▶ busy, done
                 └─────────────┘
                        │
                        ▼
   a_re,a_im ───▶ ┌─────────────┐
   b_re,b_im ───▶ │             │
   w_re,w_im ───▶ │  Datapath   │──▶ x_top_re, x_top_im
                  │             │──▶ x_bot_re, x_bot_im
                  └─────────────┘
```

**Controller FSM states**

| State | What happens |
|-------|---------------|
| `IDLE`  | Waits for `start`. On `start=1`, asserts `load_inputs` and moves to `MULT`. |
| `MULT`  | Asserts `en_mult` — datapath registers `P_re = M1-M2`, `P_im = M3+M4` (the complex product `B*W`, full 33-bit precision). |
| `SCALE` | Asserts `en_scale` — datapath rounds and saturates the product down to Q4.12 (`mul_re`, `mul_im`). |
| `ADD`   | Asserts `en_add` — datapath computes `x_top = A + mul`, `x_bot = A - mul`, each saturated independently. |
| `DONE`  | Asserts `done` for one cycle, then returns to `IDLE`. |

**Datapath stages**

1. **Register inputs** — `A`, `B`, `W` are latched on `load_inputs`.
2. **Multiply (Stage 1)** — 4 real multipliers (`M1..M4`, 32-bit each) form the complex product `P = B*W` (33-bit, to allow for the extra bit of growth from the subtract/add).
3. **Scale (Stage 2)** — `P` is rounded (add half an LSB, then arithmetic shift right by 12) and saturated to 16-bit (`mul_re`, `mul_im`).
4. **Add/Subtract (Stage 3)** — `A ± mul` is computed and saturated again to produce `x_top` / `x_bot`.

Total latency: **4 clock cycles** from `start` to `done`.

## 4. Verification

`testbench2.sv` covers everything required by the project brief:

- **Directed tests** — trivial twiddle factors (`W=1+j0`, `W=0-j1`), zero
  inputs, max-positive / min-negative saturation, and phase rotation
  through 0°/90°/180° — checked with exact, hand-calculated expected values.
- **Randomized self-checking** — 300 fully random `(A, B, W)` combinations.
  A real-number "golden model" reproduces the RTL's *exact* two-stage
  saturation (product saturated first, then the final add/sub saturated
  again) so it agrees with the DUT to within a small tolerance (`TOL = 2`
  LSB), which accounts for fixed-point rounding.
- Reports a running `PASS`/`FAIL` per test and a final summary.

**Latest run result: 307 / 307 tests passed** (7 directed + 300 random).

## 5. How to simulate in QuestaSim

1. Copy `FFT_Butterfly.sv`, `Controller.sv`, `Datapath.sv`, `testbench2.sv`,
   and `wave.do` into the same folder.
2. Open QuestaSim.
3. In the **Transcript** window, `cd` into that folder:
   ```tcl
   cd C:/path/to/your/folder
   ```
4. Run the script:
   ```tcl
   do wave.do
   ```

This will:
- Create a fresh `work` library and compile all 4 `.sv` files.
- Start the simulation on `fft_butterfly_tb`.
- Open a **Wave** window with signals grouped into three dividers:
  `TESTBENCH / TOP-LEVEL PORTS`, `CONTROLLER FSM`, `DATAPATH INTERNALS`.
- Run to completion (the testbench calls `$stop` when done).
- Print the PASS/FAIL summary in the Transcript.

To save the waveform for your report: **File > Export > Waveform...**
(or right-click the wave pane) → save as `.png` for the report, or
**File > Save Format...** to keep a `.do` file that reopens the same view.

## 6. Design justification (short)

- **4-cycle FSM instead of fully combinational**: keeps each pipeline stage
  (multiply, scale, add) as a single clocked register-to-register path,
  which is easier to close timing on and easier to debug in waveform —
  each stage's result is a named signal you can inspect directly.
- **33-bit intermediate product (`P_re`/`P_im`)**: `M1-M2` and `M3+M4` are
  each sums/differences of two 32-bit signed numbers, which can need one
  extra bit of headroom before saturation — computing the subtract/add at
  full width and saturating only once, at the very end of each stage,
  avoids double-saturation artifacts.
- **Two independent saturation points** (after scale, and after final
  add/sub): matches how a real DSP pipeline would clamp at each arithmetic
  step rather than only at the output, so intermediate overflow (e.g. a
  huge `B*W` product) is caught even if the final sum would have fit.
- **Round-to-nearest (add half an LSB before shifting)** instead of plain
  truncation: keeps the average quantization error at zero instead of
  always biasing results downward, which matters over many cascaded FFT
  stages.
