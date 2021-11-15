function runStatsForLinePlots(...
    regionName, partitionNum, ...					 
    startWaterYr, stopWaterYr, ...
    minSCP, minZ, mindays, zthresh)
% This script summarizes total snow cover fraction and median snow covered
% days for each day of each year for line graphs for multiple years
% When startWaterYr ~= stopWaterYr, it also calculates the
% interquartile range and median values
%
% Inputs
%   regionName: regionName to summarize, currently only
%   'westernUS' but eventually will include others
%   partitionNum: partition number:
%      10='westernUS_mask' (mask for full region)
%      11='State_masks' (mask for each state)
%      12='HUC2_masks', etc for 14, 16, 18
%   startWaterYr: integer, 4-digit, begin water year
%   stopWaterYr: integer, 4-digit, end water year
%   minSCP: structure with minimum snow covered fraction to use
%           in each variable's statistics, expected values for
%           .snow, .albedo, .radiative_forcing and .deltavis, 
%           units are percent (e.g. 10%)
%           should default to 10, 30, 30, 30?
%   minZ : structure with minimum elevation to use in each
%          variable's statistics, expected values for
%          .SCD, .albedo, .radiative_forcing and .deltavis, 
%          units are meters (e.g. 800)
%          snow_fraction below this elevation will not be
%          counted for respective variables
%          should default to 800 for all?
%          N.B. these values are not excluded from SCA
%   mindays: mindays for label on mosaic files to read
%   zthresh: North/South elevation threshold on mosaic files to read
%
% Outputs
%   Output will be saved to summary statistic file
%   quartile statistics will also be saved if startWaterYr != stopWaterYr

