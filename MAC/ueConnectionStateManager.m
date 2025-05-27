function CBS_ID = ueConnectionStateManager(rxDataBits, rxDiagnostics, sysParam, mmHandle)
% UE端：管理当前与控制基站建立连接的状态，决定阶段跳转并更新要发送的消息
%
% 输入:
%   rxDataBits      : 接收的比特流(已做过CRC校正)
%   rxDiagnostics   : 其中包含 dataCRCErrorFlag 等诊断信息
%   sysParam        : 系统参数(包含 UE_ID等)
%   mmHandle        : 来自 initStateMemmap(...) 的 memmapfile 句柄
%                     其中:
%                       mmHandle.Data.stage (int8)
%                       mmHandle.Data.flag  (int8)
%
% 注意:
%   - mmHandle这里使用了两个结构字段: stage 和 flag.
%   - stage表示当前所处阶段(0,1,2,3,...), flag=1表示此轮发生了阶段切换.
%   - CBS与UE的连接阶段字符串通过 getBaseStageMsgs() 获取, 并在 UE 侧, 动态解析 CBS_ID (从 recData 中提取) 
%   - 通过rePlaceholders() 替换getBaseStageMsgs获取的阶段字符串.
%   - 若无法解析到 CBS_ID, 跳过阶段更新

    %% 1. 日志文件准备
    root_logfile = './MAC/logs/';
    logFilename  = 'UE_connection_verbosity_log.txt';
    logFullPath  = fullfile(root_logfile, logFilename);
    UE_fieldname = sprintf('UE_ID_%d', sysParam.UE_ID);
    verbosity_log = false;       % 如果为 false, 就不会写详细日志
    %=== 打开日志文件, 并保持fidLog全程有效 ===
    if ~isfile(logFullPath)
        fidLog = fopen(logFullPath, 'w');   % 如果日志不存在，就新建文件并写入
        fprintf(fidLog, '--- Start ueConnectionStateManager() ---\n');
        fclose(fidLog);
    end
    
    limitLogFile(logFullPath);
    if verbosity_log
        fidLog = fopen(logFullPath, 'a');   % 日志已经存在，附加在后面继续写
        if fidLog == -1
            error('Cannot open log file "%s" for writing.', logFullPath);
        end
        
        %=== 在异常或函数结束时，统一关闭文件句柄 ===
        cleanupObj = onCleanup(@() fclose(fidLog));
        fprintf(fidLog, '\n');
    end

    % 1.1 关键日志文件（仅写关键阶段）
    briefLogName = 'UE_connection_brief_log.txt';
    briefLogPath = fullfile(root_logfile, briefLogName);

    % 如果简明日志不存在，则写入初始说明
    if ~isfile(briefLogPath)
        fidBriefInit = fopen(briefLogPath, 'w');
        fprintf(fidBriefInit, '********** connection state history **********\n');
        fclose(fidBriefInit);
    end
    
    %=== 不需要一直打开，可以在写入时再 'a' 打开，然后写完就关闭。
    %=== 因为关键信息出现频率较低，这样即可。
    %% 2. 读取当前 stage/flag (老的值)
    oldStage = mmHandle.Data.stage;  % int8
    oldFlag  = mmHandle.Data.flag;   % int8 (这里可能没啥用, 可忽略)
    
    %% 3. 将 rxDataBits 解码为字符串 recData
    if isempty(rxDataBits)
        recData = '';
    else
        numBitsToDecode = length(rxDataBits) - mod(length(rxDataBits), 7);
        if numBitsToDecode <= 0
            recData = '';
        else
            recData = char(bit2int(reshape(rxDataBits(1:numBitsToDecode), 7, []), 7));
        end
    end
    if verbosity_log
        writeLog(fidLog, sprintf('Received Data: "%s"', recData), UE_fieldname, oldStage, rxDiagnostics);
    end
    %% 4. 检查 CRC
    if rxDiagnostics.dataCRCErrorFlag
        if verbosity_log
            writeLog(fidLog, 'CRC Error detected, ignoring this packet.', UE_fieldname, oldStage, rxDiagnostics);
        end
        CBS_ID = [];
        return;
    end

    %% 5.1. 动态解析CBS_ID (从 recData 中查找)
    cbsIDParsed = parseCbsIDFromRxData(recData);  % 自定义解析函数
    if ~isempty(cbsIDParsed)
        % 如果成功解析到 cbsID, 更新 CBS_ID
        CBS_ID = cbsIDParsed;
        if verbosity_log
            writeLog(fidLog, sprintf('Parsed CBS_ID = %d from recData.', cbsIDParsed), UE_fieldname, oldStage, rxDiagnostics);
        end
    else
        % 未解析到CBSID, 跳出本次状态更新.
        if verbosity_log
            writeLog(fidLog, 'No CBS_ID found in recData. No CBS message. skip updates.', UE_fieldname, oldStage, rxDiagnostics);
        end
        CBS_ID = [];
        return
    end

    %% 5.2. 拿到阶段字符串模板, 并替换 @UE_ID / @CBS_ID
    ueBaseMsgs   = getBaseStageMsgs('UE');
    % 这里 ueID 肯定是 sysParam.UE_ID, 而 cbsID 不一定能解析到.
    ueStageMsgs  = rePlaceholders(ueBaseMsgs, sysParam.UE_ID, CBS_ID);

    cbsBaseMsgs  = getBaseStageMsgs('CBS');
    cbsStageMsgs = rePlaceholders(cbsBaseMsgs, sysParam.UE_ID, CBS_ID);

    %% 6. 阶段判断逻辑
    newStage = oldStage;  % 默认保持不变

    if oldStage < 3
        % 期望收到的 CBS 消息 (下一阶段)
        expectedCbsMsg = cbsStageMsgs{oldStage + 1};  

        if contains(recData, expectedCbsMsg)
            newStage = oldStage + 1;
            if verbosity_log
                writeLog(fidLog, sprintf('ACK RECEIVING! CONNECTING STATE TRANSITIONS FROM %d TO %d', oldStage, newStage), UE_fieldname, oldStage, rxDiagnostics);
            end
        else
            if verbosity_log
                if oldStage == 0
                    writeLog(fidLog, sprintf('NO CBS Broadcasting Signal......'), UE_fieldname, oldStage, rxDiagnostics);
                else
                    writeLog(fidLog, sprintf('@CBS_ID %d NO ACK.....REMAINS in STATE %d.', CBS_ID, oldStage), UE_fieldname, oldStage, rxDiagnostics);
                end
            end
        end

    elseif oldStage == 3
        %---------------------------
        %   新增：阶段 4 的判断
        %---------------------------
        % 如果 CBS 处于阶段 4(即 cbsStageMsgs{4}="[@CBS_ID x] Prepare for Sending Control...")，则 UE 进入阶段 4
        expectedCbsMsg = cbsStageMsgs{oldStage + 1}; 
        if contains(recData, expectedCbsMsg)
            % CBS 准备发送控制参数, UE 进入阶段4
            newStage = oldStage + 1;
            if verbosity_log
                writeLog(fidLog, sprintf('CONTROL PARAMS INCOMING... STATE TRANSITIONS FROM %d TO %d', ...
                                         oldStage, newStage), UE_fieldname, oldStage, rxDiagnostics);
            end
        else
            % 如果没检到，已进入稳定连接状态（oldstate=3），只需要对当前连接状态进行检测维护即可，不需要进入下一状态, 就维持 3
            expectedCbsMsg = cbsStageMsgs{oldStage};  
            if contains(recData, expectedCbsMsg)
                if verbosity_log
                    writeLog(fidLog, sprintf('ALREADY in STATE %d (CONNECTED WITH @CBS_ID %d), NO FURTHER TRANSITIONS.', oldStage, CBS_ID), UE_fieldname, oldStage, rxDiagnostics);
                end
                mmHandle.Data.enterTimeSec = posixtime(datetime('now')); % 记录进入新阶段的时间(秒)
    
            else
                if verbosity_log
                    writeLog(fidLog, sprintf('@CBS_ID %d NO ACK.....REMAINS in STATE %d.', CBS_ID, oldStage), UE_fieldname, oldStage, rxDiagnostics);
                end
            end
        end

    elseif oldStage == 4
        %---------------------------
        %   阶段 4 -> 等待 CBS 的控制参数文件发送
        %---------------------------
        % CBS 在 stage=5 时实际写 JSON 文件并发送(它的 cbsStageMsgs{5}='')，
        % 所以此时 recData 可能是一大段文本(或 JSON 片段)。这里自行判断 recData 是否包含JSON。
        
        % 如果检测到是JSON或标志性的字段，就认为成功接收并进入阶段5
        [isJSON,PHY_params] = isLikelyJSON(recData);
        if isJSON
            % UE 成功接收到控制参数文件, 进入阶段5
            newStage = oldStage + 1;
            if verbosity_log
                writeLog(fidLog, sprintf('CONTROL PARAMS RECEIVED! STATE TRANSITIONS FROM %d TO %d.', ...
                                 oldStage, newStage), UE_fieldname, oldStage, rxDiagnostics);
            end

            % 存储CBS下发的控制信令到本地mat文件，以供数据链路实体读取和应用:
            SaveControlParams(PHY_params); 

        else
            if verbosity_log
                writeLog(fidLog, sprintf('Waiting for Control Params JSON... no valid data yet. REMAINS in STATE %d.', oldStage), ...
                    UE_fieldname, oldStage, rxDiagnostics);
            end
        end

    elseif oldStage == 5
        %---------------------------
        %   阶段 5 -> UE 已接收控制参数并发送ACK，若收到CBS阶段3连接稳定消息，返回阶段3
        %---------------------------
        
        % 若检测到CBS已重回稳定连接状态（CBSState=3），UE连接状态重回state 3
        expectedCbsMsg = cbsStageMsgs{3};  
        if contains(recData, expectedCbsMsg)
            newStage = 3;
            if verbosity_log
                writeLog(fidLog, sprintf('CONTROLING SIGNAL TRANSMISSION COMPLETE! RETURN to STAGE %d (KEEP CONNECTED WITH @CBS_ID %d).', newStage, CBS_ID), UE_fieldname, oldStage, rxDiagnostics);
            end
        else
            if verbosity_log
                writeLog(fidLog, sprintf('@CBS_ID %d NO ACK.....REMAINS in STATE %d.', CBS_ID, oldStage), UE_fieldname, oldStage, rxDiagnostics);
            end
        end

    else
        error('Undefined UE Stage!')
    end


    %% 7. 更新 mmHandle.Data并将发送消息存储进发送文件中
    mmHandle.Data.stage = int8(newStage);  % 写回新的阶段
    if newStage ~= oldStage
        % 准备要发送给CBS的消息(UE->CBS)
        txMsg = ueStageMsgs{newStage+1};    %注意这里对ueStageMsgs索引，要在实际的stage基础上加1，因为ue message的1索引是空（对应stage0）
        if ~isempty(txMsg)
            if verbosity_log
                writeLog(fidLog, sprintf('Will send message: "%s"', txMsg), UE_fieldname, newStage, rxDiagnostics);
            end
            % 在简明日志中写同样的消息
            appendBriefLog( ...
                briefLogPath, ...
                oldStage, newStage, CBS_ID, sysParam.UE_ID, rxDiagnostics, recData, txMsg ...
            );
            if newStage == 5
                loggingRCVPHYParams(briefLogPath, PHY_params)
            end
            
            % (重要) 将该消息写入 uplink_transmit\transmit_data.txt
            saveTextFilename = '.\PHYTransmit\transmit_data.txt';
            writeMessageToFile(saveTextFilename, txMsg);

            mmHandle.Data.flag = int8(1);      % 发生了阶段切换,标志位置为1, 告知SendDataManager(或其他)“有新的数据要发”
            mmHandle.Data.enterTimeSec = posixtime(datetime('now')); % 记录进入新阶段的时间(秒)
        else
            if verbosity_log
                writeLog(fidLog, sprintf('In stage %d, no message to send.', newStage), UE_fieldname, newStage, rxDiagnostics);
            end
            % 若本阶段无消息, 设置flag=0
            mmHandle.Data.flag  = int8(0);
            mmHandle.Data.enterTimeSec = posixtime(datetime('now')); % 记录进入新阶段的时间(秒)
        end
    end

    % writeLog(fidLog, sprintf('--- End ueConnectionStateManager(), final stage = %d ---', newStage), UE_fieldname);
