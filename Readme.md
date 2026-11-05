# IPMSM Current Profile Sweep with Constant Sampling Time (Video 3 Artifacts)
*Built using MATLAB R2026a, Copyright 2026 The MathWorks, Inc.*

This project uses closed-loop Simulink simulation to generate Interior Permanent Magnet Synchronous Motor (IPMSM) phase-current profiles across a full speed-torque grid. The workflow creates simulation inputs, runs the sweep, extracts one electrical cycle per operating point, validates the resulting dataset, provides a GUI for waveform review, and extracts the full-torque envelope profiles for FEA loss-calculation test runs.

The motor-drive model includes PWM switching effects and spatial harmonics. Its simulated phase currents can be used as excitations in Finite Element Analysis (FEA) tools to refine electromagnetic loss calculations at the corresponding operating points.

The complete sweep produces **390 operating points: 15 speeds x 26 torque levels**, with a **fixed current-profile sampling time of 2 μs (500 kHz)**. Each extracted cycle retains its original logged samples without current resampling. The number of samples varies with speed: **7,500 at 1,000 rpm** and **500 at 15,000 rpm** for the supplied four-pole-pair motor. A separate envelope dataset contains **15 operating points at 100% torque**. Sweep settings are applied through `Simulink.SimulationInput` objects, preserving the structure and saved file of `GenerateIPMSMCurrentProfile.slx`.

<img width="1669" height="1521" alt="image" src="https://github.com/user-attachments/assets/7d426307-3bbb-4a3c-bcfe-2f115439186d" />

## Requirements

- MATLAB and Simulink, with Simscape and Simscape Electrical for the supplied motor-drive model. The project was built using R2026a.
- Parallel Computing Toolbox is optional. When available, the runner uses a process pool, creating up to four workers if no pool is already open. Otherwise, simulations run serially.
- Keep the model, `Model_Init.mat`, and the five workflow scripts together in this folder, and select it as the MATLAB Current Folder. Generated results remain under this folder.

## Project Files

| File | Purpose |
| --- | --- |
| `Model_Init.mat` | Motor and controller initialization data, including `Ts`, `PolePairs`, and `optimalTables`. |
| `GenerateIPMSMCurrentProfile.slx` | Closed-loop motor-drive model with root inports `Speed_rpm` and `TrqCmd`. |
| `step_01_Create_IPMSM_Simulation_Inputs.m` | Builds one simulation input per speed, including stepped absolute torque commands, Stop Time, and native 2 μs current logging. |
| `step_02_Run_IPMSM_Current_Profile_Sweep.m` | Prompts to reuse compatible saved results or rerun the complete sweep, extracts native current cycles, combines results, and invokes validation. |
| `step_03_Validate_IPMSM_Current_Profiles.m` | Validates the saved dataset and plots its operating points against the torque envelope. |
| `step_04_IPMSM_Current_Profile_GUI.m` | Opens an interactive current-profile viewer with speed and torque sliders and variable-length waveform plots. |
| `step_05_Extract_Envelop_Points.m` | Extracts one 100% torque profile per speed and saves the 15-point envelope dataset for FEA loss-calculation test runs. |

## Sweep Definition

| Setting | Value |
| --- | --- |
| Speeds | `1000:1000:15000` rpm: 15 fixed-speed runs. |
| Torque percentages | `[1, 4:4:100]`: 26 levels from 1% to 100% of the speed-specific torque envelope. |
| Pole pairs | Loaded from `Model_Init.mat`; the supplied motor has four. |
| Command duration per torque step | Two fundamental electrical cycles. |
| Duration per speed run | 52 fundamental electrical cycles: `2 x 26`. |
| Current-profile sampling time | Fixed at `2e-6` s: 2 μs, or 500 kHz. |
| Solver step | Retains the initialized `Ts`; the supplied value is 1 μs. |
| Extracted data per operating point | One complete phase-aligned electrical cycle, retaining consecutive native samples with the cycle endpoint excluded. |
| Envelope subset | 15 operating points, one at 100% torque for each speed. |

Speed remains constant throughout each simulation. Torque uses **zero-order hold**: each absolute torque command stays constant for two electrical cycles before stepping to the next level.

The torque envelope comes from `optimalTables.TrqEnvelope`, using `optimalTables.n_norm` as its speed axis. Despite its name, `n_norm` contains speeds in rpm in this project. Linear interpolation obtains the envelope torque at each requested speed:

