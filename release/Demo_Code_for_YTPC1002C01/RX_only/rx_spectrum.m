

N=10000000;
k=0;
Pow_com = set_RX_Ref_Level_ELSDR([0 -10]);
Fs=122.88e6;

%N_log=2^14;
N_log=1e5;
while(1)
    k
    
    rn=RX(1,N_log);
    P_rk=10*log10(mean(abs(rn).^2))-Pow_com
    %pwelch(rn,[],[],[],Fs,'centered');
    y=plot_spectrum(rn,Fs);
    %plot(real(rn.'))
    %plot(real(rn(1,:)),'b')
    %hold on
    %plot(imag(rn(1,:)),'r')
    %plot(real(rn(2,:)),'r')
    %plot(real(rn(3,:)),'g')
    %plot(real(rn(4,:)),'k')
    %hold off
    k=k+1;

    if P_rk > -50
        keyboard;
    end
    
    if k==N
        break;
    end
    grid on
    pause(0.1)
    
end