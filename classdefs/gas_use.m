classdef gas_use
    %ELECTRICITY Summary of this class goes here
    % Setup electriticy use for each process as seperate, so can make them
    % asynchronous
    %   Detailed explanation goes here

    properties
        Composition     % Composition of the Gas
        Component_Ratios
        CExC
        CEnC
        CO2
        Consumption     % Amount of Gas required (kg/hr)
        Requirement     % Total amount required
    end

    methods
        function obj = gas_use(Composition,Ratio)
            %ELECTRICITY Construct an instance of this class
            %   Detailed explanation goes here

            % Contributions are from chemical database to ensure
            % varibility/updates

            obj.Composition = Composition;
            obj.Component_Ratios = Ratio;

        end

        function obj = process_gas_use(obj,ConsumptionRate,MassFlowRate)

            % Duration in hours (based on machine processing rate

            obj.Consumption = ConsumptionRate; % give kgs of mix required
            % Ignoring calorific value of gas mixture at this stage


            obj.Requirement = MassFlowRate; % Total kg of gas mixture required (here can change to total energy required and from that kg

            for i = 1:length(obj.Composition)
                CExCi(i) = (obj.Requirement*obj.Component_Ratios(i))*obj.Composition(i).CExC; % Give indiviudal mass contribution
                CEnCi(i) = (obj.Requirement*obj.Component_Ratios(i))*obj.Composition(i).CEnC; % Give indiviudal mass contribution
                CO2i(i) = (obj.Requirement*obj.Component_Ratios(i))*obj.Composition(i).CO2*obj.Composition(i).CEnC; % Give indiviudal mass contribution

            end

            obj.CEnC = sum(CEnCi);
            obj.CExC = sum(CExCi);
            obj.CO2 = sum(CO2i);

        end

    end
end

