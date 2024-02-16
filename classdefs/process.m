classdef process
    %PROCESS Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
        Name                        % Name of Process
        Type                        % Type of Process
        Inputs_Named                % Cell array of named Material (Class) inputs
        Inputs_MassFlowRate         % Total amount (kg) of inputs to system
        Outputs_Named               % '' outputs
        Outputs_Mass_Fraction       % '' outputs
        Main_Products               % Object_definition of Main Process productions
        Main_MassFlowRate           % Mass Flow Rate of Defined Main products
        By_Products                 % Object Array of Byproducts
        Work_Products               % Object Array of total Work Input
        Production_Ratio            % Argicultural production ratio (input/output)
        Fuel_MassFlowRate           % Argicultural fuel input
        Fuel_Type                   % Argicultural fuel type
        Electricity_Use             % Electricity Usage
        Machine_Choice              % Manufacturing Process - Machine Choice (from Machine Lookup table)
        Machine_ProcessRate         % Process rate (kg/hr)
        Machine_ProcessTime         % Time to process inputs based on Machine_ProcessRate
        Machine_EnergyConsumption   % Electricity consumption
        Machine_GasConsumption      % Natural gas consumption (update to 'heat input')
        Machine_RejectRatio         % Rejection ratio of sorting/cleaning type process
        Machine_CO2e
        
    end
    
    methods
        function obj = process(Name,Type)
            % Class constructor
            obj.Name = Name;
            obj.Type = Type;
            obj.By_Products = [];
            obj.Work_Products = [];
        end
        
        function obj = process_inputs(obj,Inputs)
            %PROCESS Construct an instance of this class
            % M - Machine details database (lookup)
            %
            obj.Inputs_Named = Inputs;
            
            for i = 1:length(Inputs)
                obj.Inputs_Named(i) = updatematerial(obj.Inputs_Named(i));
            end
            
            obj.Inputs_MassFlowRate = 0;
            
            for i = 1:length(Inputs)
                obj.Inputs_MassFlowRate = obj.Inputs_MassFlowRate + obj.Inputs_Named(i).Mdot;
            end
        end
        
        function obj = process_outputs(obj,Outputs,OutputM)
            obj.Outputs_Named = Outputs;
            obj.Outputs_Mass_Fraction = OutputM;
        end
        
        function obj = process_work(obj, Fuel_Type,MassFlow)
            % Function to cover process work input from liquid fuels
            % (usually diesel/petrol to run agricultural vehicles)
            
            % Work_input - Fuel Class definition
            % M - Chemical Database
            obj.Fuel_Type = Fuel_Type;         % Name of material
            obj.Fuel_Type.Mdot = MassFlow;
        end
        
        function obj = process_machine(obj,machine)
            obj.Machine_Choice = machine.MachineChoice;
            obj.Machine_ProcessRate = machine.ProcessRate;              % kg/hr
            obj.Machine_EnergyConsumption = machine.EnergyConsumption;  % MJ/hr
            obj.Machine_GasConsumption = machine.GasConsumption;  % MJ/hr
            obj.Machine_CO2e = machine.CO2e; %CO2 efficiency 
        end
        
        
        function [obj,varargout] = process_run(obj,OutputDef,varargin)
            
            %obj        obj class of process
            %outputs    material class objects
            
            for i = 1:length(varargin)
                varargout{i} = varargin{i};
            end
            
            if length(OutputDef) ~= length(varargin)
                disp('Outputs fraction allocation does not outputs match definition')
            end
            
            totalMassFlow = 0;
            for i = 1:length(obj.Inputs_Named)
                totalMassFlow = totalMassFlow + obj.Inputs_Named(i).Mdot;
            end
            
            if strcmp(obj.Type,'Industrial')
                obj.Machine_ProcessTime = totalMassFlow/obj.Machine_ProcessRate;
                obj.Machine_ProcessTime = obj.Machine_ProcessTime*60; % Process time in minutes to match timeseries tables.
            end
            
            if strcmp(obj.Type,'Argicultural')
                obj.Machine_Choice = 'NA';
                obj.Machine_ProcessRate = 'NA';
                obj.Machine_ProcessTime = 'NA';
                obj.Machine_EnergyConsumption = 'NA';
                obj.Machine_GasConsumption = 'NA';
                obj.Machine_RejectRatio = 'NA';
            end
            
            
            for i = 1:length(varargin)
                
                obj.Outputs_Named(i).Mdot = totalMassFlow*obj.Outputs_Mass_Fraction(i);
                varargout{i}.Mdot = obj.Outputs_Named(i).Mdot;
                
                varargout{i} = updatematerial(varargout{i});
                obj.Outputs_Named(i) = updatematerial(obj.Outputs_Named(i));
            end
            
            j = 1;
            k = 1;
            obj.Main_MassFlowRate = 0;
            for i = 1:length(OutputDef)
                if OutputDef(i) == 1
                    obj.Main_Products{j} = obj.Outputs_Named(i);
                    obj.Main_MassFlowRate(j) = obj.Outputs_Named(i).Mdot;
                    j = j+1;
                elseif OutputDef(i) == 2
                    % Nothing happens - products are not named in main
                    % outputs or by-products (i.e. bags) and not accounted
                    % for.
                    
                else
                    obj.By_Products{k} = obj.Outputs_Named(i);
                    k = k + 1;
                end
            end
            
            % Update Fuel Usage
            j = 1;
            for i = 1:length(obj.Fuel_Type)
                obj.Fuel_Type(i) = updatematerial(obj.Fuel_Type(i));
                obj.Work_Products{j} = obj.Fuel_Type(i);
                j = j + 1;
            end
            
            % Electricity Usage
            % Want different times of day and seasonal variation
            % take each of the grid contributors - work out CEnC/CExC/CO2
            % Determine overall values from decisions
            
        end
        
        
        function [Reporting] = process_analysis(obj,varargin)
            length(varargin);
            % varargin{1} = Electricity
            % varargin{2} = Gas
            % varargin{3} = Inputs Accounted
            % varargin{4} = Outputs Accounted
            % varargin{5} = By-products Accounted
            
            
            Reporting.Input.CEnC = 0;       Reporting.Input.CExC = 0;       Reporting.Input.CO2 = 0;
            Reporting.Main.CEnC = 0;        Reporting.Main.CExC = 0;        Reporting.Main.CO2 = 0;     Reporting.Main.Mdot = 0;
            Reporting.Byproduct.CEnC = 0;   Reporting.Byproduct.CExC = 0;   Reporting.Byproduct.CO2 = 0;
            Reporting.Work.CEnC = 0;        Reporting.Work.CExC = 0;        Reporting.Work.CO2 = 0;
            
            for i = 1:length(obj.Inputs_Named)
                Reporting.Input.CEnC = Reporting.Input.CEnC + obj.Inputs_Named(i).CEnC*varargin{3}(i);
                Reporting.Input.CExC = Reporting.Input.CExC + obj.Inputs_Named(i).CExC*varargin{3}(i);
                Reporting.Input.CO2 = Reporting.Input.CO2 + obj.Inputs_Named(i).CO2*varargin{3}(i);
            end
            
            for i = 1:length(obj.Main_Products)
                % Main is the main product of a process - for intermediate
                % processes do not account. Varargin{4} must equal number of
                % outputs (main and byproduct)
                
                Reporting.Main.CEnC = Reporting.Main.CEnC + obj.Main_Products{i}.CEnC*varargin{4}(i);
                Reporting.Main.CExC = Reporting.Main.CExC + obj.Main_Products{i}.CExC*varargin{4}(i);
                Reporting.Main.CO2 =  Reporting.Main.CO2  + obj.Main_Products{i}.CO2*varargin{4}(i);
                Reporting.Main.Mdot = Reporting.Main.Mdot + obj.Main_MassFlowRate(i)*varargin{4}(i);
            end
            
            for i = 1:length(obj.By_Products)
                
                Reporting.Byproduct.CEnC = Reporting.Byproduct.CEnC + obj.By_Products{i}.CEnC*varargin{5}(i);
                Reporting.Byproduct.CExC = Reporting.Byproduct.CExC + obj.By_Products{i}.CExC*varargin{5}(i);
                Reporting.Byproduct.CO2  = Reporting.Byproduct.CO2  + obj.By_Products{i}.CO2*varargin{5}(i);
            end
                                    
            for i = 1:length(obj.Work_Products)
                Reporting.Work.CEnC = Reporting.Work.CEnC + obj.Work_Products{i}.CEnC;
                Reporting.Work.CExC = Reporting.Work.CExC + obj.Work_Products{i}.CExC;
                Reporting.Work.CO2 = Reporting.Work.CO2 + obj.Work_Products{i}.CO2;
            end
            
            if length(varargin) >= 1
                if isempty(varargin{1})
                    varargin{1}.CEnC = 0;
                    varargin{1}.CExC = 0;
                    varargin{1}.CO2 = 0;
                end
                Reporting.Work.CEnC = Reporting.Work.CEnC + varargin{1}.CEnC;
                Reporting.Work.CExC = Reporting.Work.CExC + varargin{1}.CExC;
                Reporting.Work.CO2 = Reporting.Work.CO2 + varargin{1}.CO2;
            end
            
            if length(varargin) >= 2
                if isempty(varargin{1})
                    varargin{1}.CEnC = 0;
                    varargin{1}.CExC = 0;
                    varargin{1}.CO2 = 0;
                end
                if isempty(varargin{2})
                    varargin{2}.CEnC = 0;
                    varargin{2}.CExC = 0;
                    varargin{2}.CO2 = 0;
                end
                Reporting.Work.CEnC = Reporting.Work.CEnC + varargin{1}.CEnC + varargin{2}.CEnC;
                Reporting.Work.CExC = Reporting.Work.CExC + varargin{1}.CExC + varargin{2}.CExC;
                Reporting.Work.CO2 =  Reporting.Work.CO2  + varargin{1}.CO2  + varargin{2}.CO2;
                
            end

            if isempty(obj.Machine_CO2e)
            %not a machine - do nothing
            else
            %multiply work by machine efficiency factor
            Reporting.Work.CO2 = Reporting.Work.CO2 .* obj.Machine_CO2e;
            end

        

            %             if length(varargin) == 3
            %                 % Flag to determine whether to count inputs/Main (to stop double accounting for intermediate processes)
            %                 for j = 1:length(varargin{3})
            %                     switch varargin{3}(j)
            %                         case 0
            %                             Reporting.Main.CEnC = Reporting.Main.CEnC*0;
            %                             Reporting.Main.CExC = Reporting.Main.CExC*0;
            %                             Reporting.Main.CO2 = Reporting.Main.CO2*0;
            %
            %                             Reporting.Input.CEnC = Reporting.Input.CEnC*0;
            %                             Reporting.Input.CExC = Reporting.Input.CExC + obj.Inputs_Named(i).CExC;
            %                             Reporting.Input.CO2 = Reporting.Input.CO2*0;
            %                         case 1
            %                             Reporting.Main.CEnC = Reporting.Main.CEnC*0;
            %                             Reporting.Main.CExC = Reporting.Main.CExC*0;
            %                             Reporting.Main.CO2 = Reporting.Main.CO2*0;
            %
            %                             Reporting.Input.CEnC = Reporting.Input.CEnC*1;
            %                             Reporting.Input.CExC = Reporting.Input.CExC + obj.Inputs_Named(i).CExC;
            %                             Reporting.Input.CO2 = Reporting.Input.CO2*1;
            %                         case 2
            %                             Reporting.Main.CEnC = Reporting.Main.CEnC*1;
            %                             Reporting.Main.CExC = Reporting.Main.CExC*1;
            %                             Reporting.Main.CO2 = Reporting.Main.CO2*1;
            %
            %                             Reporting.Input.CEnC = Reporting.Input.CEnC*1;
            %                             Reporting.Input.CExC = Reporting.Input.CExC + obj.Inputs_Named(i).CExC;
            %                             Reporting.Input.CO2 = Reporting.Input.CO2*1;
            %                         otherwise
            %                             disp('Error Check');
            %                     end
            %                 end
            %
            %                 for j = 1:length(varargin{3})
            %                 Reporting.Main.CEnC = Reporting.Main.CEnC*varargin{3}(j);
            %                 Reporting.Main.CExC = Reporting.Main.CExC*varargin{3}(j);
            %                 Reporting.Main.CO2 = Reporting.Main.CO2*varargin{3}(j) ;
            %
            %                 Reporting.Input.CEnC = Reporting.Input.CEnC*varargin{3}(j);
            %                 Reporting.Input.CExC = Reporting.Input.CExC*varargin{3}(j);
            %                 Reporting.Input.CO2 = Reporting.Input.CO2*varargin{3}(j);
            %
            %
            %                 end
        end
    end
end
% end

