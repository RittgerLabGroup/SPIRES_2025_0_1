function [ S ] = createStudyExtent(espEnv, extentName, varargin)
%createStudyExtent creates new region extent by study area
%
% Input
%   espEnv = object, initialized ESP Toolbox environment
%   extentName = string, study extent name, one of:
%      "SierraBighorn" or "SouthernSierraNevada"
%
% Optional Input
%   saveExtent - logical, save extent information to csv file
%               Default value: false
%   saveFilename - filename to save the extent to, as csv
%               Default value: 
%               '<extentName>Extent.csv'
%   
% Output
%   Structure with status
%   S.status = 0 success, nonzero otherwise
%   S.message = text message with error, or "OK"
%   See outputs from snapRegionExtentLL for remaining structure fields,
%   includes snapped UL and LR pixels, tiePoint, dims and
%   target pixel and block sizes.
%
%   Side effect:    
%   study area region extent is written to
%   '<regionName>Extent.csv'
%
% Notes
%
% TODO: Figure out how to get tiepoint coordinate of closest
%   MODIS cell without using mapx. For now, using the same tiePoint
%   for both regions we are using
%
% Example
% myEnv = ESPEnv();
% [ S ] = createStudyExent(myEnv, "SierraBighorn");
% 
       
%  Copyright 2018 The Regents of the University of Colorado
    numvarargs = length(varargin);
    if numvarargs > 2
        error('studyExtent:TooManyInputs', ...
            'requires at most 2 optional inputs');
    end

    % fullfile requires char vectors, not modern Strings
    outFilename = fullfile(espEnv.extentDir, ...
        char(sprintf("%sExtent.csv", extentName)));
    optargs = {...
        false, ...
        outFilename};
    optargs(1:numvarargs) = varargin;  
    [saveExtent, outFilename] = optargs{:};

    S.status = 0;
    S.message = "OK";

    % For now using same tiePoint for both regions
    % Set up input locations (from a MODIS pixel near middle
    % of historical range from DFW
    % cu-vpn-nsidc-172:unsupported brodzik$ gtest sinus_500m.gpd
    %
    % gpd: sinus_500m.gpd
    % mpp:sinus_500m.gpd
    %
    % forward_grid:
    % warning: this program uses gets(), which is unsafe.
    % enter lat lon: 37.34 -118.807
    % col,row = 20529.692232 12637.899999    status = 1
    % lat,lon = 37.340000 -118.807000    status = 1
    % enter lat lon: 
    %
    % (round pixel locations to nearest integer for
    % center of MODIS pixel)
    % 
    % inverse_grid:
    % enter col row: 20530. 12638.
    % lat,lon = 37.339583 -118.804728    status = 1
    % col,row = 20530.000000 12638.000000    status = 1
    tiePointLat = 37.339583;
    tiePointLon = -118.804728;

    % Nominal corners from ArcMap
    switch extentName
        case 'SierraBighorn'
            ulLat = 38.558316;
            ulLon = -119.929961; 
            lrLat = 36.053441;
            lrLon = -117.886791; 
        case 'SouthernSierraNevada'
            ulLat = 39.320;
            ulLon = -121.300; 
            lrLat = 35.412;
            lrLon = -117.878; 
        otherwise
            S.status = -1;
            S.message = sprintf("%s: Unrecognized regionName=%s\n", ...
                mfilename(), extentName);
            return
    end

    [ S ] = snapRegionExtentLL(ulLat, ulLon, ...
                   lrLat, lrLon,...
                   tiePointLat, tiePointLon);

    if (S.status ~= 0 )
        fprintf("%s: Error: %d, %s\n", mfilename(), ...
            S.status,...
            S.message);
        return
    end

    if (saveExtent)
        [ out ] = writeRectangleToCsv(outFilename,...
            S.snapULx, S.snapULy,...
            S.snapLRx, S.snapLRy,...
            S.tiePointx, ...
            S.tiePointy);
        fprintf("%s: Wrote extent to: %s\n",...
            mfilename, outFilename);
    end

end
