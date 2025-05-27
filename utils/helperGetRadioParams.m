function ofdmRadioParams = helperGetRadioParams(sysParams, radioDevice, sampleRate, centerFrequency, gain, channelmapping, mode, enableBurstMode)
% helperGetRadioParams 为收发配置生成USRP参数
% 参数：
%   sysParams       - 系统参数结构体
%   radioDevice     - 无线电设备类型
%   sampleRate      - 采样率
%   centerFrequency - 中心频率
%   gain            - 增益
%   channelmapping  - 通道映射
%   mode            - 模式，'tx'或'rx'
%   enableBurstMode - 启用突发模式（可选）

% % 检查 mode 参数是否被输入
% if ~exist('mode', 'var')
%     error('Mode must be specified as either "tx" or "rx".');
% end

% 配置公共参数
ofdmRadioParams.RadioDevice     = radioDevice;
ofdmRadioParams.CenterFrequency = centerFrequency;
ofdmRadioParams.Gain            = gain;
ofdmRadioParams.channelmapping  = channelmapping;
ofdmRadioParams.SampleRate      = sampleRate;
ofdmRadioParams.NumFrames      = sysParams.numFrames;        % 发送帧数
ofdmRadioParams.txWaveformSize = sysParams.txWaveformSize;     % 发送波形大小
ofdmRadioParams.modOrder       = sysParams.modOrder;

% % 通过 mode 区分不同收发配置
% if strcmpi(mode, 'tx')
%     ofdmRadioParams.NumFrames      = sysParams.numFrames;        % 发送帧数
%     ofdmRadioParams.txWaveformSize = sysParams.txWaveformSize;     % 发送波形大小
%     ofdmRadioParams.modOrder       = sysParams.modOrder;
% elseif strcmpi(mode, 'rx')
%     ofdmRadioParams.NumFrames      = sysParams.numFrames;        % 接收帧数
%     ofdmRadioParams.txWaveformSize   = sysParams.txWaveformSize;       % 接收缓存大小
%     ofdmRadioParams.modOrder       = sysParams.modOrder;
% else
%     error('Invalid mode. Choose "tx" for transmission or "rx" for reception.');
% end

% 启用突发模式（可选）
if nargin > 7
    ofdmRadioParams.enableBurstMode = enableBurstMode;
else
    ofdmRadioParams.enableBurstMode = false; % 默认关闭突发模式
end

% 设置 USRP 设备的 Master Clock Rate
if ~strcmpi(radioDevice, 'PLUTO')
    foundUSRPs = findsdru;
    deviceStatus = foundUSRPs({foundUSRPs.Platform} == radioDevice);
    if ~isempty(deviceStatus)
        if matches(radioDevice, {'B200', 'B210'})
            ofdmRadioParams.SerialNum = deviceStatus(1).SerialNum;
        else
            ofdmRadioParams.IPAddress = deviceStatus(1).IPAddress;
        end
    else
        error("USRP Device %s not found", radioDevice);
    end

    % 根据设备设置 MasterClockRate
    switch radioDevice
        case {'B200', 'B210'}
            masterClockRate = sampleRate * 2;
        case {'N320/N321'}
            masterClockRate = 245.76e6;
        case {'X310', 'X300'}
            masterClockRate = 184.32e6;
        case {'N310', 'N300'}
            masterClockRate = 122.88e6; % 默认速率
        otherwise
            error('Unsupported radio device');
    end
    ofdmRadioParams.MasterClockRate = masterClockRate;
    ofdmRadioParams.InterpDecim = masterClockRate / sampleRate;
end
end
