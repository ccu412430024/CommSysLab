function y = single_tone_generator(freq)

    SR = 122.88e6;
    ts = 1/(SR);
    T = ceil(SR/freq);    
    y = exp(1j*2*pi*freq*(0:ts:(1*T-1)*ts));

end