% Copyright 2020 The Regents of the University of Colorado

    % for testing purposes, writes output file to test location
    doTest = 0;

    partitionName = Regions.getPartitionNameFor(partitionNum);
    
    % Calculation will be for water years, beginning Oct 1.
    % In early October annually, we should run this for 2001 (beginning of
    % first full water year of MODIS record) to this year.
    % e.g. in early October 2019, do:
    %  startWaterYr=2001 and stopWaterYr=2019
    % to generate historical data.
    % For daily updates in current water year, do
    % startWaterYr == stopWaterYr
    if startWaterYr < stopWaterYr
        yrs = startWaterYr:stopWaterYr;
    elseif startWaterYr == stopWaterYr
        yrs = startWaterYr;
    else
        errorStruct.identifier = ...
            'runStatsForLinePlots:YearError';
        errorStruct.message = sprintf(...
            '%s: startWaterYr=%d should be <= stopWaterYr=%d', ...
            mfilename(), startWaterYr, stopWaterYr);
        error(errorStruct);
    end
    
    MData = MODISData();
    
    % Set the environment to point to location with mosaic files
    myEnv = ESPEnv();
    
    % MODIS data version
    version = 6;
    
    % set the file labelName with a version number for mosaic
    % files to read
    labelName = sprintf('v%02d', MData.STCversion);
    
    % Daily regional summary files are stored in this hierarchy
    myEnv.SCAGDRFSDir = fullfile(MData.archiveDir, ...
        sprintf('scagdrfs_v%02d.zthresh%04d%04d_mindays%02dadj', ...
        MData.STCversion, zthresh(1), zthresh(2), mindays));
    
    % Elevation dataset and elevation threshold to use
    elevationFile = myEnv.modisElevationFile(regionName);
    
    % Get the number of region partition areas
    partitions = Regions(partitionName);
    dim = size(partitions.LongName);
    npartitions = dim(1);
    LongName = partitions.LongName;
    ShortName = partitions.ShortName;
    
    % Preallocate vector of snow cover area and days for each year
    maxDaysPerYear = 366;
    nyrs = length(yrs);
    sca_area_km2_yr = NaN(nyrs, maxDaysPerYear, npartitions);
    scd_sum_yr = NaN(nyrs, maxDaysPerYear, npartitions);
    albedo_yr = NaN(nyrs, maxDaysPerYear, npartitions);
    albedoName = 'albedo_observed_muZ';
    radiative_forcing_yr = NaN(nyrs, maxDaysPerYear, npartitions);
    deltavis_yr = NaN(nyrs, maxDaysPerYear, npartitions);

    % Start or connect to the local pool
    % Assumes that caller has set this!
    S = configParPool('jobStorageLocation', getenv('TMPDIR'));
    addAttachedFiles(S.pool, {elevationFile});
    
    %fprintf(['%s: PARFOR LOOP FOR YEARS DISABLED ' ...
    %    'FOR TESTING ONLY DOING 2 YEARS...\n'], ...
    %    mfilename());
    parfor y=1:length(yrs)
        elevationData = load(elevationFile, 'Z');
        
        yr = yrs(y);
        [~, sca_area_km2_yr(y, :, :), ...
            scd_sum_yr(y, :, :), ...
            albedo_yr(y, :, :), ...
            radiative_forcing_yr(y, :, :), ...
            deltavis_yr(y, :, :)] = ...
            statsForLinePlots(...
            myEnv, version, regionName, partitions, labelName, ...
            albedoName, yr, elevationData.Z, minSCP, minZ, ...
            maxDaysPerYear);
    end
    
    % Save all (overwrites previous file)
    summaryFile = myEnv.SummarySnowFile(version, ...
        regionName, partitionName, yrs(1), yrs(end));
    if doTest
        [folder, basename, ext] = fileparts(summaryFile);
        folder = fullfile(folder, 'testRegions');
        summaryFile = sprintf('%s/%s%s', folder, basename, ext);
    end
    [folder, ~, ~] = fileparts(summaryFile);
    if ~exist(folder, 'dir')
        mkdir(folder);
    end
    
    save(summaryFile, 'sca_area_km2_yr', 'scd_sum_yr', ...
        'albedo_yr', 'radiative_forcing_yr', 'deltavis_yr', ...
	'minSCP', 'minZ', ... 
        'yrs', 'elevationFile', ...
        'version', 'regionName', 'partitionName', ...
        'LongName', 'ShortName', ...
        'albedoName', ...
        'labelName', 'zthresh', 'mindays', 'myEnv');
    fprintf('%s: Saved summary to %s\n', mfilename(), summaryFile);
    
    % If it was the historical run, find the median, prctiles, min/max
    % by region
    if yrs(1) ~= yrs(end)
        
        % snow fraction by day of year
        yrDim = 1;
        doyDim = 2;
        median_sca_area_km2 = median(sca_area_km2_yr, yrDim);
        prc25_sca_area_km2 = prctile(sca_area_km2_yr, 25, yrDim);
        prc75_sca_area_km2 = prctile(sca_area_km2_yr, 75, yrDim);
        sca_area_km2_yr_totalsum = nansum(sca_area_km2_yr, doyDim);
        
        % snow cover days
        median_scd_sum = median(scd_sum_yr, yrDim);
        prc25_scd_sum = prctile(scd_sum_yr, 25, yrDim);
        prc75_scd_sum = prctile(scd_sum_yr, 75, yrDim);

        % albedo
        median_albedo = median(albedo_yr, yrDim);
        prc25_albedo = prctile(albedo_yr, 25, yrDim);
        prc75_albedo = prctile(albedo_yr, 75, yrDim);

        % RF
        median_radiative_forcing = median(radiative_forcing_yr, yrDim);
        prc25_radiative_forcing = prctile(radiative_forcing_yr, 25, yrDim);
        prc75_radiative_forcing = prctile(radiative_forcing_yr, 75, yrDim);

        % DV
        median_deltavis = median(deltavis_yr, yrDim);
        prc25_deltavis = prctile(deltavis_yr, 25, yrDim);
        prc75_deltavis = prctile(deltavis_yr, 75, yrDim);
        
        % For each partition, find min/max year of sca
        yr_min = zeros(1, npartitions);
        yr_max = zeros(1, npartitions);
        for regIdx=1:npartitions
            % sca
            [~, indx_sca_sum] = sort(...
                sca_area_km2_yr_totalsum(:, regIdx), 'ascend');
            yr_min(regIdx) = yrs(indx_sca_sum(1));
            yr_max(regIdx) = yrs(indx_sca_sum(end));

        end
        
        save(summaryFile, 'median_sca_area_km2', ...
            'prc25_sca_area_km2', 'prc75_sca_area_km2', ...
            'sca_area_km2_yr_totalsum', 'yr_min', 'yr_max', ...
            'indx_sca_sum', ...
            'median_scd_sum', 'prc25_scd_sum', 'prc75_scd_sum', ...
            'median_albedo', 'prc25_albedo', 'prc75_albedo', ...
            'median_radiative_forcing', ...
	    'prc25_radiative_forcing', 'prc75_radiative_forcing', ...
            'median_deltavis', 'prc25_deltavis', 'prc75_deltavis', ...
            '-append');
        fprintf(['%s: Appended multi-year, multi-region summary ' ...
            'stats to %s\n'], ...
            mfilename(), summaryFile);
        
    end

end

