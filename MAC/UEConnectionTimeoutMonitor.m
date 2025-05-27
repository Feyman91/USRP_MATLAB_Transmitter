function UEConnectionTimeoutMonitor(m_handle, readPointerStruct, sysParamRxObj, resultStruct)
% 函数，用于定时检测UE当前阶段是否超过6秒没变化
% 若超时则回到初始阶段(stage=0).

    %=== 1) 进行一次检查
    root_logfile = './MAC/logs/';
    briefLogName = 'UE_connection_brief_log.txt';
    briefLogPath = fullfile(root_logfile, briefLogName);

    framePointer = readPointerStruct.frameprocesspointer;
    messagePointer = readPointerStruct.messageprocesspointer;
    currentStage = m_handle.Data.stage;
    timeEntered  = m_handle.Data.enterTimeSec;
    nowSec       = posixtime(datetime('now')); 
    
    ueID = sysParamRxObj.sysParam.UE_ID;
    % 仅当阶段>0时(假设0是初始阶段), 才做超时检测
    if currentStage > 0  
        cbsID = resultStruct.CBS_ID;
        elapsed = nowSec - timeEntered;
        if elapsed > 6
            % 超时, 回到初始阶段=0，仅在简短日志里记录
            appendBriefLog(briefLogPath, currentStage, cbsID, ueID, framePointer, messagePointer)
            m_handle.Data.stage        = int8(0);
            m_handle.Data.flag         = int8(1);
            m_handle.Data.enterTimeSec = nowSec; % 重置时间
        end
    end
end


function appendBriefLog(briefLogPath, crtStage, cbsID, ueID, framePointer, messagePointer)
% 仅在简短日志里记录
    fid = fopen(briefLogPath, 'a');
    if fid == -1
        error('Cannot open brief log file "%s" for appending.', briefLogPath);
    end
    fprintf(fid, '\n');
    fprintf(fid, '----------------%s----------------\n', datetime('now'));

    fprintf(fid, '[UE_ID_%d msg:%d frame:%d](STATE_%d) Waiting timed out！ (>6s)\n', ...
        ueID, messagePointer, framePointer, crtStage);
    fprintf(fid, '[UE_ID_%d msg:%d frame:%d](STATE_%d) Lost connection with @CBS_ID %d！\n', ...
        ueID, messagePointer, framePointer, crtStage, cbsID);
    fprintf(fid, '[UE_ID_%d msg:%d frame:%d](STATE_%d) Revert to stage 0\n', ...
        ueID, messagePointer, framePointer, crtStage);    
    fclose(fid);
end