```matlab
TrqCmd = (TorquePercent / 100) * TrqEnvelope_at_speed;
```

The electrical period, commanded simulation durations, and nominal sample count are calculated as:

```matlab
electricalPeriod = 60 / (Speed_rpm * PolePairs);
stepDuration = 2 * electricalPeriod;
stopTime = 26 * stepDuration;
profileSampleTime = 2e-6;
nominalSamplesPerCycle = electricalPeriod / profileSampleTime;
```

For example:

| Speed | Electrical period | Torque-step duration | Stop Time | Samples per extracted cycle |
| --- | --- | --- | --- | --- |
| 1000 rpm | 0.015 s | 0.030 s | 0.780 s | 7500 |
| 5000 rpm | 0.003 s | 0.006 s | 0.156 s | 1500 |
| 7000 rpm | Approximately 0.002142857 s | Approximately 0.004285714 s | Approximately 0.111428571 s | 1071 or 1072 |
| 15000 rpm | 0.001 s | 0.002 s | 0.052 s | 500 |

These are the commanded time boundaries. Current logging follows a fixed 2 μs grid, and extraction uses the recorded time and rotor angle to locate cycle boundaries. When an electrical period is not an integer multiple of 2 μs, a cycle contains either the floor or ceiling of the nominal sample count, depending on its position on that grid. The sample interval remains unchanged.

## Quick Start

With this folder selected in MATLAB, run:

```matlab
step_02_Run_IPMSM_Current_Profile_Sweep
step_04_IPMSM_Current_Profile_GUI
step_05_Extract_Envelop_Points
```

Step 02 opens a Y/N dialog: choose Y to reuse compatible saved results or N to rerun all 15 speeds. Choose **N when replacing legacy 1,000-point resampled results**. Choosing N automatically invokes Step 01 to create the inputs. Both choices combine the profiles and invoke Step 03 for validation. Step 04 opens the saved dataset for waveform review. Step 05 saves the full-torque envelope subset; opening the GUI is optional.

For an existing dataset in the current format, validation, GUI plotting, and envelope extraction can be run independently:

```matlab
step_03_Validate_IPMSM_Current_Profiles
step_04_IPMSM_Current_Profile_GUI
step_05_Extract_Envelop_Points
```

## Detailed Workflow

### 1. Create Simulation Inputs

```matlab
step_01_Create_IPMSM_Simulation_Inputs
```

This script loads `Model_Init.mat` and builds the workspace variables `in` and `IPMSM_Sweep_Config`. The `in` array contains 15 `Simulink.SimulationInput` objects. Each object carries initialization variables, a constant speed signal, the 26 stepped torque commands, and its Stop Time.

The two input signals are supplied as a `Simulink.SimulationData.Dataset` in root-inport order. Runtime logging overrides configure `Scope1` to capture `IPMSM_Currents` with timestamps at **2 μs**, without decimation or a sample-count limit. The original solver step is retained; the logging interval must be an integer multiple of that step.

The script also calculates the operating-point reference currents from the controller's linear two-dimensional lookup tables. `Id_ref` comes from `optimalTables.Id_Table`. `Iq_ref` comes from `optimalTables.Iq_Table` and includes the controller's `tanh(4*TrqCmd)` multiplier. The lookup axes are speed in rpm and torque percentage.

Running this script alone allows inspection of the inputs before simulation. The sweep runner invokes it automatically when N is selected.

### 2. Sweep and Extract Native Current Cycles

```matlab
step_02_Run_IPMSM_Current_Profile_Sweep
```

At startup, the script asks whether to reuse previous simulation results. The default is Y. Choosing Y reads the complete, compatible per-speed checkpoints from `IPMSM_Sweep_Results`; choosing N reruns all 15 speed simulations regardless of existing checkpoints. Parallel reruns open Simulation Manager to monitor progress. The dialog warns that rerunning the entire sweep may take a few minutes or longer. Closing the dialog cancels execution.

Each new simulation provides logged `Ia`, `Ib`, `Ic`, and mechanical rotor angle through its `IPMSM_Currents` output. A post-simulation callback processes all 26 torque steps and immediately saves a per-speed checkpoint.

For each torque step, extraction follows these steps:

