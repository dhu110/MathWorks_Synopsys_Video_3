# IPMSM current profiles with constant sampling time (Video 3 Artifacts)
*Built using MATLAB R2026a, Copyright 2026 The MathWorks, Inc.*

Run the five MATLAB steps from this folder. The workflow uses
`GenerateIPMSMCurrentProfile.slx` and `Model_Init.mat` in this folder.

<img width="1669" height="1521" alt="image" src="https://github.com/user-attachments/assets/7d426307-3bbb-4a3c-bcfe-2f115439186d" />

## Operating points

- 15 speeds: 1,000 to 15,000 rpm in 1,000 rpm increments.
- 26 torque levels per speed: 1%, then 4%, 8%, ..., 100% of the torque envelope.
- Torque command: `TrqEnvelope * TorquePercent / 100`, using the linear
  torque-envelope lookup in `optimalTables`.
- Each torque step lasts two fundamental electrical cycles. Each speed run
  lasts 52 electrical cycles; the dataset contains 390 operating points.
- Each profile retains the last complete phase-aligned electrical cycle
  contained in its torque step.

## Fixed 2 microsecond sampling

`Scope1` logs directly at **2 us (500 kHz)** through a `SimulationInput`
override. Its point limit and logging decimation are disabled. The model's
original solver step (`Ts = 1 us` in the supplied initialization) is retained.
The model file and initialization data are not modified by these overrides.

Current samples are copied directly from the log. There is no current
resampling, interpolation, or fixed-length normalization. Boundary-angle
interpolation only locates the cycle to extract.

With four pole pairs:

```matlab
electricalPeriod = 60 / (Speed_rpm * PolePairs);
nominalSamplesPerCycle = electricalPeriod / 2e-6;
```

| Speed (rpm) | Electrical period | Samples per cycle |
| --- | --- | --- |
| 1,000 | 15 ms | 7,500 |
| 5,000 | 3 ms | 1,500 |
| 7,000 | approximately 2.142857 ms | 1,071 or 1,072 |
| 15,000 | 1 ms | 500 |

A cycle is a half-open interval `[cycleStart, cycleEnd)`. The next cycle's
first sample is excluded. When the period is not an integer multiple of
2 us, the retained count is the floor or ceiling of the nominal count,
depending on where the cycle boundaries fall on the logging grid.
`Time(end)` is `(N-1)*2e-6`; `N*2e-6` represents the cycle duration to within
one sampling interval. The last sample does not repeat the first angle.

## Profile structure

`IPMSM_Current_Profiles` is a 390-by-1 structure array sorted by speed and
then torque percentage. Every element contains exactly these fields, in order:

| Field | Shape | Meaning / units |
| --- | --- | --- |
| `Speed_rpm` | Scalar | Commanded mechanical speed, rpm |
| `TrqCmd` | Scalar | Torque command, N m |
| `TorquePercent` | Scalar | Percentage of the torque envelope |
| `TrqEnvelope` | Scalar | Torque envelope at this speed, N m |
| `Id_ref` | Scalar | Operating-point d-axis reference current, A |
| `Iq_ref` | Scalar | Operating-point q-axis reference current, A |
| `Ia` | N-by-1 | Native phase-a current samples, A |
| `Ib` | N-by-1 | Native phase-b current samples, A |
| `Ic` | N-by-1 | Native phase-c current samples, A |
| `RotorAngle` | N-by-1 | Unwrapped mechanical angle relative to the first retained sample, rad |
| `Time` | N-by-1 | Time relative to the first retained sample, s; fixed 2 us spacing |

The five sampled vectors have matching lengths within each profile. Lengths
can differ between speeds and, for noninteger cycle lengths, between torque
steps at the same speed.

`Id_ref` and `Iq_ref` are scalar commands calculated at the specified speed
and torque percentage using the controller's linear two-dimensional lookup
tables. `Iq_ref` includes the controller's `tanh(4*TrqCmd)` multiplier. They
describe the operating point; they are not logged controller transients or
d/q feedback currents. `RotorAngle` spans approximately `2*pi/PolePairs`
mechanical radians per electrical cycle, with the endpoint excluded.

## Running the steps

1. **step_01_Create_IPMSM_Simulation_Inputs.m** builds the 15 self-contained
   `SimulationInput` objects in `in` and the sweep configuration. It does not
   run simulations. Inputs follow root-inport order and use zero-order hold.
