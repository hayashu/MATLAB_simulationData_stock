function run_parameter_sweep(Kp_vals, Ki_vals, Kd_vals)
%RUN_PARAMETER_SWEEP Run a Kp/Ki/Kd sweep via simulink.multisim.DesignStudy
% and export the results, without depending on the Simulink "Root
% Parameter Set" panel (whose actual per-case parameter values are not
% reliably observable from any callback -- see watertank_stopfcn_export.m
% for the incident this caused on 2026-09-05).
%
%   run_parameter_sweep(Kp_vals, Ki_vals, Kd_vals)
%
% Any of the three may be a scalar (not swept, held at that fixed value).
% Combination order matches export_batch_results.m: Kp_vals fastest, then
% Ki_vals, then Kd_vals.

if nargin < 3 || isempty(Kd_vals)
    Kd_vals = evalin('base', 'Kd_Level');
end

vars = simulink.multisim.Variable.empty;
vars(end+1) = simulink.multisim.Variable('Kp_Level', Kp_vals);
vars(end+1) = simulink.multisim.Variable('Ki_Level', Ki_vals);
vars(end+1) = simulink.multisim.Variable('Kd_Level', Kd_vals);

exComb = simulink.multisim.Exhaustive(vars);
ds = simulink.multisim.DesignStudy('WaterTankLevelControlDemo', exComb);

fprintf('パラメータスイープ実行中 (%d 件)...\n', ds.NumSims);
future = parsim(ds);
wait(future);
out = fetchOutputs(future); %#ok<NASGU>

export_batch_results(out, Kp_vals, Ki_vals, Kd_vals);
end
