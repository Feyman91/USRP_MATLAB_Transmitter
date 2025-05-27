function mappedFile = InitBitCachemap(filename, totalBitCacheSizeInMB)
    % InitBitCachemap初始化存储解调比特流的内存映射文件
    %
    % Inputs:
    %   filename - Full path for the memory-mapped file
    %   totalBitCacheSizeInMB - Total memory size in MB for the 比特 cache file
    %
    % Output:
    %   m - Memory-mapped file handle

    % 参数设置
    total_frame_reserved = 5000;  % 预留的帧数量
    max_rxDataBits_size = totalBitCacheSizeInMB * 1024 * 1024;  % 比特流区域大小（字节数）
    framemetadata_columns = 5;  % metadata的列数framemetadata 用于记录每帧的解调状态和信息，列定义如下：
                                % 第 1 列：dataReadyFlag，表示帧是否解调完成。
                                % 第 2 列：totalBitsReceived，表示帧的比特数。
                                % 第 3 和 4 列：startIdx 和 endIdx，比特流存储的起始和结束索引。
                                % 第 5 列：dataCRCErrFlag，CRC 检测结果。
    
    % 空间划分大小
    readflag_size = 1;  % 单个 uint8
    framemetadata_size = total_frame_reserved * framemetadata_columns * 4;  % uint32占4字节

    % 初始化文件
    if ~isfile(filename)
        fid = fopen(filename, 'wb');
        % 初始化 readflag 为 0
        fwrite(fid, zeros(readflag_size, 1, 'uint8'), 'uint8');
        % 初始化 framemetadata 为全零的 uint32
        fwrite(fid, zeros(total_frame_reserved, framemetadata_columns, 'uint32'), 'uint32');
        % 初始化 rxDataBits 为全零的 uint8
        fwrite(fid, zeros(max_rxDataBits_size, 1, 'uint8'), 'uint8');
        fclose(fid);
    else
        % Validate file size
        fileInfo = dir(filename);
        expectedFileSize = readflag_size + framemetadata_size + max_rxDataBits_size;
        if fileInfo.bytes ~= expectedFileSize
            error('Bitstream File size mismatch: expected %d bytes, but found %d bytes.', expectedFileSize, fileInfo.bytes);
        else
            disp('Bitstream Memory-mapped file exists and matches expected size.');
        end
    end

    % 内存映射配置
    mappedFile = memmapfile(filename, ...
        'Writable', true, ...
        'Format', { ...
            'uint8', [1, 1], 'readflag'; ...  % 第一个片区
            'uint32', [total_frame_reserved, framemetadata_columns], 'framemetadata'; ... % 第二个片区
            'uint8', [max_rxDataBits_size, 1], 'rxDataBits' ... % 第三个片区
        });
    disp('Bitstream cache mapping initialized successfully.');
end
