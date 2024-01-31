classdef transport
    %TRANPORT Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        CExC
        CEnC
        CO2emissions            %life cycle greenhouse gas intensity 50% payload for medium truck g CO2-eq/tonne km
                            %estimated from IPCC AR6 WGIII Chapter 10
                            %medium duty truck
        CO2
        Journey_Name
        Fuel_Type           % Input Definition
        Fuel_Type_Name      % Character string of Fuel name 
        Distance            % Input Parameter
        Fuel_Consumption    % Determined by Vehicle Size and Fuel Type
        Battery_Consumption % Determined by Vehicle Size (MJ/km)
        Battery_Capacity    % Determined by Vehicle Type (MJ)
        Battery_ChargeTime  % Determined by Vehicle Type
        Vehicle_Type
        Vehicle_Size
        Vehicle_Capacity    % Determined by Vehicle Size
        Number_Journey      % How many trips depending on capacity of vehicle and load
        Fuel_CEnC
        Fuel_CExC
        Fuel_Used
        Vehicle_Load
        EV_charge_grid
    end
    
    methods
        function obj = transport(inputArg1,inputArg2,inputArg3,inputArg4,inputArg5)
            %TRANPORT Construct an instance of this class
            %   Detailed explanation goes here
            obj.CO2 = 'UDPATE';
            obj.Distance =      inputArg1;
            obj.Journey_Name =  inputArg2;
            obj.Fuel_Type_Name = 'Diesel';
            obj.Vehicle_Size =  inputArg3;
            % Enforce vehicle Size - HGV by default
            if strcmpi(obj.Vehicle_Size,'HGV')==0 && strcmpi(obj.Vehicle_Size,'Van')==0 && strcmpi(obj.Vehicle_Size,'Car')==0
                obj.Vehicle_Size = 'HGV';
            end
            
            % Define Capacity of vehicle based on type (Generic
            % Approximations for battery vehicles)
            % Cite: https://ev-database.org/uk/cheatsheet/
            switch obj.Vehicle_Size
                case 'HGV'
                    obj.Vehicle_Capacity = 20000;
                    obj.Battery_Consumption = (3*3.6); %Estimated based on 3kWh/km (1kWh = 3.6MJ)
                    obj.Battery_Capacity = 200*3.6; % 200kWh*3.6 MJ/kWh
                    obj.Battery_ChargeTime = obj.Battery_Capacity/(20*3.6);
                case 'Van'
                    obj.Vehicle_Capacity = 2000;
                    obj.Battery_Consumption = 0.421*0.62*3.6; %421 Wh/mile (Vauxhall Vivaro-e Life L 50kWh)  = 0.41 KWh/mile = 0.41*0.62 (kWh/km) * 3.6 = (MJ/km)
                    obj.Battery_Capacity = 100*3.6; % 100kWh*3.6 MJ/kWh
                    obj.Battery_ChargeTime = obj.Battery_Capacity/(20*3.6);
                case 'Car'
                    obj.Vehicle_Capacity = 200;
                    obj.Battery_Consumption = 0.230*0.62*3.6; % Tesla Model 3
                    obj.Battery_Capacity = 50*3.6; % 50kWh*3.6 MJ/kWh
                    obj.Battery_ChargeTime = obj.Battery_Capacity/(20*3.6);
                otherwise
                    warning('No Vehicle capacity defined')
            end
            
            obj.Vehicle_Type =  inputArg4;
            % Enforce type of vehicle - ICE by default
            if strcmpi(obj.Vehicle_Type,'ICE')==0 && strcmpi(obj.Vehicle_Type,'EV')==0
                obj.Vehicle_Type = 'ICE';
            end
            
            if strcmpi(obj.Vehicle_Type,'ICE')
                obj.Fuel_Type = inputArg5;
                obj.Fuel_CEnC = obj.Fuel_Type(1).Composition_Energy;
                obj.Fuel_CExC = obj.Fuel_Type.Composition_Exergy;
                obj.Battery_Consumption = [];
                obj.Battery_Capacity = [];
                obj.Battery_ChargeTime = [];
                switch obj.Fuel_Type.Composition_Raw{1}
                    case 'Diesel'
                        obj.Fuel_Type_Name = 'Diesel';
                        obj.CO2emissions = 320;
                        Fuel_Density = 0.85; %(kg/L)
                        switch obj.Vehicle_Size
                            case 'HGV'
                                obj.Fuel_Consumption = (30.4/100)*Fuel_Density;  % kg/km 30.4 L/km HGV test poland (google)
                            case 'Van'
                                obj.Fuel_Consumption = (10/100)*Fuel_Density;
                            case 'Car'
                                obj.Fuel_Consumption = (7.7/100)*Fuel_Density;  %L/100km 7 = 7/100 (L/km)*(kg/L) 7.7 = Averge of UK cars (not detailed) 
                        end
                    case 'Petrol'
                        obj.CO2emissions = 340;
                        obj.Fuel_Type_Name = 'Petrol';
                        Fuel_Density = 0.8; %(kg/L)
                        switch obj.Vehicle_Size
                            
                            case 'HGV'
                                obj.Fuel_Consumption = (5*7.7/100)*Fuel_Density;
                            case 'Van'
                                obj.Fuel_Consumption = (10/100)*Fuel_Density;
                            case 'Car'
                                obj.Fuel_Consumption = (7.7/100)*Fuel_Density;  %L/100km 7 = 7/100 (L/km)*(kg/L) 7.7 = Averge of UK cars (not detailed) 
                        end
                    case 'LNG'
                        obj.Fuel_Type_Name = 'LNG';
                        obj.CO2emissions = 210;
                        Fuel_Density = 0.48; %(kg/L)
                        switch obj.Vehicle_Size
                            case 'HGV'
                                obj.Fuel_Consumption = (24.9/100); % Google search LNG fuel consumption - 
                            case 'Van'
                                obj.Fuel_Consumption = 10/100; %Estimated 
                            case 'Car'
                                obj.Fuel_Consumption = 2/100;  %estimated
                        end
                    case 'Hydrogen'
                        obj.Fuel_Type_Name = 'Hydrogen';
                        obj.CO2emissions = 90;
                        Fuel_Density = 0.071; %(kg/L) Liquid Hyrogen Density (Rough Value)
                        switch obj.Vehicle_Size
                            case 'HGV'
                                obj.Fuel_Consumption = ((2.5*0.76)/100)*Fuel_Density;  %L/100km 7 = 7/100 (L/km)*(kg/L) 0.76 kg/100 - google rough numbers 2.5 assumed number
                            case 'Van'
                                obj.Fuel_Consumption = ((1.3*0.76)/100)*Fuel_Density;  %L/100km 7 = 7/100 (L/km)*(kg/L) 0.76 kg/100 - google rough numbers 1.3 assumed 
                            case 'Car'
                                obj.Fuel_Consumption = (0.76/100)*Fuel_Density;  %L/100km 7 = 7/100 (L/km)*(kg/L) 0.76 kg/100 - google rough numbers 
                        end
                    otherwise
                        warning('Not a fuel/Vehicle Combination')
                end
            end
            
            if strcmpi(obj.Vehicle_Type,'EV')
                obj.Fuel_Type_Name = 'Electricity';
                obj.Fuel_Type = inputArg5;
                obj.Fuel_CEnC = 0;
                obj.Fuel_CExC = 0;
                obj.CO2emissions = 90; %HEAVILY dependent on grid makeup...  20 wind, 210 natgas, 350 coal
            end
        end
        
        function obj = transport_run(obj,inputArg1)
            % transport_run Calculate vehicle CExC and CEnC based on
            % previous vehicle definition and input load 
            
            %   Detailed explanation goes here
            % inputArg1 - Vehicle Load in kg
            
            obj.Vehicle_Load = inputArg1;
            obj.Number_Journey = ceil(obj.Vehicle_Load/obj.Vehicle_Capacity);
            obj.CO2 =  (obj.Vehicle_Load / 1000) * obj.Distance * obj.CO2emissions / 1000000; % kgCO2-eq/tonne km

                if strcmpi(obj.Vehicle_Type,'ICE')
                obj.Fuel_Used = obj.Distance*obj.Number_Journey*obj.Fuel_Consumption;  % (km * i * (kg/km) = kg of fuel
                obj.CEnC = obj.Fuel_Used*obj.Fuel_CEnC;  % kg * MJ/kg) = MJ energy/exergy
                obj.CExC = obj.Fuel_Used*obj.Fuel_CExC;

            elseif strcmpi(obj.Vehicle_Type,'EV')
                charger_consumption = 200*3.6; % Assume 200kW charger - 20kWh = 20*3.6 MJ
                
                % Input for EV type vehicles is electricity use object
                charge_duration = obj.Battery_Capacity / charger_consumption;
                
                obj.Fuel_Type = process_electricity_use(obj.EV_charge_grid,...
                    charger_consumption,...
                    charge_duration,...                     %need duration?
                    0);
                
                total_distance = obj.Number_Journey * obj.Distance;
                battery_distance = obj.Battery_Capacity/obj.Battery_Consumption;
                number_of_charges = total_distance / battery_distance; 
                number_of_charges = ceil(number_of_charges);
                
                obj.Fuel_CEnC = obj.Fuel_Type.CEnC;
                obj.Fuel_CExC = obj.Fuel_Type.CExC;
                

                % Number of Charges required for Journey
                
                % Treat Battery_Distance as number of complete battery
                % charges to complete journey - so a ratio of the single
                % battery charge


                %% WHhere is the distance?
                obj.CEnC = obj.Fuel_CEnC*number_of_charges;
                obj.CExC = obj.Fuel_CExC*number_of_charges;
            end
        end
    end
end

