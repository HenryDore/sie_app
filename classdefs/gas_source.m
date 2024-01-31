classdef gas_source
    %   MATERIAL Material definition for raw material
    %
    %   Detailed explanation goes here

    properties
        Name
        CEnC
        CExC
        CO2
        Mdot
        Composition_Fraction    % Fraction of contributions
        Composition_Raw         % Fraction Parts ('Named Values')
        Composition_Energy      % Unit energy of each component
        Composition_Exergy      % Unit exergy of each component
        Composition_CO2
        Composition_Mdot        % Mass Flow of each component
        Composition_Energy_Unit
        Composition_Exergy_Unit
        Composition_CO2_Unit
    end

    methods
        function obj = gas_source(M,InArg1,InArg2,InArg3)
            %   MATERIAL Construct an instance of this class
            %   Detailed explanation goes here

            % If only a name is defined - it is single species material and
            % go to properties lookup
            if nargin == 2
                InArg2{1} = InArg1;
                InArg3 = 1;

                if sum(strcmpi(M.Material,InArg1)) == 0
                    disp('Cannot find material in database');
                end

            end

            obj.Name = InArg1;                  % Name of material
            obj.Composition_Raw = InArg2;       % Raw components of material
            obj.Composition_Fraction = InArg3;  % Fractions of Raw Components

            for i = 1:length(obj.Composition_Raw)

                obj.CExC = table2array(M(strcmpi(M.Material,obj.Composition_Raw{i}),"CExC"));
                obj.CEnC = table2array(M(strcmpi(M.Material,obj.Composition_Raw{i}),"Energy"));
                obj.CO2  = table2array(M(strcmpi(M.Material,obj.Composition_Raw{i}),"CO2"));

                obj.Composition_Energy(i) =         table2array(M(strcmpi(M.Material,obj.Composition_Raw{i}),"Energy"));
                obj.Composition_Exergy(i) =          table2array(M(strcmpi(M.Material,obj.Composition_Raw{i}),'Xch'));
                obj.Composition_CO2(i) =             table2array(M(strcmpi(M.Material,obj.Composition_Raw{i}),'CO2'));

                if isnan(obj.Composition_Energy(i)) || obj.Composition_Energy(i) == 0
                    obj.Composition_Energy(i) =      table2array(M(strcmpi(M.Material,obj.Composition_Raw{i}),"LHV"));
                end

                obj.Composition_Exergy_Unit{i} =     table2array(M(strcmpi(M.Material,obj.Composition_Raw{i}),"XchUnit"));
                obj.Composition_Energy_Unit{i} =     table2array(M(strcmpi(M.Material,obj.Composition_Raw{i}),"EnergyUnit"));
                obj.Composition_CO2_Unit{i} = "kg/kg";


                if strcmpi(obj.Composition_Energy_Unit{i},'')
                    obj.Composition_Energy_Unit{i} = table2array(M(strcmpi(M.Material,obj.Composition_Raw{i}),"LHVUnit"));
                end

                if strcmpi(obj.Composition_Energy_Unit{i},'')
                    obj.Composition_Energy_Unit{i} = '-';
                end

                if strcmpi(obj.Composition_Exergy_Unit{i},'')
                    obj.Composition_Energy_Unit{i} = '-';
                end

                if strcmpi(obj.Composition_CO2_Unit{i},'')
                    obj.Composition_CO2_Unit{i} = '-';
                end

            end

            if sum(obj.Composition_Fraction) ~= 1
                obj.Composition_Raw{i+1} = 'Unaccounted Component';
                obj.Composition_Fraction(i+1) = 1 - sum(obj.Composition_Fraction);
                obj.Composition_Energy(i+1) = 0;
                obj.Composition_Exergy(i+1) = 0;
                obj.Composition_CO2(i+1) = 0;
                obj.Composition_Exergy_Unit{i+1} = '-';
                obj.Composition_Energy_Unit{i+1} = '-';
                obj.Composition_CO2_Unit{i+1} = '-';
            end


        end

        function obj = materialflowrate(obj,flowrate)
            obj.Mdot = flowrate;
            obj.Composition_Mdot = flowrate*obj.Composition_Fraction;
        end


        %         function obj = updatematerial(obj)
        %             %   updatematerial Updates material properties when called
        %             %   Detailed explanation goes here
        %
        %             if  obj.Mdot > 0
        %                 obj = materialflowrate(obj,obj.Mdot);
        %             end
        %
        %
        %             if isempty(obj.Mdot) || isempty(obj.Composition_Mdot)
        %                 disp(['Error: ',obj.Name,' has 0 kg/s flowrate'])
        %                 disp('Update flowrate before continuing')
        %                 return
        %             end
        %             obj.CEnC = sum(obj.Composition_Mdot.*obj.Composition_Energy);
        %             obj.CExC = sum(obj.Composition_Mdot.*obj.Composition_Exergy);
        %             obj.Mdot = sum(obj.Composition_Mdot);
        %         end
    end
end

