function [transport_totals,transport_results,output_report,output_machine_database,Grid_Composition,FC_data,process_timing_results] = sie_app_main(energy_mix,machine_database,chemical_database,Transport,misc)


%% TO DO LIST
% Update single element materials to have the production CExC, not the chemical Xh in material definition.

% Transport of strawberries to jam factory
% Check outputs of refined sugar production
% Transport SugarBeet to Sugar Factory
% Transport Sugar to Jam Factory
% Transport Jam to Yogurt Factory

% DONE - Track Main products of each process in terms of mass flow rate

% DONE - Check gas Exergy (chemical or CExC)
% DONE - Double accounting in sugar production for input chemicals?
% Fix electricity to loop back to start if process is longer than a day

%% Extract data from input variables
feed_concentrate = misc.final_product * 944.6; % 1135.70    Wrong values?
feed_forage = misc.final_product * 209.3;     % 251.59     rescaled to make
feed_roughage = misc.final_product * 1396.2;   % 1678.68    feed 2550 kg as per paper

product_multiplier = misc.final_product;

timing = misc.process_times; % hours to minutes

% [Gas, Wind, Nuclear, Solar]
px_gas = energy_mix(1)/100;  %gas makes up the deficit from solar
px_wind = energy_mix(2)/100;
px_coal2 = energy_mix(3)/100;
px_nuclear = energy_mix(4)/100;
px_solar = energy_mix(5)/100;

%% Define Electricity Grid Timeseries
% Electricity grd defined in 30 minute blocks
block_length = 30;

% [Gas, Wind, Coal, Nuclear, Solar] energy_mix = [41,29,6,18,6]; 

gas = (px_gas)*ones(1,(24*60/block_length))';
wind = (px_wind)*ones(1,(24*60/block_length))';
nuclear = (px_nuclear)*ones(1,(24*60/block_length))';
coal2 = (px_coal2)*ones(1,(24*60/block_length))';
solar2 = (px_solar)*ones(1,(24*60/block_length))';

% account for season, scale solar power by factors:
load("data\solar_coefficients.mat","solar_coefficients");
season = misc.season;
switch season % wind capacity factors from: https://doi.org/10.5194/asr-16-119-2019
    case "Summer"
        solar2 = solar2 .* solar_coefficients.summer;
        wind = wind .* 0.75;
    case "Spring"
        solar2 = solar2 .* solar_coefficients.spring;
        wind = wind .* 1;
    case "Autumn"
        solar2 = solar2 .* solar_coefficients.autumn;
        wind = wind .* 1.25;
    case "Winter"
        solar2 = solar2 .* solar_coefficients.winter;
        wind = wind .* 1.5;
    otherwise
end


% option to switch makeup of decifit from gas/coal
if misc.top_up_demand == "gas"
    gas = ones(1,(24*60/block_length))';
    gas = gas - wind - coal2 - nuclear - solar2;
elseif misc.top_up_demand == "coal"
    coal2 = ones(1,(24*60/block_length))';
    coal2 = coal2 - wind - gas - nuclear - solar2;
else
    %error
end

T = minutes(1:(24*60/block_length))*(block_length);

