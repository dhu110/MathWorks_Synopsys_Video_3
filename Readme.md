# IPMSM Current Profile Sweep with Constant Sampling Time (Video 3 Artifacts)
*Built using MATLAB R2026a, Copyright 2026 The MathWorks, Inc.*


This project uses closed-loop Simulink simulation to generate Interior Permanent Magnet Synchronous Motor (IPMSM) phase-current profiles across a full speed-torque grid. The workflow creates simulation inputs, runs the sweep, extracts one electrical cycle per operating point, validates the resulting dataset, and provides a GUI for waveform review.

The motor-drive model includes PWM switching effects and spatial harmonics. Its simulated phase currents can be used as excitations in Finite Element Analysis (FEA) tools to refine electromagnetic loss calculations at the corresponding operating points.

## Operating points

The complete sweep produces **148 operating points across 15 speeds**, using **absolute torque commands of 10, 25, then 50 N m increments below the torque envelope, followed by the exact envelope endpoint**. Each speed has 7–12 torque steps with the supplied initialization data. Current-profile sampling remains **fixed at 2 μs (500 kHz)**, and each extracted cycle retains its original logged samples without current resampling. The number of samples varies with speed: **7,500 at 1,000 rpm** and **500 at 15,000 rpm** for the supplied four-pole-pair motor. The complete dataset includes one **100% achievable-torque endpoint at each of the 15 speeds**. Sweep settings are applied through `Simulink.SimulationInput` objects, preserving the structure and saved file of `GenerateIPMSMCurrentProfile.slx`.

Run the four MATLAB steps from this folder. The workflow uses
`GenerateIPMSMCurrentProfile.slx` and `Model_Init.mat` in this folder.




<img width="1669" height="1521" alt="image" src="https://github.com/user-attachments/assets/7d426307-3bbb-4a3c-bcfe-2f115439186d" />

## Requirements

- MATLAB and Simulink, with Simscape and Simscape Electrical for the supplied motor-drive model. The project was built using R2026a.
- Parallel Computing Toolbox is optional. When available, the runner uses a process pool, creating up to four workers if no pool is already open. Otherwise, simulations run serially.
- Keep the model, `Model_Init.mat`, and the four workflow scripts together in this folder, and select it as the MATLAB Current Folder. Generated results remain under this folder.

## Project Files

| File | Purpose |
| --- | --- |
| `Model_Init.mat` | Motor and controller initialization data, including `Ts`, `PolePairs`, and `optimalTables`. |
| `GenerateIPMSMCurrentProfile.slx` | Closed-loop motor-drive model with root inports `Speed_rpm` and `TrqCmd`. |
| `step_01_Create_IPMSM_Simulation_Inputs.m` | Builds one simulation input per speed with its own absolute-torque grid, derived percentages and reference currents, Stop Time, and native 2 μs current logging. |
| `step_02_Run_IPMSM_Current_Profile_Sweep.m` | Prompts to reuse compatible saved results or rerun the complete sweep, extracts native current cycles, combines results, and invokes validation. |
| `step_03_Validate_IPMSM_Current_Profiles.m` | Validates the saved dataset and plots its operating points against the torque envelope. |
| `step_04_IPMSM_Current_Profile_GUI.m` | Opens an interactive viewer with speed-specific absolute-torque sliders, derived torque percentages, and variable-length waveform plots. |

## Sweep Definition

| Setting | Value |
| --- | --- |
| Speeds | `1000:1000:15000` rpm: 15 fixed-speed runs. |
| Absolute torque commands | Start with 10 and 25 N m, then 50, 100, 150, ... N m below the speed-specific envelope, and append its exact value once. Commands exceeding the envelope are omitted. |
| Torque percentages | Derived for each operating point as `100 * TrqCmd / TrqEnvelope`; the final endpoint is exactly 100%. |
| Torque steps per speed | 7–12 with the supplied initialization; counts depend on the envelope torque. |
| Pole pairs | Loaded from `Model_Init.mat`; the supplied motor has four. |
| Command duration per torque step | Two fundamental electrical cycles. |
| Duration per speed run | Two electrical cycles per torque step: `2 * numTorqueSteps`, or 14–24 cycles with the supplied initialization. |
| Current-profile sampling time | Fixed at `2e-6` s: 2 μs, or 500 kHz. |
| Solver step | Retains the initialized `Ts`; the supplied value is 1 μs. |
| Extracted data per operating point | One complete phase-aligned electrical cycle, retaining consecutive native samples with the cycle endpoint excluded. |

