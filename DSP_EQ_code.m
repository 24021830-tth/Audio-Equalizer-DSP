classdef DSP_EQ < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure            matlab.ui.Figure
        StopButton          matlab.ui.control.Button
        ChoiceButton        matlab.ui.control.Button
        TrebleSlider        matlab.ui.control.Slider
        TrebleSliderLabel   matlab.ui.control.Label
        HighmidSlider       matlab.ui.control.Slider
        HighmidSliderLabel  matlab.ui.control.Label
        MidSlider           matlab.ui.control.Slider
        MidSliderLabel      matlab.ui.control.Label
        LowmidSlider        matlab.ui.control.Slider
        LowmidSliderLabel   matlab.ui.control.Label
        BassSlider          matlab.ui.control.Slider
        Label               matlab.ui.control.Label
        UIAxes              matlab.ui.control.UIAxes
    end


   properties (Access = private)
        x_goc           % Âm thanh gốc
        fs              % Tần số lấy mẫu
        x_bass
        x_lowmid
        x_mid
        x_highmid
        x_treble
        x_out           % Âm thanh sau khi Mix
        AudioPlayerObj  % Trình phát nhạc
    end
    % =========================================================================
    % PRIVATE METHODS (HÀM XỬ LÝ LÕI)
    % =========================================================================
    methods (Access = private)
        function updateMixer(app)
            % 1. Đọc giá trị trực tiếp từ thanh trượt
            gain_bass = app.BassSlider.Value;
            gain_lowmid = app.LowmidSlider.Value;
            gain_mid = app.MidSlider.Value;
            gain_highmid = app.HighmidSlider.Value;
            gain_treble = app.TrebleSlider.Value;
            
            % 2. Mixer tín hiệu
            app.x_out = (gain_bass * app.x_bass) + (gain_lowmid * app.x_lowmid) + ... 
                        (gain_mid * app.x_mid) + (gain_highmid * app.x_highmid) + ...
                        (gain_treble * app.x_treble);
                        
            % 3. Chuẩn hóa để tránh rè loa
            max_val = max(abs(app.x_out));
            if max_val > 0
                app.x_out = app.x_out / max_val;
            end
            
            % 4. Cập nhật nhạc và đồ thị
            if isprop(app, 'AudioPlayerObj') && ~isempty(app.AudioPlayerObj) && isplaying(app.AudioPlayerObj)
                current_pos = app.AudioPlayerObj.CurrentSample;
                stop(app.AudioPlayerObj);
                
                app.AudioPlayerObj = audioplayer(app.x_out, app.fs);
                play(app.AudioPlayerObj, current_pos); 
                startFFT(app); % Chạy lại đồ thị
            end
        end

        function startFFT(app)
            window_size = 2048; 
            f = app.fs * (0:(window_size/2)) / window_size; 
            
            while isprop(app, 'AudioPlayerObj') && ~isempty(app.AudioPlayerObj) && isplaying(app.AudioPlayerObj)
                current_sample = app.AudioPlayerObj.CurrentSample;
                if current_sample > window_size && current_sample < length(app.x_out)
                    audio_chunk = app.x_out(current_sample - window_size : current_sample - 1);
                    
                    Y = fft(audio_chunk);
                    P2 = abs(Y / window_size);
                    P1 = P2(1 : window_size/2 + 1);
                    P1(2:end-1) = 2*P1(2:end-1);
                    P1_dB = 20*log10(P1 + 1e-6);
                    
                    plot(app.UIAxes, f, P1_dB, 'Color', 'cyan', 'LineWidth', 1.5);
                    xlim(app.UIAxes, [0 20000]); 
                    ylim(app.UIAxes, [-60 40]);  
                    drawnow; 
                end
                pause(0.02); 
            end
        end
         
    end
             
    % =========================================================================
    % CALLBACKS (HÀM SỰ KIỆN GIAO DIỆN)
    % =========================================================================

    % Callbacks that handle component events
    methods (Access = private)

        % Button pushed function: ChoiceButton
        function ChoiceButtonPushed(app, event)
           % Mở hộp thoại chọn file (hỗ trợ cả wav, mp3, flac)
            [file, path] = uigetfile({'*.wav;*.mp3;*.flac', 'Audio Files (*.wav, *.mp3, *.flac)'; '*.*', 'All Files (*.*)'}, 'Chọn bài hát');
            if isequal(file, 0); return; end
            
            % Nạp file và chuyển Mono
            filename = fullfile(path, file);
            [x, app.fs] = audioread(filename);
            if size(x, 2) == 2
                x = mean(x, 2);
            end
            app.x_goc = x;
            
            % Thiết kế bộ lọc và tách dải
            fn = app.fs / 2; 
            n = 4; 
            
            [z1, p1, G1] = butter(n, [20/fn, 250/fn], "bandpass"); 
            [b_bass, g_bass] = zp2sos(z1, p1, G1); 
            app.x_bass = filtfilt(b_bass, g_bass, app.x_goc);
            
            [z2, p2, G2] = butter(n, [250/fn, 500/fn], 'bandpass');
            [b_lmid, g_lmid] = zp2sos(z2, p2, G2);
            app.x_lowmid = filtfilt(b_lmid, g_lmid, app.x_goc);
            
            [z3, p3, G3] = butter(n, [500/fn, 2000/fn], "bandpass");
            [b_mid, g_mid] = zp2sos(z3, p3, G3);
            app.x_mid = filtfilt(b_mid, g_mid, app.x_goc);
            
            [z4, p4, G4] = butter(n, [2000/fn, 4000/fn], "bandpass");
            [b_hmid, g_hmid] = zp2sos(z4, p4, G4);
            app.x_highmid = filtfilt(b_hmid, g_hmid, app.x_goc);
            
            [z5, p5, G5] = butter(n, [4000/fn, 20000/fn], "bandpass");
            [b_tre, g_tre] = zp2sos(z5, p5, G5);
            app.x_treble = filtfilt(b_tre, g_tre, app.x_goc);
            
            % Trộn sẵn một bản mix mặc định ngay khi tải xong
            updateMixer(app);
            uialert(app.UIFigure, 'Đã tải và phân tách xong 5 dải tần!', 'Thành công');
        end

        % Value changed function: BassSlider
        function BassSliderValueChanged(app, event)
              
            updateMixer(app);
           
        end

        % Value changed function: MidSlider
        function MidSliderValueChanged(app, event)
            
            updateMixer(app);
           
        end

        % Value changed function: LowmidSlider
        function LowmidSliderValueChanged(app, event)
            
            updateMixer(app);
            
        end

        % Value changed function: HighmidSlider
        function HighmidSliderValueChanged(app, event)

            updateMixer(app);
            
        end

        % Value changed function: TrebleSlider
        function TrebleSliderValueChanged(app, event)
            
            updateMixer(app);
         
        end

        % Button pushed function: StopButton
        function StopButtonPushed(app, event)
          % 1. Kiểm tra xem đã có dữ liệu âm thanh chưa
