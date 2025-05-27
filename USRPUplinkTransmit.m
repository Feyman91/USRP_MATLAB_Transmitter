%% 主函数 main.m
clear
clear captureData
close all

% 启用 diary 记录终端输出
startLogging();

%% 初始化USRP硬件参数
radioConfig = 'My USRP X310';  % Baseband transceiver 配置
bbtrx = basebandTransceiver(radioConfig);  % 初始化 basebandTransceiver 对象

%% 初始化UE上行发射机参数 (从 JSON 文件加载, 该文件参数是控制基站与UE控制信令传输时协商好的协议，由setDefaultParams脚本生成)
% 原本这里初始化的是下行接收机的参数，但这里的PHYParam.json参数文件里只配置了上行发送机参数（用于上行分集接收实验调试）
% 故代码写为初始化uplink的参数
% PHYParams = initializePHYParams('downlink');
PHYParams = initializePHYParams('uplink');

UE_ID = PHYParams.UE_ID;

% 这些参数用于计算通过内存映射文件能存储的接收message总数的统计情况
FFTlength = PHYParams.FFTLength;
cplen = FFTlength * PHYParams.CPFraction;
scs = PHYParams.Subcarrierspacing;  % Subcarrier spacing (30 kHz)
sampleRate = FFTlength * scs;  % 计算采样率
SymbolsPerFrame = PHYParams.numSymPerFrame;   % symbols
SamplesPerFrame = (FFTlength + cplen) * SymbolsPerFrame;

% 这个参数真正用于USRP接收机打开接收窗口的时间长度（持续捕获时间）
captureLength = milliseconds(5);

%% USRP无线参数设置
bbtrx.SampleRate = sampleRate;  % 设置 basebandTransceiver 对象的采样率
% Tx 参数
TXantenna = "RFA:TX/RX";        % 设置传输天线，例如 "RF0:TX/RX" 对于 N310
TXcenterFrequency = 2.38e9;     % 传输中心频率，单位为 Hz
TXgain = 27;                    % 传输增益，单位为 dB
% Rx 参数
RXCenterFrequency = 2.3e9;         % 接收中心频率，单位为 Hz
RXantenna = "RFA:RX2";              % 设置接收天线
RXgain = 10;                        % 接收增益，单位为 dB
RXDataType = "double";              % 数据类型
DroppedSamplesAction = "warning";   % 丢弃样本行为

verbosity = false;  % 是否打印调试信息

if verbosity
    % 输出初始配置信息，包括发送和接收配置
    disp(['Starting UE ', num2str(UE_ID), ' duplex communication with the following configuration:']);
    disp(['  Radio Config: ', radioConfig]);
    disp(['  Sample Rate: ', num2str(sampleRate), ' Hz (FFTlength: ', num2str(FFTlength), ' Subcarrier Spacing: ', num2str(scs), ')']);
    disp(' ');
    disp('  Transmission Parameters:');
    disp(['    TX Antenna: ', char(TXantenna)]);
    disp(['    TX Center Frequency: ', num2str(TXcenterFrequency), ' Hz']);
    disp(['    TX Gain: ', num2str(TXgain), ' dB']);
    disp(' ');
    disp('  Reception Parameters:');
    disp(['    RX Antenna: ', char(RXantenna)]);
    disp(['    RX Center Frequency: ', num2str(RXCenterFrequency), ' Hz']);
    disp(['    RX Gain: ', num2str(RXgain), ' dB']);
    disp(['    RX Data Type: ', char(RXDataType)]);
    disp(['    Dropped Samples Action: ', char(DroppedSamplesAction)]);
    disp(' ');
end

%% 配置上行发送以及下行接收USRP bbtrx对象（不进行实际传输，仅返回配置后的对象和生成的波形）
bbtrx = configureUplinkTxTransceiver(bbtrx, ...
    TXantenna, TXcenterFrequency, TXgain, radioConfig);
bbtrx = configureDownlinkRxTransceiver(bbtrx, ...
    RXantenna, RXCenterFrequency, RXgain, RXDataType, DroppedSamplesAction, radioConfig);

%% 配置初始化内存 buffer 映射文件
% 初始化中断持续接收循环的共享文件（存储中断flag 用）
root_rx = "./PHYReceive/cache_file/";
flagFileName = 'interrupt_reception_flag.bin';
filename4 = fullfile(root_rx, flagFileName);
if ~isfile(filename4)
    fid = fopen(filename4, 'w');
    fwrite(fid, 1, 'int8');  % flag置为1表示继续接收
    fclose(fid);
end
m_receiveCtlflag = memmapfile(filename4, 'Writable', true, 'Format', 'int8');
m_receiveCtlflag.Data(1) = 1;

% 发射端内存cache buffer配置
% 初始化发送数据信标flag共享文件（用于检测发送数据的变化）
root_tx = "./PHYTransmit/cache_file/";
sendFlagFileName = 'Send_flag.bin';
filename5 = fullfile(root_tx, sendFlagFileName);
if ~isfile(filename5)
    fid = fopen(filename5, 'w');
    fwrite(fid, 1, 'int8');  % 初始化 flag 为 0
    fclose(fid);
end
m_sendDataFlag = memmapfile(filename5, 'Writable', true, 'Format', 'int8');
% 在未接收到CBS的广播信息前，UE先保持静默
m_sendDataFlag.Data(1) = int8(0);
% 在上行多基站协作接收测试中，这个flag直接设置为1，让USRP一开始就发送上行数据
m_sendDataFlag.Data(1) = int8(1);

%% 启动发送数据管理程序（这里使用并行计算工具箱） 
% 异步运行发送数据管理程序
f = parfeval(@SendDataManager, 1);

%% 在上行、下行、处理缓冲区配置完成后，打开数据管道
isPipelineOpen = openDataPipeline(bbtrx);
fprintf('\nPress Enter to continue...');
input('');
fprintf('Running "stopTransmission(bbtrx)" function to stop TX....\n');
fprintf('Running "stop_receiving.m" script to stop RX....\n');

% % 指定运行时间（单位：秒）
% runTime = 40;  % 运行 40 秒
% tic;  % 开始计时

try 
    while m_receiveCtlflag.Data(1)
        % 检查发送新数据的 flag
        if m_sendDataFlag.Data(1) == 1
            % 如果检测到新的发送数据 flag，停止当前传输
            stopTransmission(bbtrx);
            % 调用发送函数发送新的数据
            txflag = transmitData(bbtrx, "continuous");
            % 重置发送数据的 flag
            m_sendDataFlag.Data(1) = 0;
        elseif m_sendDataFlag.Data(1) == 2
            % 这种情况是连接超时，重置连接阶段，需要停止UE端当前发送数据
            stopTransmission(bbtrx);
            % 重置发送数据的 flag
            m_sendDataFlag.Data(1) = 0;            
        end

        % 接收数据
        % 在上行多基站协作接收测试中，UE不需要接收数据,这里就暂停10ms以避免占用主机资源
        % rxDiagnostics = captureData(bbtrx, captureLength, m_receiveData);
        pause(10/1000)
    end
catch ME
    fprintf('Receiving terminated: %s\n', ME.message);
end

stopTransmission(bbtrx);
fprintf('\n********Stop transmitting!********\n');
% 获取返回值
txDiagnostics = fetchOutputs(f);
fprintf(f.Diary)
disp('********Retrieve txDiagnostics with SendDataManager from background!********')
disp("Main script completed successfully.");
diary off;  % 关闭日志功能
disp("close diary recording");