Speed remains constant throughout each simulation. Torque uses **zero-order hold**: each absolute torque command stays constant for two electrical cycles before stepping to the next level.

The torque envelope comes from `optimalTables.TrqEnvelope`, using `optimalTables.n_norm` as its speed axis. Despite its name, `n_norm` contains speeds in rpm in this project. Linear interpolation obtains the envelope torque at each requested speed. The absolute-torque grid is then constructed as:

```matlab
candidates = [10, 25, 50:50:TrqEnvelope_at_speed];
TrqCmd = [candidates(candidates < TrqEnvelope_at_speed - 1e-9), ...
    TrqEnvelope_at_speed];
TorquePercent = 100 * TrqCmd / TrqEnvelope_at_speed;
TorquePercent(end) = 100;
```

The electrical period, commanded simulation durations, and nominal sample count are calculated as:

```matlab
electricalPeriod = 60 / (Speed_rpm * PolePairs);
stepDuration = 2 * electricalPeriod;
numTorqueSteps = numel(TrqCmd);
stopTime = numTorqueSteps * stepDuration;
profileSampleTime = 2e-6;
nominalSamplesPerCycle = electricalPeriod / profileSampleTime;
```

For example:

| Speed | Electrical period | Torque-step duration | Torque steps | Stop Time | Samples per extracted cycle |
| --- | --- | --- | --- | --- | --- |
| 1000 rpm | 0.015 s | 0.030 s | 12 | 0.360 s | 7500 |
| 5000 rpm | 0.003 s | 0.006 s | 12 | 0.072 s | 1500 |
| 7000 rpm | Approximately 0.002142857 s | Approximately 0.004285714 s | 11 | Approximately 0.047142857 s | 1071 or 1072 |
| 15000 rpm | 0.001 s | 0.002 s | 7 | 0.014 s | 500 |

For example, the 1000 rpm grid is `[10, 25, 50, 100, 150, 200, 250, 300, 350, 400, 450, 497.4331...]` N m. At 15000 rpm it is `[10, 25, 50, 100, 150, 200, 200.5986...]` N m. The scripts use the full-precision envelope values. Even when the final 50 N m increment is close to the envelope, both distinct operating points are retained. If the envelope coincides with a requested torque within 1e-9 N m, its exact value is included once.

These are the commanded time boundaries. Current logging follows a fixed 2 μs grid, and extraction uses the recorded time and rotor angle to locate cycle boundaries. When an electrical period is not an integer multiple of 2 μs, a cycle contains either the floor or ceiling of the nominal sample count, depending on its position on that grid. The sample interval remains unchanged.

## Quick Start

With this folder selected in MATLAB, run:

```matlab
step_02_Run_IPMSM_Current_Profile_Sweep
step_04_IPMSM_Current_Profile_GUI
```

Step 02 opens a Y/N dialog: choose Y to reuse compatible saved results or N to rerun all 15 speeds. Choose **N when replacing the earlier percentage-based sweep or legacy resampled results**. Choosing N automatically invokes Step 01 to create the inputs. Both choices combine the profiles and invoke Step 03 for validation. Step 04 opens the saved dataset for waveform review.

To rerun the entire process without the Y/N dialog:

```matlab
IPMSM_Sweep_ReuseChoice = "N";
step_02_Run_IPMSM_Current_Profile_Sweep
step_04_IPMSM_Current_Profile_GUI
```

`IPMSM_Sweep_ReuseChoice` accepts Y or N and is consumed by Step 02. Without this override, the dialog behavior is unchanged.

For an existing dataset in the current format, validation and GUI plotting can be run independently:

```matlab
step_03_Validate_IPMSM_Current_Profiles
step_04_IPMSM_Current_Profile_GUI
```

## Detailed Workflow

### 1. Create Simulation Inputs

