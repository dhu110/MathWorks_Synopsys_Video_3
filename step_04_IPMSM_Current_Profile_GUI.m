function fig = step_04_IPMSM_Current_Profile_GUI(dataFile)
% Browse variable speed-specific absolute-torque grids with native 2 us samples.
if nargin < 1
    dataFile = fullfile(fileparts(mfilename("fullpath")), "IPMSM_Current_Profiles.mat");
end
data = load(dataFile, "IPMSM_Current_Profiles");
assert(isfield(data, "IPMSM_Current_Profiles") && ...
    isstruct(data.IPMSM_Current_Profiles) && ~isempty(data.IPMSM_Current_Profiles), ...
    "The MAT file must contain the IPMSM_Current_Profiles structure array.");
profiles = data.IPMSM_Current_Profiles(:);
requiredFields = {'Speed_rpm', 'TrqCmd', 'TorquePercent', 'TrqEnvelope', ...
    'Id_ref', 'Iq_ref', 'Ia', 'Ib', 'Ic', 'RotorAngle', 'Time'};
assert(isequal(fieldnames(profiles), requiredFields(:)), ...
    "The dataset must contain the 11 required fields. Run step_02 again for legacy data.");
signalNames = {'Ia', 'Ib', 'Ic', 'RotorAngle', 'Time'};
for profileIndex = 1:numel(profiles)
    sampleCount = numel(profiles(profileIndex).Time);
    assert(sampleCount >= 2, "Each profile must contain at least two samples.");
    for fieldIndex = 1:6
        validateattributes(profiles(profileIndex).(requiredFields{fieldIndex}), {'numeric'}, ...
            {'scalar', 'real', 'finite'});
    end
    for signalIndex = 1:numel(signalNames)
        values = profiles(profileIndex).(signalNames{signalIndex});
        assert(isnumeric(values) && isreal(values) && isvector(values) && ...
            numel(values) == sampleCount && all(isfinite(values(:))), ...
            "All signals within a profile must have matching finite samples.");
    end
    assert(profiles(profileIndex).Time(1) == 0 && ...
        all(abs(diff(profiles(profileIndex).Time(:)) - 2e-6) < 1e-12), ...
        "Each profile must use native 2 us sampling. Run step_02 again for legacy data.");
end
speeds = unique([profiles.Speed_rpm]);
assert(numel(speeds) >= 2, "The GUI requires profiles at two or more speeds.");
[~, speedIndex] = min(abs(speeds - 5000));
selectedSpeed = speeds(speedIndex);
availableIndices = find([profiles.Speed_rpm] == selectedSpeed);
[availableTorques, torqueOrder] = sort([profiles(availableIndices).TrqCmd]);
availableIndices = availableIndices(torqueOrder);
assert(all(diff(availableTorques) > 0), "Torque commands at each speed must be distinct.");
selectedIndex = availableIndices(end);

fig = uifigure("Name", "IPMSM Current Profile Validation", ...
    "Position", [100, 100, 960, 740], "Visible", "off");
layout = uigridlayout(fig, [4, 2]);
layout.RowHeight = {64, 64, '2x', '1x'};
layout.ColumnWidth = {140, '1x'};
layout.Padding = [24, 20, 30, 20];
layout.RowSpacing = 24;
layout.ColumnSpacing = 20;

speedLabel = uilabel(layout, "FontSize", 13);
speedLabel.Layout.Row = 1;
speedLabel.Layout.Column = 1;
speedTicks = speeds(unique(round(linspace(1, numel(speeds), 4))));
speedSlider = uislider(layout, "Limits", [speeds(1), speeds(end)], ...
    "Value", selectedSpeed, "MajorTicks", speedTicks, "MinorTicks", speeds, ...
    "MajorTickLabels", cellstr(compose("%.0f", speedTicks)), "Tag", "Speed_rpm");
speedSlider.Layout.Row = 1;
speedSlider.Layout.Column = 2;

torqueLabel = uilabel(layout, "FontSize", 13);
torqueLabel.Layout.Row = 2;
torqueLabel.Layout.Column = 1;
torqueSlider = uislider(layout, "Limits", [availableTorques(1), availableTorques(end)], ...
    "Value", profiles(selectedIndex).TrqCmd, "Tag", "Trq_cmd");
torqueSlider.Layout.Row = 2;
torqueSlider.Layout.Column = 2;
updateTorqueTicks();

currentAxes = uiaxes(layout, "Tag", "IabcAxes");
currentAxes.Layout.Row = 3;
currentAxes.Layout.Column = [1, 2];
currentAxes.ColorOrder = [0.85, 0.12, 0.12; 0.12, 0.55, 0.20; 0.10, 0.35, 0.85];
sampleCount = numel(profiles(selectedIndex).Time);
sampleNumbers = (1:sampleCount).';
currentLines = plot(currentAxes, sampleNumbers, ...
    [profiles(selectedIndex).Ia(:), profiles(selectedIndex).Ib(:), ...
    profiles(selectedIndex).Ic(:)], "LineWidth", 1);