% Electricity = (1-(energy_mix(1)/100))*ones(1,(24*60/block_length))'; % Length of one day in 30 minute blocks
% solar = (energy_mix(4)/100)*ones(1,(24*60/block_length))';      % length of one day in 30 minute blocks
% Grid_Composition = timetable(T',Electricity,solar); %Composition names must match names given in energy sources
% Grid_Electricity = energy_source(chemical_database,'Electricity');
% Grid_Solar = energy_source(chemical_database,'Solar');
% Grid_Makeup = [Grid_Solar Grid_Electricity];

Grid_Composition = timetable(T',gas,wind,coal2,nuclear,solar2); %Composition names must match names given in energy sources
Grid_gas = energy_source(chemical_database,'gas');
Grid_wind = energy_source(chemical_database,'wind');
Grid_coal2 = energy_source(chemical_database,'coal2');
Grid_nuclear = energy_source(chemical_database,'nuclear');
Grid_solar2 = energy_source(chemical_database,'solar2');
Grid_Makeup = [Grid_gas Grid_wind Grid_coal2 Grid_nuclear Grid_solar2];
%Grid_Makeup = [Grid_gas Grid_wind Grid_nuclear Grid_solar2];
%% Define Gas Supply Composition
% Leave gas supply as a possible variable for different mixtures
Gas_Natural_Gas  = gas_source(chemical_database,'Gas_Natural_Gas',{'Natural Gas'},1);

if misc.hydrogen == "grey"
Gas_Hydrogen_Grey = gas_source(chemical_database,'Gas_Hydrogen_Grey',{'Hydrogen_Grey'},1);
Gas_Makeup = [Gas_Natural_Gas Gas_Hydrogen_Grey];
elseif misc.hydrogen == "blue"
Gas_Hydrogen_Blue = gas_source(chemical_database,'Gas_Hydrogen_Blue',{'Hydrogen_Blue'},1);
Gas_Makeup = [Gas_Natural_Gas Gas_Hydrogen_Blue];
elseif misc.hydrogen == "green"
Gas_Hydrogen_Green = gas_source(chemical_database,'Gas_Hydrogen_Green',{'Hydrogen_Green'},1);
Gas_Makeup = [Gas_Natural_Gas Gas_Hydrogen_Green];
else
    %fail
end

Gas_Ratios = [1-misc.gas_composition misc.gas_composition];
FC_data.Gas_CEnC = Gas_Makeup(1,1).CEnC*Gas_Ratios(1) + Gas_Makeup(1,2).CEnC*Gas_Ratios(2);

tic

%% Raw Milk Production - Argicultural Process

% Define Process materials - these can be single type or composites
Material.Feed_Concentrate = material(chemical_database,'Concantrate');
Material.Feed_Roughage = material(chemical_database,'Roughage');
Material.Feed_Forage = material(chemical_database,'Forage');
% Outputs
Material.Raw_Milk = material(chemical_database,'Raw_Milk',[{'Protein'},{'Fat'},{'Carbohydrate'},{'Water'}],[0.0330 0.0360 0.0470 0.8840]);
Material.Manure = material(chemical_database,'Manure',[{'Hemicellulose'},{'Cellulose'},{'Lignin'},{'Protein'},{'Ash'}],[0.210 0.250 0.130 0.120 0.09]);
Material.Calves = material(chemical_database,'Calves',[{'Fat'},{'Protein'}],[0.025 0.190]);
%Fuels
Fuel_Agriculture.Milk_Fuel = material(chemical_database,'Milk_Fuel',{'Diesel'},1);

% Set material flow rates into initial process feed_concentrate,feed_forage,feed_roughage)
Material.Feed_Concentrate = materialflowrate(Material.Feed_Concentrate,feed_concentrate);
Material.Feed_Forage = materialflowrate(Material.Feed_Forage,feed_forage);
Material.Feed_Roughage = materialflowrate(Material.Feed_Roughage,feed_roughage);

% Define Process of milk production
System_Processes.Raw_Milk = process('Milk Production','Argicultural');
System_Processes.Raw_Milk = process_work(System_Processes.Raw_Milk,Fuel_Agriculture.Milk_Fuel,40.6*product_multiplier);
System_Processes.Raw_Milk = process_inputs(System_Processes.Raw_Milk,[Material.Feed_Concentrate,Material.Feed_Forage,Material.Feed_Roughage]);
System_Processes.Raw_Milk = process_outputs(System_Processes.Raw_Milk,[Material.Calves,Material.Manure,Material.Raw_Milk],[0.0083 0.0637 0.9281]);
[System_Processes.Raw_Milk,Material.Calves,Material.Manure,Material.Raw_Milk] = process_run(System_Processes.Raw_Milk,[0,0,1],Material.Calves,Material.Manure,Material.Raw_Milk);

[Report.Milk_Production] = process_analysis(...
    System_Processes.Raw_Milk,...
    [],...
    [],...
    [1 1 1],...
    [1],...
    [1 1]);

FC_data.milk.feed = round((feed_concentrate + feed_forage + feed_roughage),3,"significant");
FC_data.milk.diesel = round(40.6*product_multiplier,3,"significant");
FC_data.milk.calves = round(Material.Calves.Mdot,3,"significant");
FC_data.milk.raw_milk = round(Material.Raw_Milk.Mdot,3,"significant");

%% Skimming Process - Industrial

% Inputs - From Previous Process
% Raw_Milk
% Outputs
Material.Skimmed_Milk = material(chemical_database,'Skimmed_Milk',[{'Protein'},{'Fat'},{'Carbohydrate'},{'Water'}],[0.034 0.001 0.049 0.916]);
Material.Skimmed_Fat = material(chemical_database,'Fat');

% Electricity /Gas Usage Objects
Electricity_Inputs.Skimmed_Milk = electricity_use(Grid_Composition,Grid_Makeup); % Define an electricity use object for the process and the contributions
GasSystem_Inputs.Skimmed_Milk = gas_use(Gas_Makeup,Gas_Ratios);

% Redefine Gas Rate of Machine
%machine_database.Milk_Skimming.GasRate = 0; % kg gas per kg of input/output mass flow (Update database to include)

% Process Definition
System_Processes.Skimmed_Milk = process('Skimmed Milk Production','Industrial');          % Define milk skimming industrial process
System_Processes.Skimmed_Milk = process_inputs(System_Processes.Skimmed_Milk,[Material.Raw_Milk]);
System_Processes.Skimmed_Milk = process_outputs(System_Processes.Skimmed_Milk,[Material.Skimmed_Milk, Material.Skimmed_Fat],[0.965 0.035]);
System_Processes.Skimmed_Milk = process_machine(System_Processes.Skimmed_Milk,machine_database.Milk_Skimming);

% Electricity cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
Electricity_Inputs.Skimmed_Milk = process_electricity_use(Electricity_Inputs.Skimmed_Milk,...
    machine_database.Milk_Skimming.EnergyConsumption,...
    Material.Raw_Milk.Mdot/machine_database.Milk_Skimming.ProcessRate,...
    timing(2));

% Gas cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
GasSystem_Inputs.Skimmed_Milk = process_gas_use(GasSystem_Inputs.Skimmed_Milk,...
    machine_database.Milk_Skimming.GasConsumption,...
    System_Processes.Skimmed_Milk.Inputs_MassFlowRate*machine_database.Milk_Skimming.GasRate);

% Run Process to calculate reporting Metrics
[System_Processes.Skimmed_Milk,Material.Skimmed_Milk,Material.Skimmed_Fat] = process_run(...
    System_Processes.Skimmed_Milk,...
    [1,0],...
    Material.Skimmed_Milk,Material.Skimmed_Fat);

% Report of process in Report Structure
[Report.Skimmed_Milk_Production] = process_analysis(...
    System_Processes.Skimmed_Milk,...
    Electricity_Inputs.Skimmed_Milk,...
    GasSystem_Inputs.Skimmed_Milk,...
    [1],...
    [1],...
    [1]);

FC_data.yogh.fat = round(Material.Skimmed_Fat.Mdot,3,"significant"); %round(0,3,"significant");
FC_data.yogh.elec1 = round(Electricity_Inputs.Skimmed_Milk.Requirement,3,"significant");
FC_data.yogh.skim_milk = round(Material.Skimmed_Milk.Mdot,3,"significant");
%% Split Milk
% Unique process in system to split the mass flow stream into two
[Material.Skimmed_Milk_1,Material.Skimmed_Milk_2] = process_splitter(Material.Skimmed_Milk,[0.6212 0.3788]);

%% Powered Milk Production

% Inputs - From Previous
% Material.Skimmed_Milk_1
% Output
Material.Powdered_Milk = material(chemical_database,'Powdered Milk',[{'Protein'},{'Fat'},{'Carbohydrate'},{'Water'}],[0.350 0.010 0.499 0.141]);
Material.Powdered_Milk_Water_Waste = material(chemical_database,'Water');

% Electricity /Gas Usage Objects
Electricity_Inputs.Powdered_Milk = electricity_use(Grid_Composition,Grid_Makeup); % Define an electricity use object for the process and the contributions
GasSystem_Inputs.Powdered_Milk = gas_use(Gas_Makeup,Gas_Ratios);

% Redefine Gas Rate of Machine
%machine_database.Milk_Powder.GasRate = 0; % kg gas per kg of input/output mass flow (Update database to include)

% Process Definition
System_Processes.Powdered_Milk = process('Powdered Milk Production','Industrial');
System_Processes.Powdered_Milk = process_inputs(System_Processes.Powdered_Milk,[Material.Skimmed_Milk_1]);
System_Processes.Powdered_Milk = process_outputs(System_Processes.Powdered_Milk,[Material.Powdered_Milk, Material.Powdered_Milk_Water_Waste],[0.098 0.902]);
System_Processes.Powdered_Milk = process_machine(System_Processes.Powdered_Milk,machine_database.Milk_Powder);

% Electricity cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
Electricity_Inputs.Powdered_Milk = process_electricity_use(Electricity_Inputs.Powdered_Milk,...
    machine_database.Milk_Powder.EnergyConsumption,...
    Material.Skimmed_Milk_1.Mdot/machine_database.Milk_Powder.ProcessRate,...
    timing(2)); % Start Time

% Gas cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
GasSystem_Inputs.Powdered_Milk = process_gas_use(GasSystem_Inputs.Powdered_Milk,...
    machine_database.Milk_Powder.GasConsumption,...
    System_Processes.Powdered_Milk.Inputs_MassFlowRate*machine_database.Milk_Powder.GasRate);

% Run Process to calculate reporting Metrics
[System_Processes.Powdered_Milk,Material.Powdered_Milk,Material.Powdered_Milk_Water_Waste] = process_run(...
    System_Processes.Powdered_Milk,...
    [1 0],...
    Material.Powdered_Milk,Material.Powdered_Milk_Water_Waste);

% Report of process in Report Structure
[Report.Powdered_Milk_Production] = process_analysis(...
    System_Processes.Powdered_Milk,...
    Electricity_Inputs.Powdered_Milk,...
    GasSystem_Inputs.Powdered_Milk,...
    [1],...
    [1],...
    [1]);

FC_data.yogh.elec2 = round(Electricity_Inputs.Powdered_Milk.Requirement,3,"significant");
FC_data.yogh.water = round(Material.Powdered_Milk_Water_Waste.Mdot,3,"significant");
FC_data.yogh.milk_pow = round(Material.Powdered_Milk.Mdot,3,"significant");

%% Milk Powder Splitter
[Material.Powdered_Milk_1,Material.Powdered_Milk_2] = process_splitter(Material.Powdered_Milk,[0.5935 0.4065]);

%% Microbial Culture Production

% Inputs
% Material.Powdered_Milk_1
% Outputs
Material.Microbes = material(chemical_database,'Microbial Culture');
Material.Microbes_Waste = material(chemical_database,'Waste Product');

% Electricity /Gas Usage Objects
Electricity_Inputs.Microbial_Culture = electricity_use(Grid_Composition,Grid_Makeup);
GasSystem_Inputs.Microbial_Culture = gas_use(Gas_Makeup,Gas_Ratios);

% Redefine Gas Rate of Machine
%machine_database.Microbial_Culture.GasRate = 0; % kg gas per kg of input/output mass flow (Update database to include)

% Process Definition
System_Processes.Microbial_Culture = process('Microbial Culture Production','Industrial');
System_Processes.Microbial_Culture = process_inputs(System_Processes.Microbial_Culture,[Material.Powdered_Milk_1]);
System_Processes.Microbial_Culture = process_outputs(System_Processes.Microbial_Culture,[Material.Microbes,Material.Microbes_Waste],[0.35 0.65]);
System_Processes.Microbial_Culture = process_machine(System_Processes.Microbial_Culture,machine_database.Microbial_Culture);

% Electricity cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
Electricity_Inputs.Microbial_Culture = process_electricity_use(Electricity_Inputs.Microbial_Culture,...
    machine_database.Microbial_Culture.EnergyConsumption,...
    Material.Powdered_Milk_1.Mdot/machine_database.Microbial_Culture.ProcessRate,...
    timing(2));

% Gas cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
GasSystem_Inputs.Microbial_Culture = process_gas_use(GasSystem_Inputs.Microbial_Culture,...
    machine_database.Milk_Skimming.GasConsumption,...
    System_Processes.Microbial_Culture.Inputs_MassFlowRate*machine_database.Microbial_Culture.GasRate);

% Run Process to calculate reporting Metrics
[System_Processes.Microbial_Culture,Material.Microbes,Material.Microbes_Waste] = process_run(...
    System_Processes.Microbial_Culture,...
    [1 0],...
    Material.Microbes,Material.Microbes_Waste);

[Report.Microbial_Culture_Production] = process_analysis(...
    System_Processes.Microbial_Culture,...
    Electricity_Inputs.Microbial_Culture,...
    GasSystem_Inputs.Microbial_Culture,...
    [1],...
    [1],...
    [1]);

FC_data.yogh.elec3 = round(Electricity_Inputs.Microbial_Culture.Requirement,3,"significant");
FC_data.yogh.microb = round(Material.Microbes.Mdot,3,"significant");


%% Yogurt Production
% Inputs
% Material.Skimmed_Milk_2
% Material.Powdered_Milk_2
% Material.Microbes Yogurt_Water
Material.Yogurt_Water = material(chemical_database,'Water');
% Outputs
Material.Yogurt_Plain_Non_Fat = material(chemical_database,'Yogurt_Plain',[{'Protein'},{'Fat'},{'Carbohydrate'},{'Water'}],[0.045 0.0015 0.0740 0.8795]);

% Input Material Stream
Material.Yogurt_Water = materialflowrate(Material.Yogurt_Water,9.6 * product_multiplier); % Review

% Electricity /Gas Usage Objects
Electricity_Inputs.Yogurt_Plain = electricity_use(Grid_Composition,Grid_Makeup);
GasSystem_Inputs.Yogurt_Plain = gas_use(Gas_Makeup,Gas_Ratios);

% Redefine Gas Rate of Machine
%machine_database.Yogurt_Machine.GasRate = 0.35; % kg gas per kg of input/output mass flow (Update database to include)

% Process Definition
System_Processes.Yogurt_Plain = process('Plain Yogurt Production','Industrial');
System_Processes.Yogurt_Plain = process_inputs(System_Processes.Yogurt_Plain,[Material.Skimmed_Milk_2 Material.Powdered_Milk_2 Material.Microbes Material.Yogurt_Water]);
System_Processes.Yogurt_Plain = process_outputs(System_Processes.Yogurt_Plain,[Material.Yogurt_Plain_Non_Fat],[1]); %#ok<*NBRAK>
System_Processes.Yogurt_Plain = process_machine(System_Processes.Yogurt_Plain,machine_database.Yogurt_Machine);

% Electricity cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
Electricity_Inputs.Yogurt_Plain = process_electricity_use(Electricity_Inputs.Yogurt_Plain,...
    machine_database.Yogurt_Machine.EnergyConsumption,...
    System_Processes.Yogurt_Plain.Inputs_MassFlowRate/machine_database.Yogurt_Machine.ProcessRate,...
    timing(2));

% Gas cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
GasSystem_Inputs.Yogurt_Plain = process_gas_use(GasSystem_Inputs.Yogurt_Plain,...
    machine_database.Yogurt_Machine.GasConsumption,...
    System_Processes.Yogurt_Plain.Inputs_MassFlowRate*machine_database.Yogurt_Machine.GasRate);

% Run Process to calculate reporting Metrics
[System_Processes.Yogurt_Plain,Material.Yogurt_Plain_Non_Fat] = process_run(...
    System_Processes.Yogurt_Plain,...
    [1],...
    Material.Yogurt_Plain_Non_Fat);

% Report of process in Report Structure
[Report.Plain_Yogurt_Production] = process_analysis(...
    System_Processes.Yogurt_Plain,...
    Electricity_Inputs.Yogurt_Plain,...
    GasSystem_Inputs.Yogurt_Plain,...
    [1 1 1 1],...
    [1],...
    [0]);

FC_data.yogh.non_fat_yo = round(Material.Yogurt_Plain_Non_Fat.Mdot,3,"significant");
FC_data.yogh.elec4 = round(Electricity_Inputs.Yogurt_Plain.Requirement,3,"significant");
FC_data.yogh.gas = round(GasSystem_Inputs.Yogurt_Plain.Requirement,3,"significant");


%% Strawberry Production Stream
%---------------------------------------------------------------------------------------------------------------------------

%% Raw Strawberry Production Agricultural

% Inputs - From Previous Process
Material.Strawberry_Fertilizer = material(chemical_database,'Fertilizer',[{'Nitrogenous'},{'Phosphorus'},{'Potassium'}],[0.18 0.55 0.27]);
Material.Strawberry_Microelements = material(chemical_database,'Microelements',[{'Fe'},{'Boron'},{'Mn'},{'Zn'}],[0.919 0.017 0.044 0.020]);
Material.Strawberry_Pesticides = material(chemical_database,'Pesticides',[{'herbicides'},{'insecticides'},{'funghicides'}],[0.3333 0.3333 0.3334]);
Material.Strawberry_Manure = material(chemical_database,'Strawberry_Manure',[{'Hemicellulose'},{'Cellulose'},{'Lignin'},{'Protein'},{'Ash'}],[0.210 0.250 0.130 0.120 0.09]);
Material.Growth_Medium = material(chemical_database,'Dummy');

% Outputs
Material.Strawberries_Raw = material(chemical_database,'Strawberries_Raw',[{'Carbohydrate'},{'Protein'},{'Fat'},{'Ash'},{'Water'}],[0.083 0.008 0.005 0.005 0.899]);

% Fuel
Fuel_Agriculture.Strawberry = material(chemical_database,'Strawberry_Fuel',{'Diesel'},[1]);

% Define Input Material FlowRates
Material.Strawberry_Fertilizer = materialflowrate(Material.Strawberry_Fertilizer,1.574402 * product_multiplier);
Material.Strawberry_Microelements = materialflowrate(Material.Strawberry_Microelements,0.023831776 * product_multiplier);
Material.Strawberry_Pesticides = materialflowrate(Material.Strawberry_Pesticides,0.020026035 * product_multiplier);
Material.Strawberry_Manure = materialflowrate(Material.Strawberry_Manure,1.05 * product_multiplier);
Strawberry_Input_flow = (Material.Strawberry_Fertilizer.Mdot + Material.Strawberry_Microelements.Mdot + Material.Strawberry_Pesticides.Mdot + Material.Strawberry_Manure.Mdot);

Raw_strawberry_initial_mdot = 31.6 * product_multiplier;
Material.Growth_Medium = materialflowrate(Material.Growth_Medium,Raw_strawberry_initial_mdot-Strawberry_Input_flow);

% Define Production process
System_Processes.Strawberries = process('Strawberries Production','Argicultural');
System_Processes.Strawberries = process_work(System_Processes.Strawberries,Fuel_Agriculture.Strawberry,5.1*product_multiplier);
System_Processes.Strawberries = process_inputs(System_Processes.Strawberries,[Material.Strawberry_Fertilizer,Material.Strawberry_Microelements,Material.Strawberry_Pesticides,Material.Strawberry_Manure,Material.Growth_Medium]);
System_Processes.Strawberries = process_outputs(System_Processes.Strawberries,[Material.Strawberries_Raw],[1]);
[System_Processes.Strawberries,Material.Strawberries_Raw] = process_run(System_Processes.Strawberries,[1],Material.Strawberries_Raw);

% Assume electricity requirement of strawberry production represented in a one day consumption block
Electricity_Inputs.Strawberries = electricity_use(Grid_Composition,Grid_Makeup);
Electricity_Inputs.Strawberries = process_electricity_use(Electricity_Inputs.Strawberries,(5.17588785/24)* product_multiplier,24,timing(5)); % Number defined directly

% Argicultural use of electricity
[Report.Raw_Strawberry_Production] = process_analysis(...
    System_Processes.Strawberries,...
    Electricity_Inputs.Strawberries,...
    [],...
    [1 1 1 1 1],...
    [0],...
    [1]);

FC_data.strawb.diesel = round(System_Processes.Strawberries.Fuel_Type.Composition_Mdot,3,"significant");
FC_data.strawb.elec1 = round(Electricity_Inputs.Strawberries.Requirement,3,"significant");
FC_data.strawb.pest = round(Material.Strawberry_Pesticides.Mdot,3,"significant");
FC_data.strawb.fert = round(Material.Strawberry_Fertilizer.Mdot,3,"significant");
FC_data.strawb.raw = round(Material.Strawberries_Raw.Mdot,3,"significant");
FC_data.strawb.micron = round(Material.Strawberry_Microelements.Mdot,3,"significant");


%% Strawberry Sorting - Industrial

% Input
% Raw Strawberries
% Outputs
Material.Strawberries_Cleaned = Material.Strawberries_Raw;
Material.Strawberries_Cleaned.Name = 'Strawberries_Cleaned';
Material.Strawberries_Waste = material(chemical_database,'Strawberry_Waste',[{'Hemicellulose'},{'Cellulose'},{'Lignin'},{'Protein'},{'Ash'}],[0.210 0.250 0.130 0.120 0.09]);

% Electricity /Gas Usage Objects
Electricity_Inputs.Strawberries_Cleaned = electricity_use(Grid_Composition,Grid_Makeup);
GasSystem_Inputs.Strawberries_Cleaned = gas_use(Gas_Makeup,Gas_Ratios);

% Redefine Gas Rate of Machine
%machine_database.Strawberry_Cleaning_Machine.GasRate = 0; % kg gas per kg of input/output mass flow (Update database to include)

% Process Definition
System_Processes.Strawberries_Cleaned = process('Strawberry Cleaning','Industrial');
System_Processes.Strawberries_Cleaned = process_inputs(System_Processes.Strawberries_Cleaned,Material.Strawberries_Raw);
System_Processes.Strawberries_Cleaned = process_outputs(System_Processes.Strawberries_Cleaned,[Material.Strawberries_Cleaned, Material.Strawberries_Waste],[0.95 0.05]);
System_Processes.Strawberries_Cleaned = process_machine(System_Processes.Strawberries_Cleaned,machine_database.Strawberry_Cleaning_Machine);

% Electricity cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
Electricity_Inputs.Strawberries_Cleaned = process_electricity_use(Electricity_Inputs.Strawberries_Cleaned,...
    machine_database.Strawberry_Cleaning_Machine.EnergyConsumption,...
    System_Processes.Strawberries_Cleaned.Inputs_MassFlowRate/machine_database.Strawberry_Cleaning_Machine.ProcessRate,...
    timing(5));

% Gas cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
GasSystem_Inputs.Strawberries_Cleaned = process_gas_use(GasSystem_Inputs.Strawberries_Cleaned,...
    machine_database.Strawberry_Cleaning_Machine.GasConsumption,...
    System_Processes.Strawberries_Cleaned.Inputs_MassFlowRate*machine_database.Strawberry_Cleaning_Machine.GasRate);

% Run Process to calculate reporting Metrics
[System_Processes.Strawberries_Cleaned,Material.Strawberries_Cleaned,Material.Strawberries_Waste] = process_run(...
    System_Processes.Strawberries_Cleaned,...
    [1 2],...
    Material.Strawberries_Cleaned,Material.Strawberries_Waste);

% Report of process in Report Structure
[Report.Strawberry_Cleaning] = process_analysis(...
    System_Processes.Strawberries_Cleaned,...
    Electricity_Inputs.Strawberries_Cleaned,...
    GasSystem_Inputs.Strawberries_Cleaned,...
    [0],...
    [1],...
    [1]);


FC_data.strawb.diesel = round(System_Processes.Strawberries.Fuel_Type.Composition_Mdot,3,"significant");
FC_data.strawb.elec2 = round(Electricity_Inputs.Strawberries_Cleaned.Requirement,3,"significant");
FC_data.strawb.cleaned = round(Material.Strawberries_Cleaned.Mdot,3,"significant");

%% Ground Strawberries Waste

% Inputs
% Material.Strawberries_Waste
% Outputs
Material.Strawberry_bag = material(chemical_database,'Strawberry_Bag',{'Polylactic acid'},1);

% Define input flow rate of bags used
Material.Strawberry_bag = materialflowrate(Material.Strawberry_bag,Material.Strawberries_Waste.Mdot*9.375e-4);

% Electricity /Gas Usage Objects
Electricity_Inputs.Strawberries_Ground = electricity_use(Grid_Composition,Grid_Makeup);
GasSystem_Inputs.Strawberries_Ground = gas_use(Gas_Makeup,Gas_Ratios);

% Redefine Gas Rate of Machine
%machine_database.Strawberry_Pulping_Machine.GasRate = 0; % kg gas per kg of input/output mass flow (Update database to include)

% Process Definition
System_Processes.Strawberries_Ground_Waste = process('Ground Strawberries Production','Industrial');
System_Processes.Strawberries_Ground_Waste = process_inputs(System_Processes.Strawberries_Ground_Waste,[Material.Strawberries_Waste,Material.Strawberry_bag]);
System_Processes.Strawberries_Ground_Waste = process_outputs(System_Processes.Strawberries_Ground_Waste,[Material.Strawberries_Waste, Material.Strawberry_bag],[0.9990712 0.000928]);
System_Processes.Strawberries_Ground_Waste = process_machine(System_Processes.Strawberries_Ground_Waste,machine_database.Strawberry_Pulping_Machine);

% calcualte the electricity cost of the process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
Electricity_Inputs.Strawberries_Ground = process_electricity_use(...
    Electricity_Inputs.Strawberries_Ground,...                              % Electricity_use object
    machine_database.Strawberry_Pulping_Machine.EnergyConsumption,...       % Energy Consumption from machine database
    System_Processes.Strawberries_Ground_Waste.Inputs_MassFlowRate/machine_database.Strawberry_Pulping_Machine.ProcessRate,... % Duration of process from machine/flow rate
    timing(5));                                                                     % Start time during day

% Gas cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
GasSystem_Inputs.Strawberries_Ground = process_gas_use(GasSystem_Inputs.Strawberries_Ground,...
    machine_database.Strawberry_Pulping_Machine.GasConsumption,...
    System_Processes.Strawberries_Ground_Waste.Inputs_MassFlowRate*machine_database.Strawberry_Pulping_Machine.GasRate);

% Run Process
[System_Processes.Strawberries_Ground_Waste,Material.Strawberries_Waste,Material.Strawberry_bag] = process_run(...
    System_Processes.Strawberries_Ground_Waste,...                          % Object definition - Process type
    [1 1],...                                                               % Binary definition of type of output (1 = main, 0 = byproduct)
    Material.Strawberries_Waste,Material.Strawberry_bag);                   % Comma seperated list of materials - update materials

% Report of process in Report Structure
[Report.Strawberry_Grinding] = process_analysis(...
    System_Processes.Strawberries_Ground_Waste,...        % Production Process
    Electricity_Inputs.Strawberries_Ground,...
    GasSystem_Inputs.Strawberries_Ground,...
    [0 1],...
    [0 0],...
    [1]);

FC_data.strawb.poly = round(Material.Strawberry_bag.Mdot,3,"significant");
FC_data.strawb.waste = round(Material.Strawberries_Waste.Mdot,3,"significant");
FC_data.strawb.elec3 = round(Electricity_Inputs.Strawberries_Ground.Requirement,3,"significant");


%% Sugar Beet Production
%--------------------------------------------------------------------------

%% Raw SugarBeet Production Agricultural

% Inputs
Material.SugarBeet_Fertilizer = material(chemical_database,'Fertilizer',[{'Nitrogenous'},{'Phosphorus'},{'Potassium'}],[0.533 0.333 0.134]);
Material.SugarBeet_Pesticides = material(chemical_database,'Pesticides',[{'herbicides'},{'insecticides'},{'funghicides'}],[0.183 0.250 0.567]);
Material.SugarBeet_Manure = material(chemical_database,'SugarBeet_Manure',[{'Hemicellulose'},{'Cellulose'},{'Lignin'},{'Protein'},{'Ash'}],[0.210 0.250 0.130 0.120 0.09]);
Material.SugarBeet_Growth_Medium = material(chemical_database,'Dummy');
% Outputs
Material.SugarBeet_Raw = material(chemical_database,'SugarBeet_Raw',{'Sugar'},1);
% Fuel
Fuel_Agriculture.SugarBeet = material(chemical_database,'SugarBeet_Fuel',{'Diesel'},[1]);

% Input flowrates
Material.SugarBeet_Fertilizer = materialflowrate(Material.SugarBeet_Fertilizer,1.043 * product_multiplier);
Material.SugarBeet_Pesticides = materialflowrate(Material.SugarBeet_Pesticides,0.0013066 * product_multiplier);
Material.SugarBeet_Manure = materialflowrate(Material.SugarBeet_Manure,19.816 * product_multiplier);

SugarBeet_Input_flow = Material.SugarBeet_Fertilizer.Mdot+Material.SugarBeet_Pesticides.Mdot+Material.SugarBeet_Manure.Mdot;
SugarBeet_Raw_initial_mdot = 139.4 * product_multiplier;
Material.SugarBeet_Growth_Medium = materialflowrate(Material.SugarBeet_Growth_Medium,SugarBeet_Raw_initial_mdot-SugarBeet_Input_flow);

% Define Electricity Grid
Electricity_Inputs.SugarBeet = electricity_use(Grid_Composition,Grid_Makeup);

% Define Process
System_Processes.SugarBeet = process('Sugar Beet Production','Argicultural');
System_Processes.SugarBeet = process_work(System_Processes.SugarBeet,Fuel_Agriculture.SugarBeet,0.309);
System_Processes.SugarBeet = process_inputs(System_Processes.SugarBeet,[...
    Material.SugarBeet_Fertilizer,Material.SugarBeet_Pesticides,Material.SugarBeet_Manure,Material.SugarBeet_Growth_Medium]);
System_Processes.SugarBeet = process_outputs(System_Processes.SugarBeet,[Material.SugarBeet_Raw],[1]);

% Assume electricity requirement of strawberry production represented in a one day consumption block
Electricity_Inputs.SugarBeet = process_electricity_use(Electricity_Inputs.SugarBeet,4.104/24,24,timing(3));

% Run Process
[System_Processes.SugarBeet,Material.SugarBeet_Raw] = process_run(...
    System_Processes.SugarBeet,...
    [1],...% 0 = By-product, 1 = Main Product, 2 = Not accounted
    Material.SugarBeet_Raw);

% Argicultural use of electricity
[Report.Raw_SugarBeet_Production] = process_analysis(...
    System_Processes.SugarBeet,...
    Electricity_Inputs.SugarBeet,...
    [],...
    [1 1 1 1],...
    [0],...
    [1]);

FC_data.sugar.pest = round(Material.SugarBeet_Pesticides.Mdot,3,"significant");
FC_data.sugar.diesel = round(System_Processes.SugarBeet.Fuel_Type.Composition_Mdot,3,"significant");
FC_data.sugar.fert = round(Material.SugarBeet_Fertilizer.Mdot,3,"significant");
FC_data.sugar.elec1 = round(Electricity_Inputs.SugarBeet.Requirement,3,"significant");
FC_data.sugar.beetraw = round(Material.SugarBeet_Raw.Mdot,3,"significant");


%% Sugar Beet Cleaning - Industrial

% Inputs
Material.SugarBeet_Cleaned = Material.SugarBeet_Raw;
Material.SugarBeet_Cleaned.Name = 'SugarBeet_Cleaned';
% Outputs
Material.SugarBeet_Waste = material(chemical_database,'SugarBeet_Waste',{'Sugar'},1);

% Electricity /Gas Usage Objects
Electricity_Inputs.SugarBeet_Cleaned = electricity_use(Grid_Composition,Grid_Makeup);
GasSystem_Inputs.SugarBeet_Cleaned = gas_use(Gas_Makeup,Gas_Ratios);

% Redefine Gas Rate of Machine
%machine_database.SugarBeet_Cleaning_Machine.GasRate = 0; % kg gas per kg of input/output mass flow (Update database to include)

% Process Definition
System_Processes.SugarBeet_Cleaned = process('SugarBeet Cleaning','Industrial');
System_Processes.SugarBeet_Cleaned = process_inputs(System_Processes.SugarBeet_Cleaned,Material.SugarBeet_Raw);
System_Processes.SugarBeet_Cleaned = process_outputs(System_Processes.SugarBeet_Cleaned,[Material.SugarBeet_Cleaned,Material.SugarBeet_Waste],[132.4/139.4 6.97/139.4]);
System_Processes.SugarBeet_Cleaned = process_machine(System_Processes.SugarBeet_Cleaned,machine_database.SugarBeet_Cleaning_Machine);

% Electricity cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
Electricity_Inputs.SugarBeet_Cleaned = process_electricity_use(Electricity_Inputs.SugarBeet_Cleaned,...
    machine_database.SugarBeet_Cleaning_Machine.EnergyConsumption,...
    System_Processes.SugarBeet_Cleaned.Inputs_MassFlowRate/machine_database.SugarBeet_Cleaning_Machine.ProcessRate,...
    timing(3));

% Gas cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
GasSystem_Inputs.SugarBeet_Cleaned = process_gas_use(GasSystem_Inputs.SugarBeet_Cleaned,...
    machine_database.SugarBeet_Cleaning_Machine.GasConsumption,...
    System_Processes.SugarBeet_Cleaned.Inputs_MassFlowRate*machine_database.SugarBeet_Cleaning_Machine.GasRate);

% Run Process to calculate reporting Metrics
[System_Processes.SugarBeet_Cleaned,Material.SugarBeet_Cleaned,Material.SugarBeet_Waste] = process_run(...
    System_Processes.SugarBeet_Cleaned,...
    [1,2],... % 0 = By-product, 1 = Main Product, 2 = Not accounted
    Material.SugarBeet_Cleaned,Material.SugarBeet_Waste);

% Report of process in Report Structure
[Report.SugarBeet_Cleaning] = process_analysis(...
    System_Processes.SugarBeet_Cleaned,...
    Electricity_Inputs.SugarBeet_Cleaned,...
    GasSystem_Inputs.SugarBeet_Cleaned,...
	[0],...
    [0],...
    [0]);

FC_data.sugar.elec2 = round(Electricity_Inputs.SugarBeet_Cleaned.Requirement,3,"significant");
FC_data.sugar.beetclean = round(Material.SugarBeet_Cleaned.Mdot,3,"significant");
FC_data.sugar.beetwaste = round(Material.SugarBeet_Waste.Mdot,3,"significant");


%% Sugar Beet Sorting - Industrial

% Inputs
% SugarBeet_Waste
% Outputs
Material.SugarBeet_bag = material(chemical_database,'SugarBeet_Bag',{'Polylactic acid'},1);

% Define input flow rate of bags used
Material.SugarBeet_bag = materialflowrate(Material.SugarBeet_bag,Material.SugarBeet_Waste.Mdot*8.895e-4); %8.895e-4 kg of polylactic acid per kilo of sugar beet

% Electricity /Gas Usage Objects
Electricity_Inputs.SugarBeet_Recycled = electricity_use(Grid_Composition,Grid_Makeup);
GasSystem_Inputs.SugarBeet_Recycled = gas_use(Gas_Makeup,Gas_Ratios);

% Redefine Gas Rate of Machine
%machine_database.SugarBeet_Sorting_Machine.GasRate = 0; % kg gas per kg of input/output mass flow (Update database to include)

% Process Definition
System_Processes.SugarBeet_Ground_Waste = process('Ground Strawberries Production','Industrial');
System_Processes.SugarBeet_Ground_Waste = process_inputs(System_Processes.SugarBeet_Ground_Waste,[Material.SugarBeet_Waste,Material.SugarBeet_bag]);
System_Processes.SugarBeet_Ground_Waste = process_outputs(System_Processes.SugarBeet_Ground_Waste,[Material.SugarBeet_Waste, Material.SugarBeet_bag],[0.9990712 0.000928]);
System_Processes.SugarBeet_Ground_Waste = process_machine(System_Processes.SugarBeet_Ground_Waste,machine_database.SugarBeet_Sorting_Machine);

% Electricity cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
Electricity_Inputs.SugarBeet_Recycled = process_electricity_use(...
    Electricity_Inputs.SugarBeet_Recycled,...                                       % electricity_use object
    machine_database.SugarBeet_Sorting_Machine.EnergyConsumption,...                % Energy Consumption from machine database
    System_Processes.SugarBeet_Ground_Waste.Inputs_MassFlowRate/machine_database.SugarBeet_Sorting_Machine.ProcessRate,... % Duration of process from machine/flow rate
    timing(3));                                                                             % Start time during day

% Gas cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
GasSystem_Inputs.SugarBeet_Recycled = process_gas_use(GasSystem_Inputs.SugarBeet_Recycled,...
    machine_database.SugarBeet_Sorting_Machine.GasConsumption,...
    System_Processes.SugarBeet_Ground_Waste.Inputs_MassFlowRate*machine_database.SugarBeet_Sorting_Machine.GasRate);

% Run Process to calculate reporting Metrics
[System_Processes.SugarBeet_Ground_Waste,Material.SugarBeet_Waste,Material.SugarBeet_bag] = process_run(...
    System_Processes.SugarBeet_Ground_Waste,...                     % Object definition - Process type
    [2 2],...                                                       % % 0 = By-product, 1 = Main Product, 2 = Not accounted
    Material.SugarBeet_Waste,Material.SugarBeet_bag);               % Comma seperated list of materials - update materials

% Report of process in Report Structure
[Report.SugarBeet_Recycle] = process_analysis(...
    System_Processes.SugarBeet_Ground_Waste,...                     % Production Process
    Electricity_Inputs.SugarBeet_Recycled,...                       % Electricity_use object
    GasSystem_Inputs.SugarBeet_Recycled,...
    [0 1],...
    [0 0],...
    [0]);

FC_data.sugar.elec3 = round(Electricity_Inputs.SugarBeet_Recycled.Requirement,3,"significant");
FC_data.sugar.poly = round(Material.SugarBeet_bag.Mdot,3,"significant");


%% Sugar Production - Industrial

% Inputs
% SugarBeet_Waste
% Outputs
Material.Sugar_Processed = material(chemical_database,'Sugar_Processed',{'Sugar'},1);
Material.Sugar_Processed_Water = material(chemical_database,'Sugar_Processed_Water',{'Water'},1); % Assume Water is byproduct of SugarBeet Processing

% Electricity /Gas Usage Objects
Electricity_Inputs.Sugar_Processed = electricity_use(Grid_Composition,Grid_Makeup);
GasSystem_Inputs.Sugar_Processed = gas_use(Gas_Makeup,Gas_Ratios);

% Redefine Gas Rate of Machine
%machine_database.Sugar_Machine.GasRate = 0.9/132.4; % kg gas per kg of input/output mass flow (Update database to include)

% Process Definition
System_Processes.Sugar_Processed = process('Ground Strawberries Production','Industrial');
System_Processes.Sugar_Processed = process_inputs(System_Processes.Sugar_Processed,[Material.SugarBeet_Cleaned]);
System_Processes.Sugar_Processed = process_outputs(System_Processes.Sugar_Processed,[Material.Sugar_Processed, Material.Sugar_Processed_Water],[20/132.4 (1-20/132.4)]);
System_Processes.Sugar_Processed = process_machine(System_Processes.Sugar_Processed,machine_database.Sugar_Machine);

% Electricity cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
Electricity_Inputs.Sugar_Processed = process_electricity_use(...
    Electricity_Inputs.Sugar_Processed,...                                       % electricity_use object
    machine_database.Sugar_Machine.EnergyConsumption,...       % Energy Consumption from machine database
    System_Processes.Sugar_Processed.Inputs_MassFlowRate/machine_database.Sugar_Machine.ProcessRate,... % Duration of process from machine/flow rate
    timing(4));                                                                     % Start time during day

% Gas cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
GasSystem_Inputs.Sugar_Processed = process_gas_use(GasSystem_Inputs.Sugar_Processed,...
    machine_database.Sugar_Machine.GasConsumption,...
    System_Processes.Sugar_Processed.Inputs_MassFlowRate*machine_database.Sugar_Machine.GasRate);

% Run Process to calculate reporting Metrics
[System_Processes.Sugar_Processed,Material.Sugar_Processed,Material.Sugar_Processed_Water] = process_run(...
    System_Processes.Sugar_Processed,...                      % Object definition - Process type
    [1 0],...                                           % Binary definition of type of output (1 = main, 0 = byproduct)
    Material.Sugar_Processed,Material.Sugar_Processed_Water);             % Comma seperated list of materials - update materials - match outputs

[Report.Sugar_Processed_Production] = process_analysis(...
    System_Processes.Sugar_Processed,...                      % Production Process
    Electricity_Inputs.Sugar_Processed,...
    GasSystem_Inputs.Sugar_Processed,...
    [0],...
    [0 0],...
    [1]);                      % Gas Use object

FC_data.sugar.gas = round(GasSystem_Inputs.Sugar_Processed.Requirement,3,"significant");
FC_data.sugar.elec4 = round(Electricity_Inputs.Sugar_Processed.Requirement,3,"significant");


%% Sugar Packing - Industrial

% Inputs - From Previous Process
% Sugar_Processed
% Outputs
Material.Sugar_bag = material(chemical_database,'Sugar_bag',{'Polylactic acid'},1);

% define input flow rate of bags used
Material.Sugar_bag = materialflowrate(Material.Sugar_bag,Material.Sugar_Processed.Mdot*2.5e-3);

% Define Machine
machine_database.Sugar_Packing = machine_database.Sugar_Machine; % In absense of information - assume same machine but filling back takes 1% of processing time
machine_database.Sugar_Packing.ProcessRate = machine_database.Sugar_Packing.ProcessRate*100;
machine_database.Sugar_Packing.GasRate = 0; % kg gas per kg of input/output mass flow (Update database to include)


% Electricity /Gas Usage Objects
Electricity_Inputs.Sugar_Packing = electricity_use(Grid_Composition,Grid_Makeup); % Define an electricity use object for the process and the contributions
GasSystem_Inputs.Sugar_Packing = gas_use(Gas_Makeup,Gas_Ratios);

% Process Definition
System_Processes.Sugar_Processed_Packed = process('Ground Strawberries Production','Industrial');
System_Processes.Sugar_Processed_Packed = process_inputs(System_Processes.Sugar_Processed_Packed,[Material.Sugar_Processed,Material.Sugar_bag]);
System_Processes.Sugar_Processed_Packed = process_outputs(System_Processes.Sugar_Processed_Packed,[Material.Sugar_Processed, Material.Sugar_bag],[20/20.05 0.05/20.05]);
System_Processes.Sugar_Processed_Packed = process_machine(System_Processes.Sugar_Processed_Packed,machine_database.Strawberry_Pulping_Machine);

% Electricity cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
Electricity_Inputs.Sugar_Packing = process_electricity_use(...
    Electricity_Inputs.Sugar_Packing,...                                    % electricity_use object
    machine_database.Sugar_Packing.EnergyConsumption,...       % Energy Consumption from machine database
    System_Processes.Sugar_Processed_Packed.Inputs_MassFlowRate/machine_database.Sugar_Packing.ProcessRate,... % Duration of process from machine/flow rate
    timing(4));                                                                     % Start time during day

% Gas cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
GasSystem_Inputs.Sugar_Packing = process_gas_use(GasSystem_Inputs.Sugar_Packing,...
    machine_database.Milk_Skimming.GasConsumption,...
    System_Processes.Sugar_Processed_Packed.Inputs_MassFlowRate*machine_database.Sugar_Packing.GasRate);

% Run Process to calculate reporting Metrics
[System_Processes.Sugar_Processed_Packed,Material.Sugar_Processed,Material.Sugar_bag] = process_run(...
    System_Processes.Sugar_Processed_Packed,...                    %    Object definition - Process type
    [1 2],...                                                % Binary definition of type of output (1 = main, 0 = byproduct)
    Material.Sugar_Processed,Material.Sugar_bag);                     % Comma seperated list of materials - update materials

% Report of process in Report Structure
[Report.Sugar_Packing] = process_analysis(...
    System_Processes.Sugar_Processed_Packed,...        % Production Process
    Electricity_Inputs.Sugar_Packing,...
    GasSystem_Inputs.Sugar_Packing,...
    [0 1],...
    [1 0],...
    [0]);                 % Electricity_use object

FC_data.sugar.poly2 = round(Material.Sugar_bag.Mdot,3,"significant");
FC_data.sugar.sugar = round(Material.Sugar_Processed.Mdot,3,"significant");


%% Jam Making
% -------------------------------------------------------------------------

%% Strawberry Pulping

% Inputs - From Previous Process
% Material.Strawberries_Cleaned
% Outputs
Material.Strawberries_Pulped = Material.Strawberries_Cleaned;
Material.Strawberries_Pulped.Name = 'Strawberries_Pulped';

% Electricity /Gas Usage Objects
Electricity_Inputs.Jam_Pulper = electricity_use(Grid_Composition,Grid_Makeup); % Define an electricity use object for the process and the contributions
GasSystem_Inputs.Jam_Pulper = gas_use(Gas_Makeup,Gas_Ratios);

% Redefine Gas Rate of Machine
%machine_database.Jam_Pulping_Machine.MachineChoice = 1;         %From Paper
%machine_database.Jam_Pulping_Machine.ProcessRate = 5000;        %kg/hr
%machine_database.Jam_Pulping_Machine.EnergyConsumption = 39.6;  %MJ/hr
%machine_database.Jam_Pulping_Machine.GasConsumption = 0;  %MJ/hr
%machine_database.Jam_Pulping_Machine.GasRate = 0; % kg gas per kg of input/output mass flow (Update database to include)

System_Processes.Strawberries_Pulper = process('Strawberry Pulping','Industrial');
System_Processes.Strawberries_Pulper = process_inputs(System_Processes.Strawberries_Pulper,[Material.Strawberries_Cleaned]);
System_Processes.Strawberries_Pulper = process_outputs(System_Processes.Strawberries_Pulper,[Material.Strawberries_Pulped],1);
System_Processes.Strawberries_Pulper = process_machine(System_Processes.Strawberries_Pulper,machine_database.Jam_Pulping_Machine);

% Electricity cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
Electricity_Inputs.Jam_Pulper = process_electricity_use(...
    Electricity_Inputs.Jam_Pulper,...                                    % electricity_use object
    machine_database.Jam_Pulping_Machine.EnergyConsumption,...       % Energy Consumption from machine database
    System_Processes.Strawberries_Pulper.Inputs_MassFlowRate/machine_database.Jam_Pulping_Machine.ProcessRate,... % Duration of process from machine/flow rate
    timing(6));                                                                     % Start time during day

% Gas cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
GasSystem_Inputs.Jam_Pulper = process_gas_use(GasSystem_Inputs.Jam_Pulper,...
    machine_database.Jam_Pulping_Machine.GasConsumption,...
    System_Processes.Strawberries_Pulper.Inputs_MassFlowRate*machine_database.Jam_Pulping_Machine.GasRate);

% Run Process to calculate reporting Metrics
[System_Processes.Strawberries_Pulper,Material.Strawberries_Pulped] = process_run(...
    System_Processes.Strawberries_Pulper,...                     % Object definition - Process type
    1,...                                                  % Binary definition of type of output (1 = main, 0 = byproduct)
    Material.Strawberries_Pulped);                         % Comma seperated list of materials - update materials

% Report of process in Report Structure
[Report.Strawberry_Pulping] = process_analysis(...
    System_Processes.Strawberries_Pulper,...        % Production Process
    Electricity_Inputs.Jam_Pulper,...
    GasSystem_Inputs.Jam_Pulper,...
    [1],...
    [0],...
    [1]);                 % Electricity_use object



%% Jam Blending

% Inputs - From Previous Process
% Material.Strawberries_Pulped
% Outputs
Material.Jam_Blended = material(chemical_database,'Jam_Blended',[{'Carbohydrate'},{'Protein'},{'Fat'},{'Ash'},{'Water'},{'Sugar'}],[0.083/2 0.008/2 0.005/2 0.005/2 0.899/2 0.5]);

% Electricity /Gas Usage Objects
Electricity_Inputs.Jam_Blender = electricity_use(Grid_Composition,Grid_Makeup);
GasSystem_Inputs.Jam_Blender = gas_use(Gas_Makeup,Gas_Ratios);

% Redefine Gas Rate of Machine
%machine_database.Jam_Blending_Machine.GasRate = 0; % kg gas per kg of input/output mass flow (Update database to include)

% Process Definition
System_Processes.Jam_Blender = process('Jam Ingredient Blending','Industrial');
System_Processes.Jam_Blender = process_inputs(System_Processes.Jam_Blender,[Material.Strawberries_Pulped,Material.Sugar_Processed]);
System_Processes.Jam_Blender = process_outputs(System_Processes.Jam_Blender,Material.Jam_Blended,1);
System_Processes.Jam_Blender = process_machine(System_Processes.Jam_Blender,machine_database.Jam_Blending_Machine);

% Electricity cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
Electricity_Inputs.Jam_Blender = process_electricity_use(...
    Electricity_Inputs.Jam_Blender,...                                            % electricity_use object
    machine_database.Jam_Blending_Machine.EnergyConsumption,...             % Energy Consumption from machine database
    System_Processes.Jam_Blender.Inputs_MassFlowRate/machine_database.Jam_Blending_Machine.ProcessRate,... % Duration of process from machine/flow rate
    timing(6));                                                                     % Start time during day

% Gas cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
GasSystem_Inputs.Jam_Blender = process_gas_use(GasSystem_Inputs.Jam_Blender,...
    machine_database.Jam_Blending_Machine.GasConsumption,...
    System_Processes.Jam_Blender.Inputs_MassFlowRate*machine_database.Jam_Blending_Machine.GasRate);

% Run Process to calculate reporting Metrics
[System_Processes.Jam_Blender,Material.Jam_Blended] = process_run(...
    System_Processes.Jam_Blender,...                     % Object definition - Process type
    1,...                                       % Binary definition of type of output (1 = main, 0 = byproduct)
    Material.Jam_Blended);                         % Comma seperated list of materials - update materials

% Report of process in Report Structure
[Report.Jam_Blending] = process_analysis(...
    System_Processes.Jam_Blender,...                  % Production Process
    Electricity_Inputs.Jam_Blender,...
    GasSystem_Inputs.Jam_Blender,...
    [0 1],...
    [0],...
    [0]);% Electricity_use object

%% Jam Evaporator

% Inputs - From Previous Process
% Material.Jam_Blended
% Outputs
Material.Jam_Evaporated = material(chemical_database,'Jam_Blended',[{'Carbohydrate'},{'Protein'},{'Fat'},{'Ash'},{'Water'},{'Sugar'}],[0.083/2 0.008/2 0.005/2 0.005/2 0.899/2 0.5]);
Material.Jam_Water = material(chemical_database,'Jam_Water',{'Water'},1);

% Electricity /Gas Usage Objects
Electricity_Inputs.Jam_Evaporator = electricity_use(Grid_Composition,Grid_Makeup);
GasSystem_Inputs.Jam_Evaporator = gas_use([Gas_Natural_Gas Gas_Natural_Gas],[0.5 0.5]);

% Redefine Gas Rate of Machine
%machine_database.Jam_Evaporator_Machine.GasRate = 0.051358025/50; % kg gas per kg of input/output mass flow (Update database to include)

% Process Definition
System_Processes.Jam_Evaporator = process('Jam Ingredient Blending','Industrial');
System_Processes.Jam_Evaporator = process_inputs(System_Processes.Jam_Evaporator,[Material.Jam_Blended]);
System_Processes.Jam_Evaporator = process_outputs(System_Processes.Jam_Evaporator,[Material.Jam_Evaporated,Material.Jam_Water],[4/5 1/5]);
System_Processes.Jam_Evaporator = process_machine(System_Processes.Jam_Evaporator,machine_database.Jam_Evaporator_Machine);

% Electricity cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
Electricity_Inputs.Jam_Evaporator = process_electricity_use(...
    Electricity_Inputs.Jam_Evaporator,...                                                                         % electricity_use object
    machine_database.Jam_Evaporator_Machine.EnergyConsumption,...                                           % Energy Consumption from machine database
    System_Processes.Jam_Evaporator.Inputs_MassFlowRate/machine_database.Jam_Evaporator_Machine.ProcessRate,...   % Duration of process from machine/flow rate
    timing(6));                                                                                                     % Start time during day

% Gas cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
GasSystem_Inputs.Jam_Evaporator = process_gas_use(GasSystem_Inputs.Jam_Evaporator,...
    machine_database.Jam_Evaporator_Machine.GasConsumption,...
    System_Processes.Sugar_Processed.Inputs_MassFlowRate*machine_database.Jam_Evaporator_Machine.GasRate);

% Run Process to calculate reporting Metrics
[System_Processes.Jam_Evaporator,Material.Jam_Evaporated,Material.Jam_Water] = process_run(...
    System_Processes.Jam_Evaporator,...                       % Object definition - Process type
    [1 0],...                                             % Binary definition of type of output (1 = main, 0 = byproduct)
    Material.Jam_Evaporated,Material.Jam_Water);                          % Comma seperated list of materials - update materials

% Report of process in Report Structure
[Report.Jam_Evaporation] = process_analysis(...
    System_Processes.Jam_Evaporator,...                       % Production Process
    Electricity_Inputs.Jam_Evaporator,...                     % Electricity_use object
    GasSystem_Inputs.Jam_Evaporator,...
    [0],...
    [0 0],...
    [1]);% Gas Use object );