```matlab
step_01_Create_IPMSM_Simulation_Inputs
```

This script loads `Model_Init.mat` and builds the workspace variables `in` and `IPMSM_Sweep_Config`. The `in` array contains 15 `Simulink.SimulationInput` objects. Each object carries initialization variables, a constant speed signal, that speed's increasing absolute torque commands including the envelope endpoint, and its Stop Time. The number of steps and run duration vary by speed.

The two input signals are supplied as a `Simulink.SimulationData.Dataset` in root-inport order. Runtime logging overrides configure `Scope1` to capture `IPMSM_Currents` with timestamps at **2 μs**, without decimation or a sample-count limit. The original solver step is retained; the logging interval must be an integer multiple of that step.

The script also calculates the operating-point reference currents from the controller's linear two-dimensional lookup tables. `Id_ref` comes from `optimalTables.Id_Table`. `Iq_ref` comes from `optimalTables.Iq_Table` and includes the controller's `tanh(4*TrqCmd)` multiplier. The lookup axes are speed in rpm and the percentage derived from each absolute torque command. Lookup percentages are clipped to the table's breakpoint range, matching the controller; the profile's `TorquePercent` remains the actual calculated percentage.

Because the torque grids have different lengths, `TrqCmd`, `TorquePercent`, `Id_ref`, and `Iq_ref` in `IPMSM_Sweep_Config` are 15-by-1 cell arrays. Entry `{speedIndex}` contains a row vector for that speed's operating points. `TorqueStepsPerSpeed` is a 15-by-1 count vector, and `TotalOperatingPoints` is their sum. The configuration uses `SweepMode = "AbsoluteTorque"` and `ProfileFormatVersion = 3`.

Running this script alone allows inspection of the inputs before simulation. The sweep runner invokes it automatically when N is selected.

### 2. Sweep and Extract Native Current Cycles

```matlab
step_02_Run_IPMSM_Current_Profile_Sweep
```

At startup, the script asks whether to reuse previous simulation results. The default is Y. Choosing Y reads the complete, compatible per-speed checkpoints from `IPMSM_Sweep_Results`; choosing N reruns all 15 speed simulations regardless of existing checkpoints. Parallel reruns open Simulation Manager to monitor progress. The dialog warns that rerunning the entire sweep may take a few minutes or longer. Closing the dialog cancels execution.

Each new simulation provides logged `Ia`, `Ib`, `Ic`, and mechanical rotor angle through its `IPMSM_Currents` output. A post-simulation callback processes that speed's torque steps and immediately saves a per-speed checkpoint. A newly created process pool stores its job files in `IPMSM_Parallel_Jobs` under this folder.

For each torque step, extraction follows these steps:

1. Unwrap the logged mechanical rotor angle and determine the step's start and end angles. Boundary-angle interpolation is used only to locate the cycle.
2. Select the **latest complete, electrically phase-aligned cycle** contained within that step. With four pole pairs, one electrical cycle spans `2*pi/4 = pi/2` mechanical radians.
3. Select consecutive logged samples in the half-open cycle interval `[cycleStart, cycleEnd)`, also checking that their times lie within the torque step. The first sample of the next cycle is excluded.
4. Copy `Ia`, `Ib`, and `Ic` directly from those indices. Their original values and 2 μs spacing are preserved; no current reconstruction or resampling is performed.
5. Rebase the selected mechanical angle and time arrays by subtracting their first retained values, so the saved `RotorAngle` and `Time` start at zero.

In the supplied phase-aligned, two-cycle setup, the selected cycle normally corresponds to the **second half** of each torque step. At 1000 rpm, for example, the first step covers 0–30 ms and the extracted cycle normally covers 15–30 ms, excluding the sample at 30 ms. Selection follows the measured angle rather than an unconditional split of the sample array; if alignment shifts, it selects the latest complete aligned cycle that still fits inside the step.

When a cycle boundary falls between logging samples, the first retained sample can lie slightly past the true boundary. Its stored `RotorAngle` becomes zero by subtraction. Zero therefore identifies the **first retained sample's relative angle**, without changing the associated currents or asserting an exact physical zero-angle crossing.

