%% Export a completed "Root Parameter Set" batch (out = parsim results) to MLflow-syncable runs.
% Use this after running a sweep via the Simulink "Run All" / Root Parameter Set
% panel, when the result array (e.g. `out`, an Nx1/1xN Simulink.SimulationOutput)
% is still in the base workspace.
%
% Set these to exactly match the Root Parameter Set panel's Variable_1/2/3
% ranges before running (see export_batch_results.m for the combination
% order this assumes).

Kp_vals = 10:12;          % Variable_1 in the Root Parameter Set panel
Ki_vals = 1.0:0.1:1.2;    % Variable_2
Kd_vals = 0;              % Not swept this batch (Kd_Level fixed at base workspace value)

export_batch_results(out, Kp_vals, Ki_vals, Kd_vals);