1. Unwrap the logged mechanical rotor angle and determine the step's start and end angles. Boundary-angle interpolation is used only to locate the cycle.
2. Select the **latest complete, electrically phase-aligned cycle** contained within that step. With four pole pairs, one electrical cycle spans `2*pi/4 = pi/2` mechanical radians.
3. Select consecutive logged samples in the half-open cycle interval `[cycleStart, cycleEnd)`, also checking that their times lie within the torque step. The first sample of the next cycle is excluded.
4. Copy `Ia`, `Ib`, and `Ic` directly from those indices. Their original values and 2 μs spacing are preserved; no current reconstruction or resampling is performed.
5. Rebase the selected mechanical angle and time arrays by subtracting their first retained values, so the saved `RotorAngle` and `Time` start at zero.

In the supplied phase-aligned, two-cycle setup, the selected cycle normally corresponds to the **second half** of each torque step. At 1000 rpm, for example, the first step covers 0–30 ms and the extracted cycle normally covers 15–30 ms, excluding the sample at 30 ms. Selection follows the measured angle rather than an unconditional split of the sample array; if alignment shifts, it selects the latest complete aligned cycle that still fits inside the step.

When a cycle boundary falls between logging samples, the first retained sample can lie slightly past the true boundary. Its stored `RotorAngle` becomes zero by subtraction. Zero therefore identifies the **first retained sample's relative angle**, without changing the associated currents or asserting an exact physical zero-angle crossing.

For a profile containing `N` samples, `Time(end)` is `(N-1)*2e-6`, and `N*2e-6` represents the cycle duration to within one sampling interval. The last angle sample does not duplicate the cycle's first angle. The extractor checks sample continuity, sampling interval, torque-step boundaries, and cycle coverage. Using the later cycle gives the controller an initial cycle to respond to the torque change; steady-state convergence is not explicitly tested.

After all speed runs complete, the runner combines the profiles, sorts them by speed and torque percentage, saves `IPMSM_Current_Profiles.mat`, and invokes validation. This MAT file contains only `IPMSM_Current_Profiles`. On successful completion, the runner clears all other workspace variables and leaves only `IPMSM_Current_Profiles`. The shared configuration is saved separately in `IPMSM_Sweep_Config.mat`, and the validation report is saved in `IPMSM_Current_Profiles_Validation.mat`.

### 3. Validate and Plot the Operating Map

```matlab
step_03_Validate_IPMSM_Current_Profiles
```

Validation reads the saved dataset independently of the simulation workspace and checks:

- Dataset and initialization-file checksums match the configuration saved separately in `IPMSM_Sweep_Config.mat`. Checkpoint reuse also checks the model-file checksum in Step 02.
- There are exactly 390 operating points, with 26 distinct torque percentages at each of the 15 expected speeds.
- Absolute torque commands match the requested percentage of the torque envelope, and `Id_ref` and `Iq_ref` match the controller's operating-point lookup calculations.
- Each profile contains exactly the 11 required fields in order, with matching finite column vectors for currents, rotor angle, and time.
- Sample counts follow the electrical period at each speed: an exact count for integer cycle lengths, or the floor or ceiling for noninteger lengths.
- Relative time starts at zero and increases at a fixed 2 μs interval.
- Relative mechanical rotor angle starts at zero, increases consistently with speed and time, and excludes a duplicate end-of-cycle sample.
- Sample coverage represents one electrical period to within one 2 μs interval.
- The saved sweep configuration specifies profile format version 2, 2 μs sampling, two cycles per torque step, and 52 cycles per run.

Successful validation prints:

```text
PASS: 390 operating points, 15 speeds x 26 torques, native 2 us sampling.
Samples per electrical cycle: 500 to 7500, depending on speed.
```

The script also reports the maximum cycle-duration error and saves `IPMSM_Validation` in `IPMSM_Current_Profiles_Validation.mat`. The report includes per-profile sample counts, the minimum and maximum counts, and the maximum sampling-interval and cycle-duration errors.

The torque-speed map displays all operating points as **magenta `*` markers**, with speed in rpm on the x-axis, torque in N m on the y-axis, and the full torque envelope superimposed as a black line.

### 4. Review Waveforms in the GUI

```matlab
step_04_IPMSM_Current_Profile_GUI
```

