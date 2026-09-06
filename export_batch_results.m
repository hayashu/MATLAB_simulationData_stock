function export_batch_results(out, Kp_vals, Ki_vals, Kd_vals)
%EXPORT_BATCH_RESULTS Write run manifests for a completed parsim batch and sync to MLflow.
%
%   export_batch_results(out, Kp_vals, Ki_vals, Kd_vals)
%
% `out` is an array of Simulink.SimulationOutput (e.g. from the Root
% Parameter Set "Run All" panel, or from run_parameter_sweep.m).
% Kp_vals/Ki_vals/Kd_vals are the exact value lists used to produce it, in
% the same combination order: Kp_vals varies fastest, then Ki_vals, then
% Kd_vals slowest (index = kp_idx + (ki_idx-1)*nKp + (kd_idx-1)*nKp*nKi).
% This ordering was empirically verified against the Root Parameter Set
% panel on 2026-09-05 (see watertank_export_from_out.m history) and also
% matches simulink.multisim.Exhaustive's own combination order.
%
% Writes one run_*/metadata.json (+ response_plot.png, signals.mat) per
% element of `out` under mlflow_sync/, then syncs everything to MLflow via
% test_mlflow.py.

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

%% Sync to MLflow
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
end
