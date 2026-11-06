% Step 02: Run the absolute-torque sweep and retain native 2 us current cycles.
% Optional unattended choice: set IPMSM_Sweep_ReuseChoice to "Y" or "N" first.
if exist('IPMSM_Sweep_ReuseChoice', 'var')
    reuseChoice = validatestring(IPMSM_Sweep_ReuseChoice, {'Y', 'N'});
    clear IPMSM_Sweep_ReuseChoice
else
    reuseChoice = questdlg(sprintf([ ...
    'Reuse previous simulation results?\n\n' ...
    'Y: Reuse saved results in IPMSM_Sweep_Results.\n' ...
    'N: Re-run the entire 15-speed sweep.\n\n' ...
    'Re-running the entire sweep may take a few minutes or longer.']), ...
        'IPMSM Sweep', 'Y', 'N', 'Y');
end
if isempty(reuseChoice)
    fprintf("Sweep cancelled.\n");
    clear reuseChoice
    return
end
projectFolder = fileparts(mfilename("fullpath"));
resultsFolder = fullfile(projectFolder, "IPMSM_Sweep_Results");
IPMSM_Current_Profiles = struct([]);
pendingRuns = [];

if strcmp(reuseChoice, 'Y')
    [IPMSM_Current_Profiles, IPMSM_Sweep_Config] = ...
        loadSavedProfiles(resultsFolder);
else
    run(fullfile(projectFolder, "step_01_Create_IPMSM_Simulation_Inputs.m"));
    if ~isfolder(resultsFolder)
        mkdir(resultsFolder);
    end
    pendingRuns = 1:numel(in);
    fprintf("Re-running the entire sweep: %d speed runs.\n", numel(in));
end

if ~isempty(pendingRuns)
    for speedIndex = pendingRuns
        in(speedIndex) = in(speedIndex).setPostSimFcn(@(simOutput) ...
            processCompletedRun(simOutput, IPMSM_Sweep_Config, speedIndex, resultsFolder)); %#ok<SAGROW>
    end
    if license("test", "Distrib_Computing_Toolbox") && numel(pendingRuns) > 1
        pool = gcp("nocreate");
        if isempty(pool)
            cluster = parcluster("Processes");
            jobFolder = fullfile(projectFolder, "IPMSM_Parallel_Jobs");
            if ~isfolder(jobFolder)
                mkdir(jobFolder);
            end
            cluster.JobStorageLocation = jobFolder;
            capacity = min(cluster.PreferredPoolNumWorkers, cluster.NumWorkers);
            parpool(cluster, min([4, numel(pendingRuns), capacity]));
        end
        out = parsim(in(pendingRuns), "AttachedFiles", {[mfilename("fullpath"), '.m']}, ...
            "ShowSimulationManager", "on");
    else
        out = repmat(Simulink.SimulationOutput, numel(pendingRuns), 1);
        for runIndex = 1:numel(pendingRuns)
            out(runIndex) = sim(in(pendingRuns(runIndex)));
        end
    end
    for runIndex = 1:numel(pendingRuns)
        if ~isempty(out(runIndex).ErrorMessage)
            error("IPMSM_Sweep:SimulationFailed", "Run at %d rpm failed: %s", ...
                IPMSM_Sweep_Config.Speeds(pendingRuns(runIndex)), out(runIndex).ErrorMessage);
        end
        IPMSM_Current_Profiles = [IPMSM_Current_Profiles; out(runIndex).runProfiles]; %#ok<AGROW>
    end
    clear out