end

%% =============== 辅助函数 ===============
function writeLog(fid, msg, prefix, statefield, rxDiagnostics)
    % 写日志信息到verbosity log
    % 利用已有的fid, 直接fprintf追加写
    crt_frameNum = rxDiagnostics.frameNum;
    crt_msgNum = rxDiagnostics.messageNum;
    fprintf(fid, '[%s msg:%d frame:%d](STATE_%d) %s\n', prefix, crt_msgNum, crt_frameNum, statefield, msg);
end


function limitLogFile(logFilePath)
    % 检查文件是否存在
    maxLines = 10000;

    % 读取文件内容
    fileID = fopen(logFilePath, 'r');
    if fileID == -1
        error('无法打开文件：%s', logFilePath);
    end

    % 按行读取文件内容
    fileContent = textscan(fileID, '%s', 'Delimiter', '\n');
    fclose(fileID);

    lines = fileContent{1}; % 获取所有行的内容
    numLines = length(lines); % 获取行数

    if numLines > maxLines
        lines = lines(1); % 保留第一行内容
    else
        % 如果行数未超过 maxLines，不做任何修改
        return;
    end

    % 写回文件
    fileID = fopen(logFilePath, 'w');
    if fileID == -1
        error('无法打开文件：%s', logFilePath);
    end
    fprintf(fileID, '%s\n', lines{:}); % 按行写入文件
    fclose(fileID);