function [datevalsYr, sca_area_km2_yr, scd_sum_yr, albedo_yr, ...
    radiative_forcing_yr, deltavis_yr] = ...
    statsForLinePlots(myEnv, version, ...
    regionName, partitions, labelName, albedoName, waterYr, Z, ...
    minSCP, minZ, maxDays)
%statsForLinePlots summarizes total snow cover fraction, 
%median snow covered days, median albedo, radiative_forcing and
%deltavis, for each day of each year and each region partition
%area, for use in line graphs
%
% Input
%    myEnv : ESPEnv object with mosaic filename information
%    version : MODIS version data
%    partitions : structure with Regions object with partitions information, 
%    labelName : labelName for mosaic files
%    albedoName : name of albedo field to read from mosaicFile
%    waterYr : water year to process (begins Oct of prior year)
%    Z : array of elevations to match mosaic array
%    minSCP: structure with minimum snow covered fraction to use
%            in each variable's statistics, expected values for
%            .snow, .albedo, .radiative_forcing and .deltavis, 
%            units are percent (e.g. 10%)
%    minZ : structure with minimum elevation to use in each
%           variable's statistics, expected values for
%           .SCD, .albedo, .radiative_forcing and .deltavis, 
%           units are meters (e.g. 800)
%           snow_fraction below this elevation will not be
%           counted for respective variables
%           N.B. these values are not excluded from SCA
%    maxDays : number in days dimension (366, allows for leaps)
%
% Output
%    datevalsYr : maxDays vector of datetime values
%    sca_area_km2_yr : snow covered area vector
%    scd_sum_yr : (cumulative) snow covered days 
%    albedo_yr : median scene albedo by day
%    radiative_forcing_yr : median scene radiative forcing by day
%    deltavis_yr : median scene deltavis by day
%

% Copyright 2020 The Regents of the University of Colorado

MData = MODISData();

datevalsYr = datenum([waterYr-1 10 1 12 0 0]):...
    datenum([waterYr 9 30 12 0 0]);

% Pre-allocate data matrices for area and scd sum by partition region
dim = size(partitions.LongName);
npartitions = dim(1);
sca_area_km2_yr = NaN(1, maxDays, npartitions);
scd_sum_yr = NaN(1, maxDays, npartitions);
scd_sum = NaN(1, npartitions);
albedo_yr = NaN(1, maxDays, npartitions);
radiative_forcing_yr = NaN(1, maxDays, npartitions);
deltavis_yr = NaN(1, maxDays, npartitions);

fNames = fieldnames(minZ);
for fidx=1:length(fNames)
    ZbelowMin.(fNames{fidx}) = Z < minZ.(fNames{fidx});
end

