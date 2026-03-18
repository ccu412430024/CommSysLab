

Number_of_RX_rows=1;  % 1:SISO, 2:MIMO
rx_len=1e5;
Pow_com = set_RX_Ref_Level_ELSDR([0 -10]);
rk = RX(Number_of_RX_rows,rx_len);
P_rk=10*log10(mean(abs(rk).^2))-Pow_com
% P_rk=10*log10(mean(abs(rk).^2))

Fs=122.88e6;
figure(1)
P1=plot(0:size(rk,2)-1,real(rk),'b',0:size(rk,2)-1,imag(rk),'r');
set(P1,'LineWidth',1);   %=== 設定線的粗細
%set(P1,'Position',[32 223 951 420]) %=== 控制圖要秀在螢幕的哪個位置
%axis([-2*width 3*width -1.2 1.2]);  %=== 設定要畫的區間
AX=gca;
set(AX,'FontSize',12);   %=== 設定 X軸 和 Y軸 的字型大小
X=xlabel('nTs : 1/122.88MHz');
set(X,'FontSize',14);    %=== 設定 xlabel 的字型大小
Y=ylabel('  Received Data  ');
set(Y,'FontSize',14); %=== 設定 ylabel 的字型大小
%T=title('Constellation');
%set(T,'FontSize',14);    %=== 設定 xlabel 的字型大小
% axis([-1.5 1.5 -1.5 1.5])
grid on

figure(2)
FFT_SIZE=2^14;
df=Fs/FFT_SIZE;
xf=(-FFT_SIZE/2:FFT_SIZE/2-1)*df;
rk_f=fftshift(fft(rk(1,:),FFT_SIZE));
P2=plot(xf,20*log10(abs(rk_f)),'b');
set(P2,'LineWidth',1);   %=== 設定線的粗細
%set(P1,'Position',[32 223 951 420]) %=== 控制圖要秀在螢幕的哪個位置
%axis([-2*width 3*width -1.2 1.2]);  %=== 設定要畫的區間
AX=gca;
set(AX,'FontSize',14);   %=== 設定 X軸 和 Y軸 的字型大小
X=xlabel('f ');
set(X,'FontSize',14);    %=== 設定 xlabel 的字型大小
Y=ylabel('  PSD  ');
set(Y,'FontSize',14); %=== 設定 ylabel 的字型大小
%T=title('Constellation');
%set(T,'FontSize',14);    %=== 設定 xlabel 的字型大小
%axis([-1.5 1.5 -1.5 1.5])
grid on