end


function cbsID = parseCbsIDFromRxData(recData)
% 解析 recData 中所有形如:
%   "[@CBS_ID  123]"
% 的段落, 并返回最后一个出现的数字(作为 cbsID).
% 如果没找到, 返回 [].
% 如果 CBS_ID 格式不止是数字，也可以改成 (\w+) 或其他正则。
% 如果想要第一个出现而非最后一个，则用 tokens{1}{1}。
% 如果要记录所有出现的 CBS_ID，也可以把 tokens 全部转换成数组返回。

    % 使用正则表达式, 捕获 (数字) 到 tokens
    % 说明: \s+ 表示一个或多个空白, \d+ 表示一个或多个数字
    pattern = '\[@CBS_ID\s+(\d+)\]';

    % tokens 形如 {{'1'},{'1'},{'1'},...} 若匹配多个
    tokens = regexp(recData, pattern, 'tokens');
    
    if ~isempty(tokens)
        % 取最后一个匹配, tokens{end} 是形如 {'123'}
        cbsIDstr = tokens{end}{1};  
        cbsID = str2double(cbsIDstr);
    else
        cbsID = [];
    end
end


function finalStageMsgs = rePlaceholders(baseStageMsgs, ueID, cbsID)
% 将 baseStageMsgs 中的 @UE_ID, @CBS_ID 替换为实际的数字ID
%
% 输入:
%   baseStageMsgs : 形如 {...} 的字符串 cell
%   ueID, cbsID   : 要替换的数值或字符串
%
% 输出:
%   finalStageMsgs: 替换完成的字符串 cell

    finalStageMsgs = cell(size(baseStageMsgs));
    ueID_str  = sprintf('@UE_ID %d', ueID);
    cbsID_str = sprintf('@CBS_ID %d', cbsID);

    for k = 1:length(baseStageMsgs)
        msg = baseStageMsgs{k};
        msg = strrep(msg, '@UE_ID',  ueID_str);
        msg = strrep(msg, '@CBS_ID', cbsID_str);
        finalStageMsgs{k} = msg;
    end
