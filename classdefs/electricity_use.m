classdef electricity_use
    %ELECTRICITY Summary of this class goes here
    % Setup electriticy use for each process as seperate, so can make them
    % asynchronous
    %   Detailed explanation goes here
    
    properties
        Timeseries      % Input based on Seasonal Average, Variation during day
        Composition     % Contributions to National Grid
        CExC
        CEnC
        CO2
        Consumption_per_tblock     % Amount of Electricity required (MJ/hr)
        Start_Time      % When use of electricity starts - start point in timeseries
        Requirement     % Total amount required
        Duration        % Duration of process
        timetable
        End_Time
        
    end
    
    methods
        function obj = electricity_use(Timeseries,Grid_Contributions)
            %ELECTRICITY Construct an instance of this class
            %   Detailed explanation goes here
            
            % Timeseries rows must match contributions
            % Contributions are from chemical database to ensure
            % varibility/updates
            
            obj.Timeseries = Timeseries;
            obj.Composition = Grid_Contributions;
            
        end
        
        function obj = process_electricity_use(obj,Consumption,Duration,Start_Time)
            block_length = 30;
            % Start time to nearest hour
            obj.Consumption_per_tblock = Consumption;              % Amount of MJ required per hr
            obj.Consumption_per_tblock = obj.Consumption_per_tblock*(block_length/60);   % Amount of MJ required per 5 minute block (averaged)
            obj.Duration = minutes(Duration*60);                    % Length of process (required to draw electricity) in hours
            obj.Requirement = Duration*Consumption;     % Total MJ required by process
            obj.Start_Time = minutes(Start_Time*60);    % Start time inputs as double array of 24-hour format
            r_duration = ceil((Duration*60)/block_length)*block_length;
            obj.End_Time = obj.Start_Time + minutes(r_duration);
            
            obj.timetable = obj.Timeseries(timerange(obj.Start_Time,obj.End_Time,'closed'),:);
            
            %             if isempty(obj.timetable)
            %                 obj.timetable = obj.Timeseries(timerange(obj.Start_Time_Time
            %
            CExC_step = zeros(1,height(obj.timetable)) ;  % Pre-allocate
            CEnC_step = zeros(1,height(obj.timetable)) ;  % Pre-allocate
            CO2C_step  = zeros(1,height(obj.timetable)); 
            
            temp_duration = obj.Duration;
            
            for i = 1:height(obj.timetable) % for each row of the table
                
                temp_duration = temp_duration - minutes(block_length);
                
                CExC_components = zeros(1,length(obj.Composition));
                CEnC_components = zeros(1,length(obj.Composition));
                CO2C_components = zeros(1,length(obj.Composition));

                Exergy_index = zeros(1,length(obj.Composition));
                Energy_index = zeros(1,length(obj.Composition));
                CO2_index = zeros(1,length(obj.Composition));

                for j = 1:length(obj.Composition)

                    % Find index of table column for matching to composition name
                    for k = 1:length(obj.timetable.Properties.VariableNames)
                        if strcmpi(obj.Composition(j).Name,obj.timetable.Properties.VariableNames(k))
                            obj.timetable.Properties.VariableNames(k);
                            tidx = k;
                            break
                        end
                    end
                    
                    Exergy_index(j) = obj.Composition(j).CExC;
                    Energy_index(j) = obj.Composition(j).CEnC;
                    CO2_index(j) = obj.Composition(j).CO2;
                    
                    frac = table2array(obj.timetable(i,tidx));
                    
                    % Update this block - consumption is fraction of time
                    % block
                    
                    if temp_duration > 0
                        CExC_components(j) = frac*obj.Consumption_per_tblock*Exergy_index(j);
                        CEnC_components(j) = frac*obj.Consumption_per_tblock*Energy_index(j);
                        CO2C_components(j) = frac*obj.Consumption_per_tblock*CO2_index(j);
                    else
                        temp_duration = temp_duration + minutes(block_length);
                        CExC_components(j) = frac.*obj.Consumption_per_tblock*Exergy_index(j)*(temp_duration/minutes(block_length));
                        CEnC_components(j) = frac.*obj.Consumption_per_tblock*Energy_index(j)*(temp_duration/minutes(block_length));
                        CO2C_components(j) = frac.*obj.Consumption_per_tblock*CO2_index(j)*(temp_duration/minutes(block_length));
                        temp_duration = temp_duration - minutes(block_length);
                    end
                   
                    CExC_step(i) = sum(CExC_components);
                    CEnC_step(i) = sum(CEnC_components);
                    CO2C_step(i) = sum(CO2C_components);
                    
                end
                
                obj.CExC = sum(CExC_step);
                obj.CEnC = sum(CEnC_step);
                obj.CO2 = sum(CO2C_step) ;
                
            end
            
        end
    end
end

