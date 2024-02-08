classdef gas_source
    %   MATERIAL Material definition for raw material
    %
    %   Detailed explanation goes here

    properties
        Name
        CEnC
        CExC
        CO2
        LHV
        Mdot
        Composition_Fraction    % Fraction of contributions
        Composition_Raw         % Fraction Parts ('Named Values')
        Composition_Energy      % Unit energy of each component
        Composition_LHV         % lower heating value
        Composition_Exergy      % Unit exergy of each component
        Composition_CO2
        Composition_Mdot        % Mass Flow of each component
        Composition_Energy_Unit
        Composition_Exergy_Unit
        Composition_CO2_Unit
        Composition_LHV_Unit
    end

    methods
        function obj = gas_source(M,InArg1,InArg2,InArg3)
            %   GAS SOURCE  Construct an instance of this class
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
                obj.LHV  = table2array(M(strcmpi(M.Material,obj.Composition_Raw{i}),"LHV"));

                obj.Composition_Energy(i)   =  table2array(M(strcmpi(M.Material,obj.Composition_Raw{i}),"Energy"));
                obj.Composition_Exergy(i)   =  table2array(M(strcmpi(M.Material,obj.Composition_Raw{i}),'Xch'));
                obj.Composition_CO2(i)      =  table2array(M(strcmpi(M.Material,obj.Composition_Raw{i}),'CO2'));
                obj.Composition_LHV(i)      =  table2array(M(strcmpi(M.Material,obj.Composition_Raw{i}),"LHV"));

                obj.Composition_Exergy_Unit{i}  =   table2array(M(strcmpi(M.Material,obj.Composition_Raw{i}),"XchUnit"));
                obj.Composition_Energy_Unit{i}  =   table2array(M(strcmpi(M.Material,obj.Composition_Raw{i}),"EnergyUnit"));
                obj.Composition_CO2_Unit{i}     =   "kg/kg";
                obj.Composition_LHV_Unit{i}     =   table2array(M(strcmpi(M.Material,obj.Composition_Raw{i}),"LHVUnit"));


                if strcmpi(obj.Composition_Energy_Unit{i},'')
                    obj.Composition_Energy_Unit{i} = '-';
                end

                if strcmpi(obj.Composition_Exergy_Unit{i},'')
                    obj.Composition_Energy_Unit{i} = '-';
                end

                if strcmpi(obj.Composition_CO2_Unit{i},'')
                    obj.Composition_CO2_Unit{i} = '-';
                end

                if strcmpi(obj.Composition_LHV_Unit{i},'')
                    obj.Composition_LHV_Unit{i} = '-';
                end
            end

            if sum(obj.Composition_Fraction) ~= 1
                obj.Composition_Raw{i+1} = 'Unaccounted Component';
                obj.Composition_Fraction(i+1) = 1 - sum(obj.Composition_Fraction);
                obj.Composition_Energy(i+1) = 0;
                obj.Composition_Exergy(i+1) = 0;
                obj.Composition_CO2(i+1) = 0;
                obj.Composition_LHV(i+1) = 0;
                obj.Composition_Exergy_Unit{i+1} = '-';
                obj.Composition_Energy_Unit{i+1} = '-';
                obj.Composition_CO2_Unit{i+1} = '-';
                obj.Composition_LHV_Unit{i+1} = '-';
            end


        end
        %%
        function obj = materialflowrate(obj,flowrate)
            obj.Mdot = flowrate;
            obj.Composition_Mdot = flowrate*obj.Composition_Fraction;
        end
    end
end