For a profile containing `N` samples, `Time(end)` is `(N-1)*2e-6`, and `N*2e-6` represents the cycle duration to within one sampling interval. The last angle sample does not duplicate the cycle's first angle. The extractor checks sample continuity, sampling interval, torque-step boundaries, and cycle coverage. Using the later cycle gives the controller an initial cycle to respond to the torque change; steady-state convergence is not explicitly tested.

After all speed runs complete, the runner combines the profiles, sorts them by speed and absolute torque, saves `IPMSM_Current_Profiles.mat`, and invokes validation. This MAT file contains only `IPMSM_Current_Profiles`. On successful completion, the runner clears all other workspace variables and leaves only `IPMSM_Current_Profiles`. The shared configuration is saved separately in `IPMSM_Sweep_Config.mat`, and the validation report is saved in `IPMSM_Current_Profiles_Validation.mat`.

### 3. Validate and Plot the Operating Map

```matlab
step_03_Validate_IPMSM_Current_Profiles
```

Validation reads the saved dataset independently of the simulation workspace and checks:

- Dataset and initialization-file checksums match the configuration saved separately in `IPMSM_Sweep_Config.mat`. Checkpoint reuse also checks the model-file checksum in Step 02.
- Operating points match the absolute-torque grids independently reconstructed from the initialization envelope: 148 total with the supplied data, and 7–12 distinct steps per speed.
- Each grid contains the feasible 10 and 25 N m commands, the 50 N m increments below the envelope, and exactly one full-precision envelope endpoint.
- `TorquePercent` matches `100 * TrqCmd / TrqEnvelope`, and `Id_ref` and `Iq_ref` match the controller's operating-point lookup calculations.
- Each profile contains exactly the 11 required fields in order, with matching finite column vectors for currents, rotor angle, and time.
- Sample counts follow the electrical period at each speed: an exact count for integer cycle lengths, or the floor or ceiling for noninteger lengths.
- Relative time starts at zero and increases at a fixed 2 μs interval.
- Relative mechanical rotor angle starts at zero, increases consistently with speed and time, and excludes a duplicate end-of-cycle sample.
- Sample coverage represents one electrical period to within one 2 μs interval.
- The saved sweep configuration specifies absolute-torque mode, profile format version 3, 2 μs sampling, two cycles per torque step, and the correct speed-specific step counts and Stop Times.

Successful validation prints:

```text
PASS: 148 operating points, 15 speeds with 7 to 12 absolute-torque steps, native 2 us sampling.
Samples per electrical cycle: 500 to 7500, depending on speed.
```

The script also reports the maximum cycle-duration error and saves `IPMSM_Validation` in `IPMSM_Current_Profiles_Validation.mat`. The report includes the speed-specific torque-step counts, sweep mode, per-profile sample counts, the minimum and maximum sample counts, and the maximum sampling-interval and cycle-duration errors.

The torque-speed map displays all operating points as **magenta `*` markers**, with speed in rpm on the x-axis, torque in N m on the y-axis, and the full torque envelope superimposed as a black line.

### 4. Review Waveforms in the GUI

```matlab
step_04_IPMSM_Current_Profile_GUI
```

The GUI loads `IPMSM_Current_Profiles.mat` and initially selects the highest saved torque at 5000 rpm. Its controls and plots are:

- **Speed_rpm slider:** selects the nearest saved speed.
- **Trq_cmd slider:** selects the nearest saved absolute torque in N m. Its range, tick values, and number of available torque levels update for the selected speed. The label also shows the corresponding envelope percentage.
- **Phase-current plot:** displays `Ia`, `Ib`, and `Ic` together. Its title shows the sample count, 2 μs sampling interval, and d/q reference currents.
- **Rotor-angle plot:** displays the zero-based relative mechanical rotor angle in radians.

Both plots use **Sample No. 1–N** on the x-axis and share their x-axis limits. Each waveform's data length and the axis limits update to the selected profile's actual sample count. Waveforms update while dragging; sliders snap to saved operating points when released. When speed changes, the GUI selects the closest available torque to the previously selected absolute torque. The displayed values identify the actual saved profile being plotted.

