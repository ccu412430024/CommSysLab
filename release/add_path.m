function add_path(flag_AddRm)
%   AddRm = add remove
%   command:
%       1. addpath: Add directory to search path
%       2. rmpath: Remove directory from search path
%

if flag_AddRm == 'a'
    addpath('./Tool');
    addpath('./Demo_Code_for_YTPC1002C01/TX_only');
    %===========
elseif flag_AddRm == 'r'
    rmpath('./Tool');
    rmpath('./Demo_Code_for_YTPC1002C01/TX_only');
    %===========
end

