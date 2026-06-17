%% 16-QAM Receiver for SDR
clc; clear; close all;

%% 1. 參數設定 (System Parameters)
Fs = 122.88e6;             % 取樣率 (Hz)
M = 16;                    % 16-QAM (調變階數)
k_bits = 4;                
sps = 4;                   
CenterFreq = 433;          % 載波頻率 (MHz)
RxGain = -20;              
RxTime = 0.02;             % 錄取時間稍微拉長以抓取完整封包

% 濾波器與星座圖
Rolloff = 0.5;
FilterSpan = 10;
rrc_filter = rcosdesign(Rolloff, FilterSpan, sps, 'sqrt');
ref_constellation = qammod(0:M-1, M, 'UnitAveragePower', true);

% 本地已知 Preamble 波形 (用於同步與通道估測)
lfsr = comm.PNSequence('Polynomial', [6 5 0], 'SamplesPerFrame', 63, 'InitialConditions', [0 0 0 0 0 1]);
pn_seq = lfsr();
ref_preamble = 1 - 2 * pn_seq; 

%% 2. SDR 硬體接收 (Hardware Reception)
fprintf('\n--- 開始設定 SDR RX ---\n');
try
    LO_CHANGE(0, CenterFreq, CenterFreq);
    set_RX_Ref_Level_ELSDR([0 RxGain]);
    RxLen = round(RxTime * Fs);
    
    rx_data_raw = RX(1, RxLen);
    if size(rx_data_raw, 1) == 2
        rx_signal = rx_data_raw(1,:) + 1j*rx_data_raw(2,:);
    else
        rx_signal = rx_data_raw;
    end
    rx_signal = double(rx_signal(:));
catch
    warning('SDR 連接失敗，使用模擬雜訊測試...');
    RxLen = round(RxTime * Fs);
    rx_signal = (randn(RxLen, 1) + 1j*randn(RxLen, 1)) * 0.1; 
end

%% 3. 前處理與時序回復
% 移除 DC 偏差並做全域 AGC
rx_signal = rx_signal - mean(rx_signal); 
rx_agc = rx_signal / rms(rx_signal);  

rx_mf = conv(rx_agc, rrc_filter, 'same');

% 尋找最佳取樣相位 (Symbol Timing Recovery)
energy_per_phase = zeros(sps, 1);
for p = 0:sps-1
    energy_per_phase(p+1) = sum(abs(rx_mf(p+1:sps:end)).^2);
end
[~, best_p] = max(energy_per_phase);
rx_sync = rx_mf(best_p:sps:end);

%% 4. 封包同步與通道等化 (Synchronization & Equalization)
% 滑動相關尋找 Preamble 起點
[R, lags] = xcorr(rx_sync, ref_preamble);
[~, max_idx] = max(abs(R));
delay_syms = lags(max_idx);

if delay_syms < 0 || (delay_syms + 100 > length(rx_sync))
    error('同步失敗：找不到封包起點或擷取長度不足');
end

start_idx = delay_syms + 1;
preamble_rx = rx_sync(start_idx : start_idx + length(ref_preamble) - 1);

% LS 通道估測 (Channel Estimation)
H_est = sum(preamble_rx .* conj(ref_preamble)) / sum(abs(ref_preamble).^2);
fprintf('-> [通道估測] 幅度衰減: %.2f, 相位偏移: %.2f 度\n', abs(H_est), angle(H_est)*180/pi);

% Zero-Forcing Equalization (補償硬體引起的相位與衰減)
rx_eq = rx_sync / H_est;

%% 5. 動態解析與解調 (Dynamic Demodulation)
% A. 解析長度欄位 (8-bit BPSK)
start_len_idx = start_idx + length(ref_preamble);
rx_len_syms = rx_eq(start_len_idx : start_len_idx + 7);
rx_len_bits = real(rx_len_syms) < 0;
rx_msg_len = bi2de(rx_len_bits.', 'left-msb');

% B. 擷取 16-QAM Payload
start_qam_idx = start_len_idx + 8;
qam_sym_len = ceil((rx_msg_len * 8) / k_bits); 

if start_qam_idx + qam_sym_len - 1 > length(rx_eq)
    error('接收數據被截斷，無法解碼完整 Payload');
end
rx_qam_eq = rx_eq(start_qam_idx : start_qam_idx + qam_sym_len - 1);

% C. 最小歐氏距離硬判決 (16-QAM)
rx_indices = zeros(length(rx_qam_eq), 1);
for i = 1:length(rx_qam_eq)
    [~, min_idx] = min(abs(rx_qam_eq(i) - ref_constellation));
    rx_indices(i) = min_idx - 1;
end

% D. 解碼與解擾碼
rx_bits = de2bi(rx_indices, k_bits, 'left-msb').';
rx_bits = rx_bits(:);

descrambler = comm.Descrambler(2, [1 1 1 0 1], 'InitialConditions', [0 0 0 0]);
rx_payload_descrambled = descrambler(rx_bits);
rx_payload_descrambled = rx_payload_descrambled(1 : rx_msg_len * 8);

rx_msg_matrix = reshape(rx_payload_descrambled, 8, []).';
rx_ascii = bi2de(rx_msg_matrix, 'left-msb');
rx_str = char(rx_ascii.');

%% 6. 結果與視覺化 (Visualization)
fprintf('\n----------------------------------------\n');
fprintf('成功讀取: %d 個字元\n', rx_msg_len);
fprintf('解碼訊息: "%s"\n', rx_str);
fprintf('----------------------------------------\n');

S_ideal = ref_constellation(rx_indices + 1).';
evm_rms = sqrt(mean(abs(rx_qam_eq - S_ideal).^2) / mean(abs(S_ideal).^2)) * 100;

figure('Name', '16-QAM SDR Result', 'Color', 'w', 'Position', [100, 100, 900, 450]);

subplot(1,2,1);
plot(rx_sync(start_qam_idx : start_qam_idx + qam_sym_len - 1), 'r.', 'MarkerSize', 8);
title('等化前接收星座圖 (Raw from SDR)');
xlabel('I'); ylabel('Q'); grid on; axis square;

subplot(1,2,2);
plot(rx_qam_eq, 'b.', 'MarkerSize', 8); hold on;
plot(ref_constellation, 'k+', 'MarkerSize', 10, 'LineWidth', 2);
title(sprintf('等化後 16-QAM 星座圖 (EVM: %.1f%%)', evm_rms));
xlabel('I'); ylabel('Q'); grid on; axis square;
xlim([-1.5 1.5]); ylim([-1.5 1.5]);