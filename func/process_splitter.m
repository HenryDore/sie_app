function [varargout] = process_splitter(material,split_ratio)
%PROCESS_SPLITTER Summary of this function goes here
%   Detailed explanation goes here

out_materials = length(split_ratio); 

for i = 1:out_materials

    varargout{i} = material; 
    varargout{i}.Mdot = varargout{i}.Mdot*split_ratio(i);

    varargout{i} = updatematerial(varargout{i});
end


end

