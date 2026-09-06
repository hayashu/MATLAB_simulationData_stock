%% Run WaterTankLevelControlDemo once and record the result as an MLflow-syncable run.
% Mirrors the run_*/metadata.json convention used by test_mlflow.py:
%   ~/Documents/MATLAB/mlflow_sync/run_<timestamp>/{metadata.json, response_plot.png, ...}
% After this script finishes, running pr1/test_mlflow.py uploads the new run to MLflow.

%% 1. Load model (PreLoadFcn runs WaterTankLevelControlDemo_init automatically)
model = 'WaterTankLevelControlDemo';
load_system(model);

%% 2. Run the simulation
fprintf('シミュレーション実行中: %s ...\n', model);
simOut = sim(model);

%% 3. Extract logged signals (LevelRef = setpoint, LevelMeas = tank level)
logsout = simOut.get('logsout');
sigRef  = logsout.get('LevelRef').Values;
sigMeas = logsout.get('LevelMeas').Values;

tRef  = sigRef.Time;   yRef  = sigRef.Data;
tMeas = sigMeas.Time;  yMeas = sigMeas.Data;

%% 4. Metrics (step response after the setpoint change at t = StepTime)
stepTime = get_param([model '/LevelSetpoint'], 'Time');
stepTime = str2double(stepTime);
target   = get_param([model '/LevelSetpoint'], 'FinalValue');
target   = evalin('base', target); % may be a workspace expression

post = tMeas >= stepTime;
err  = yMeas(post) - target;
RMSE = sqrt(mean(err.^2));
Overshoot_pct  = max(0, (max(yMeas(post)) - target) / target * 100);

band = 0.02 * abs(target);
outOfBand = find(abs(err) > band);
if isempty(outOfBand)
    SettlingTime_s = 0;
else
    tPost = tMeas(post);
    SettlingTime_s = tPost(outOfBand(end)) - stepTime;
end

FinalLevel = yMeas(end);

fprintf('RMSE=%.4f, Overshoot=%.2f%%, SettlingTime=%.2fs, FinalLevel=%.4f\n', ...
    RMSE, Overshoot_pct, SettlingTime_s, FinalLevel);

%% 5. Output folder (shared sync dir consumed by pr1/test_mlflow.py)
batchTimestamp = datestr(now, 'yyyymmdd_HHMMSS');
runFolder = sprintf('run_%s_WaterTank', batchTimestamp);
syncDir   = fullfile(fileparts(mfilename('fullpath')), 'mlflow_sync');
outputDir = fullfile(syncDir, runFolder);
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

%% 6. Response plot
fig = figure('Visible', 'off');
plot(tRef, yRef, '--', 'LineWidth', 1.5); hold on;
plot(tMeas, yMeas, 'LineWidth', 1.5);
legend('LevelRef (setpoint)', 'LevelMeas (tank level)', 'Location', 'best');
title(sprintf('Water Tank Level Control - RMSE: %.4f, Overshoot: %.1f%%', RMSE, Overshoot_pct));
xlabel('Time [s]'); ylabel('Level [m]');
grid on;
saveas(fig, fullfile(outputDir, 'response_plot.png'));
close(fig);

%% 7. Raw signal data + SDI session (artifacts)
save(fullfile(outputDir, 'signals.mat'), 'tRef', 'yRef', 'tMeas', 'yMeas');
runIDs = Simulink.sdi.getAllRunIDs();
if ~isempty(runIDs)
    Simulink.sdi.save(fullfile(outputDir, 'sdi_data.mldatx'));
end

%% 8. MLflow metadata
metadata = struct();
metadata.experiment_name = 'WaterTank_Level_Control';
metadata.run_name = sprintf('WaterTank_%s', batchTimestamp);

metadata.params = struct(...
    'Model', model, ...
    'Kp_Level', evalin('base', 'Kp_Level'), ...
    'Ki_Level', evalin('base', 'Ki_Level'), ...
    'Kd_Level', evalin('base', 'Kd_Level'), ...
    'A_tank', evalin('base', 'A_tank'), ...
    'MaxValveArea', evalin('base', 'MaxValveArea'), ...
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
tags = struct(...
    'BatchID', batchTimestamp, ...
    'Controller', 'PID', ...
    'git_commit', gitInfo.commit, ...
    'git_dirty', gitInfo.dirty ...
);
if evalin('base', 'exist(''session_id'',''var'')')
    tags.session_id = evalin('base', 'session_id');
end
metadata.tags = tags;

metadata.description = sprintf('Water tank level control: Kp=%.2f, Ki=%.2f, Kd=%.2f', ...
    evalin('base', 'Kp_Level'), evalin('base', 'Ki_Level'), evalin('base', 'Kd_Level'));

fid = fopen(fullfile(outputDir, 'metadata.json'), 'w');
fwrite(fid, jsonencode(metadata));
fclose(fid);

fprintf('run manifest 書き出し完了: %s\n', outputDir);

%% 9. Sync to MLflow (invokes pr1/test_mlflow.py)
syncScript = fullfile(fileparts(mfilename('fullpath')), 'test_mlflow.py');
if isfile(syncScript)
    fprintf('MLflowへ同期中...\n');
    pythonExe = '/Library/Frameworks/Python.framework/Versions/3.13/bin/python3';
    [status, cmdout] = system(sprintf('"%s" "%s"', pythonExe, syncScript));
    disp(cmdout);
    if status ~= 0
        warning('test_mlflow.py の実行に失敗しました (status=%d)。手動で実行してください。', status);
    end
else
    warning('test_mlflow.py が見つかりません: %s', syncScript);
end