%% Jam Filling Machine - Industrial

% Inputs - From Previous Process
% Material.Jam_Evaporated
% Outputs
Material.Jam_Packed = material(chemical_database,'Jam_Packed',[{'Carbohydrate'},{'Protein'},{'Fat'},{'Ash'},{'Water'},{'Sugar'}],[0.083/2 0.008/2 0.005/2 0.005/2 0.899/2 0.5]);
Material.Jam_Bag  = material(chemical_database,'Jam_bag',{'Polylactic acid'},1);

%Define Packing Bag Flow Rate as function of input mass
Material.Jam_Bag = materialflowrate(Material.Jam_Bag,Material.Jam_Evaporated.Mdot*2e-4);

% Electricity /Gas Usage Objects
Electricity_Inputs.Jam_Filling = electricity_use(Grid_Composition,Grid_Makeup);
GasSystem_Inputs.Jam_Filling = gas_use(Gas_Makeup,Gas_Ratios);

% Redefine Gas Rate of Machine
%machine_database.Jam_Filling_Machine.GasRate = 0.004855967/50; % kg gas per kg of input/output mass flow (Update database to include)

% Process Definition
System_Processes.Jam_Filling = process('Jam Ingredient Blending','Industrial');
System_Processes.Jam_Filling = process_inputs(System_Processes.Jam_Filling,[Material.Jam_Evaporated Material.Jam_Bag]);
System_Processes.Jam_Filling = process_outputs(System_Processes.Jam_Filling,[Material.Jam_Packed,Material.Jam_Bag],[40/40.008 0.008/40.008]);
System_Processes.Jam_Filling = process_machine(System_Processes.Jam_Filling,machine_database.Jam_Filling_Machine);

