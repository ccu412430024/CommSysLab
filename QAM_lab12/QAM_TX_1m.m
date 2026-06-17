%% 16-QAM Transmitter for SDR
clc; clear; close all;

%% 1. 參數設定 (System Parameters)
Fs = 122.88e6;             % 取樣率 (Hz)
CenterFreq_MHz = 433;      % 載波頻率 (MHz)
TX_Power_dBm = 0;          % 發射功率 (dBm) - 根據簡報 P.6 修改

M = 16;                    % 16-QAM (調變階數)
k_bits = 4;                % 每符元位元數 (Bits per symbol)
sps = 4;                   % Samples per Symbol (上取樣倍率)

% --- RRC 脈衝成型濾波器參數 ---
Rolloff = 0.5;
FilterSpan = 10;
rrc_filter = rcosdesign(Rolloff, FilterSpan, sps, 'sqrt');

% --- 標準星座表 ---
ref_constellation = qammod(0:M-1, M, 'UnitAveragePower', true);

%% 2. 動態產生資料封包 (Packet Generation)
Tx_Message = 'Hello world!! This is a fully automatic dynamic packet test 2026';
fprintf('準備發射內容 (%d bytes): %s\n', length(Tx_Message), Tx_Message);

% 產生 PN Sequence (63 bits) 用作 Preamble (BPSK)
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

scrambler = comm.Scrambler(2, [1 1 1 0 1], 'InitialConditions', [0 0 0 0]);
scrambled_payload = scrambler(msg_bits);

%% 3. BPSK + 16-QAM 調變
% (C1) Preamble & Length 使用 BPSK
bpsk_bits = [pn_seq; len_header]; % 63 + 8 = 71 bits
tx_bpsk_syms = 1 - 2 * bpsk_bits; 

% (C2) Payload 使用 16-QAM
num_pad = mod(k_bits - mod(length(scrambled_payload), k_bits), k_bits);
payload_padded = [scrambled_payload; zeros(num_pad, 1)];
payload_indices = bi2de(reshape(payload_padded, k_bits, []).', 'left-msb');
tx_qam_syms = ref_constellation(payload_indices + 1).';

% Packet Assembly
tx_symbols = [tx_bpsk_syms; tx_qam_syms];

%% 4. 脈衝成型與硬體格式轉換
tx_baseband = upfirdn(tx_symbols, rrc_filter, sps);

% 調整訊號振幅以符合 DAC 範圍 (+-1)
scale_factor = max(abs([real(tx_baseband); imag(tx_baseband)]));
tx_signal_norm = tx_baseband / scale_factor * 0.8;

% 轉成硬體 API 格式並重複以產生連續流
tx_data = repmat(tx_signal_norm.', 1, 100);

%% 5. SDR 硬體發射 (Hardware Transmission)
fprintf('\n--- 開始設定 SDR 硬體 ---\n');
try
    LO_CHANGE(0, CenterFreq_MHz, CenterFreq_MHz);
    set_TX_power([0 TX_Power_dBm]);
    fprintf('開始發射 16-QAM 訊號...\n');
    
    TX_start(tx_data, 0);
    
    fprintf('SDR 正在發射中。請開啟接收端程式碼進行自動解調。\n');
    fprintf('若要停止，請在 Command Window 輸入: TX_close\n');
catch
    warning('SDR 硬體未連接，僅完成數位訊號模擬。');
end