% Loop for each day
% Can't be done in parallel because of the way scd_sum is used.
tic;
for d=1:length(datevalsYr)
%fprintf('%s: DEBUG Only doing 16 days for TESTING...\n', mfilename());
%for d=1:16
    
    % Fetch the full daily mosaic for this date
    thisYr = year(datevalsYr(d));
    thisMonth = month(datevalsYr(d));
    thisDay = day(datevalsYr(d));
    mosaicFile = myEnv.MosaicFile(version, regionName, ...
        thisYr, thisMonth, thisDay, labelName);
    
    % Warning if a date is missing
    if ~isfile(mosaicFile)
        fprintf('%s: Missing mosaic file %s\n', mfilename(), ...
            mosaicFile);
        continue;
    end
    
    % Read layers and attributes from mosaic
    snow = readVarFromMosaic(mosaicFile, 'snow_fraction', ...
			     'percent', 1);
    albedo = readVarFromMosaic(mosaicFile, albedoName, ...
			      'percent', 100);
    RF = readVarFromMosaic(mosaicFile, 'radiative_forcing', ...
			  'W/m^2', 1);
    DV = readVarFromMosaic(mosaicFile, 'deltavis', ...
			  'percent', 1);
    percent2fraction = 100.;
    
    %% Loop for each partition
    %fprintf('%s: DEBUG only doing last 3 regions...\n', ...
    %    mfilename());
    for regIdx=1:npartitions
        %for regIdx=(npartitions-2):npartitions
        
        % this is a mask for pixels in this region
        outsideRegMask = partitions.indxMosaic ~= regIdx;
        
        %%%%%%%% SCA %%%%%%%%%
        % make a copy to manipulate
        thisSnow = snow.data;
        
        % mask for only the area of this partition
        thisSnow(outsideRegMask) = 0;
        snowIsMissing = thisSnow == snow.missingValue;
        
        % Set low snow and nan snow to 0
        thisSnow(thisSnow < minSCP.snow) = 0;
        thisSnow(snowIsMissing) = 0;
        
        % Calculate area as an image and then sum for this day
        ascag = (thisSnow) * (MData.pixSize_500m^2 / 1000^2);
        
        % should scale snow_fraction, but this is fast cause
        % 1 number instead of grid
        sca_area_km2 = sum(sum(ascag)) ./ percent2fraction;
        sca_area_km2_yr(1, d, regIdx) = sca_area_km2;
        
        %%%%%%%% SCD %%%%%%%%%
        % Logical image for snow cover days and set to NaN
        % at low elevation to reduce noise
        % (could mask out some low elevation snow)
        bd = logical(thisSnow); %make 0 and 1
        bd = single(bd); %So I can add nans
        bd(ZbelowMin.SCD) = NaN;
        
        % Mean of snow cover days
        if d == 1
            scd_sum(regIdx) = mean(...
                reshape(bd, [numel(bd) 1]), 'omitnan');
        else
            scd_sum(regIdx) = scd_sum(regIdx) + ...
                mean(reshape(bd, [numel(bd) 1]), 'omitnan');
        end
        scd_sum_yr(1, d, regIdx) = scd_sum(regIdx);
        
        % Start with new copy of snow
        % since snow threshold may be different for remaining
        % variables
        thisSnow = single(snow.data);
        thisSnow(outsideRegMask) = NaN;
        
        %%%%%%%% albedo %%%%%%%%%
        % mask albedo for only the area of this partition
        % Only use albedo where:
        % - snow fraction is high enough, and
        % - snow fraction and albedo are not nan
        thisAlbedo = single(albedo.data) ./ albedo.divisor;
        thisAlbedo(outsideRegMask) = NaN;
        thisAlbedo(ZbelowMin.albedo) = NaN;
        thisAlbedo(thisSnow < minSCP.albedo) = NaN;
        thisAlbedo(snowIsMissing) = NaN;
        thisAlbedo(albedo.data == albedo.missingValue) = NaN;
        
        % calculate median for this region and day
        albedo_yr(1, d, regIdx) = nanmedian(thisAlbedo(:));

        %%%%%%%% RF %%%%%%%%%
        % mask RF for only the area of this partition
        % Only use RF where:
        % - snow fraction is high enough, and
        % - snow fraction and RF are not nan
        thisRF = single(RF.data) ./ RF.divisor;
        thisRF(outsideRegMask) = NaN;
        thisRF(ZbelowMin.radiative_forcing) = NaN;
        thisRF(thisSnow < minSCP.radiative_forcing) = NaN;
        thisRF(snowIsMissing) = NaN;
        thisRF(RF.data == RF.missingValue) = NaN;
        
        % calculate median for this region and day
        % FIXME: figure out why the 500 values aren't set to RF.missingValue?
        radiative_forcing_yr(1, d, regIdx) = nanmedian(...
            thisRF(0 < thisRF & thisRF < 500));

        %%%%%%%% DV %%%%%%%%%
        % mask DV for only the area of this partition
        % Only use DV where:
        % - snow fraction is high enough, and
        % - snow fraction and DV are not nan
        thisDV = single(DV.data) ./ DV.divisor;
        thisDV(outsideRegMask) = NaN;
        thisDV(ZbelowMin.deltavis) = NaN;
        thisDV(thisSnow < minSCP.deltavis) = NaN;
        thisDV(snowIsMissing) = NaN;
        thisDV(DV.data == DV.missingValue) = NaN;
        
        % calculate median albedo for this region and day
        deltavis_yr(1, d, regIdx) = nanmedian(thisDV(thisDV > 0));
        
    end
    
end


t1 = toc;
fprintf('%s: Finished summary for water yr=%04d in %s seconds\n', ...
    mfilename(), waterYr, num2str(roundn(t1, -1)));

end

function S = readVarFromMosaic( mosaicFile, varName, ...
    expectedUnits, expectedDivisor )
% Reads variable from mosaicFile, checking for expected units/divisor

    S = readMosaic(mosaicFile, varName);
    S.data = S.(varName);
    S = rmfield(S, varName);
    if ~strcmp(S.units, expectedUnits) || S.divisor ~= expectedDivisor
        errorStruct.identifier = 'statsForLinePlots:MosaicError';
        errorStruct.message = sprintf(...
            ['%s: %s has unexpected %s units %s ' ...
            'or divisor %f\n'], ...
            mfilename(), mosaicFile, varName, ...
            S.units, ...
            S.divisor);
        error(errorStruct);
    end
end
