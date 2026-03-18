% TX Example: Single Tone Generator

freq=122.88e6;

xk = single_tone_generator(freq);
xk = repmat(xk, 2, 1000);
% set_TX_Attenuation([0 10])
LO_CHANGE(0, 2400, 2400);

set_TX_power([0 -10]); % dBm, set TX1 to a specific channel power

%=== Transmit for a while ====
rep = 0;% infinite repeat
% TX(xk, rep, 10); % seconds
TX_start(xk, rep); % continuous
%=============================
%=== Transmit for rep times ==
% rep=1;? % finite repeat
% TX(xk, rep); % rep times
%=============================

%=== Stop Transmit ===========
% TX_close;  