end

function [isJSON, Tr_params] = isLikelyJSON(recData)
% 改进后：搜索文本中出现的第一个"[@CBS_ID ...]"和第一个"[@UE_ID ...]"，
%         只取它们之间的字符串作为JSON解码。
%
% 使用示例：
%   [isJSON, Tr_params] = isLikelyJSON(recData);

    % 1) 去掉首尾空白
    recDataTrim = strip(recData);

    % 2) 正则模式 (不限定必须在开头或结尾)
    prefixPattern = '\[@CBS_ID\s+\d+\]';
    suffixPattern = '\[@UE_ID\s+\d+\]';

    % 3) 搜索第一个前缀出现的位置
    prefixStart = regexp(recDataTrim, prefixPattern, 'once');  
    if isempty(prefixStart)
        % 没找到 prefix
        isJSON = false;
        Tr_params = [];
        return;
    end
    % prefixMatch 用于知道前缀的完整字符串
    prefixMatch = regexp(recDataTrim(prefixStart:end), prefixPattern, 'match', 'once');
    prefixEnd = prefixStart + length(prefixMatch) - 1;  % 前缀结束的位置

    % 4) 搜索第一个后缀出现的位置
    suffixStart = regexp(recDataTrim, suffixPattern, 'once');
    if isempty(suffixStart)
        % 没找到 suffix
        isJSON = false;
        Tr_params = [];
        return;
    end
    % suffixMatch 用于知道后缀的完整字符串
    suffixMatch = regexp(recDataTrim(suffixStart:end), suffixPattern, 'match', 'once');

    % 5) 判断前缀是否在后缀之前(逻辑上必须prefixEnd < suffixStart)
    if prefixEnd >= suffixStart
        % 如果前缀结束位置比后缀开始还要靠后，说明顺序有问题
        isJSON = false;
        Tr_params = [];
        return;
    end

    % 6) 截取前缀与后缀之间的内容
    substring = recDataTrim(prefixEnd+1 : suffixStart-1);
    substring = strip(substring);

    % 7) 尝试解析JSON
    try
        Tr_params = jsondecode(substring);
        isJSON = true;
    catch
        Tr_params = [];
        isJSON = false;
    end