% Electricity cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
Electricity_Inputs.Jam_Filling = process_electricity_use(...
    Electricity_Inputs.Jam_Filling,...                                                                            % electricity_use object
    machine_database.Jam_Filling_Machine.EnergyConsumption,...                                              % Energy Consumption from machine database
    System_Processes.Jam_Filling.Inputs_MassFlowRate/machine_database.Jam_Filling_Machine.ProcessRate,...         % Duration of process from machine/flow rate
    timing(6));                                                                                                     % Start time during day

% Gas cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
GasSystem_Inputs.Jam_Filling = process_gas_use(...
    GasSystem_Inputs.Jam_Filling,...
    machine_database.Jam_Filling_Machine.GasConsumption,...
    System_Processes.Jam_Filling.Inputs_MassFlowRate*machine_database.Jam_Filling_Machine.GasRate);

% Run Process to calculate reporting Metrics
[System_Processes.Jam_Filling,Material.Jam_Packed,Material.Jam_Bag] = process_run(...
    System_Processes.Jam_Filling,...                         % Object definition - Process type
    [1 0],...                                          % Binary definition of type of output (1 = main, 0 = byproduct)
    Material.Jam_Packed,Material.Jam_Bag);                               % Comma seperated list of materials - update materials

% Report of process in Report Structure
[Report.Jam_Filling] = process_analysis(...
    System_Processes.Jam_Filling,...              % Production Process
    Electricity_Inputs.Jam_Filling,...            % Electricity_use object
    GasSystem_Inputs.Jam_Filling,...
    [0 1],...
    [1 1],...
    [1]);% Gas Use object );

