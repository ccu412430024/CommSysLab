%% 16-QAM Receiver for SDR
clc; clear; close all;

%% 1. 參數設定 (System Parameters)
Fs = 122.88e6;             
CenterFreq_MHz = 433;      
M = 16;                    
k_bits = 4;                
sps = 32;                   
RxTime = 0.02;             

% --- RRC 濾波器 ---
Rolloff = 0.5;
FilterSpan = 10;
rrc_filter = rcosdesign(Rolloff, FilterSpan, sps, 'sqrt');

% --- 同步序列與標準星座表 ---
ref_constellation = qammod(0:M-1, M, 'UnitAveragePower', true);

lfsr = comm.PNSequence('Polynomial', [6 5 0], 'SamplesPerFrame', 63, 'InitialConditions', [0 0 0 0 0 1]);
pn_seq = lfsr();
ref_preamble = 1 - 2 * pn_seq; 

%% 2. SDR 硬體接收 (Hardware Reception)
fprintf('\n--- 開始設定 SDR RX ---\n');
try
    LO_CHANGE(0, CenterFreq_MHz, CenterFreq_MHz);
    set_RX_Ref_Level_ELSDR([0 -30]); % 根據簡報 P.8 設定
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
% 1. 前處理: DC 移除與全域 AGC
rx_signal = rx_signal - mean(rx_signal); 
rx_agc = rx_signal / rms(rx_signal);  

% 2. Matched Filter
rx_mf = conv(rx_agc, rrc_filter, 'same');

% 3. Symbol Timing Recovery
energy_per_phase = zeros(sps, 1);
for p = 0:sps-1
    energy_per_phase(p+1) = sum(abs(rx_mf(p+1:sps:end)).^2);
end
[~, best_p] = max(energy_per_phase);
rx_sync = rx_mf(best_p:sps:end);

%% 4. 封包偵測與 CFAR 同步
[R, lags] = xcorr(rx_sync, ref_preamble);
R_abs = abs(R);
[max_val, max_idx] = max(R_abs);
delay_syms = lags(max_idx);

% 動態門檻判斷 (模擬 CFAR 精神)
noise_floor = mean(R_abs);
dynamic_threshold = noise_floor * 4; % 設定 CFAR 門檻倍率
if max_val < dynamic_threshold
    warning('警告：未偵測到明顯封包，相關性峰值低於動態門檻。距離可能過遠或無訊號。');
end

if delay_syms < 0 || (delay_syms + 100 > length(rx_sync))
    error('同步失敗：找不到封包起點或擷取長度不足');
end

start_idx = delay_syms + 1;
preamble_rx = rx_sync(start_idx : start_idx + length(ref_preamble) - 1);

%% 5. 通道估測與 Zero-Forcing
% 取完整的 63 BPSK Preamble 進行通道頻率響應估測
H_est = sum(preamble_rx .* conj(ref_preamble)) / sum(abs(ref_preamble).^2);
rx_eq = rx_sync / H_est;

%% 6. 解調 (混合 BPSK 與 16-QAM)
% (A) 解調 BPSK (標頭解析提取長度資訊)
start_len_idx = start_idx + length(ref_preamble);
rx_len_syms = rx_eq(start_len_idx : start_len_idx + 7);
rx_len_bits = real(rx_len_syms) < 0;
rx_msg_len = bi2de(rx_len_bits.', 'left-msb');

% (B) 解調 16-QAM (Scrambled Payload)
start_qam_idx = start_len_idx + 8;
qam_sym_len = ceil((rx_msg_len * 8) / k_bits); 

if start_qam_idx + qam_sym_len - 1 > length(rx_eq)
    error('接收數據被截斷，無法解碼完整 Payload');
end
rx_qam_syms = rx_eq(start_qam_idx : start_qam_idx + qam_sym_len - 1);

rx_indices = zeros(length(rx_qam_syms), 1);
for i = 1:length(rx_qam_syms)
    [~, min_idx] = min(abs(rx_qam_syms(i) - ref_constellation));
    rx_indices(i) = min_idx - 1;
end

rx_bits = de2bi(rx_indices, k_bits, 'left-msb').';
rx_bits = rx_bits(:);

% (C) Descramble
descrambler = comm.Descrambler(2, [1 1 1 0 1], 'InitialConditions', [0 0 0 0]);
rx_payload_descrambled = descrambler(rx_bits);
rx_payload_descrambled = rx_payload_descrambled(1 : rx_msg_len * 8);

rx_msg_matrix = reshape(rx_payload_descrambled, 8, []).';
rx_ascii = bi2de(rx_msg_matrix, 'left-msb');
rx_str = char(rx_ascii.');

%% 7. 誤差計算與結果繪圖
% (D) EVM 分析與 SNR 計算 (根據簡報 P.9 算式)
ideal_qam_syms = ref_constellation(rx_indices + 1).';
error_vec = rx_qam_syms(:) - ideal_qam_syms(:);

evm_rms_ratio = sqrt(mean(abs(error_vec).^2) / mean(abs(ref_constellation).^2));
est_snr = 10 * log10(1 / (evm_rms_ratio^2));
evm_rms_pct = evm_rms_ratio * 100;

% 符合簡報 P.10 的 Command Window 輸出
fprintf('\n');
fprintf('成功! Msg: %s  SNR: %.2f dB (EVM: %.2f%%)\n', rx_str, est_snr, evm_rms_pct);
fprintf('\n');

% 繪圖設定 (符合簡報要求)
figure('Name', '16-QAM SDR Result', 'Color', 'w', 'Position', [200, 150, 500, 500]);
plot(real(rx_qam_syms), imag(rx_qam_syms), 'b.', 'MarkerSize', 8); hold on;
plot(real(ref_constellation), imag(ref_constellation), 'r+', 'MarkerSize', 10, 'LineWidth', 2);
title(sprintf('16-QAM (SNR: %.2f dB)', est_snr)); % 依照簡報 P.10 的標題格式
xlabel('I'); ylabel('Q'); 
grid on; axis square;
xlim([-2 2]); ylim([-2 2]);