2. **step_02_Run_IPMSM_Current_Profile_Sweep.m** asks whether to reuse results.
   Choose **N for the first run after this update**. It rebuilds step_01,
   reruns all 15 speeds, extracts native profiles in each post-simulation
   callback, and saves a checkpoint as each speed completes. With Parallel
   Computing Toolbox it uses `parsim`, reusing an existing pool or creating
   up to four workers; otherwise it runs serially. Simulation Manager remains
   enabled for parallel runs. Choose **Y** on later runs to assemble all 15
   compatible checkpoints without simulating.
3. **step_03_Validate_IPMSM_Current_Profiles.m** reloads the saved dataset and
   configuration independently, checks checksums, all operating points,
   the exact field order, reference commands, sample counts, 2 us spacing,
   and relative rotor angles. It saves a validation summary and displays
   the torque-speed envelope with all operating points. Step_02 calls it
   automatically.
4. **step_04_IPMSM_Current_Profile_GUI.m** opens the saved profiles:

   ```matlab
   fig = step_04_IPMSM_Current_Profile_GUI;
   ```

   The speed slider snaps to available speeds. The absolute-torque slider
   snaps to available commands for the selected speed, preserving the
   nearest absolute torque when speed changes. The initial selection is
   5,000 rpm at its maximum torque. Current and mechanical-angle plots use
   sample number; their data and axis limits update to the selected profile's
   sample count. The current-plot title shows sample count, sampling interval,
   and d/q reference commands.

5. **step_05_Extract_Envelop_Points.m** extracts the 100% torque profile at
   each of the 15 speeds from the saved `IPMSM_Current_Profiles.mat` dataset:

   ```matlab
   step_05_Extract_Envelop_Points
   ```

   It creates `IPMSM_Envelope_Current_Profiles`, a 15-by-1 structure array
   sorted from 1,000 to 15,000 rpm. Every profile has `TorquePercent == 100`
   and `TrqCmd == TrqEnvelope` within numerical tolerance. All 11 fields and
   their values are copied from the corresponding source profile, including
   the original 2 us current samples, relative rotor angles, and time vectors.
   This step performs no simulation or resampling. It checks for missing or
   duplicate envelope operating points and saves the subset in
   `IPMSM_Envelope_Current_Profiles.mat` in this folder.

   These 15 envelope operating points can be used for **FEA loss-calculation
   test runs**. For example, access a speed's currents and mechanical angle:

   ```matlab
   envelopeData = load("IPMSM_Envelope_Current_Profiles.mat", ...
       "IPMSM_Envelope_Current_Profiles");
   profile = envelopeData.IPMSM_Envelope_Current_Profiles(1); % 1000 rpm, 100% torque
   Iabc = [profile.Ia, profile.Ib, profile.Ic];
   rotorAngle = profile.RotorAngle; % mechanical radians, relative to first sample
   time = profile.Time;            % seconds, 2 us spacing
   ```

   Use each profile's own vector length when preparing FEA inputs. The
   stored angle starts at zero relative to the first retained sample; a true
   cycle boundary can fall between logging samples. Step_05 preserves that
   convention and does not calculate FEA losses itself. It can be run after
   step_02 has generated and validated the full dataset; opening step_04 is
   optional.

## Saved files and reuse

- `IPMSM_Sweep_Results/Profiles_<speed>rpm.mat`: 26 profiles and their
  configuration for one completed speed run.
- `IPMSM_Current_Profiles.mat`: combined profile structure array (`-v7.3`).
- `IPMSM_Envelope_Current_Profiles.mat`: 15 full-torque profiles for FEA
  loss-calculation test runs, stored as `IPMSM_Envelope_Current_Profiles`
  (`-v7.3`). Run step_05 again after regenerating the full dataset to refresh
  this subset.
- `IPMSM_Sweep_Config.mat`: configuration, including profile format version 2,
  sample interval, nominal sample counts, reference commands, and checksums.
- `IPMSM_Current_Profiles_Validation.mat`: pass summary, per-profile sample
  counts, sample-count range, and maximum sampling/cycle-duration errors.

Reuse requires a complete, consistent set of checkpoints matching the model
and initialization checksums, the required sweep, and the native 2 us format.
Legacy 1,000-point resampled checkpoints are rejected with instructions to
choose N. The GUI also rejects legacy profile schemas or time spacing.
The pre-existing profile MAT file needs regeneration by step_02 before use
with the updated steps; editing the scripts does not convert that dataset.

Step_02 leaves only `IPMSM_Current_Profiles` in the MATLAB workspace when it
finishes. All generated result files are written under this folder.
