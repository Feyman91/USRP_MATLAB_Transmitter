function PHYParams = initializePHYParams(direction)
    % initializePHYParams: 初始化 UE 端的 PHY 参数
    %
    % 功能：
    %   本函数用于初始化物理层（PHY）参数，这些参数是从控制基站端通过控制信令
    %   下发到用户设备（UE）端的，用于支持接收下行数据基站（DL-DBS）或向上行
    %   数据基站（UL-DBS）发送数据的传输操作。
    %
    % 输入：
    %   direction: 指定 PHY 参数的方向模式，支持以下值：
    %       - 'uplink'：用于 UE 向 UL-DBS 发送数据时的传输参数初始化。
    %       - 'downlink'：用于 UE 从 DL-DBS 接收数据时的传输参数初始化。
    %
    % 输出：
    %   PHYParams: 包含通用（Common）参数和指定方向（Uplink 或 Downlink）
    %              参数的一级结构体。
    %       
    %
    % 功能描述：
    %   - 本函数通过读取预定义的 JSON 配置文件（PHYParams.json），
    %     提取通用参数和方向特定参数，并根据输入的 direction 参数合并为
    %     一个一级结构体。
    %   - 该函数提供动态方向选择功能（上行或下行），无需修改代码即可支持两种场景。
    %   - 在 JSON 文件缺失关键参数时，函数会抛出错误，以确保初始化的正确性。
    %
    % 示例：
    %   % 初始化用于上行通信的 PHY 参数
    %   PHYParams = initializePHYParams('uplink');
    %
    %   % 初始化用于下行通信的 PHY 参数
    %   PHYParams = initializePHYParams('downlink');
    %
    % 注意：
    %   1. JSON 文件路径已在函数中定义为固定值：'PHYParams.json'。
    %   2. JSON 文件必须包含以下顶级字段：'Common'、'Uplink'、'Downlink'。
    %   3. JSON 文件内容需要与 PHY 层协议保持一致。
    %

    % JSON 文件路径
    jsonFilePath = fullfile(fileparts(mfilename('fullpath')), 'PHYParams.json');

    % 检查输入参数
    if nargin < 1
        error('Missing input argument. You must specify the direction.');
    end
    if ~isfile(jsonFilePath)
        error('PHYParams.json 文件未找到，请检查路径：%s', jsonFilePath);
    end
    if ~any(strcmp(direction, {'uplink', 'downlink'}))
        error('Invalid direction. Must be ''uplink'' or ''downlink''.');
    end

    % 读取 JSON 文件内容
    jsonData = fileread(jsonFilePath);

    % 解析 JSON 数据为 MATLAB 结构体
    allParams = jsondecode(jsonData);

    % 提取通用参数
    if ~isfield(allParams, 'Common')
        error('JSON 文件缺少 "Common" 参数，请检查文件内容。');
    end
    commonParams = allParams.Common;

    % 提取方向参数
    if strcmp(direction, 'uplink')
        if ~isfield(allParams, 'Uplink')
            error('JSON 文件缺少 "Uplink" 参数，请检查文件内容。');
        end
        directionParams = allParams.Uplink;
    elseif strcmp(direction, 'downlink')
        if ~isfield(allParams, 'Downlink')
            error('JSON 文件缺少 "Downlink" 参数，请检查文件内容。');
        end
        directionParams = allParams.Downlink;
    end

    % 合并 Common 和指定方向参数为一级结构体
    PHYParams = commonParams; % 初始化为 Common 参数
    directionFields = fieldnames(directionParams);
    for i = 1:numel(directionFields)
        PHYParams.(directionFields{i}) = directionParams.(directionFields{i});
    end
end
