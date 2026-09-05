% Parameters for WaterTankLevelControlDemo.slx
rho_water    = 1000;    % Liquid density [kg/m^3]
g_const      = 9.81;    % Gravitational acceleration [m/s^2]

A_tank       = 0.25;    % Tank cross-sectional area [m^2]
H0           = 0.3;     % Initial tank level [m]
Hmax         = 2;       % Maximum tank level [m]

MaxValveArea = 5e-4;    % Maximum inlet valve opening area [m^2]
DrainArea    = 2e-4;    % Fixed drain orifice area [m^2]
P_atm        = 1e5;     % Reference (atmosphere) absolute pressure [Pa]
P_supply     = 3e4;     % Supply reservoir pressure above reference [Pa]

Kp_Level     = 4;       % PID proportional gain
Ki_Level     = 0.4;     % PID integral gain
Kd_Level     = 0;       % PID derivative gain

V_chamber    = A_tank;  % Chamber volume [m^3], chosen so beta_L = rho*g (see below)
beta_L       = rho_water*g_const*V_chamber/A_tank; % Artificial fluid bulk modulus [Pa]
                        % so that dP/dt = rho*g*dH/dt for a chamber of volume V_chamber,
                        % making the chamber behave like a free-surface tank of area A_tank.