FC_data.jam.poly = round(Material.Jam_Bag.Mdot,3,"significant");
FC_data.jam.gas = round(GasSystem_Inputs.Jam_Pulper.Requirement...
                       +GasSystem_Inputs.Jam_Blender.Requirement...
                       +GasSystem_Inputs.Jam_Evaporator.Requirement...
                       +GasSystem_Inputs.Jam_Filling.Requirement...
                        ,3,"significant");
FC_data.jam.elec = round(Electricity_Inputs.Jam_Pulper.Requirement...
                       +Electricity_Inputs.Jam_Blender.Requirement...
                       +Electricity_Inputs.Jam_Evaporator.Requirement...
                       +Electricity_Inputs.Jam_Filling.Requirement...
                        ,3,"significant");
FC_data.jam.sugar = round(Material.Sugar_Processed.Mdot,3,"significant");
FC_data.jam.strawbs = round(Material.Strawberries_Cleaned.Mdot,3,"significant");
FC_data.jam.jam = round(Material.Jam_Packed.Mdot,3,"significant");

%% Yogurt Making - Ingedient Mixing

% Inputs - From Previous Process
% Material.Jam_Packed
% Material.Yogurt_Plain_Non_Fat
% Outputs
A = [0.083 0.008 0.005 0.005 0.899]*(20/1000);
B = [1]*(20/1000);
C = [0.045 0.0015 0.0740 0.8795]*(960/1000);

D = [A,B,C];

Material.Yogurt_Flavoured = material(chemical_database,'Yogurt_Flavoured',...        %
    [{'Carbohydrate'},{'Protein'},{'Fat'},{'Ash'},{'Water'},...             % Strawberries 20kg
    {'Sugar'},...                                                           % Sugar        20kg
    {'Protein'},{'Fat'},{'Carbohydrate'},{'Water'}],...                     % Yogurt       960kg
    D);             % Mass Accounted Ratios
clear A B C D

% Define Work Inputs
Electricity_Inputs.Yogurt_Mixing = electricity_use(Grid_Composition,Grid_Makeup);
GasSystem_Inputs.Yogurt_Mixing = gas_use(Gas_Makeup,Gas_Ratios);

% Redefine Gas Rate of Machine
%machine_database.Flavour_Yogurt_Machine.GasRate = 0; % kg gas per kg of input/output mass flow (Update database to include)

% Process Definition
System_Processes.Yogurt_Mixing = process('Flavoured Yogurt Mixing','Industrial');
System_Processes.Yogurt_Mixing = process_inputs(System_Processes.Yogurt_Mixing,[Material.Jam_Packed,Material.Yogurt_Plain_Non_Fat]);
System_Processes.Yogurt_Mixing = process_outputs(System_Processes.Yogurt_Mixing,Material.Yogurt_Flavoured,1);
System_Processes.Yogurt_Mixing = process_machine(System_Processes.Yogurt_Mixing,machine_database.Flavour_Yogurt_Machine);