if isempty(app.x_out)
    uialert(app.UIFigure, 'Bạn chưa tải file nhạc!', 'Thông báo');
    return;
end

% 2. Điều khiển Phát / Tạm dừng theo thời gian thực
if isempty(app.AudioPlayerObj)
    % Lần đầu tiên mở App và bấm nút -> Phát từ đầu bài
    app.AudioPlayerObj = audioplayer(app.x_out, app.fs);
    play(app.AudioPlayerObj);
    app.StopButton.Text = 'Stop'; % Đổi chữ hiển thị thành Stop
    startFFT(app); % Kích hoạt màn hình FFT nhảy múa
    
elseif ~isplaying(app.AudioPlayerObj)
    % Đang TẠM DỪNG -> Tiếp tục phát tiếp đúng vị trí cũ (Resume)
    resume(app.AudioPlayerObj);
    app.StopButton.Text = 'Stop'; % Đổi chữ hiển thị thành Stop
    startFFT(app); % Gọi lại đồ thị FFT chạy tiếp theo nhịp nhạc
    
else
    % Đang PHÁT -> Tạm dừng nhạc lại tại vị trí hiện tại (Pause)
    pause(app.AudioPlayerObj);
    app.StopButton.Text = 'Play'; % Đổi chữ hiển thị thành Play