end



% function [isJSON,Tr_params] = isLikelyJSON(recData)
% % 改进后：适应“[@CBS_ID x] {json...} [@UE_ID y]”这样的格式
% % 你也可以再做更复杂/更严格的校验
%     % 1) 去掉首尾空白
%     recDataTrim = strip(recData);
% 
%     % 2) 匹配并截掉"[@CBS_ID ...]"前缀
%     prefixPattern = '^\[@CBS_ID\s+\d+\]';
%     prefixMatch = regexp(recDataTrim, prefixPattern, 'match');
%     if ~isempty(prefixMatch)
%         % prefixMatch{1} 形如 '[@CBS_ID 7]'
%         prefixLen = length(prefixMatch{1});
%         % 删除前缀部分
%         recDataTrim(1:prefixLen) = [];
%         recDataTrim = strip(recDataTrim);  % 再次去空白
%     end
% 
%     % 3) 匹配并截掉"[@UE_ID ...]"后缀
%     suffixPattern = '\[@UE_ID\s+\d+\]$';
%     suffixMatch = regexp(recDataTrim, suffixPattern, 'match');
%     if ~isempty(suffixMatch)
%         suffixLen = length(suffixMatch{1});
%         % 删除后缀部分
%         recDataTrim((end - suffixLen + 1):end) = [];
%         recDataTrim = strip(recDataTrim);  % 再次去空白
%     end
% 
%     % 4) 判断剩余文本是否“看起来像JSON”
%     %    (最简方式：判断首尾大括号)
%     % isJSON = startsWith(recDataTrim, '{') && endsWith(recDataTrim, '}');
% 
%     % 如果你想更严格，可以这样:
%     try
%         Tr_params = jsondecode(recDataTrim);
%         isJSON = true;
%     catch
%         isJSON = false;
%         Tr_params = [];
%     end
% end


