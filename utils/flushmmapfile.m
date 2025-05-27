function flushmmapfile(mode)
    % FLUSHMEMORYMAPPEDFILE Resets the memory-mapped file based on the mode
    % Input:
    % mode - "all": resets both received buffer and bit cache
    %        "radio cache": resets only the received buffer
    %        "bit cache": resets only the bitstream cache
    %        empty or omitted: defaults to "all"

    if nargin < 1 || isempty(mode)
        mode = "radio cache";
        % fprintf('This will flush all memory map file!(including radio cache and bitstream cahce)\n');
        % fprintf('Press Enter to continue(or ctrl+C to stop)...');
        % input('');
    elseif ~ismember(mode, ["all", "radio cache", "bit cache"])
        error('Invalid mode. Supported values are "all", "radio cache", or "bit cache".');
    end

    % Common parameters
    defaultRoot = "./PHYReceive/cache_file/";

    % Reset "received_buffer_new.bin"
    if strcmp(mode, "all") || strcmp(mode, "radio cache")
        defaultFilename = "received_buffer_new.bin";
        filename_rcvmmap = fullfile(defaultRoot, defaultFilename);

        totalMemorySizeInGB = 4; % Default memory size (4 GB)

        headerSizePerMessage = 1;     % Header flag size per message (int8)
        metadataSizePerMessage = 12;  % Metadata per message: [numSamples, startIndex, endIndex] (int32 x 3)
        sampleSize = 16;              % Data size per complex sample (double for real and imag parts)
        totalMessages = 30000;        % Maximum number of messages

        headerSize = headerSizePerMessage * totalMessages;        % Total header flag space
        metadataSize = metadataSizePerMessage * totalMessages;    % Total metadata space
        pointerSize = 2; % Each pointer (writePointer, maxWritePointer) is int16, hence 2 bytes
        totalPointerSize = 2 * pointerSize;                       % Total pointer space
        dataSize = totalMemorySizeInGB * 1024^3 - (headerSize + metadataSize + totalPointerSize);
        maxSamples = floor(dataSize / sampleSize);                % Calculate max samples that can fit in Data region

        InitHeader = -ones(totalMessages, 1, 'int8');             % All initialized to -1
        InitMetadata = zeros(totalMessages, 3, 'int32');          % Metadata: [numSamples, startIndex, endIndex]
        InitData = zeros(maxSamples, 2, 'double');                % Data storage for complex samples
        InitWritePointer = int16(1);                              % Initialize writePointer to 1
        InitMaxWritePointer = int16(0);                           % Initialize maxWritePointer to 0

        if ~exist(filename_rcvmmap, 'file')
            [f, msg] = fopen(filename_rcvmmap, 'w');
            if f ~= -1
                fwrite(f, InitHeader, 'int8');
                fwrite(f, InitMetadata, 'int32');
                fwrite(f, InitWritePointer, 'int16');
                fwrite(f, InitMaxWritePointer, 'int16');
                fwrite(f, InitData, 'double');
                fclose(f);
                disp('Radio Memory-mapped file created successfully.');
            else
                error('Radio File creation failed: %s', msg);
            end
        end

        m = memmapfile(filename_rcvmmap, ...
            'Format', { ...
                'int8', [totalMessages, 1], 'headerFlags'; ...        % 标头部分
                'int32', [totalMessages, 3], 'messageMetadata'; ...   % 元数据部分
                'int16', [1, 1], 'writePointer'; ...                  % 写入指针
                'int16', [1, 1], 'maxWritePointer'; ...               % 最大写入指针
                'double', [maxSamples, 2], 'complexData' ...          % 数据部分
            }, ...
            'Writable', true);

        try
            m.Data.headerFlags(:) = InitHeader;                       % 重置标头部分
            m.Data.messageMetadata(:) = InitMetadata;                 % 重置元数据部分
            m.Data.writePointer = InitWritePointer;                   % 重置写入指针
            m.Data.maxWritePointer = InitMaxWritePointer;             % 重置最大写入指针
            m.Data.complexData(:) = InitData;                         % 重置数据部分
            disp('Radio Memory-mapped file reset successfully.');
        catch ME
            error('Failed to reset radio memory-mapped file: %s', ME.message);
        end
    end

    % Reset "rxDataBits_shared.bin"
    if strcmp(mode, "all") || strcmp(mode, "bit cache")
        defaultFilename = "rxDataBits_shared.bin";
        filename_bitcache = fullfile(defaultRoot, defaultFilename);
        totalBitCacheSizeInMB = 50;

        total_frame_reserved = 5000;  % 预留的帧数量
        max_rxDataBits_size = totalBitCacheSizeInMB * 1024 * 1024;  % 比特流区域大小（字节数）
        framemetadata_columns = 5;  % metadata的列数

        readflag_size = 1;  % 单个 uint8
        
        % 初始化文件
        if ~isfile(filename_bitcache)
            fid = fopen(filename_bitcache, 'wb');
            % 初始化 readflag 为 0
            fwrite(fid, zeros(readflag_size, 1, 'uint8'), 'uint8');
            % 初始化 framemetadata 为全零的 uint32
            fwrite(fid, zeros(total_frame_reserved, framemetadata_columns, 'uint32'), 'uint32');
            % 初始化 rxDataBits 为全零的 uint8
            fwrite(fid, zeros(max_rxDataBits_size, 1, 'uint8'), 'uint8');
            fclose(fid);
        end

        mappedFile = memmapfile(filename_bitcache, ...
            'Writable', true, ...
            'Format', { ...
                'uint8', [1, 1], 'readflag'; ...  % 第一个片区
                'uint32', [total_frame_reserved, framemetadata_columns], 'framemetadata'; ... % 第二个片区
                'uint8', [max_rxDataBits_size, 1], 'rxDataBits' ... % 第三个片区
            });

        try
            mappedFile.Data.readflag = zeros(readflag_size, 1, 'uint8');                          % 初始化 readflag
            mappedFile.Data.framemetadata(:) = zeros(total_frame_reserved, framemetadata_columns, 'uint32');                         % 重置元数据部分
            mappedFile.Data.rxDataBits(:) = zeros(max_rxDataBits_size, 1, 'uint8');                            % 重置数据部分
            disp('Bitstream memory-mapped file reset successfully.');
        catch ME
            error('Failed to reset bitstream memory-mapped file: %s', ME.message);
        end
    end
end
