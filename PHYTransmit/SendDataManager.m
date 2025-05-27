function txDiagnosticsAll = SendDataManager()
% SendDataManager - 在后台运行, 不需要任何输入参数
%                  在函数开头自己初始化内存映射句柄, 并检查interrupt标志
%
% 核心逻辑:
%   1. 通过 initStateMemmap() 打开/创建 UE_connection_state.bin 并得到m_connectStage
%   2. 通过 interrupt_reception_flag.bin 控制无限循环
%   3. 当 m_connectStage.Data.flag == 1 时, 生成并保存波形, 然后置flag=0
%   4. 不再根据阶段生成文本消息, 因为 ueConnectionStateManager 已经写好
%
% 注意:
%   - 需在外部先初始化 interrupt_reception_flag.bin, 并将其值置为1
%   - 当需要退出SendDataManager时, 将interrupt_reception_flag.bin置为0

    %=== 1) 初始化内存映射 (阶段 & flag) ===
    root_stagefile = './MAC/cache_file/';
    binName   = 'UE_connection_state.bin';  
    binFullPath = fullfile(root_stagefile, binName);
    m_connectState = initStateMemmap(binFullPath); 
    % 现在 m_connectStage.Data.stage / m_connectStage.Data.flag 可用

    %=== 2) interrupt标志文件, 控制循环退出 ===
    root_rx = "./PHYReceive/cache_file/";
    flagFileName = 'interrupt_reception_flag.bin'; % 中断标志文件
    filename4 = fullfile(root_rx, flagFileName);
    if ~isfile(filename4)
        error('Interrupt flag file does not exist. Please initialize it in the main program.');
    end
    m_receiveCtlflag = memmapfile(filename4, 'Writable', true, 'Format', 'int8');
    % 当 m_receiveCtlflag.Data(1) == 0 时退出循环

    %=== 3) 其他需要的标志文件(示例) ===
    root_tx = "./PHYTransmit/cache_file/";
    sendFlagFileName = 'Send_flag.bin';
    filenameSendFlag = fullfile(root_tx, sendFlagFileName);
    if ~isfile(filenameSendFlag)
        fid = fopen(filenameSendFlag, 'w');
        fwrite(fid, 0, 'int8');  % 初始化
        fclose(fid);
    end
    m_sendDataFlag = memmapfile(filenameSendFlag, 'Writable', true, 'Format', 'int8');

    %=== 4) 用于保存最终生成的波形 ===
    waveformFileName = 'current_waveform.mat';
    waveformFilePath = fullfile(root_tx, waveformFileName);

    %=== 5) 初始化返回值数组(存放txDiagnostics) ===
    txDiagnosticsAll = {};

    %=== 6) UL分集接收中，UE上来直接发送数据，所以flag置为1先发一次 ===
    m_connectState.Data.flag = int8(1);
    if m_connectState.Data.flag == 1
        txDiagnostics = generateAndSaveWaveform(waveformFilePath);
        txDiagnosticsAll{end+1} = txDiagnostics;
        % 告知下游(或USRP)有新数据
        m_sendDataFlag.Data(1) = 1;
        % 清除flag
        m_connectState.Data.flag = int8(0);
    end

    %=== 7) 主循环 ===
    while m_receiveCtlflag.Data(1) == 1
        if m_connectState.Data.flag == 1
            if m_connectState.Data.stage == 0
                % 这是一个不寻常的情况，这种情况只发生在连接中断超时后的重置条件下
                % 此时应当在UE处中断当前传输，静默，等待下一个CBS广播信息
                m_sendDataFlag.Data(1) = 2; % 使用特殊的值：2，来表示这种情况
                
                % 清除flag
                m_connectState.Data.flag = int8(0);
            else
                % 说明 ueConnectionStateManager 那边有新消息要发
                txDiagnostics = generateAndSaveWaveform(waveformFilePath);
                txDiagnosticsAll{end+1} = txDiagnostics;
    
                % 告知下游(或USRP)有新数据
                m_sendDataFlag.Data(1) = 1;
    
                % 清除flag
                m_connectState.Data.flag = int8(0);
            end
        end

        pause(10/1000);  % 每10ms检查一次, 视实际需求可改
    end

    disp('SendDataManager exited safely.');
end

%% 仅示例: 生成&保存USRP波形
function txDiagnostics = generateAndSaveWaveform(waveformFilePath)
    [txWaveform, txDiagnostics] = generateUSRPWaveform();
    saveTxWaveform(waveformFilePath, txWaveform);
end

function [txWaveform, txDiagnostics] = generateUSRPWaveform()
    % generateUSRPWaveform: 生成用于 USRP 发送的波形
    %
    % 使用基于 JSON 文件初始化的 PHY 参数生成发送波形。
    % 返回：
    %   txWaveform - 生成的发送波形
    %   txDiagnostics - 发送诊断信息

    % 初始化上行发送参数 (从 JSON 文件加载, 该JSON文件由控制基站端通过控制信令下发到用户设备（UE）端)
    PHYParams = initializePHYParams('uplink');

    % 配置功能参数（与控制基站端控制信令传输无关，取决于本地配置和更改）
    cfg = struct();
    cfg.enableScopes = false;
    cfg.verbosity = false;
    cfg.printData = false;
    cfg.enableConst_measure = false;

    % 格式化 PHY 参数
    [OFDMParams, dataParams] = reformatPHYParams(PHYParams, cfg);

    % 生成系统参数并从文件中加载数据
    [sysParam, txParam, trBlk] = helperOFDMSetParamsSDR(OFDMParams, dataParams, 'tx');

    % 初始化发送对象
    txObj = helperOFDMTxInit(sysParam);

    % 传输数据块
    txParam.txDataBits = trBlk;

    % 生成发送波形
    [txOut, txGrid, txDiagnostics] = helperOFDMTx(txParam, sysParam, txObj);

    % 如果启用了显示，绘制资源网格
    if dataParams.verbosity
        helperOFDMPlotResourceGrid(txGrid, sysParam);
    end

    % 输出波形和诊断信息
    txWaveform = txOut;
end

function saveTxWaveform(filename, txWaveform)
    save(filename, 'txWaveform');
end

