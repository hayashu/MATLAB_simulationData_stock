%% Export a completed "Root Parameter Set" batch (out = parsim results) to MLflow-syncable runs.
% Use this after running a sweep via the Simulink "Run All" / Root Parameter Set
% panel, when the result array (e.g. `out`, an Nx1/1xN Simulink.SimulationOutput)
% is still in the base workspace.
%
% IMPORTANT: the combination order below (Variable_1 fastest, then
% Variable_2, then Variable_3 slowest) was empirically verified against a
% real 5x5x5 Kp/Ki/Kd sweep on 2026-09-05 by re-simulating two candidate
% index->parameter mappings and matching overshoot to out(2). Re-verify if
% the panel's variable order or count changes.

Kp_vals = 10:12;          % Variable_1 in the Root Parameter Set panel
Ki_vals = 1.0:0.1:1.2;    % Variable_2
Kd_vals = 0;              % Not swept this batch (Kd_Level fixed at base workspace value)

nKp = numel(Kp_vals); nKi = numel(Ki_vals); nKd = numel(Kd_vals);
assert(numel(out) == nKp*nKi*nKd, 'out size does not match the parameter grid size');

stepTime = 20;
target   = 1.2;
syncDir  = fullfile(fileparts(mfilename('fullpath')), 'mlflow_sync');
gitInfo  = watertank_git_info();

% One shared session_id for the whole batch, so every run in it can be
% grouped under the same experiment note (see new_experiment_note.m).
if evalin('base', 'exist(''session_id'',''var'')')
    session_id = evalin('base', 'session_id');
else
    session_id = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<TNOW1,DATST>
end

for i = 1:numel(out)
    kp_idx = mod(i-1, nKp) + 1;
    ki_idx = mod(floor((i-1)/nKp), nKi) + 1;
    kd_idx = floor((i-1)/(nKp*nKi)) + 1;

    Kp_Level = Kp_vals(kp_idx);
    Ki_Level = Ki_vals(ki_idx);
    Kd_Level = Kd_vals(kd_idx);

    lg = out(i).logsout;
    sigRef  = lg.get('LevelRef').Values;
    sigMeas = lg.get('LevelMeas').Values;
    tRef  = sigRef.Time;   yRef  = sigRef.Data;
    tMeas = sigMeas.Time;  yMeas = sigMeas.Data;

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

    runFolder = sprintf('run_%s_%03d_Kp%.2f_Ki%.2f_Kd%.2f_WaterTank', ...
        datestr(now, 'yyyymmdd_HHMMSS'), i, Kp_Level, Ki_Level, Kd_Level);
    outputDir = fullfile(syncDir, runFolder);
    mkdir(outputDir);

    fig = figure('Visible', 'off');
    plot(tRef, yRef, '--', 'LineWidth', 1.5); hold on;
    plot(tMeas, yMeas, 'LineWidth', 1.5);
    legend('LevelRef (setpoint)', 'LevelMeas (tank level)', 'Location', 'best');
    title(sprintf('Kp=%.2f, Ki=%.2f, Kd=%.2f - RMSE: %.4f', Kp_Level, Ki_Level, Kd_Level, RMSE));
    xlabel('Time [s]'); ylabel('Level [m]');
    grid on;
    saveas(fig, fullfile(outputDir, 'response_plot.png'));
    close(fig);

    save(fullfile(outputDir, 'signals.mat'), 'tRef', 'yRef', 'tMeas', 'yMeas');

    metadata = struct();
    metadata.experiment_name = 'WaterTank_Level_Control_Sweep';
    metadata.run_name = sprintf('Kp=%.2f_Ki=%.2f_Kd=%.2f', Kp_Level, Ki_Level, Kd_Level);
    metadata.params = struct('Model', 'WaterTankLevelControlDemo', ...
        'Kp_Level', Kp_Level, 'Ki_Level', Ki_Level, 'Kd_Level', Kd_Level, ...
        'StepTime', stepTime, 'TargetLevel', target);
    metadata.metrics = struct('RMSE', RMSE, 'Overshoot_pct', Overshoot_pct, ...
        'SettlingTime_s', SettlingTime_s, 'FinalLevel', FinalLevel);
    metadata.tags = struct('Controller', 'PID', 'Source', 'RootParameterSet', ...
        'git_commit', gitInfo.commit, 'git_dirty', gitInfo.dirty, ...
        'session_id', session_id);
    metadata.description = sprintf('Water tank level control sweep: Kp=%.2f, Ki=%.2f, Kd=%.2f', ...
        Kp_Level, Ki_Level, Kd_Level);

    fid = fopen(fullfile(outputDir, 'metadata.json'), 'w');
    fwrite(fid, jsonencode(metadata));
    fclose(fid);
end

fprintf('%d 件のrun manifestを書き出しました: %s\n', numel(out), syncDir);

%% Sync to MLflow (2ステップ目をここに統合: この後test_mlflow.pyを手動実行しなくてよい)
syncScript = fullfile(fileparts(mfilename('fullpath')), 'test_mlflow.py');
if isfile(syncScript)
    fprintf('MLflowへ同期中...\n');
    pythonExe = '/Library/Frameworks/Python.framework/Versions/3.13/bin/python3';
    [status, cmdout] = system(sprintf('"%s" "%s"', pythonExe, syncScript));
    disp(cmdout);
    if status ~= 0
        warning('test_mlflow.py の実行に失敗しました (status=%d)。手動で実行してください。', status);
    end
end