The GUI reads the saved profiles directly and does not run simulations or interpolate between operating points. It checks the 11-field schema and 2 μs time spacing. An optional MAT-file path can be passed to `step_04_IPMSM_Current_Profile_GUI` to view another dataset with the same required format.

## Saved Outputs

| Output | Contents |
| --- | --- |
| `IPMSM_Current_Profiles.mat` | Only the combined `IPMSM_Current_Profiles` structure array: 148 operating points with the supplied initialization, saved with `-v7.3`. |
| `IPMSM_Sweep_Config.mat` | Absolute-torque sweep settings, per-speed torque/percentage/reference-current cell arrays, step counts, total operating-point count, format version 3, 2 μs sampling interval, nominal sample counts, and checksums. |
| `IPMSM_Sweep_Results/Profiles_<speed>rpm.mat` | A completed speed run's variable number of `runProfiles`, plus its sweep configuration. |
| `IPMSM_Current_Profiles_Validation.mat` | Validation status, operating-point counts, per-profile sample counts, sample-count range, and maximum sampling-interval and cycle-duration errors. |

Each entry of `IPMSM_Current_Profiles` contains exactly these fields, in this order:

| Field | Shape | Meaning |
| --- | --- | --- |
| `Speed_rpm` | Scalar | Commanded mechanical speed in rpm. |
| `TrqCmd` | Scalar | Absolute torque command in N m. |
| `TorquePercent` | Scalar | Derived percentage `100 * TrqCmd / TrqEnvelope`; exactly 100 at the final endpoint. |
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

Shared motor and sweep metadata, including pole pairs, electrical periods, Stop Times, nominal sample counts, and checksums, are stored in `IPMSM_Sweep_Config.mat` for validation and in the per-speed checkpoints for reuse. Loading `IPMSM_Current_Profiles.mat` loads only its profile structure array. Absolute rotor position and absolute simulation timestamps are omitted from the compact profiles. A zero-based `RotorAngle` describes the extracted samples' relative mechanical angle; it does not indicate that every torque step or first retained sample occurs at physical mechanical zero.

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

- **Y:** reuse all saved per-speed results and rebuild the combined dataset without running simulations. Checkpoints must have consistent absolute-torque sweep settings, match the model and `Model_Init.mat` checksums, use profile format version 3 with native 2 μs sampling, and contain all expected speed-specific torque commands, derived percentages, and profile fields.
- **N:** rerun the entire 15-speed sweep. Completed runs overwrite their per-speed checkpoints, and the combined dataset is saved after every requested run completes.

If Y is selected but checkpoints are missing, incomplete, inconsistent, or obsolete, the script reports an error and directs you to select N. It does not silently launch simulations. Both the previous percentage-based sweep and legacy 1,000-point resampled checkpoints are rejected. Closing the dialog cancels execution.

Model-file or initialization-data changes invalidate checkpoint reuse through checksum checks. Choose N to generate new results after changing the model, initialization data, or cycle-selection logic. Rerunning the entire sweep may take a few minutes or longer, depending on the model and hardware.

## Configuration Changes

The speed list, `InitialTorques = [10, 25]`, `TorqueIncrement = 50`, and fixed profile sampling interval are defined in `IPMSM_Sweep_Config` inside `step_01_Create_IPMSM_Simulation_Inputs.m`. Motor parameters, the torque envelope, the solver step `Ts`, and pole pairs come from `Model_Init.mat`; operating-point inputs and percentages are generated by the scripts. `SamplesPerCycle` stores the nominal period-to-sampling-interval ratio, which can be noninteger. There is no fixed output sample-count setting or common percentage-sweep axis.

The supplied implementation enforces the documented 15 speeds, absolute-torque rule, and **2 μs profile sampling**. Step counts, total operating-point count, and Stop Times are derived from each speed's envelope. Changing the absolute-torque rule requires updating the settings in the input builder, the checkpoint requirements in the runner, and the independent grid reconstruction in Step 03. Changing speeds also requires updating Step 03. The builder and extractor use `CyclesPerStep` for timing; validation currently enforces two cycles per torque step. The GUI derives speed and torque selections and waveform lengths from the saved dataset and requires 2 μs time spacing.
