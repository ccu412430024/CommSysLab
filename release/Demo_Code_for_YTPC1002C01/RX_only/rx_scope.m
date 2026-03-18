

N=10000000;
k=0;
LO_CHANGE(0, 433, 433);
Pow_com = set_RX_Ref_Level_ELSDR([0 0]);
figure(1)

Fs=122.88e6;
while(1)
    k
    N_log=10000;
    rn=RX(1,N_log);
    plot(real(rn.'))
   
    %plot(real(rn(1,:)),'b')
    %hold on
    %plot(imag(rn(1,:)),'r')
    %plot(real(rn(2,:)),'r')
    %plot(real(rn(3,:)),'g')
    %plot(real(rn(4,:)),'k')
    %hold off
    k=k+1;
    
    if k==N
        break;
    end
    grid on
    pause(0.1)
    
end