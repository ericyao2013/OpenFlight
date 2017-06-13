%% setupNL.m
% Nonlinear Simulation setup
%
% This script will setup the nonlinear simulation and call
% trim and linearization routines.
%
% Note: the model is not opened by default. This is not
% necessary to trim, linearize, and simulate via command line inputs.
% 
% University of Minnesota 
% Aerospace Engineering and Mechanics 
% Copyright 2017 Regents of the University of Minnesota. 
% All rights reserved.
%


%% Configure Simulation
% 1 = UltraStick25e, standard outfit
if ~exist('aircraftType', 'var')
    aircraftType = 1 ; 
end


%% Configure Simulation Fidelity
% 1 = Simplified Open-Source
% 2 = High-Fidelity, requires Aerospace Blockset
if ~exist('simulation_type', 'var')
    simulation_type = 1 ;
end


%% Configure simulation specifically for this airfame
switch aircraftType
    case 1 % UltraStick25e, AVL AeroModel, Standard Actuators and Sensors
        % Simulation sample time
        SampleTime = 0.02; % sec
        
        % Aircraft Config
        [AC, Env] = SimConfig('UltraStick25e');
        % [AC, Env] = SimConfig('UltraStick25e_AVL');

        % Configure variant for model refenence   
        aeroType = 1;
        aeroVariant = Simulink.Variant('aeroType == 1');
        
end


%% Setup simulation fidelity specific parameters
switch simulation_type
    case 1 % Simplified Open-Source
        SimEnvironConst_Temperature_K = 2.875001140067589e+02 ;
        SimEnvironConst_SpeedOfSound_mps = 3.399101459434841e+02 ;
        SimEnvironConst_Pressure_kPa = 1.001296472649073e+05 ;
        SimEnvironConst_Density_kgpm3 = 1.213283987428570 ;
        SimEnvironConst_Gravity_mps2 = 9.805475067186025 ;   
end

% Simulation Fidelity Variants Definition
sim_fidelity_simple_var = Simulink.Variant('simulation_type == 1') ;
sim_fidelity_full_var   = Simulink.Variant('simulation_type == 2') ;
    


%% Setup simulation buses
GeneralBuses;


%% Set aircraft initial conditions 
% Note: these are NOT the trim condition targets. If the trim fails to
% coverge, try using different initial conditions. Also note that the trim
% function will overwrite these initial conditions with the trimmed
% conditions.

% Constants
r2d = 180/pi;
d2r = pi/180;

% Set initial state values
TrimCondition.InertialIni    = [0, 0, -100]'; % Initial Position in Inertial Frame [Xe Ye Ze], [m]
TrimCondition.LLIni          = [44.7258357, -93.07501316]'; % Initial Latitude/Longitude of Aircraft [Lat Long], [deg]
TrimCondition.AttitudeIni    = [0, 0.0217, 155*d2r]'; % Initial Euler orientation [roll, pitch, yaw], [rad], can't use 0 heading, causes large entry in C matrix for psi 
TrimCondition.RatesIni       = [0, 0, 0]'; % Initial Body Frame rotation rates [p q r], [rad/s]

% Steady state wind values, m/s
TrimCondition.Inputs.Wind     = [0, 0, 0]';

