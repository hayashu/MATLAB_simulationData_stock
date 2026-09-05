function simOut = watertank_postsim_export(simOut, simIn)
%WATERTANK_POSTSIM_EXPORT Post-simulation callback for the Simulink
% "Multiple Simulations" pane (simulink.multisim.DesignStudy PostSimFcn).
%
% For each run in the batch, extracts LevelRef/LevelMeas, computes step
% response metrics, and writes a run_*/metadata.json folder consumed by
% pr1/test_mlflow.py. Configure this as the "Post-Simulation Function" in
% the Multiple Simulations pane; the parameter sweep itself (Kp_Level,
% Ki_Level, ...) is defined entirely in that GUI.

%% Parameters actually used for this run (from the swept Variables, else base workspace)
Kp_Level = localGetVar(simIn, 'Kp_Level');
Ki_Level = localGetVar(simIn, 'Ki_Level');
Kd_Level = localGetVar(simIn, 'Kd_Level');

%% Logged signals
logsout = simOut.get('logsout');
sigRef  = logsout.get('LevelRef').Values;
sigMeas = logsout.get('LevelMeas').Values;

tRef  = sigRef.Time;   yRef  = sigRef.Data;
tMeas = sigMeas.Time;  yMeas = sigMeas.Data;

%% Step response metrics (matches WaterTankLevelControlDemo_mlflow_run.m)
stepTime = 20;   % LevelSetpoint block Time
target   = 1.2;  % LevelSetpoint block FinalValue

post = tMeas >= stepTime;
err  = yMeas(post) - target;
RMSE = sqrt(mean(err.^2));
Overshoot_pct = max(0, (max(yMeas(post)) - target) / target * 100);

band = 0.02 * abs(target);
outOfBand = find(abs(err) > band);
if isempty(outOfBand)
    SettlingTime_s = 0;
else
    tPost = tMeas(post);
    SettlingTime_s = tPost(outOfBand(end)) - stepTime;
end

FinalLevel = yMeas(end);

%% Output folder (shared sync dir consumed by pr1/test_mlflow.py)
runTag    = sprintf('%s_Kp%.2f_Ki%.2f_Kd%.2f', datestr(now, 'yyyymmdd_HHMMSSFFF'), Kp_Level, Ki_Level, Kd_Level);
runFolder = sprintf('run_%s_WaterTank', runTag);
syncDir   = fullfile(fileparts(mfilename('fullpath')), 'mlflow_sync');
outputDir = fullfile(syncDir, runFolder);
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

%% Response plot
fig = figure('Visible', 'off');
plot(tRef, yRef, '--', 'LineWidth', 1.5); hold on;
plot(tMeas, yMeas, 'LineWidth', 1.5);
legend('LevelRef (setpoint)', 'LevelMeas (tank level)', 'Location', 'best');
title(sprintf('Kp=%.2f, Ki=%.2f, Kd=%.2f - RMSE: %.4f', Kp_Level, Ki_Level, Kd_Level, RMSE));
xlabel('Time [s]'); ylabel('Level [m]');
grid on;
saveas(fig, fullfile(outputDir, 'response_plot.png'));
close(fig);

%% Raw signal data
save(fullfile(outputDir, 'signals.mat'), 'tRef', 'yRef', 'tMeas', 'yMeas');

%% MLflow metadata
metadata = struct();
metadata.experiment_name = 'WaterTank_Level_Control_Sweep';
metadata.run_name = sprintf('Kp=%.2f_Ki=%.2f_Kd=%.2f', Kp_Level, Ki_Level, Kd_Level);

metadata.params = struct(...
    'Model', 'WaterTankLevelControlDemo', ...
    'Kp_Level', Kp_Level, ...
    'Ki_Level', Ki_Level, ...
    'Kd_Level', Kd_Level, ...
    'StepTime', stepTime, ...
    'TargetLevel', target ...
);

metadata.metrics = struct(...
    'RMSE', RMSE, ...
    'Overshoot_pct', Overshoot_pct, ...
    'SettlingTime_s', SettlingTime_s, ...
    'FinalLevel', FinalLevel ...
);

metadata.tags = struct('Controller', 'PID', 'Source', 'MultipleSimulationsGUI');
metadata.description = sprintf('Water tank level control sweep: Kp=%.2f, Ki=%.2f, Kd=%.2f', ...
    Kp_Level, Ki_Level, Kd_Level);

fid = fopen(fullfile(outputDir, 'metadata.json'), 'w');
fwrite(fid, jsonencode(metadata));
fclose(fid);
end

function v = localGetVar(simIn, name)
v = [];
vars = simIn.Variables;
for i = 1:numel(vars)
    if strcmp(vars(i).Name, name)
        v = vars(i).Value;
        return
    end
end
if isempty(v)
    v = evalin('base', name); % not swept in this run -> use base workspace value
end
end