% Calculate Electricity Usage
Electricity_Inputs.Yogurt_Mixing = process_electricity_use(...
    Electricity_Inputs.Yogurt_Mixing,...                                                                         % electricity_use object
    machine_database.Flavour_Yogurt_Machine.EnergyConsumption,...                                           % Energy Consumption from machine database
    System_Processes.Yogurt_Mixing.Inputs_MassFlowRate/machine_database.Flavour_Yogurt_Machine.ProcessRate,...   % Duration of process from machine/flow rate
    timing(7));                                                                                                     % Start time during day

% Gas cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
GasSystem_Inputs.Yogurt_Mixing = process_gas_use(GasSystem_Inputs.Yogurt_Mixing,...
    machine_database.Flavour_Yogurt_Machine.GasConsumption,...
    System_Processes.Yogurt_Mixing.Inputs_MassFlowRate*machine_database.Flavour_Yogurt_Machine.GasRate);

% Run Process
[System_Processes.Yogurt_Mixing,Material.Yogurt_Flavoured] = process_run(...
    System_Processes.Yogurt_Mixing,...                         % Object definition - Process type
    [1],...                                              % Binary definition of type of output (1 = main, 0 = byproduct)
    Material.Yogurt_Flavoured);                                   % Comma seperated list of materials - update materials

[Report.Yogurt_Mixing] = process_analysis(...
    System_Processes.Yogurt_Mixing,...            % Production Process
    Electricity_Inputs.Yogurt_Mixing,...          % Electricity_use object
    GasSystem_Inputs.Jam_Filling,...
    [1 1],...
    [1],...
    [1]);              % Gas Use object );

FC_data.flav_yogh.flav_yogh = round(Material.Yogurt_Flavoured.Mdot,3,'significant');
FC_data.flav_yogh.flav_yogh = round(Material.Yogurt_Flavoured.Mdot,3,'significant');

%% Yogurt Packing

% Inputs - From Previous Process
% Material.Yogurt_Flavoured,
Material.Yogurt_Bag  = material(chemical_database,'Yogurt_bag',{'Polylactic acid'},1);
% Outputs
Material.Yogurt_Packed = Material.Yogurt_Flavoured; Material.Yogurt_Packed.Name = 'Yogurt Packed';

%Define Packing Bag Flow Rate as function of input mass
Material.Yogurt_Bag = materialflowrate(Material.Yogurt_Bag,Material.Yogurt_Flavoured.Mdot*(6/1000));

% Define Work Inputs
Electricity_Inputs.Yogurt_Packing = electricity_use(Grid_Composition,Grid_Makeup);
GasSystem_Inputs.Yogurt_Packing = gas_use(Gas_Makeup,Gas_Ratios);

% Redefine Gas Rate of Machine
%machine_database.Flavour_Yogurt_Packing_Machine.GasRate = 0; % kg gas per kg of input/output mass flow (Update database to include)

% Process Definition
System_Processes.Yogurt_Filling = process('Yogurt Packing','Industrial');
System_Processes.Yogurt_Filling = process_inputs(System_Processes.Yogurt_Filling,[Material.Yogurt_Flavoured,Material.Yogurt_Bag]);
System_Processes.Yogurt_Filling = process_outputs(System_Processes.Yogurt_Filling,[Material.Yogurt_Packed,Material.Yogurt_Bag],[1000/1006 6/1006]);
System_Processes.Yogurt_Filling = process_machine(System_Processes.Yogurt_Filling,machine_database.Flavour_Yogurt_Packing_Machine);

% Calculate Electricity Usage
Electricity_Inputs.Yogurt_Packing = process_electricity_use(...
    Electricity_Inputs.Yogurt_Packing,...                                                                                 % electricity_use object
    machine_database.Flavour_Yogurt_Packing_Machine.EnergyConsumption,...                                           % Energy Consumption from machine database
    System_Processes.Yogurt_Filling.Inputs_MassFlowRate/machine_database.Flavour_Yogurt_Packing_Machine.ProcessRate,...   % Duration of process from machine/flow rate
    timing(7));                                                                                                             % Start time during day

% Gas cost of Process, (Object,Consumption(MJ/hr), Duration (hrs), Start-Time))
GasSystem_Inputs.Yogurt_Packing = process_gas_use(GasSystem_Inputs.Yogurt_Packing,...
    machine_database.Flavour_Yogurt_Packing_Machine.GasConsumption,...
    System_Processes.Yogurt_Filling.Inputs_MassFlowRate*machine_database.Flavour_Yogurt_Packing_Machine.GasRate);

% Run Process to calculate reporting Metrics
[System_Processes.Yogurt_Filling,Material.Yogurt_Packed,Material.Yogurt_Bag] = process_run(...
    System_Processes.Yogurt_Filling,...                         % Object definition - Process type
    [1 2],...                                                % Binary definition of type of output (1 = main, 0 = byproduct)
    Material.Yogurt_Packed,Material.Yogurt_Bag);                               % Comma seperated list of materials - update materials

% Report of process in Report Structure
[Report.Yogurt_Packing] = process_analysis(...
    System_Processes.Yogurt_Filling,...        % Production Process
    Electricity_Inputs.Yogurt_Packing,...
    GasSystem_Inputs.Yogurt_Packing,...
    [1 1],...
    [1 1],...
    [1]);

FC_data.flav_yogh.elec = round(Electricity_Inputs.Yogurt_Mixing.Requirement...
                              +Electricity_Inputs.Yogurt_Packing.Requirement...
                              ,3,"significant");
FC_data.flav_yogh.poly = round(Material.Yogurt_Bag.Mdot,3,'significant');
%% Run Transportation Subscript


%   Transportation List 
%  ---------------------
%   Milk to Yogurt Factory
%   Strawberry to Jam Factory 
%   Sugar Beet to Sugar Factory 
%   Sugar to Jam Factory 
%   Jam to Yogurt Factory 
%   Yogurt to Distribution 
%   Distribution to Shop

%% BLANK
% Transport.X.Distance = 100;         % in km
% Transport.X.Load = 100;             % in kg
% Transport.X.Fuel = material(chemical_database,'.X.Fuel',{'Diesel'},[1]);
% 
% Transport.X.Object = transport(...
%     Transport.X.Distance,...            % End-to-end distance
%     '.X.',...                           % Transport Name 
%     'HGV',...                           % Vehicle Size (HGV,Van,Car)
%     'ICE',...                           % Vehicle Type (ICE,EV)     
%     Transport.X.Fuel);                  % Vehicle Fuel (Diesel,Petrol,LNG,Hydrogen)
% 
% Transport.X.Object = transport_run(...
%     Transport.X.Object,...              % Transport Object
%     Transport.X.Load);                  % Transport Load

%% LOAD MULTIPLIER
%misc.load_multiplier added, this allows to simulate larger processes
%without distrubing the mdot rates of the actual CExC/CEnC/CO2 process
%calculations

%% Milk to Yogurt Factory 

%Transport.Milk_to_Factory.Distance = 100;
Transport.Milk_to_Factory.Load = Material.Skimmed_Milk.Mdot * misc.load_multiplier;     % All skimmed milk to Yogurt Factory (Powder and Culture made at Factory)
Transport.Milk_to_Factory.Fuel = material(chemical_database,'Milk_to_Factory',{Transport.Milk_to_Factory.Object.Fuel_Type_Name},[1]);


Transport.Milk_to_Factory.Object = transport(...
    Transport.Milk_to_Factory.Distance,...          % End-to-end distance
    'Milk_to_Factory',...                           % Transport Name 
    Transport.Milk_to_Factory.Object.Vehicle_Size,...            % Vehicle Size (HGV,Van,Car)
    Transport.Milk_to_Factory.Object.Vehicle_Type,...            % Vehicle Type (ICE,EV)     
    Transport.Milk_to_Factory.Fuel);                % Vehicle Fuel (Diesel,Petrol,LNG,Hydrogen)

Transport.Milk_to_Factory.Object.EV_charge_grid = electricity_use(Grid_Composition,Grid_Makeup);

Transport.Milk_to_Factory.Object = transport_run(...
    Transport.Milk_to_Factory.Object,...            % Transport Object
    Transport.Milk_to_Factory.Load);                % Transport Load


%%   Strawberry to Jam Factory 
Transport.Strawberry_to_JamFactory.Load = Material.Strawberries_Cleaned.Mdot * misc.load_multiplier;             % in kg
Transport.Strawberry_to_JamFactory.Fuel = material(chemical_database,'Strawberry_to_JamFactory',{Transport.Strawberry_to_JamFactory.Object.Fuel_Type_Name},[1]);

Transport.Strawberry_to_JamFactory.Object = transport(...
    Transport.Strawberry_to_JamFactory.Distance,...            % End-to-end distance
    'Strawberry_to_JamFactory',...                           % Transport Name 
    Transport.Strawberry_to_JamFactory.Object.Vehicle_Size,...                           % Vehicle Size (HGV,Van,Car)
    Transport.Strawberry_to_JamFactory.Object.Vehicle_Type,...                           % Vehicle Type (ICE,EV)     
    Transport.Strawberry_to_JamFactory.Fuel);                  % Vehicle Fuel (Diesel,Petrol,LNG,Hydrogen)

Transport.Strawberry_to_JamFactory.Object.EV_charge_grid = electricity_use(Grid_Composition,Grid_Makeup);

Transport.Strawberry_to_JamFactory.Object = transport_run(...
    Transport.Strawberry_to_JamFactory.Object,...              % Transport Object
    Transport.Strawberry_to_JamFactory.Load);                  % Transport Load



%%   Sugar Beet to Sugar Factory 
%Transport.SugarBeet_to_SugarFactory.Distance = 100;         % in km
Transport.SugarBeet_to_SugarFactory.Load = Material.SugarBeet_Raw.Mdot * misc.load_multiplier;             % in kg
Transport.SugarBeet_to_SugarFactory.Fuel = material(chemical_database,'SugarBeet_to_SugarFactory',{Transport.SugarBeet_to_SugarFactory.Object.Fuel_Type_Name},[1]);

Transport.SugarBeet_to_SugarFactory.Object = transport(...
    Transport.SugarBeet_to_SugarFactory.Distance,...            % End-to-end distance
    'SugarBeet_to_SugarFactory',...                           % Transport Name 
    Transport.SugarBeet_to_SugarFactory.Object.Vehicle_Size,...                           % Vehicle Size (HGV,Van,Car)
    Transport.SugarBeet_to_SugarFactory.Object.Vehicle_Type,...                           % Vehicle Type (ICE,EV)     
    Transport.SugarBeet_to_SugarFactory.Fuel);                  % Vehicle Fuel (Diesel,Petrol,LNG,Hydrogen)

Transport.SugarBeet_to_SugarFactory.Object.EV_charge_grid = electricity_use(Grid_Composition,Grid_Makeup);

Transport.SugarBeet_to_SugarFactory.Object = transport_run(...
    Transport.SugarBeet_to_SugarFactory.Object,...              % Transport Object
    Transport.SugarBeet_to_SugarFactory.Load);                  % Transport Load
%%   Sugar to Jam Factory 
%Transport.Sugar_to_JamFactory.Distance = 100;         % in km
Transport.Sugar_to_JamFactory.Load = Material.Sugar_Processed.Mdot * misc.load_multiplier + Material.Sugar_bag.Mdot * misc.load_multiplier;             % in kg
Transport.Sugar_to_JamFactory.Fuel = material(chemical_database,'Sugar_to_JamFactory',{Transport.Sugar_to_JamFactory.Object.Fuel_Type_Name},[1]);

Transport.Sugar_to_JamFactory.Object = transport(...
    Transport.Sugar_to_JamFactory.Distance,...            % End-to-end distance
    'Sugar_to_JamFactory',...                           % Transport Name 
    Transport.Sugar_to_JamFactory.Object.Vehicle_Size,...                           % Vehicle Size (HGV,Van,Car)
    Transport.Sugar_to_JamFactory.Object.Vehicle_Type,...                           % Vehicle Type (ICE,EV)  
    Transport.Sugar_to_JamFactory.Fuel);                  % Vehicle Fuel (Diesel,Petrol,LNG,Hydrogen)

Transport.Sugar_to_JamFactory.Object.EV_charge_grid = electricity_use(Grid_Composition,Grid_Makeup);

Transport.Sugar_to_JamFactory.Object = transport_run(...
    Transport.Sugar_to_JamFactory.Object,...              % Transport Object
    Transport.Sugar_to_JamFactory.Load);                  % Transport Load
%%   Jam to Yogurt Factory 
%Transport.Jam_to_YogurtFactory.Distance = 100;         % in km
Transport.Jam_to_YogurtFactory.Load = Material.Jam_Packed.Mdot * misc.load_multiplier;             % in kg
Transport.Jam_to_YogurtFactory.Fuel = material(chemical_database,'Jam_to_YogurtFactory',{Transport.Sugar_to_JamFactory.Object.Fuel_Type_Name},[1]);