switch lower(AC.aircraft)
    case 'ultrastick120'
        % Control surface initial values, rad:
        % elevator, rudder, aileron, left flap, right flap
        TrimCondition.Inputs.Effector = [0.091 0 0 0 0]';
        
        % number of the control surfaces (required to initialize the input
        % port dimension; dynamically relocating it returns an error)
        AC.nctrls = size(TrimCondition.Inputs.Effector,1);
        
        % Throttle initial value, nd
        TrimCondition.Inputs.Throttle = 0.559;
        
        % Initial velocity vector, m/s: [u v w]
        TrimCondition.VelocitiesIni  = [23 0 0.369]';
        
        % Initial Engine Speed [rad/s]
        TrimCondition.EngineSpeedIni = 827;
        
    case 'ultrastick25e'
        % Control surface initial values, rad:
        % elevator, rudder, aileron, left flap, right flap
        TrimCondition.Inputs.Actuator = [0.091 0 0 0 0]';
        
        % number of the control surfaces (required to initialize the input
        % port dimension; dynamically relocating it returns an error)
        AC.nctrls = size(TrimCondition.Inputs.Actuator,1);
        
        % Throttle initial value, nd
        TrimCondition.Inputs.Motor = 0.559;
        
        % Initial velocity vector, m/s: [u v w]
        TrimCondition.VelocitiesIni  = [17 0 0.369]';
        
        % Initial Engine Speed [rad/s]
        TrimCondition.EngineSpeedIni = 827;
        
    case 'maewing1'
        % Control surface initial values, rad:
        % elevator, aileron, L1, L4, R1, R4
        TrimCondition.Inputs.Effector = [-.09 0 0 0 0 0]';
        AC.nctrls = size(TrimCondition.Inputs.Effector,1);
        
        % Throttle initial value, nd
        TrimCondition.Inputs.Throttle = 0.559;
        
        % Initial velocity vector, m/s: [u v w]
        TrimCondition.VelocitiesIni  = [23.6 0 0.369]';
        
        % Initial flexible state values:
        
        % Get dimensions of the structural and aerodynamics model
        nstates = size(AC.Aero.RFA.A0,1); %overall number of states
        nrigidstates = 6; %number of rigid body states
        nflexstates = nstates-nrigidstates; %number of flexible states
        nflaps = size(AC.Aero.RFA.A0,2)-nstates; %number of control surfaces
        nlagstates = size(AC.Aero.RFA.Alag,1); %number of lag states
        
        % Initial values of structural model
        % Displacements in modal coordinates
        TrimCondition.FlexIni = zeros(nflexstates,1);
        % Velocities in modal coordinates
        TrimCondition.FlexRatesIni = zeros(nflexstates,1);
        
        % Inital values of the unsteady aerodynamics
        % Lag states
        TrimCondition.LagStatesIni = zeros(nlagstates,1);
        % DT1 filter states to obtain control surface velocities
        % (XXX not required if we have an actuator model, should we
        % consider that?)
        TrimCondition.DT1CtrlSurfIni = zeros(nflaps,1);
        % DT1 filter states to obtain accelerations
        TrimCondition.DT1AccAllModes = zeros(nstates+nflaps,1);
end


%% Trim aircraft to a specific flight condition
% Set the trim targets here. See trim_UAV for complete list of target
% variables. Sideslip angle (beta), flight path angle (gamma) and flap
% setting default to zero. If a fixed control input setting is desired,
% specify as a target.

% straight and level, (m/s, rad)
TrimCondition.target = struct('V_s', TrimCondition.VelocitiesIni(1), 'gamma', 0 * d2r, 'h', 100);
% TrimCondition.target = struct('V_s', TrimCondition.VelocitiesIni(1), 'gamma', 5 * d2r); % level climb, (m/s, rad)
% TrimCondition.target = struct('V_s', TrimCondition.VelocitiesIni(1), 'gamma', 0 * d2r, 'psidot', 20 * d2r); % level turn, (m/s, rad, rad/sec)
% TrimCondition.target = struct('V_s', TrimCondition.VelocitiesIni(1), 'gamma', 5 * d2r, 'psidot',20 * d2r); % climbing turn, (m/s, rad, rad/sec)
% TrimCondition.target = struct('V_s', TrimCondition.VelocitiesIni(1), 'gamma', 0 * d2r, 'beta', 5 * d2r); % level steady heading sideslip, (m/s, rad, rad)

% Find the trim solution
simModel = 'SimNL';
[TrimCondition, OperatingPoint] = TrimSim(simModel, TrimCondition, AC);


%% Linearize about the operating point
[longmod, spmod, latmod, linmodel] = LinearizeSim(simModel, OperatingPoint, AC);