The GUI loads `IPMSM_Current_Profiles.mat` and initially selects the highest saved torque at 5000 rpm. Its controls and plots are:

- **Speed_rpm slider:** selects the nearest saved speed.
- **Trq_cmd slider:** selects the nearest saved absolute torque in N m. Its range and tick values update for the selected speed.
- **Phase-current plot:** displays `Ia`, `Ib`, and `Ic` together. Its title shows the sample count, 2 μs sampling interval, and d/q reference currents.
- **Rotor-angle plot:** displays the zero-based relative mechanical rotor angle in radians.

Both plots use **Sample No. 1–N** on the x-axis and share their x-axis limits. Each waveform's data length and the axis limits update to the selected profile's actual sample count. Waveforms update while dragging; sliders snap to saved operating points when released. When speed changes, the GUI selects the closest available torque to the previously selected absolute torque. The displayed values identify the actual saved profile being plotted.

The GUI reads the saved profiles directly and does not run simulations or interpolate between operating points. It checks the 11-field schema and 2 μs time spacing. An optional MAT-file path can be passed to `step_04_IPMSM_Current_Profile_GUI` to view another dataset with the same required format.

### 5. Extract Envelope Operating Points for FEA Test Runs

```matlab
step_05_Extract_Envelop_Points
```

This script reads the saved `IPMSM_Current_Profiles.mat` and selects profiles with `TorquePercent == 100`. It creates **`IPMSM_Envelope_Current_Profiles`**, a **15-by-1 structure array** sorted by speed from 1000 to 15000 rpm, and saves it in `IPMSM_Envelope_Current_Profiles.mat`.

Extraction checks that there is exactly one full-torque operating point at each expected speed, that `TrqCmd` matches `TrqEnvelope` within numerical tolerance, and that all sampled signals have matching finite column vectors with native 2 μs time spacing.

All 11 fields are copied from each selected source profile. Current values, sample counts, reference commands, rotor angles, and time vectors remain unchanged. Step 05 performs no simulation, resampling, or loss calculation.

These 15 envelope operating points can be used for **FEA loss-calculation test runs**. For example:

```matlab
envelopeData = load("IPMSM_Envelope_Current_Profiles.mat", ...
    "IPMSM_Envelope_Current_Profiles");
profile = envelopeData.IPMSM_Envelope_Current_Profiles(1); % 1000 rpm, 100% torque
Iabc = [profile.Ia, profile.Ib, profile.Ic];
rotorAngle = profile.RotorAngle; % Relative mechanical radians
time = profile.Time;            % Seconds, 2 us spacing
```

Run Step 05 after Step 02 has generated and validated the full dataset. Opening Step 04 is optional. Rerun Step 05 whenever the full dataset is regenerated to refresh the envelope subset.

## Saved Outputs

| Output | Contents |
| --- | --- |
| `IPMSM_Current_Profiles.mat` | Only the combined 390-point `IPMSM_Current_Profiles` structure array, saved with `-v7.3`. |
| `IPMSM_Envelope_Current_Profiles.mat` | Only the 15 full-torque `IPMSM_Envelope_Current_Profiles`, saved with `-v7.3` for FEA loss-calculation test runs. |
| `IPMSM_Sweep_Config.mat` | Shared sweep and motor metadata, profile format version, 2 μs sampling interval, nominal sample counts, reference commands, and checksums. |
| `IPMSM_Sweep_Results/Profiles_<speed>rpm.mat` | A completed speed run's 26 `runProfiles`, plus its sweep configuration. |
| `IPMSM_Current_Profiles_Validation.mat` | Validation status, operating-point counts, per-profile sample counts, sample-count range, and maximum sampling-interval and cycle-duration errors. |

Each entry of `IPMSM_Current_Profiles` and `IPMSM_Envelope_Current_Profiles` contains exactly these fields, in this order:

| Field | Shape | Meaning |
| --- | --- | --- |
| `Speed_rpm` | Scalar | Commanded mechanical speed in rpm. |
| `TrqCmd` | Scalar | Absolute torque command in N m. |
| `TorquePercent` | Scalar | Torque percentage relative to the speed-specific envelope. |
| `TrqEnvelope` | Scalar | Envelope torque at the selected speed, in N m. |
| `Id_ref` | Scalar | Operating-point d-axis reference current in A. |
| `Iq_ref` | Scalar | Operating-point q-axis reference current in A, including the controller's `tanh(4*TrqCmd)` multiplier. |
| `Ia` | N x 1 | Native phase-A current samples in A. |
| `Ib` | N x 1 | Native phase-B current samples in A. |
| `Ic` | N x 1 | Native phase-C current samples in A. |
| `RotorAngle` | N x 1 | Unwrapped mechanical angle in radians relative to the first retained sample; cycle endpoint excluded. |
| `Time` | N x 1 | Relative time in seconds, starting at zero with fixed 2 μs spacing. |

