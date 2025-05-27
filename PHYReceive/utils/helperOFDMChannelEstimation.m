function channelEst = helperOFDMChannelEstimation(refSymOld,refSymCurr,chanEstRefSymbols,sysParam)
%helperOFDMChannelEstimation Estimates channel using reference symbols.
%   This function returns the estimated channel of a frame of data by
%   linearly interpolating over two reference signals across consecutive
%   frames.
%
%   channelEst = helperOFDMChannelEstimation(refSymOld,refSymCurr,chanEstRefSymbols,sysParam)
%   refSymOld - reference symbols from previous frame
%   refSymCurr - reference symbols from current frame
%   chanEstRefSymbols - reference symbols used to estimate channel
%   sysParam - system parameters structure
%   channelEst - Estimated channel output of the frame of OFDM symbols

% Copyright 2023 The MathWorks, Inc.

ssIdx = sysParam.ssIdx;         % sync symbol index
rsIdx = sysParam.rsIdx;         % reference symbol index

nDataSubCarr = sysParam.usedSubCarr;
nDataSym = sysParam.numSymPerFrame - length(ssIdx) - length(rsIdx);
% RSSpacing = 2; % will be able to create reference symbol with interleaved data in v2
RSSpacing = 1; % will be able to create reference symbol with interleaved data in v2

chanEstLast    = zeros(length(refSymOld),1);
chanEstCurrent = zeros(length(refSymOld),1);

% Compute least-squares channel estimates at reference symbols
ii=1:RSSpacing:nDataSubCarr;
chanEstLast(ii)    = refSymOld(ii).*conj(chanEstRefSymbols(ii));
chanEstCurrent(ii) = refSymCurr(ii).*conj(chanEstRefSymbols(ii));

% Interpolate estimates over frequency
% for ii=1:RSSpacing:nDataSubCarr-RSSpacing
%     chanEstLast(ii+1:ii+RSSpacing-1) = chanEstLast(ii) + (1:RSSpacing-1).'*...
%         (chanEstLast(ii+RSSpacing) - chanEstLast(ii))/RSSpacing;
%     chanEstCurrent(ii+1:ii+RSSpacing-1) = chanEstCurrent(ii) + (1:RSSpacing-1).'*...
%         (chanEstCurrent(ii+RSSpacing) - chanEstCurrent(ii))/RSSpacing;
% end
% The last end of the frequency bins just use the last pilot's channel
% estimate since there's nothing to interpolate between
% chanEstLast(nDataSubCarr-(RSSpacing-1-1):nDataSubCarr) = ...
%     chanEstLast(nDataSubCarr-RSSpacing-1)*ones(RSSpacing-1,1);
% chanEstCurrent(nDataSubCarr-(RSSpacing-1-1):nDataSubCarr) = ...
%     chanEstCurrent(nDataSubCarr-RSSpacing-1)*ones(RSSpacing-1,1);

% Interpolate estimates over time
channelEst = chanEstLast + (1:nDataSym).*...
    (chanEstCurrent - chanEstLast)/(nDataSym+length(ssIdx)+length(rsIdx));

end

% function channelEst = helperOFDMChannelEstimation(refSymOld,refSymCurr,chanEstRefSymbols,sysParam)
% %helperOFDMChannelEstimation Estimates channel using reference symbols.
% %   This function returns the estimated channel of a frame of data by
% %   linearly interpolating over two reference signals across consecutive
% %   frames using MMSE estimation.
% %
% %   channelEst = helperOFDMChannelEstimation(refSymOld,refSymCurr,chanEstRefSymbols,sysParam)
% %   refSymOld - reference symbols from previous frame
% %   refSymCurr - reference symbols from current frame
% %   chanEstRefSymbols - reference symbols used to estimate channel
% %   sysParam - system parameters structure
% %   channelEst - Estimated channel output of the frame of OFDM symbols
% 
% % Copyright 2023 The MathWorks, Inc.
% 
% ssIdx = sysParam.ssIdx;         % sync symbol index
% rsIdx = sysParam.rsIdx;         % reference symbol index
% 
% nDataSubCarr = sysParam.usedSubCarr;
% nDataSym = sysParam.numSymPerFrame - length(ssIdx) - length(rsIdx);
% RSSpacing = 1; % Reference symbol spacing (can be adjusted as needed)
% 
% chanEstLast    = zeros(length(refSymOld),1);
% chanEstCurrent = zeros(length(refSymOld),1);
% 
% % Compute least-squares channel estimates at reference symbols
% ii = 1:RSSpacing:nDataSubCarr;
% chanEstLast(ii)    = refSymOld(ii).*conj(chanEstRefSymbols(ii));
% chanEstCurrent(ii) = refSymCurr(ii).*conj(chanEstRefSymbols(ii));
% 
% % MMSE estimation parameters
% noiseVar = 0; % Noise variance,SET zero to use LS channel estimation(original algrithm)
% powerRefSymbols = mean(abs(chanEstRefSymbols).^2); % Power of reference symbols
% 
% % Compute MMSE channel estimates at reference symbols
% for k = ii
%     H_LS_last = chanEstLast(k);
%     H_LS_current = chanEstCurrent(k);
%     % MMSE estimation using the known noise variance and signal power
%     chanEstLast(k) = H_LS_last * powerRefSymbols / (powerRefSymbols + noiseVar);
%     chanEstCurrent(k) = H_LS_current * powerRefSymbols / (powerRefSymbols + noiseVar);
% end
% 
% % Interpolate estimates over time
% channelEst = chanEstLast + (1:nDataSym) .* ...
%     (chanEstCurrent - chanEstLast) / (nDataSym + length(ssIdx) + length(rsIdx));
% 
% end
