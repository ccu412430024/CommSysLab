%% 16-QAM Simulation
clc; clear; close all;

%% 1. 參數設定 (System Parameters)
Fs = 122.88e6;             % 取樣率 (Hz)
M = 16;                    % 16-QAM (調變階數)
k_bits = 4;                % 每符元位元數 (Bits per symbol, log2(M))
sps = 4;                   % 上/下取樣倍率 (Samples per symbol)

target_points = 50000;     % 發射端 Buffer 大小
capture_points = 100000;   % 接收端視窗長度

% --- RRC 脈衝成型濾波器參數 ---
Rolloff = 0.5;
FilterSpan = 10;
rrc_filter = rcosdesign(Rolloff, FilterSpan, sps, 'sqrt');

% --- 同步序列與標準星座表 ---
% 建立 16-QAM 標準星座點對照表 (平均功率歸一化為 1)
ref_constellation = qammod(0:M-1, M, 'UnitAveragePower', true);

%% 2. TX 發射端處理 (Transmitter)
Tx_Message = 'Hello world!! This is a fully automatic dynamic packet test 2026';
fprintf('發射內容 (%d bytes): %s\n', length(Tx_Message), Tx_Message);

% 產生 PN Sequence (63 bits) 用作 Preamble
lfsr = comm.PNSequence('Polynomial', [6 5 0], 'SamplesPerFrame', 63, 'InitialConditions', [0 0 0 0 0 1]);
pn_seq = lfsr();

% (A) 製作長度欄位 (8 bits)
msg_len = length(Tx_Message);
if msg_len > 255
    error('錯誤：訊息長度超過 1 byte (255) 上限');
end
len_header = de2bi(msg_len, 8, 'left-msb').';

% (B) 內文處理：轉二進位 + 擾碼
msg_ascii = double(Tx_Message);
msg_bits = de2bi(msg_ascii, 8, 'left-msb')';
msg_bits = msg_bits(:);

% Data Scrambling (將原始資料位元與擾碼種子進行 XOR)
scrambler = comm.Scrambler(2, [1 1 1 0 1], 'InitialConditions', [0 0 0 0]);
scrambled_payload = scrambler(msg_bits);

% (C) BPSK + 16QAM Modulation
% Preamble & Length 使用 BPSK
bpsk_bits = [pn_seq; len_header]; % 63 + 8 = 71 bits
tx_bpsk_syms = 1 - 2 * bpsk_bits; % BPSK 映射: 0->1, 1->-1