grid(currentAxes, "on");
xlabel(currentAxes, "Sample No.");
ylabel(currentAxes, "Current (A)");
title(currentAxes, "Phase Currents");
legend(currentAxes, currentLines, ["Ia", "Ib", "Ic"], ...
    "Location", "northeast", "Orientation", "horizontal");

angleAxes = uiaxes(layout, "Tag", "RotorAngleAxes");
angleAxes.Layout.Row = 4;
angleAxes.Layout.Column = [1, 2];
angleLine = plot(angleAxes, sampleNumbers, profiles(selectedIndex).RotorAngle(:), ...
    "k", "LineWidth", 1.2);
grid(angleAxes, "on");
xlabel(angleAxes, "Sample No.");
ylabel(angleAxes, "Mechanical Angle (rad)");
title(angleAxes, "Rotor Angle");
linkaxes([currentAxes, angleAxes], "x");
xlim(currentAxes, [1, sampleCount]);

speedSlider.ValueChangingFcn = @(~, event) selectSpeed(event.Value, false);
speedSlider.ValueChangedFcn = @(~, event) selectSpeed(event.Value, true);
torqueSlider.ValueChangingFcn = @(~, event) selectTorque(event.Value, false);
torqueSlider.ValueChangedFcn = @(~, event) selectTorque(event.Value, true);
updatePlots();
fig.Visible = "on";

    function selectSpeed(requestedSpeed, commit)
        [~, nearestSpeed] = min(abs(speeds - requestedSpeed));
        nextSpeed = speeds(nearestSpeed);
        if nextSpeed ~= selectedSpeed
            requestedTorque = profiles(selectedIndex).TrqCmd;
            selectedSpeed = nextSpeed;
            availableIndices = find([profiles.Speed_rpm] == selectedSpeed);
            [availableTorques, order] = sort([profiles(availableIndices).TrqCmd]);
            availableIndices = availableIndices(order);
            assert(all(diff(availableTorques) > 0), "Torque commands at each speed must be distinct.");
            torqueSlider.Limits = [availableTorques(1), availableTorques(end)];
            updateTorqueTicks();
            selectTorque(requestedTorque, true);
        end
        if commit
            speedSlider.Value = selectedSpeed;
        end
    end

    function selectTorque(requestedTorque, commit)
        [~, nearestTorque] = min(abs(availableTorques - requestedTorque));
        selectedIndex = availableIndices(nearestTorque);
        if commit
            torqueSlider.Value = profiles(selectedIndex).TrqCmd;
        end
        updatePlots();
    end

    function updateTorqueTicks()
        tickIndices = unique(round(linspace(1, numel(availableTorques), 5)));
        torqueSlider.MajorTicks = availableTorques(tickIndices);
        torqueSlider.MinorTicks = availableTorques;
        torqueSlider.MajorTickLabels = cellstr(compose("%.1f", availableTorques(tickIndices)));
    end

    function updatePlots()
        profile = profiles(selectedIndex);
        sampleCount = numel(profile.Time);
        sampleNumbers = (1:sampleCount).';
        for lineIndex = 1:numel(currentLines)
            currentLines(lineIndex).XData = sampleNumbers;
        end
        angleLine.XData = sampleNumbers;
        currentLines(1).YData = profile.Ia(:);
        currentLines(2).YData = profile.Ib(:);
        currentLines(3).YData = profile.Ic(:);
        angleLine.YData = profile.RotorAngle(:);
        currentAxes.YLimMode = "auto";
        angleAxes.YLimMode = "auto";
        xlim(currentAxes, [1, sampleCount]);
        title(currentAxes, sprintf("Phase Currents | %d samples | 2 us | Id ref %.2f A, Iq ref %.2f A", ...
            sampleCount, profile.Id_ref, profile.Iq_ref));
        speedLabel.Text = sprintf("Speed_rpm\n%d rpm", profile.Speed_rpm);
        torqueLabel.Text = sprintf("Trq_cmd\n%.2f N m (%.1f%%)", ...
            profile.TrqCmd, profile.TorquePercent);
        fig.UserData = struct("ProfileIndex", selectedIndex, ...
            "Speed_rpm", profile.Speed_rpm, "TrqCmd", profile.TrqCmd, ...
            "SampleCount", sampleCount, "ProfileSampleTime", 2e-6, ...
            "Id_ref", profile.Id_ref, "Iq_ref", profile.Iq_ref);
        fig.UserData.TorquePercent = profile.TorquePercent;
        fig.UserData.TorqueStepsAtSpeed = numel(availableTorques);
        drawnow limitrate;
    end
end