function appendBriefLog(briefLogPath, oldStage, newStage, cbsID, ueID, rxDiagnostics, receivedDataStr, txMsg)
% 合并之前的两个函数: 既写"接收+解析+阶段切换"信息, 也可写"Will send message..."
%
% 输入:
%   briefLogPath     : 简明日志文件的完整路径 (e.g. "./MAC/logs/UE_connection_brief_log.txt")
%   oldStage, newStage : 整数, 表示切换前与切换后的阶段
%   cbsID, ueID      : 分别指明本次接收到的 CBS_ID 与 UE_ID
%   rxDiagnostics    : 含 frameNum, messageNum 等信息
%   receivedDataStr  : 实际解码到的字符串(可记入日志)
%   txMsg            : 若不为空, 表示要发送给对端的消息, 需要写"Will send message"到简明日志
%
% 说明:
%   - 通常在 `newStage ~= oldStage` 时调用, 以记录关键状态变更.

    fid = fopen(briefLogPath, 'a');
    if fid == -1
        error('Cannot open brief log file "%s" for appending.', briefLogPath);
    end
    fprintf(fid, '\n');
    fprintf(fid, '----------------%s----------------\n', datetime('now'));
    
    if newStage == 5
        % newStage = 5表示成功接收到了控制参数，这里设置独特的log文本以区分
        % 1) Parsed CBS_ID
        fprintf(fid, '[UE_ID_%d msg:%d frame:%d](STATE_%d) Parsed CBS_ID = %d from recData.\n', ...
            ueID, rxDiagnostics.messageNum, rxDiagnostics.frameNum, oldStage, cbsID);
    
        % 2) ACK RECEIVING (显示 oldStage -> newStage)
        fprintf(fid, '[UE_ID_%d msg:%d frame:%d](STATE_%d) RECEIVED CONTROL SIGNALING! CONNECTING STATE TRANSITIONS FROM %d TO %d\n', ...
            ueID, rxDiagnostics.messageNum, rxDiagnostics.frameNum, oldStage, oldStage, newStage);
    
        % 3) 如果传入了非空 txMsg, 写“Will send message: ...”
        fprintf(fid, '[UE_ID_%d msg:%d frame:%d](STATE_%d) Will send message: "%s"\n', ...
            ueID, rxDiagnostics.messageNum, rxDiagnostics.frameNum, newStage, txMsg);

    else
        % 1) Received Data
        fprintf(fid, '[UE_ID_%d msg:%d frame:%d](STATE_%d) Received Data: "%s"\n', ...
            ueID, rxDiagnostics.messageNum, rxDiagnostics.frameNum, oldStage, receivedDataStr);
    
        % 2) Parsed CBS_ID
        fprintf(fid, '[UE_ID_%d msg:%d frame:%d](STATE_%d) Parsed CBS_ID = %d from recData.\n', ...
            ueID, rxDiagnostics.messageNum, rxDiagnostics.frameNum, oldStage, cbsID);
    
        % 3) ACK RECEIVING (显示 oldStage -> newStage)
        fprintf(fid, '[UE_ID_%d msg:%d frame:%d](STATE_%d) ACK RECEIVING! CONNECTING STATE TRANSITIONS FROM %d TO %d\n', ...
            ueID, rxDiagnostics.messageNum, rxDiagnostics.frameNum, oldStage, oldStage, newStage);
    
        % 4) 如果传入了非空 txMsg, 写“Will send message: ...”
        fprintf(fid, '[UE_ID_%d msg:%d frame:%d](STATE_%d) Will send message: "%s"\n', ...
            ueID, rxDiagnostics.messageNum, rxDiagnostics.frameNum, newStage, txMsg);
    end

    fclose(fid);
end


function loggingRCVPHYParams(briefLogPath, PHY_params_DL)
    jsonData = jsonencode(PHY_params_DL);

    % 格式化 JSON 字符串
    jsonData = strrep(jsonData, ',', sprintf(',\n\t'));
    jsonData = strrep(jsonData, '{', sprintf('{\n\t'));
    jsonData = strrep(jsonData, '}', sprintf('\n}\t'));
    
    % 写入文件
    fid = fopen(briefLogPath, 'a');
    if fid == -1
        error('Cannot open brief log file "%s" for appending.', briefLogPath);
    end
    fprintf(fid,'\n***************Downlink DBS Transmission Parameters*******************\n');
    fwrite(fid, jsonData, 'char');
    fprintf(fid,'\n***************Downlink DBS Transmission Parameters*******************\n');
    fclose(fid);
end


function writeMessageToFile(filename, message)
    % 将message覆盖写到filename
    fileID = fopen(filename, 'w');
    if fileID == -1
        error('Cannot open file "%s" for writing.', filename);
    end
    fprintf(fileID, '%s', message);
    fclose(fileID);
end