Transport.Jam_to_YogurtFactory.Object = transport(...
    Transport.Jam_to_YogurtFactory.Distance,...            % End-to-end distance
    'Jam_to_YogurtFactory',...                           % Transport Name 
    Transport.Jam_to_YogurtFactory.Object.Vehicle_Size,...                           % Vehicle Size (HGV,Van,Car)
    Transport.Jam_to_YogurtFactory.Object.Vehicle_Type,...                           % Vehicle Type (ICE,EV)     
    Transport.Jam_to_YogurtFactory.Fuel);                  % Vehicle Fuel (Diesel,Petrol,LNG,Hydrogen)

Transport.Jam_to_YogurtFactory.Object.EV_charge_grid = electricity_use(Grid_Composition,Grid_Makeup);

Transport.Jam_to_YogurtFactory.Object = transport_run(...
    Transport.Jam_to_YogurtFactory.Object,...              % Transport Object
    Transport.Jam_to_YogurtFactory.Load);                  % Transport Load
%%   Yogurt to Distribution 
%Transport.Yogurt_to_Distribution.Distance = 100;                                                                    % in km
Transport.Yogurt_to_Distribution.Load = Material.Yogurt_Packed.Mdot * misc.load_multiplier + Material.Yogurt_Bag.Mdot * misc.load_multiplier;                     % in kg
Transport.Yogurt_to_Distribution.Fuel = material(chemical_database,'Yogurt_to_Distribution',{Transport.Yogurt_to_Distribution.Object.Fuel_Type_Name},[1]);

Transport.Yogurt_to_Distribution.Object = transport(...
    Transport.Yogurt_to_Distribution.Distance,...            % End-to-end distance
    'Yogurt_to_Distribution',...                           % Transport Name 
    Transport.Yogurt_to_Distribution.Object.Vehicle_Size,...                           % Vehicle Size (HGV,Van,Car)
    Transport.Yogurt_to_Distribution.Object.Vehicle_Type,...                           % Vehicle Type (ICE,EV)   
    Transport.Yogurt_to_Distribution.Fuel);                  % Vehicle Fuel (Diesel,Petrol,LNG,Hydrogen)

Transport.Yogurt_to_Distribution.Object.EV_charge_grid = electricity_use(Grid_Composition,Grid_Makeup);

Transport.Yogurt_to_Distribution.Object = transport_run(...
    Transport.Yogurt_to_Distribution.Object,...              % Transport Object
    Transport.Yogurt_to_Distribution.Load);                  % Transport Load
%%   Distribution to Shop
%Transport.Distribution_to_Shop.Distance = 100;         % in km
Transport.Distribution_to_Shop.Load = Material.Yogurt_Packed.Mdot * misc.load_multiplier + Material.Yogurt_Bag.Mdot * misc.load_multiplier;             % in kg
Transport.Distribution_to_Shop.Fuel = material(chemical_database,'Distribution_to_Shop',{Transport.Yogurt_to_Distribution.Object.Fuel_Type_Name},[1]);

Transport.Distribution_to_Shop.Object = transport(...
    Transport.Distribution_to_Shop.Distance,...            % End-to-end distance
    'Distribution_to_Shop',...                           % Transport Name 
    Transport.Distribution_to_Shop.Object.Vehicle_Size,...                           % Vehicle Size (HGV,Van,Car)
    Transport.Distribution_to_Shop.Object.Vehicle_Type,...                           % Vehicle Type (ICE,EV)  
    Transport.Distribution_to_Shop.Fuel);                  % Vehicle Fuel (Diesel,Petrol,LNG,Hydrogen)

Transport.Distribution_to_Shop.Object.EV_charge_grid = electricity_use(Grid_Composition,Grid_Makeup);

Transport.Distribution_to_Shop.Object = transport_run(...
    Transport.Distribution_to_Shop.Object,...              % Transport Object
    Transport.Distribution_to_Shop.Load);                  % Transport Load

toc

%% Results Inspection

fields = fieldnames(Report);
fields2 = {'Input','Main','Byproduct','Work'};
fields3 = {'CEnC','CExC','CO2'};
for i = 1 : (numel(fields))
    for j = 1 : numel(fields2)
        for k = 1 : numel(fields3)
            if isempty(Report.(fields{i}).(fields2{j}).(fields3{k}))
            %app.report.(fields{i}).(fields2{j}).(fields3{k}) = 0;
            else
            Report.(fields{i}).(fields2{j}).(fields3{k}) = abs(Report.(fields{i}).(fields2{j}).(fields3{k}));
            end
        end
    end
end

Ex_Row_Names = {...
    'Raw Milk Production';...
    'Milk Skimming ';...
    'Milk Powder Production';...
    'Culture Growing';...
    'Plain Yoghurt Making';...
    'Raw Strawberry Growing';...
    'Strawberry Cleaning';...
    'Strawberry Grinding';...
    '--Strawberry Production--';...
    'Raw Sugar Beet Growing';...
    'Sugar Beet Cleaning';...
    'Sugar Beet Recycling';...
    'Sugar Refining';...
    'Sugar_Packing';...
    '--Sugar Production--';...
    'Strawberry Pulping';...
    'Jam Blending';...
    'Jam Reducing';...
    'Jam Packing';...
    '--Jam Production--';...
    'Flavoured Yoghurt Mixing';...
    'Flavoured Yoghurt Packing'};

Ex_MDot = [...
    Report.Milk_Production.Main.Mdot;...
    Report.Skimmed_Milk_Production.Main.Mdot;...
    Report.Powdered_Milk_Production.Main.Mdot;...
    Report.Microbial_Culture_Production.Main.Mdot;...
    Report.Plain_Yogurt_Production.Main.Mdot;...
    Report.Raw_Strawberry_Production.Main.Mdot;...
    Report.Strawberry_Cleaning.Main.Mdot;...
    Report.Strawberry_Grinding.Main.Mdot;...
    Report.Raw_Strawberry_Production.Main.Mdot+Report.Strawberry_Cleaning.Main.Mdot+Report.Strawberry_Grinding.Main.Mdot;...
    Report.Raw_SugarBeet_Production.Main.Mdot;...
    Report.SugarBeet_Cleaning.Main.Mdot;...
    Report.SugarBeet_Recycle.Main.Mdot;...
    Report.Sugar_Processed_Production.Main.Mdot;...
    Report.Sugar_Packing.Main.Mdot;...
    
    Report.Raw_SugarBeet_Production.Main.Mdot+Report.SugarBeet_Cleaning.Main.Mdot+Report.SugarBeet_Recycle.Main.Mdot+Report.Sugar_Processed_Production.Main.Mdot+Report.Sugar_Packing.Main.Mdot;...
    
    Report.Strawberry_Pulping.Main.Mdot;...
    Report.Jam_Blending.Main.Mdot;...
    Report.Jam_Evaporation.Main.Mdot;...
    Report.Jam_Filling.Main.Mdot;...
    
    Report.Strawberry_Pulping.Main.Mdot+Report.Jam_Blending.Main.Mdot+Report.Jam_Evaporation.Main.Mdot+Report.Jam_Filling.Main.Mdot;...
    
    Report.Yogurt_Mixing.Main.Mdot;...
    Report.Yogurt_Packing.Main.Mdot];

%Ex_MDot(end+1) = sum(Ex_MDot);

Ex_Input = [...
    Report.Milk_Production.Input.CExC;...
    Report.Skimmed_Milk_Production.Input.CExC;...
    Report.Powdered_Milk_Production.Input.CExC;...
    Report.Microbial_Culture_Production.Input.CExC;...
    Report.Plain_Yogurt_Production.Input.CExC;...
    Report.Raw_Strawberry_Production.Input.CExC;...
    Report.Strawberry_Cleaning.Input.CExC;...
    Report.Strawberry_Grinding.Input.CExC;...
    Report.Raw_Strawberry_Production.Input.CExC+Report.Strawberry_Cleaning.Input.CExC+Report.Strawberry_Grinding.Input.CExC;...
    Report.Raw_SugarBeet_Production.Input.CExC;...
    Report.SugarBeet_Cleaning.Input.CExC;...
    Report.SugarBeet_Recycle.Input.CExC;...
    Report.Sugar_Processed_Production.Input.CExC;...
    Report.Sugar_Packing.Input.CExC;...
    Report.Raw_SugarBeet_Production.Input.CExC+Report.SugarBeet_Cleaning.Input.CExC+Report.SugarBeet_Recycle.Input.CExC+Report.Sugar_Processed_Production.Input.CExC+Report.Sugar_Packing.Input.CExC;...
    
    Report.Strawberry_Pulping.Input.CExC;...
    Report.Jam_Blending.Input.CExC;...
    Report.Jam_Evaporation.Input.CExC;...
    Report.Jam_Filling.Input.CExC;...
    Report.Strawberry_Pulping.Input.CExC+Report.Jam_Blending.Input.CExC+Report.Jam_Evaporation.Input.CExC+Report.Jam_Filling.Input.CExC;...
    
    Report.Yogurt_Mixing.Input.CExC;...
    Report.Yogurt_Packing.Input.CExC];

%Ex_Input(end+1) = sum(Ex_Input);

Ex_Work = [...
    Report.Milk_Production.Work.CExC;...
    Report.Skimmed_Milk_Production.Work.CExC;...
    Report.Powdered_Milk_Production.Work.CExC;...
    Report.Microbial_Culture_Production.Work.CExC;...
    Report.Plain_Yogurt_Production.Work.CExC;...
    Report.Raw_Strawberry_Production.Work.CExC;...
    Report.Strawberry_Cleaning.Work.CExC;...
    Report.Strawberry_Grinding.Work.CExC;...
    Report.Raw_Strawberry_Production.Work.CExC+Report.Strawberry_Cleaning.Work.CExC+Report.Strawberry_Grinding.Work.CExC;...
    Report.Raw_SugarBeet_Production.Work.CExC;...
    Report.SugarBeet_Cleaning.Work.CExC;...
    Report.SugarBeet_Recycle.Work.CExC;...
    Report.Sugar_Processed_Production.Work.CExC;...
    Report.Sugar_Packing.Work.CExC;...
    Report.Raw_SugarBeet_Production.Work.CExC+Report.SugarBeet_Cleaning.Work.CExC+Report.SugarBeet_Recycle.Work.CExC+Report.Sugar_Processed_Production.Work.CExC+Report.Sugar_Packing.Work.CExC;...
    
    Report.Strawberry_Pulping.Work.CExC;...
    Report.Jam_Blending.Work.CExC;...
    Report.Jam_Evaporation.Work.CExC;...
    Report.Jam_Filling.Work.CExC;...
    Report.Strawberry_Pulping.Work.CExC+Report.Jam_Blending.Work.CExC+Report.Jam_Evaporation.Work.CExC+Report.Jam_Filling.Work.CExC;...
    
    Report.Yogurt_Mixing.Work.CExC;...
    Report.Yogurt_Packing.Work.CExC];

%Ex_Work(end+1) = sum(Ex_Work);

Ex_ByProduct = [...
    Report.Milk_Production.Byproduct.CExC;...
    Report.Skimmed_Milk_Production.Byproduct.CExC;...
    Report.Powdered_Milk_Production.Byproduct.CExC;...
    Report.Microbial_Culture_Production.Byproduct.CExC;...
    Report.Plain_Yogurt_Production.Byproduct.CExC;...
    Report.Raw_Strawberry_Production.Byproduct.CExC;...
    Report.Strawberry_Cleaning.Byproduct.CExC;...
    Report.Strawberry_Grinding.Byproduct.CExC;...
    Report.Raw_Strawberry_Production.Byproduct.CExC+Report.Strawberry_Cleaning.Byproduct.CExC+Report.Strawberry_Grinding.Byproduct.CExC;...
    Report.Raw_SugarBeet_Production.Byproduct.CExC;...
    Report.SugarBeet_Cleaning.Byproduct.CExC;...
    Report.SugarBeet_Recycle.Byproduct.CExC;...
    Report.Sugar_Processed_Production.Byproduct.CExC;...
    Report.Sugar_Packing.Byproduct.CExC;...
    Report.Raw_SugarBeet_Production.Byproduct.CExC+Report.SugarBeet_Cleaning.Byproduct.CExC+Report.SugarBeet_Recycle.Byproduct.CExC+Report.Sugar_Processed_Production.Byproduct.CExC+Report.Sugar_Packing.Byproduct.CExC;...
    
    Report.Strawberry_Pulping.Byproduct.CExC;...
    Report.Jam_Blending.Byproduct.CExC;...
    Report.Jam_Evaporation.Byproduct.CExC;...
    Report.Jam_Filling.Byproduct.CExC;...
    Report.Strawberry_Pulping.Byproduct.CExC+Report.Jam_Blending.Byproduct.CExC+Report.Jam_Evaporation.Byproduct.CExC+Report.Jam_Filling.Byproduct.CExC;...
    
    Report.Yogurt_Mixing.Byproduct.CExC;...
    Report.Yogurt_Packing.Byproduct.CExC];

