function watertank_stopfcn_export()
%WATERTANK_STOPFCN_EXPORT Model StopFcn callback for WaterTankLevelControlDemo.
% Runs automatically every time a simulation of this model ends, no matter
% how it was started (manual "Run", the toolstrip "Run All" batch panel, or
% a script). Reads the just-finished run from the Simulation Data Inspector
% and the current Kp_Level/Ki_Level/Kd_Level from the base workspace, then
% writes a run_*/metadata.json folder consumed by pr1/test_mlflow.py.

runIDs = Simulink.sdi.getAllRunIDs();
if isempty(runIDs)
    return
end
run = Simulink.sdi.getRun(runIDs(end));

sigRef = []; sigMeas = [];
for i = 1:run.SignalCount
    sig = run.getSignalByIndex(i);
    if strcmp(sig.Name, 'LevelRef')
        sigRef = sig;
    elseif strcmp(sig.Name, 'LevelMeas')
        sigMeas = sig;
    end
end
if isempty(sigRef) || isempty(sigMeas)
    return
end

tRef  = sigRef.Values.Time;   yRef  = sigRef.Values.Data;
tMeas = sigMeas.Values.Time;  yMeas = sigMeas.Values.Data;

%% Parameters used for this run (base workspace at the moment the sim stopped)
Kp_Level = evalin('base', 'Kp_Level');
Ki_Level = evalin('base', 'Ki_Level');
Kd_Level = evalin('base', 'Kd_Level');

%% Step response metrics
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

gitInfo = watertank_git_info();
metadata.tags = struct('Controller', 'PID', 'Source', 'StopFcn', ...
    'git_commit', gitInfo.commit, 'git_dirty', gitInfo.dirty);
metadata.description = sprintf('Water tank level control: Kp=%.2f, Ki=%.2f, Kd=%.2f', ...
    Kp_Level, Ki_Level, Kd_Level);

fid = fopen(fullfile(outputDir, 'metadata.json'), 'w');
fwrite(fid, jsonencode(metadata));
fclose(fid);
end
