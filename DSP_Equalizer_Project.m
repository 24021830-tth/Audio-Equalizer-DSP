% =========================================================================
% BƯỚC 1: ĐỌC VÀ TIỀN XỬ LÝ TÍN HIỆU
% =========================================================================
filename = 'test_audio.wav';
[x, fs] = audioread(filename);

% Chuyển Stereo sang Mono để đồng bộ kênh xử lý
if size(x, 2) == 2
    x = mean(x, 2);
end

% Vẽ đồ thị dạng sóng miền thời gian (Chỉ nên dùng khi test ngoại tuyến)
t = (0:length(x) - 1) / fs;
figure('Name', 'Waveform', 'NumberTitle', 'off');
plot(t, x, 'b');
xlabel('Thời gian (s)'); ylabel('Biên độ');
title('Dạng sóng tín hiệu gốc trong miền thời gian');

% =========================================================================
% BƯỚC 2: KHỞI TẠO VÀ PHÂN TÁCH 5 DẢI TẦN (IIR BUTTERWORTH BẬC 4)
% =========================================================================
fn = fs / 2; % Tần số Nyquist
n = 4;       % Bậc bộ lọc

% 1. Dải Bass (20Hz - 250Hz)
[z1, p1, G1] = butter(n, [20, 250]/fn, 'bandpass');
[b_bass, g_bass] = zp2sos(z1, p1, G1);
x_bass = filtfilt(b_bass, g_bass, x);

% 2. Dải Low-Mid (250Hz - 500Hz)
[z2, p2, G2] = butter(n, [250, 500]/fn, 'bandpass');
[b_lmid, g_lmid] = zp2sos(z2, p2, G2);
x_lowmid = filtfilt(b_lmid, g_lmid, x);

% 3. Dải Mid (500Hz - 2000Hz)
[z3, p3, G3] = butter(n, [500, 2000]/fn, 'bandpass');
[b_mid, g_mid] = zp2sos(z3, p3, G3);
x_mid = filtfilt(b_mid, g_mid, x);

% 4. Dải High-Mid (2000Hz - 4000Hz)
[z4, p4, G4] = butter(n, [2000, 4000]/fn, 'bandpass');
[b_hmid, g_hmid] = zp2sos(z4, p4, G4);
x_highmid = filtfilt(b_hmid, g_hmid, x);

% 5. Dải Treble (4000Hz - 20000Hz)
[z5, p5, G5] = butter(n, [4000, 20000]/fn, 'bandpass');
[b_tre, g_tre] = zp2sos(z5, p5, G5);
x_treble = filtfilt(b_tre, g_tre, x);

% Hiển thị Đồ thị Đặc tuyến (Chỉ vẽ 1 biểu đồ duy nhất chứa cả 5 dải)
pre = fvtool(b_bass, b_lmid, b_mid, b_hmid, b_tre, 'Fs', fs);
legend(pre, 'Bass (20-250 Hz)', 'Low-Mid (250-500 Hz)', ...
            'Mid (500-2000 Hz)', 'High-Mid (2000-4000 Hz)', ...
            'Treble (4000-20000 Hz)', 'Location', 'best');
title('Đáp ứng biên độ của 5 dải bộ lọc IIR');

% =========================================================================
% BƯỚC 3: PHỐI TRỘN TÍN HIỆU (MIXER)
% =========================================================================
% 1. Đọc hệ số Gain từ giao diện App Designer
gain_bass    = app.BassSlider.Value;
gain_lowmid  = app.LowmidSlider.Value;
gain_mid     = app.MidSlider.Value;
gain_highmid = app.HighmidSlider.Value;
gain_treble  = app.TrebleSlider.Value;

% 2. Xếp chồng tuyến tính (Tổ hợp các dải tần)
x_mix = (gain_bass    * x_bass)   + ...
        (gain_lowmid  * x_lowmid) + ... 
        (gain_mid     * x_mid)    + ...
        (gain_highmid * x_highmid)+ ...
        (gain_treble  * x_treble);

% 3. Chuẩn hóa (Normalization - Chống clipping)
app.x_out = x_mix / max(abs(x_mix)); 
app.fs = fs; % Lưu lại tần số lấy mẫu vào app

% =========================================================================
% BƯỚC 4: QUẢN LÝ LUỒNG PHÁT ÂM THANH
% =========================================================================
% Dọn dẹp luồng phát cũ nếu đang có nhạc chạy
if isprop(app, 'AudioPlayerObj') && ~isempty(app.AudioPlayerObj)
    stop(app.AudioPlayerObj);
end

% Khởi tạo và kích hoạt luồng phát mới
app.AudioPlayerObj = audioplayer(app.x_out, app.fs);
play(app.AudioPlayerObj);