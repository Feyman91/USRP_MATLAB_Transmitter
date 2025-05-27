function storeFrameBits(rxDataBits, mappedFile, rxDiagnostics)
    % storeFrameBits: 存储帧的比特流数据并更新元数据，支持循环存储
    % 
    % 输入参数：
    % mappedFile - 内存映射文件对象
    % framePointer - 当前帧指针
    % rxDataBits - 当前帧的比特流
    % rxDiagnostics - CRC 校验信息来源，其中包含 rxDiagnostics.dataCRCErrorFlag

    % 使用 persistent framePointer 来管理帧指针
    persistent framePointer;

    % 初始化 framePointer 为 1
    if isempty(framePointer)
        framePointer = 1;
    end

    % 当前帧的比特流长度
    bitLength = length(rxDataBits);

    % 计算起始和结束索引
    if framePointer == 1
        startIdx = 1;
    else
        prevEndIdx = mappedFile.Data.framemetadata(framePointer - 1, 4); % 上一帧的结束索引
        startIdx = prevEndIdx + 1;
    end

    % 结束索引
    endIdx = startIdx + bitLength - 1;

    % 检查是否超出存储空间
    maxStorageSize = length(mappedFile.Data.rxDataBits); % 最大存储大小
    if endIdx > maxStorageSize
        warning('比特流缓存空间不足，启用循环存储...');
        startIdx = 1;
        endIdx = bitLength;
    end

    % 判断目标存储区域是否已被使用(通过dataReadyFlag来判断）
    if mappedFile.Data.framemetadata(framePointer, 1) == 1
        error(['目标存储区域已被占用，不能覆盖未处理的信息。' ...
            '如果第一次解调出比特流时即遇到此错误，请在程序运行前使用flushmmapfile("bit cache")刷新缓存']);
    end

    % 写入比特流数据
    mappedFile.Data.rxDataBits(startIdx:endIdx) = rxDataBits;

    % 更新元数据
    crcErrorFlag = rxDiagnostics.dataCRCErrorFlag; % 从 rxDiagnostics 获取 CRC 校验结果
    dataReadyFlag = 1; % 表示数据已写入
    mappedFile.Data.framemetadata(framePointer, :) = [dataReadyFlag, bitLength, startIdx, endIdx, crcErrorFlag];

    % 更新 framePointer 并实现循环
    totalFrameReserved = size(mappedFile.Data.framemetadata, 1); % 总预留帧数
    framePointer = framePointer + 1;
    if framePointer > totalFrameReserved
        framePointer = 1; % 回绕到第一帧
        warning('frame record exceeds maximum size in memmapfile! recurrenting...');
    end
end