end
        end

        % Button down function: UIAxes
        function UIAxesButtonDown(app, event)
                
        end
    end

    % Component initialization
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)

            % Create UIFigure and hide until all components are created
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Color = [0.902 0.902 0.902];
            app.UIFigure.Position = [100 100 640 480];
            app.UIFigure.Name = 'MATLAB App';

            % Create UIAxes
            app.UIAxes = uiaxes(app.UIFigure);
            title(app.UIAxes, 'FFT')
            xlabel(app.UIAxes, 'X')
            ylabel(app.UIAxes, 'Y')
            zlabel(app.UIAxes, 'Z')
            app.UIAxes.ButtonDownFcn = createCallbackFcn(app, @UIAxesButtonDown, true);
            app.UIAxes.Position = [1 196 640 285];

            % Create Label
            app.Label = uilabel(app.UIFigure);
            app.Label.HorizontalAlignment = 'right';
            app.Label.Position = [11 175 62 22];
            app.Label.Text = 'BassSlider';

            % Create BassSlider
            app.BassSlider = uislider(app.UIFigure);
            app.BassSlider.Limits = [0 5];
            app.BassSlider.ValueChangedFcn = createCallbackFcn(app, @BassSliderValueChanged, true);
            app.BassSlider.Position = [95 184 150 3];
            app.BassSlider.Value = 1;

            % Create LowmidSliderLabel
            app.LowmidSliderLabel = uilabel(app.UIFigure);
            app.LowmidSliderLabel.HorizontalAlignment = 'right';
            app.LowmidSliderLabel.Position = [346 175 77 22];
            app.LowmidSliderLabel.Text = 'LowmidSlider';

            % Create LowmidSlider
            app.LowmidSlider = uislider(app.UIFigure);
            app.LowmidSlider.Limits = [0 5];
            app.LowmidSlider.ValueChangedFcn = createCallbackFcn(app, @LowmidSliderValueChanged, true);
            app.LowmidSlider.Position = [445 184 150 3];
            app.LowmidSlider.Value = 1;

            % Create MidSliderLabel
            app.MidSliderLabel = uilabel(app.UIFigure);
            app.MidSliderLabel.HorizontalAlignment = 'right';
            app.MidSliderLabel.Position = [24 108 55 22];
            app.MidSliderLabel.Text = 'MidSlider';

            % Create MidSlider
            app.MidSlider = uislider(app.UIFigure);
            app.MidSlider.Limits = [0 5];
            app.MidSlider.ValueChangedFcn = createCallbackFcn(app, @MidSliderValueChanged, true);
            app.MidSlider.Position = [101 117 150 3];
            app.MidSlider.Value = 1;

            % Create HighmidSliderLabel
            app.HighmidSliderLabel = uilabel(app.UIFigure);
            app.HighmidSliderLabel.HorizontalAlignment = 'right';
            app.HighmidSliderLabel.Position = [343 118 80 22];
            app.HighmidSliderLabel.Text = 'HighmidSlider';

            % Create HighmidSlider
            app.HighmidSlider = uislider(app.UIFigure);
            app.HighmidSlider.Limits = [0 5];
            app.HighmidSlider.ValueChangedFcn = createCallbackFcn(app, @HighmidSliderValueChanged, true);
            app.HighmidSlider.Position = [445 127 150 3];
            app.HighmidSlider.Value = 1;

            % Create TrebleSliderLabel
            app.TrebleSliderLabel = uilabel(app.UIFigure);
            app.TrebleSliderLabel.HorizontalAlignment = 'right';
            app.TrebleSliderLabel.Position = [384 41 39 22];
            app.TrebleSliderLabel.Text = 'Treble';

            % Create TrebleSlider
            app.TrebleSlider = uislider(app.UIFigure);
            app.TrebleSlider.Limits = [0 5];
            app.TrebleSlider.ValueChangedFcn = createCallbackFcn(app, @TrebleSliderValueChanged, true);
            app.TrebleSlider.Position = [445 50 150 3];
            app.TrebleSlider.Value = 1;

            % Create ChoiceButton
            app.ChoiceButton = uibutton(app.UIFigure, 'push');
            app.ChoiceButton.ButtonPushedFcn = createCallbackFcn(app, @ChoiceButtonPushed, true);
            app.ChoiceButton.Position = [37 41 100 22];
            app.ChoiceButton.Text = 'Choice';

            % Create StopButton
            app.StopButton = uibutton(app.UIFigure, 'push');
            app.StopButton.ButtonPushedFcn = createCallbackFcn(app, @StopButtonPushed, true);
            app.StopButton.Position = [178 41 100 22];
            app.StopButton.Text = 'Stop';

            % Show the figure after all components are created
            app.UIFigure.Visible = 'on';
        end
    end

    % App creation and deletion
    methods (Access = public)

        % Construct app
        function app = DSP_EQ

            % Create UIFigure and components
            createComponents(app)

            % Register the app with App Designer
            registerApp(app, app.UIFigure)

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)

            % Delete UIFigure when app is deleted
            delete(app.UIFigure)
        end
    end
end