`N` is the actual sample count of the individual profile. The five sampled vectors have matching lengths within a profile; lengths differ between speeds and can differ between torque steps at the same speed when the cycle length is not an integer number of sampling intervals.

`Id_ref` and `Iq_ref` describe the commanded operating point. They are calculated from the controller's lookup tables rather than logged controller transients or measured d/q feedback currents.

Shared motor and sweep metadata, including pole pairs, electrical periods, Stop Times, nominal sample counts, and checksums, are stored in `IPMSM_Sweep_Config.mat` for validation and in the per-speed checkpoints for reuse. Loading either profile MAT file loads only its profile structure array. Absolute rotor position and absolute simulation timestamps are omitted from the compact profiles. A zero-based `RotorAngle` describes the extracted samples' relative mechanical angle; it does not indicate that every torque step or first retained sample occurs at physical mechanical zero.

For example, access the 100% torque profile at 5000 rpm in the complete dataset with:

```matlab
load("IPMSM_Current_Profiles.mat", "IPMSM_Current_Profiles")
selected = [IPMSM_Current_Profiles.Speed_rpm] == 5000 & ...
    [IPMSM_Current_Profiles.TorquePercent] == 100;
profile = IPMSM_Current_Profiles(selected);
```

Use the phase-current arrays, rotor angle, time, and operating-point metadata to prepare excitations in the format required by the downstream FEA tool. Each profile retains a 500 kHz sample rate, corresponding to a Nyquist frequency of 250 kHz. Use the individual profile's actual sample count and 2 μs interval when preparing waveform inputs or frequency-domain calculations.

## Checkpoints and Reruns

Run `step_02_Run_IPMSM_Current_Profile_Sweep` and choose:

- **Y:** reuse all saved per-speed results and rebuild the combined dataset without running simulations. Checkpoints must have consistent sweep settings, match the model and `Model_Init.mat` checksums, use profile format version 2 with native 2 μs sampling, and contain all expected operating points and fields.
- **N:** rerun the entire 15-speed sweep. Completed runs overwrite their per-speed checkpoints, and the combined dataset is saved after every requested run completes.

If Y is selected but checkpoints are missing, incomplete, inconsistent, or obsolete, the script reports an error and directs you to select N. It does not silently launch simulations. Legacy 1,000-point resampled checkpoints are rejected because their original 2 μs current samples cannot be recovered. Closing the dialog cancels execution.

Model-file or initialization-data changes invalidate checkpoint reuse through checksum checks. Choose N to generate new results after changing the model, initialization data, or cycle-selection logic. Rerunning the entire sweep may take a few minutes or longer, depending on the model and hardware. After regenerating the combined dataset, run Step 05 again to update the envelope profiles.

## Configuration Changes

The speed list, torque percentages, and fixed profile sampling interval are defined in `IPMSM_Sweep_Config` inside `step_01_Create_IPMSM_Simulation_Inputs.m`. Motor parameters, the solver step `Ts`, and pole pairs come from `Model_Init.mat`; operating-point inputs are generated by the scripts. `SamplesPerCycle` stores the nominal period-to-sampling-interval ratio, which can be noninteger. There is no fixed output sample-count setting.

The supplied implementation enforces the documented 15-speed, 26-torque grid and **2 μs profile sampling**. When changing the operating-point grid, also update the fixed torque-step bounds and counts in the input builder, checkpoint requirements in the runner, the corresponding expectations in `step_03_Validate_IPMSM_Current_Profiles.m`, and the 15-speed expectation in `step_05_Extract_Envelop_Points.m`. The builder and extractor use `CyclesPerStep` for timing; validation currently enforces two cycles per torque step and 52 cycles per run. The GUI derives speed and torque selections and waveform lengths from the saved dataset, while the GUI and envelope extractor both require 2 μs time spacing.