%Ex_ByProduct(end+1) = sum(Ex_ByProduct);

Ex_Main = [...
    Report.Milk_Production.Main.CExC;...
    Report.Skimmed_Milk_Production.Main.CExC;...
    Report.Powdered_Milk_Production.Main.CExC;...
    Report.Microbial_Culture_Production.Main.CExC;...
    Report.Plain_Yogurt_Production.Main.CExC;...
    Report.Raw_Strawberry_Production.Main.CExC;...
    Report.Strawberry_Cleaning.Main.CExC;...
    Report.Strawberry_Grinding.Main.CExC;...
    Report.Raw_Strawberry_Production.Main.CExC+Report.Strawberry_Cleaning.Main.CExC+Report.Strawberry_Grinding.Main.CExC;...
    Report.Raw_SugarBeet_Production.Main.CExC;...
    Report.SugarBeet_Cleaning.Main.CExC;...
    Report.SugarBeet_Recycle.Main.CExC;...
    Report.Sugar_Processed_Production.Main.CExC;...
    Report.Sugar_Packing.Main.CExC;...
    Report.Raw_SugarBeet_Production.Main.CExC+Report.SugarBeet_Cleaning.Main.CExC+Report.SugarBeet_Recycle.Main.CExC+Report.Sugar_Processed_Production.Main.CExC+Report.Sugar_Packing.Main.CExC;...
    
    Report.Strawberry_Pulping.Main.CExC;...
    Report.Jam_Blending.Main.CExC;...
    Report.Jam_Evaporation.Main.CExC;...
    Report.Jam_Filling.Main.CExC;...
    Report.Strawberry_Pulping.Main.CExC+Report.Jam_Blending.Main.CExC+Report.Jam_Evaporation.Main.CExC+Report.Jam_Filling.Main.CExC;...
    
    Report.Yogurt_Mixing.Main.CExC;...
    Report.Yogurt_Packing.Main.CExC];

Total_ExLost = (Ex_Input+Ex_Work)-Ex_ByProduct-Ex_Main;

%Ex_Main(end+1) = sum(Ex_Main);

Ex_Com = categorical({...
    'YES';...
    'YES';...
    'YES';...
    'YES';...
    'YES';...
    'YES';...
    'YES';...
    'YES';...
    '--';...
    'YES';...
    'YES';...
    'YES';...
    'YES';...
    'YES';...
    '--';...
    'YES';...
    'YES';...
    'YES';...
    'YES';...
    '--';...
    'YES';...
    'YES';...
    });


Results = table(Ex_MDot,Ex_Input,Ex_Work,Ex_ByProduct,Ex_Main,Total_ExLost,Ex_Com,'RowNames',Ex_Row_Names);

Results.Properties.VariableNames = {'Mdot';'Input Exergy (MJ)';'Work Exergy (MJ)';'By-Product Exergy (MJ)';'Main Exergy (MJ)';'Total_Exergy Lost (MJ)';'Checked'};

%Results
output_report = Report;
output_machine_database = machine_database;

%% Process timing results
%assumed to be serial not paralell processes...
%yoghurt making 2
process_timing_results = [...
timing(2)*60 System_Processes.Skimmed_Milk.Machine_ProcessTime; ...
timing(2)*60 System_Processes.Powdered_Milk.Machine_ProcessTime; ...
timing(2)*60 System_Processes.Microbial_Culture.Machine_ProcessTime; ...
timing(2)*60 System_Processes.Yogurt_Plain.Machine_ProcessTime ...

%raw sugar beet 3
timing(3)*60 System_Processes.SugarBeet_Cleaned.Machine_ProcessTime; ...
timing(3)*60 System_Processes.SugarBeet_Ground_Waste.Machine_ProcessTime;

%sugar 4
timing(4)*60 System_Processes.Sugar_Processed.Machine_ProcessTime; ...
timing(4)*60 System_Processes.Sugar_Processed_Packed.Machine_ProcessTime; ...

%strawbs 5
timing(5)*60 System_Processes.Strawberries_Cleaned.Machine_ProcessTime; ...
timing(5)*60 System_Processes.Strawberries_Ground_Waste.Machine_ProcessTime; ...

%jam 6
timing(6)*60 System_Processes.Strawberries_Pulper.Machine_ProcessTime; ...
timing(6)*60 System_Processes.Jam_Blender.Machine_ProcessTime; ...
timing(6)*60 System_Processes.Jam_Evaporator.Machine_ProcessTime; ...
timing(6)*60 System_Processes.Jam_Filling.Machine_ProcessTime; ...

%flav yoghurt 7
timing(7)*60 System_Processes.Yogurt_Mixing.Machine_ProcessTime; ...
timing(7)*60 System_Processes.Yogurt_Filling.Machine_ProcessTime; ];

process_timing_results = process_timing_results /60;

%extra data required for summary, added in FC_data (flowchart data) for
%CONVENIENCE
FC_data.Electricity_Inputs = Electricity_Inputs;
FC_data.System_Processes = System_Processes;
FC_data.GasSystem_Inputs = GasSystem_Inputs;
FC_data.Gas_Makeup = Gas_Makeup;
FC_data.Transport = Transport;
%% Results Table for Transportation

% Row NAmes
% Load 
% Vehicle Type
% Vehicle Fuel 
% Distance 
% CExC
% CEnC
% CO2

Ex_Row_Names = {...
    Transport.Milk_to_Factory.Object.Journey_Name;...
    Transport.Strawberry_to_JamFactory.Object.Journey_Name;...
    Transport.SugarBeet_to_SugarFactory.Object.Journey_Name;...
    Transport.Sugar_to_JamFactory.Object.Journey_Name;...
    Transport.Jam_to_YogurtFactory.Object.Journey_Name;...
    Transport.Yogurt_to_Distribution.Object.Journey_Name;...
    Transport.Distribution_to_Shop.Object.Journey_Name...
    };


T_Load = [...
    Transport.Milk_to_Factory.Object.Vehicle_Load;...
    Transport.Strawberry_to_JamFactory.Object.Vehicle_Load;...
    Transport.SugarBeet_to_SugarFactory.Object.Vehicle_Load;...
    Transport.Sugar_to_JamFactory.Object.Vehicle_Load;...
    Transport.Jam_to_YogurtFactory.Object.Vehicle_Load;...
    Transport.Yogurt_to_Distribution.Object.Vehicle_Load;...
    Transport.Distribution_to_Shop.Object.Vehicle_Load...
    ];

T_Type = categorical({...
    Transport.Milk_to_Factory.Object.Vehicle_Size;...
    Transport.Strawberry_to_JamFactory.Object.Vehicle_Size;...
    Transport.SugarBeet_to_SugarFactory.Object.Vehicle_Size;...
    Transport.Sugar_to_JamFactory.Object.Vehicle_Size;...
    Transport.Jam_to_YogurtFactory.Object.Vehicle_Size;...
    Transport.Yogurt_to_Distribution.Object.Vehicle_Size;...
    Transport.Distribution_to_Shop.Object.Vehicle_Size...
    });

T_Fuel = categorical({...
    Transport.Milk_to_Factory.Object.Fuel_Type_Name;...
    Transport.Strawberry_to_JamFactory.Object.Fuel_Type_Name;...
    Transport.SugarBeet_to_SugarFactory.Object.Fuel_Type_Name;...
    Transport.Sugar_to_JamFactory.Object.Fuel_Type_Name;...
    Transport.Jam_to_YogurtFactory.Object.Fuel_Type_Name;...
    Transport.Yogurt_to_Distribution.Object.Fuel_Type_Name;...
    Transport.Distribution_to_Shop.Object.Fuel_Type_Name...
    });

T_Distance = [...
    Transport.Milk_to_Factory.Object.Distance;...
    Transport.Strawberry_to_JamFactory.Object.Distance;...
    Transport.SugarBeet_to_SugarFactory.Object.Distance;...
    Transport.Sugar_to_JamFactory.Object.Distance;...
    Transport.Jam_to_YogurtFactory.Object.Distance;...
    Transport.Yogurt_to_Distribution.Object.Distance;...
    Transport.Distribution_to_Shop.Object.Distance...
    ];

T_CExC = [...
    Transport.Milk_to_Factory.Object.CExC;...
    Transport.Strawberry_to_JamFactory.Object.CExC;...
    Transport.SugarBeet_to_SugarFactory.Object.CExC;...
    Transport.Sugar_to_JamFactory.Object.CExC;...
    Transport.Jam_to_YogurtFactory.Object.CExC;...
    Transport.Yogurt_to_Distribution.Object.CExC;...
    Transport.Distribution_to_Shop.Object.CExC...
    ];

T_CEnC = [...
    Transport.Milk_to_Factory.Object.CEnC;...
    Transport.Strawberry_to_JamFactory.Object.CEnC;...
    Transport.SugarBeet_to_SugarFactory.Object.CEnC;...
    Transport.Sugar_to_JamFactory.Object.CEnC;...
    Transport.Jam_to_YogurtFactory.Object.CEnC;...
    Transport.Yogurt_to_Distribution.Object.CEnC;...
    Transport.Distribution_to_Shop.Object.CEnC...
    ];

T_CO2 = [...
    Transport.Milk_to_Factory.Object.CO2;...
    Transport.Strawberry_to_JamFactory.Object.CO2;...
    Transport.SugarBeet_to_SugarFactory.Object.CO2;...
    Transport.Sugar_to_JamFactory.Object.CO2;...
    Transport.Jam_to_YogurtFactory.Object.CO2;...
    Transport.Yogurt_to_Distribution.Object.CO2;...
    Transport.Distribution_to_Shop.Object.CO2...
    ];

T_num_journeys = [...
    Transport.Milk_to_Factory.Object.Number_Journey;...
    Transport.Strawberry_to_JamFactory.Object.Number_Journey;...
    Transport.SugarBeet_to_SugarFactory.Object.Number_Journey;...
    Transport.Sugar_to_JamFactory.Object.Number_Journey;...
    Transport.Jam_to_YogurtFactory.Object.Number_Journey;...
    Transport.Yogurt_to_Distribution.Object.Number_Journey;...
    Transport.Distribution_to_Shop.Object.Number_Journey...
];


T_en_calc = [...
    Transport.Milk_to_Factory.Object.CO2;...
    Transport.Strawberry_to_JamFactory.Object.CO2;...
    Transport.SugarBeet_to_SugarFactory.Object.CO2;...
    Transport.Sugar_to_JamFactory.Object.CO2;...
    Transport.Jam_to_YogurtFactory.Object.CO2;...
    Transport.Yogurt_to_Distribution.Object.CO2;...
    Transport.Distribution_to_Shop.Object.CO2...
];

T_fuel_consumption = [...
    Transport.Milk_to_Factory.Object.Fuel_Consumption;...
    Transport.Strawberry_to_JamFactory.Object.Fuel_Consumption;...
    Transport.SugarBeet_to_SugarFactory.Object.Fuel_Consumption;...
    Transport.Sugar_to_JamFactory.Object.Fuel_Consumption;...
    Transport.Jam_to_YogurtFactory.Object.Fuel_Consumption;...
    Transport.Yogurt_to_Distribution.Object.Fuel_Consumption;...
    Transport.Distribution_to_Shop.Object.Fuel_Consumption...
];


%
Results_T = table(T_Load,T_Type,T_Fuel,T_Distance,T_CExC,T_CEnC,T_CO2,T_num_journeys,T_en_calc,T_fuel_consumption,'RowNames',Ex_Row_Names);

Results_T.Properties.VariableNames = {'Load (kg)','Size','Fuel','Distance (km)','CExC (MJ)','CEnC (MJ)','C02','Number of journeys','calculated_cenc','Fuel Consumption'};

%Results_T; 
transport_results = Results_T;

transport_totals.Load = sum(Results_T{1:3,1})+Results_T{7,1};
transport_totals.CO2 = sum(Results_T{1:3,7})+Results_T{7,7};
transport_totals.CExC = sum(Results_T{1:3,5})+Results_T{7,5};
transport_totals.CEnC = sum(Results_T{1:3,6})+Results_T{7,6};
transport_totals.consumption = sum(Results_T{1:3,10})+Results_T{7,10};
transport_totals.journeys = sum(Results_T{1:3,8})+Results_T{7,8};
transport_totals.distance = sum(Results_T{1:3,4})+Results_T{7,4};

% Load 
% Vehicle Type
% Vehicle Fuel 
% Distance 
% CExC
% CEnC
% CO2
%% Script Cleanup
clear Ex_* T_* Total_*

end