% Payload 使用 16-QAM
% Padding 補零使長度為 4 的倍數
num_pad = mod(k_bits - mod(length(scrambled_payload), k_bits), k_bits);
payload_padded = [scrambled_payload; zeros(num_pad, 1)];
% Bit to Symbol mapping
payload_indices = bi2de(reshape(payload_padded, k_bits, []).', 'left-msb');
tx_qam_syms = ref_constellation(payload_indices + 1).';

% Packet Assembly (串接 BPSK Header 與 16-QAM Payload)
tx_symbols = [tx_bpsk_syms; tx_qam_syms];

% Up-sampling & RRC Pulse Shaping Filter
tx_baseband = upfirdn(tx_symbols, rrc_filter, sps);

%% 3. 通道模擬 (Simulated Channel)
SNR_dB = 15; % 模擬通道訊雜比

% 模擬延遲 (Time Offset)
delay_samples = randi([1000, 5000]);
rx_raw_sim = [zeros(delay_samples, 1); tx_baseband; zeros(capture_points, 1)];
rx_raw_sim = rx_raw_sim(1:capture_points);

% 模擬未知相位偏移 (Phase Offset)
phase_offset = exp(1j * rand() * 2 * pi);
rx_raw_sim = rx_raw_sim * phase_offset;

% 加入 AWGN (白雜訊)
sig_pwr_dBW = 10 * log10(mean(abs(tx_baseband).^2));
rx_raw = awgn(rx_raw_sim, SNR_dB, sig_pwr_dBW);

%% 4. 接收端處理 (Receiver)
% --- 1. 前處理: DC 移除與全域 AGC ---
rx_raw = rx_raw - mean(rx_raw); % 減去訊號平均值
rx_agc = rx_raw / rms(rx_raw);  % 正規化平均功率為 1

% --- 2. Matched Filter (RRC 匹配濾波) ---
rx_mf = conv(rx_agc, rrc_filter, 'same');

% --- 3. Symbol Timing Recovery (時序回復) ---
% 找出最佳取樣點 (最大化能量)
energy_per_phase = zeros(sps, 1);
for p = 0:sps-1
    energy_per_phase(p+1) = sum(abs(rx_mf(p+1:sps:end)).^2);
end
[~, best_p] = max(energy_per_phase);
best_p = best_p - 1;

% Down sampling (降取樣取得符元序列)
rx_sync = rx_mf(best_p+1:sps:end);

% --- 4. 封包偵測與同步 (Sliding Cross-Correlation) ---
ref_preamble = 1 - 2 * pn_seq; % 本地已知 Preamble 波形
[R, lags] = xcorr(rx_sync, ref_preamble);

% 尋找波峰 (此處簡化為直接尋找最大值，實務上可套用 PPT 中的 Dynamic Threshold)
[~, max_idx] = max(abs(R));
delay_syms = lags(max_idx);

if delay_syms < 0
    error('同步失敗：找不到封包起點');
end

% 擷取封包
start_idx = delay_syms + 1;
preamble_rx = rx_sync(start_idx : start_idx + length(ref_preamble) - 1);

% --- 5. 通道估測與等化 (LS Channel Est. & Zero-Forcing) ---
% Least Square Channel Estimation
H_est = sum(preamble_rx .* conj(ref_preamble)) / sum(abs(ref_preamble).^2);

% Zero-Forcing Equalization (補償振幅衰減與相位旋轉)
rx_eq = rx_sync / H_est;

% 擷取 Header 與 Payload 符元
rx_bpsk_eq = rx_eq(start_idx : start_idx + length(bpsk_bits) - 1);
start_qam_idx = start_idx + length(bpsk_bits);

% 先從 Header 讀取訊息長度
rx_len_syms = rx_bpsk_eq(64:71); % 取得長度欄位 8 bits
rx_len_bits = real(rx_len_syms) < 0; % BPSK 硬判決
rx_msg_len = bi2de(rx_len_bits.', 'left-msb');

% 計算 Payload 應有的 16-QAM Symbol 數量
qam_sym_len = ceil((rx_msg_len * 8) / k_bits); 
rx_qam_eq = rx_eq(start_qam_idx : start_qam_idx + qam_sym_len - 1);

%% 5. 解調 (Demodulation & Parsing)
% Hard Decision (最小歐幾里德距離)
rx_indices = zeros(length(rx_qam_eq), 1);
for i = 1:length(rx_qam_eq)
    [~, min_idx] = min(abs(rx_qam_eq(i) - ref_constellation));
    rx_indices(i) = min_idx - 1;
end

% Symbol De-mapping (查表轉換為二進制)
rx_bits = de2bi(rx_indices, k_bits, 'left-msb').';
rx_bits = rx_bits(:);

% Descrambling (解除擾碼)
% 必須建立獨立的 Descrambler 物件，確保解擾碼的初始狀態與發射端完全一致
descrambler = comm.Descrambler(2, [1 1 1 0 1], 'InitialConditions', [0 0 0 0]);
rx_payload_descrambled = descrambler(rx_bits);
rx_payload_descrambled = rx_payload_descrambled(1 : rx_msg_len * 8); % 移除補零位元

% ASCII Decoding (重建文字)
rx_msg_matrix = reshape(rx_payload_descrambled, 8, []).';
rx_ascii = bi2de(rx_msg_matrix, 'left-msb');
rx_str = char(rx_ascii.');

%% 6. 結果分析 (Results)
fprintf('\n----------------------------------------\n');
fprintf('解碼訊息: "%s"\n', rx_str);
fprintf('----------------------------------------\n');

% 誤差向量幅度計算 (EVM Analysis)
S_ideal = ref_constellation(rx_indices + 1).';
error_vec = rx_qam_eq - S_ideal;
evm_rms = sqrt(mean(abs(error_vec).^2) / mean(abs(S_ideal).^2)) * 100;
est_snr = -20 * log10(evm_rms/100);

fprintf('EVM (RMS): %.2f%%\n', evm_rms);
fprintf('Estimated SNR: %.2f dB\n', est_snr);

% 繪製星座圖
figure('Name', '16-QAM Simulation', 'Color', 'w', 'Position', [100, 100, 900, 450]);

% 繪製等化前星座圖
subplot(1,2,1);
plot(rx_sync(start_qam_idx : start_qam_idx + qam_sym_len - 1), 'b.', 'MarkerSize', 8);
title('等化前接收星座圖 (含相位與通道衰減)');
xlabel('In-Phase (I)'); ylabel('Quadrature (Q)');
grid on; axis square; xlim([-2 2]); ylim([-2 2]);

% 繪製等化後星座圖
subplot(1,2,2);
plot(rx_qam_eq, 'b.', 'MarkerSize', 8);
hold on;
plot(ref_constellation, 'r+', 'MarkerSize', 10, 'LineWidth', 2);
title(sprintf('等化後 16-QAM 星座圖 (EVM: %.1f%%)', evm_rms));
xlabel('In-Phase (I)'); ylabel('Quadrature (Q)');
legend('接收符元 (x_d[k])', '標準理想點', 'Location', 'best');
grid on; axis square; xlim([-1.5 1.5]); ylim([-1.5 1.5]);