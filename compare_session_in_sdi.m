function compare_session_in_sdi(session_id)
%COMPARE_SESSION_IN_SDI Import every run of an experiment session into the
% Simulation Data Inspector so LevelRef/LevelMeas can be overlaid, zoomed,
% and cursor-compared across runs the way SDI is built for -- MLflow's
% own "Compare Runs" chart is far more limited for this.
%
%   compare_session_in_sdi('20260906_132535')
%
% Reads mlflow_sync/run_*/{metadata.json,signals.mat} for every run tagged
% with this session_id, and creates one SDI run per simulation run, named
% after its params (e.g. "Kp=3.00_Ki=0.40_Kd=0.00").

syncDir = fullfile(fileparts(mfilename('fullpath')), 'mlflow_sync');
folders = dir(fullfile(syncDir, 'run_*'));

count = 0;
for i = 1:numel(folders)
    metaFile = fullfile(syncDir, folders(i).name, 'metadata.json');
    if ~isfile(metaFile)
        continue;
    end
    meta = jsondecode(fileread(metaFile));
    if ~isfield(meta, 'tags') || ~isfield(meta.tags, 'session_id') ...
            || ~strcmp(meta.tags.session_id, session_id)
        continue;
    end

    matFile = fullfile(syncDir, folders(i).name, 'signals.mat');
    if ~isfile(matFile)
        continue;
    end
    d = load(matFile);

    tsMeas = timeseries(d.yMeas, d.tMeas, 'Name', 'LevelMeas');
    tsRef  = timeseries(d.yRef, d.tRef, 'Name', 'LevelRef');

    runLabel = meta.run_name;
    Simulink.sdi.createRun(runLabel, 'vars', tsMeas, tsRef);
    count = count + 1;
end

if count == 0
    warning('session_id=%s に該当するrunが見つかりませんでした', session_id);
    return;
end

fprintf('%d 件のrunをSDIにインポートしました (session_id=%s)。\n', count, session_id);
Simulink.sdi.view;
end
