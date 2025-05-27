%% 初始化环境
clear;
clear helperOFDMRx helperOFDMRxFrontEnd helperOFDMRxSearch helperOFDMFrequencyOffset getTrParamsforSpecificBS_id;
clear processOneFrameData processDLRcvBSsDatadebug storeFrameBits
close all;
% flushmmapfile('bit cache')      % 用于刷新比特流读出缓存，调试时可以注释掉本行
% 启用 diary 记录终端输出
startLogging();

%% Initialize Receiver Parameters
% 全局 OFDM 参数, 该部分参数是与控制基站协商好的协议，为固定不更改值。

% 从 JSON 文件提取下行接收机PHY参数，该JSON文件由控制基站端通过控制信令下发到用户设备（UE）端
downlinkRcvParams = initializePHYParams('downlink');

% 配置接收机解调后处理参数（与控制基站端控制信令传输无关，取决于本地配置和更改）
cfg.enableCFO = true;
cfg.enableCPE = false;
cfg.enableChest = true;
cfg.enableHeaderCRCcheck = true;

cfg.enableTimescope = true;
cfg.enableScopes = true;
cfg.verbosity = false;
cfg.printData = false;
cfg.enableConst_measure = true;
watch_filteredResult = false;

% 初始化接收参数和工具
sysParamRxObj = setupSysParamsAndRxObjects(downlinkRcvParams, cfg);
visualizationTools = setupVisualizationTools(sysParamRxObj);
MeasurementTools = setupMeasurementTools(sysParamRxObj);

%% 初始化关键DMA内存映射
% 初始化缓存基带数据的文件路径与内存映射
root = "./PHYReceive/cache_file/";
filename = "received_buffer_new.bin";
filename1 = fullfile(root, filename);
% 初始化内存映射
totalMemorySizeInGB = 4; % 4GB 缓冲区
m_receiveData = InitMemmap(filename1, totalMemorySizeInGB);


% 初始化存储解调比特流的内存映射文件
% filename = "rxDataBits_shared.bin";
% fullpath = fullfile(root, filename);
% % 创建或初始化文件
% totalBitCacheSizeInMB = 50; % 50MB 缓冲区
% m_decodingBits = InitBitCachemap(fullpath, totalBitCacheSizeInMB);
% % 设置 readflag 为 1，表示允许读取解调比特流
% m_decodingBits.Data.readflag(1) = uint8(1);
m_decodingBits = 1; %这行保证程序跳过检查m_decodingBits是否初始化


% 初始化中断当前处理状态的共享文件（存储 中断flag 用）
flagFileName = 'interrupt_process_flag.bin';
filename3 = fullfile(root,flagFileName);
% 如果文件不存在，初始化并写入默认 flag 值
if ~isfile(filename3)
    fid = fopen(filename3, 'w');
    fwrite(fid, 1, 'int8');  % flag置为1表示继续处理
    fclose(fid);
end
% 创建内存映射文件对象
m_processCtlflag = memmapfile(filename3, 'Writable', true, 'Format', 'int8');
m_processCtlflag.Data(1) = 1;


% 初始化存储当前连接状态的共享文件
root_stagefile = './MAC/cache_file/';
binName   = 'UE_connection_state.bin';  
binFullPath = fullfile(root_stagefile, binName);
m_connectState = initStateMemmap(binFullPath);
%% 创建结构体存储每个基站的结果
readPointerStruct = struct();

maxMessages = 5000; % 预分配存储结果中的最大存储 message 的数量
maxFrames = 200;   % 预分配存储结果中的最大存储 frame 的数量
% 初始化与控制基站建立连接的结果存储
resultStruct.BER_collection = zeros(maxMessages,maxFrames); 
resultStruct.RSSI_collection = zeros(maxMessages,maxFrames);
resultStruct.EVM_collection.header = zeros(maxMessages,maxFrames);
resultStruct.EVM_collection.data = zeros(maxMessages,maxFrames);
resultStruct.MER_collection.header = zeros(maxMessages,maxFrames);
resultStruct.MER_collection.data = zeros(maxMessages,maxFrames);
resultStruct.CFO_collection = zeros(maxMessages,maxFrames);
resultStruct.dataRateCollection = zeros(maxMessages,maxFrames);
resultStruct.processTimePerFrame = zeros(maxMessages,maxFrames,'single');
resultStruct.previousTimePerBS = 0;
resultStruct.currentTimePerBS = 0;
resultStruct.totalBitsReceived = 0;
resultStruct.peakRate = zeros(maxMessages,1);
resultStruct.isConnected = zeros(maxMessages,maxFrames,'int8');

% 初始化帧读取指针和消息读取指针
readPointerStruct.frameprocesspointer = 1;
readPointerStruct.messageprocesspointer = m_receiveData.Data.writePointer;

%% Continuous Processing Loop

% 指定运行时间（单位：秒）
runTime = 20; % 运行 120 秒
% tic; % 开始计时

% while toc < runTime
while m_processCtlflag.Data(1)
     [rxDataBits, resultStruct, readPointerStruct,SigOccured_frameNum,...
         sysParamRxObj,visualizationTools,MeasurementTools] = ...
     processOneFrameData(sysParamRxObj, watch_filteredResult, m_receiveData, ...
        visualizationTools, ...
        MeasurementTools, ...
        resultStruct, readPointerStruct,m_decodingBits,m_connectState);

     % 在数据链路的传输中，不需要进行控制信令的管理，故注释
     % UEConnectionTimeoutMonitor(m_connectState,readPointerStruct,sysParamRxObj,resultStruct)
    
    % pause(0.01); % 等待 10ms
end

% 收集解调结果
allResults = struct();

allResults.result = resultStruct;
allResults.readPointer = readPointerStruct;
allResults.sysParamRxObj = sysParamRxObj;
allResults.visualizationTools = visualizationTools;
allResults.MeasurementTools = MeasurementTools;

% 设置 readflag为m_processCtlflag.Data(1)，程序结束，关闭处理比特流通道
% m_decodingBits.Data.readflag(1) = m_processCtlflag.Data(1);

fprintf('The next write pointer in Buffer: %d\n', m_receiveData.Data.writePointer)
diary off; % 关闭日志功能
disp("close diary recording")

