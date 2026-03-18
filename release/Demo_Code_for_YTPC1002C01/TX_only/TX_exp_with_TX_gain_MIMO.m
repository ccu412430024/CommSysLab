

freq=1.92e6;
xk = single_tone_generator(freq);
xk = repmat(xk, 2, 1000);

% set_TX_Attenuation([0 10; 1 10])
set_TX_power([0 -10; 1 -10]); % dBm, set channel power of TX1 to -20 dBm and TX2 to -10 dBm
pause(0.1)
%=== Transmit for a while ====
rep=0;  % infinite repeat
% TX(xk, rep, 10); % seconds
TX_start(xk, rep); % continuous
%=============================
%=== Transmit for rep times ==
% rep=1;  % finite repeat
% TX(xk, rep); % rep times
%=============================

%=== Stop Transmit ===========
% TX_close;