end
[~, profileOrder] = sortrows([[IPMSM_Current_Profiles.Speed_rpm].', ...
    [IPMSM_Current_Profiles.TrqCmd].']);
IPMSM_Current_Profiles = IPMSM_Current_Profiles(profileOrder);
save(fullfile(projectFolder, "IPMSM_Current_Profiles.mat"), ...
    "IPMSM_Current_Profiles", "-v7.3");
IPMSM_Sweep_Config.DatasetChecksum = Simulink.getFileChecksum( ...
    fullfile(projectFolder, "IPMSM_Current_Profiles.mat"));
save(fullfile(projectFolder, "IPMSM_Sweep_Config.mat"), "IPMSM_Sweep_Config");
run(fullfile(projectFolder, "step_03_Validate_IPMSM_Current_Profiles.m"));
clearvars -except IPMSM_Current_Profiles

function [profiles, config] = loadSavedProfiles(resultsFolder)
    referenceFile = fullfile(resultsFolder, "Profiles_1000rpm.mat");
    if ~isfile(referenceFile)
        error("IPMSM_Sweep:MissingCheckpoint", ...
            "Saved results are incomplete or missing in %s. Select N to re-run the entire sweep.", ...
            resultsFolder);
    end
    reference = load(referenceFile, "IPMSM_Sweep_Config");
    assert(isfield(reference, "IPMSM_Sweep_Config"), ...
        "The saved checkpoint must contain its sweep configuration.");
    ignoredFields = {'DatasetChecksum'};
    config = rmfield(reference.IPMSM_Sweep_Config, ...
        intersect(ignoredFields, fieldnames(reference.IPMSM_Sweep_Config)));
    assert(all(isfield(config, {'ProfileFormatVersion', 'ProfileSampleTime', ...
        'ModelChecksum', 'Id_ref', 'Iq_ref', 'SweepMode', 'TorqueStepsPerSpeed'})) && ...
        config.ProfileFormatVersion == 3 && config.SweepMode == "AbsoluteTorque" && ...
        config.ProfileSampleTime == 2e-6 && ~isfield(config, 'NumSamples'), ...
        "Saved results use an obsolete sweep format. Select N to re-run absolute torques.");
    assert(isequal(config.Speeds, (1000:1000:15000).') && ...
        isequal(config.InitialTorques, [10, 25]) && config.TorqueIncrement == 50 && ...
        config.CyclesPerStep == 2, ...
        "Saved sweep settings differ from the required sweep. Select N to re-run.");
    modelFile = fullfile(fileparts(resultsFolder), config.Model + ".slx");
    assert(strcmp(config.ModelChecksum, Simulink.getFileChecksum(modelFile)), ...
        "Saved results do not match the model. Select N to re-run the entire sweep.");
    initializationFile = fullfile(fileparts(resultsFolder), "Model_Init.mat");
    assert(strcmp(config.InitializationChecksum, Simulink.getFileChecksum(initializationFile)), ...
        "Saved results do not match Model_Init.mat. Select N to re-run the entire sweep.");
    profiles = struct([]);
    for speedIndex = 1:numel(config.Speeds)
        checkpointFile = fullfile(resultsFolder, sprintf("Profiles_%drpm.mat", config.Speeds(speedIndex)));
        if ~isfile(checkpointFile)
            error("IPMSM_Sweep:MissingCheckpoint", ...
                "Missing checkpoint %s. Select N to re-run the entire sweep.", checkpointFile);
        end
        checkpoint = load(checkpointFile, "runProfiles", "IPMSM_Sweep_Config");
        assert(all(isfield(checkpoint, {'runProfiles', 'IPMSM_Sweep_Config'})), ...
            "The saved checkpoint must contain profiles and its configuration.");
        checkpointConfig = rmfield(checkpoint.IPMSM_Sweep_Config, ...
            intersect(ignoredFields, fieldnames(checkpoint.IPMSM_Sweep_Config)));
        assert(isequal(checkpointConfig, config), ...
            "Checkpoint sweep settings are inconsistent. Select N to re-run the entire sweep.");
        runProfiles = checkpoint.runProfiles(:);
        assert(numel(runProfiles) == config.TorqueStepsPerSpeed(speedIndex) && ...
            all([runProfiles.Speed_rpm] == config.Speeds(speedIndex)) && ...
            isequal(sort([runProfiles.TrqCmd]), config.TrqCmd{speedIndex}) && ...
            isequal(sort([runProfiles.TorquePercent]), config.TorquePercent{speedIndex}), ...
            "Checkpoint operating points are incomplete. Select N to re-run the entire sweep.");
        requiredFields = {'Speed_rpm', 'TrqCmd', 'TorquePercent', 'TrqEnvelope', ...
            'Id_ref', 'Iq_ref', 'Ia', 'Ib', 'Ic', 'RotorAngle', 'Time'};
        assert(isequal(fieldnames(runProfiles), requiredFields(:)), ...
            "Checkpoint profile fields are obsolete. Select N to re-run at 2 us.");
        for profileIndex = 1:numel(runProfiles)
            profile = runProfiles(profileIndex);
            assert(numel(profile.Time) >= 2 && ...
                all(abs(diff(profile.Time) - config.ProfileSampleTime) < 1e-12), ...
                "Checkpoint samples are not spaced at 2 us. Select N to re-run.");
        end
        profiles = [profiles; runProfiles]; %#ok<AGROW>
        fprintf("Reusing completed %d rpm run.\n", config.Speeds(speedIndex));
    end
end

function reduced = processCompletedRun(simOutput, config, speedIndex, resultsFolder)
    if ~isempty(simOutput.ErrorMessage)
        error("IPMSM_Sweep:SimulationFailed", "%s", simOutput.ErrorMessage);
    end
    runProfiles = extractRunProfiles(simOutput.IPMSM_Currents, config, speedIndex);
    IPMSM_Sweep_Config = config;
    save(fullfile(resultsFolder, sprintf("Profiles_%drpm.mat", ...
        config.Speeds(speedIndex))), "runProfiles", "IPMSM_Sweep_Config");
    fprintf("Saved %d operating points at %d rpm.\n", numel(runProfiles), config.Speeds(speedIndex));
    reduced = struct("runProfiles", runProfiles);
end

function profiles = extractRunProfiles(logged, config, speedIndex)
    assert(isstruct(logged) && isfield(logged, "time") && ...
        isfield(logged, "signals") && numel(logged.signals) == 4, ...
        "IPMSM_Currents must contain time and four logged signals.");
    time = logged.time(:);
    signals = zeros(numel(time), 4);
    for signalIndex = 1:4
        values = squeeze(logged.signals(signalIndex).values);
        assert(numel(values) == numel(time), "Logged signal lengths must match time.");
        signals(:, signalIndex) = values(:);
    end
    assert(all(isfinite(time)) && all(diff(time) > 0) && ...
        all(isfinite(signals), "all"), "Logged samples must be finite and ordered.");
    assert(numel(time) >= 2 && ...
        max(abs(diff(time) - config.ProfileSampleTime)) < 1e-12, ...
        "Scope1 must log native samples at exactly 2 us without decimation.");
    mechanicalAngle = unwrap(signals(:, 4));
    assert(all(diff(mechanicalAngle) >= -1e-10), ...
        "The logged mechanical angle must increase at positive speed.");
    period = config.ElectricalPeriods(speedIndex);
    angleSpan = 2*pi/config.PolePairs;
    timeTolerance = 1e-12;
    angularSpeed = 2*pi*config.Speeds(speedIndex)/60;
    % Allow small solver roundoff at phase boundaries without moving samples.
    angleTolerance = max(1e-8, angularSpeed * timeTolerance);
    profiles = struct([]);

    for torqueIndex = 1:config.TorqueStepsPerSpeed(speedIndex)
        stepStart = (torqueIndex - 1) * config.CyclesPerStep * period;
        stepEnd = torqueIndex * config.CyclesPerStep * period;
        assert(stepStart >= time(1) - timeTolerance && ...
            stepEnd <= time(end) + config.ProfileSampleTime + timeTolerance, ...
            "The logged run does not cover all torque steps.");
        % Interpolate boundary angles only to locate a cycle; retain raw samples.
        edgeAngles = interp1(time, mechanicalAngle, [stepStart; stepEnd], "linear", "extrap");
        % Prefer the last phase-aligned full cycle contained in this torque step.
        firstCycle = ceil((edgeAngles(1) - angleTolerance) / angleSpan);
        lastCycle = floor((edgeAngles(2) - angleSpan + angleTolerance) / angleSpan);
        assert(lastCycle >= firstCycle, ...
            "No complete phase-aligned electrical cycle at %d rpm, torque step %d.", ...
            config.Speeds(speedIndex), torqueIndex);
        cycleStartAngle = lastCycle * angleSpan;
        % Half-open cycle [start, end): do not duplicate the next cycle's first sample.
        sampleIndices = find(mechanicalAngle >= cycleStartAngle - angleTolerance & ...
            mechanicalAngle < cycleStartAngle + angleSpan - angleTolerance & ...
            time >= stepStart - timeTolerance & time < stepEnd - timeTolerance);
        assert(numel(sampleIndices) >= 2 && all(diff(sampleIndices) == 1), ...
            "The cycle must contain consecutive native logged samples.");
        simulationTime = time(sampleIndices);
        assert(simulationTime(1) >= stepStart - timeTolerance && ...
            simulationTime(end) < stepEnd, ...
            "The extracted cycle crosses a torque-step boundary.");
        assert(simulationTime(1) >= time(1) - timeTolerance && ...
            simulationTime(end) <= time(end) + timeTolerance, ...
            "Cycle boundary is outside the logged run.");
        assert(abs(numel(sampleIndices)*config.ProfileSampleTime - period) < ...
            config.ProfileSampleTime + timeTolerance, ...
            "The extracted profile must represent one fundamental electrical cycle.");
        currents = signals(sampleIndices, 1:3);
        relativeAngle = mechanicalAngle(sampleIndices) - mechanicalAngle(sampleIndices(1));
        profile = struct( ...
            "Speed_rpm", config.Speeds(speedIndex), ...
            "TrqCmd", config.TrqCmd{speedIndex}(torqueIndex), ...
            "TorquePercent", config.TorquePercent{speedIndex}(torqueIndex), ...
            "TrqEnvelope", config.EnvelopeTorque(speedIndex), ...
            "Id_ref", config.Id_ref{speedIndex}(torqueIndex), ...
            "Iq_ref", config.Iq_ref{speedIndex}(torqueIndex), ...
            "Ia", currents(:, 1), ...
            "Ib", currents(:, 2), ...
            "Ic", currents(:, 3), ...
            "RotorAngle", relativeAngle, ...
            "Time", simulationTime - simulationTime(1));
        if torqueIndex == 1
            profiles = repmat(profile, config.TorqueStepsPerSpeed(speedIndex), 1);
        else
            profiles(torqueIndex, 1) = profile;
        end
    end
end
