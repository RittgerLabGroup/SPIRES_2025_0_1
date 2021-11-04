function runStatsForLinePlots(...
    regionName, partitionNum, ...					 
    startWaterYr, stopWaterYr, ...
    minSCF, minZ, mindays, zthresh)
% This script summarizes total snow cover fraction and median snow covered
% days for each day of each year for line graphs for multiple years
% It then calculates the interquartile range and median values
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
%   minSCF: 0-100, fSCA threshold below which to ignore (percent)
%         should default to 10
%   minSCFforAlbedo: 0-100, fSCA threshold below which to ignore (percent)
%         for albedo stats  (should default to 30)
%   minZ: elevation threshold (meters) below which to ignore for
%         SCD only
%         should default to 800
%   mindays: mindays for label on mosaic files to read
%   zthresh: North/South elevation threshold on mosaic files to read
%
% Outputs
%   Output will be saved to summary statistic file
%   quartile statistics will also be saved if startWaterYr != stopWaterYr

% Copyright 2020 The Regents of the University of Colorado

    % for testing purposes, writes output file to test location
    doTest = 1;

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

    % Start or connect to the local pool
    % Assumes that caller has set this!
    S = configParPool('jobStorageLocation', getenv('TMPDIR'));
    addAttachedFiles(S.pool, {elevationFile});
    
    parfor y=1:length(yrs)
        %fprintf('%s: PARFOR LOOP FOR YEARS DISABLED FOR TESTING...\n', ...
        %    mfilename());
        %for y=1:length(yrs)
        
        elevationData = load(elevationFile, 'Z');
        
        yr = yrs(y);
        [~, sca_area_km2_yr(y, :, :), scd_sum_yr(y, :, :), ...
            albedo_yr(y, :, :)] = ...
            statsForLinePlots(...
            myEnv, version, regionName, partitions, labelName, ...
            yr, minSCF, elevationData.Z, minZ, ...
	    minSCFforAlbedo, ...
            MODISData.pixSize_500m, maxDaysPerYear);
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
	'albedo_yr', 'minSCFforAlbedo', ... 
        'yrs', 'elevationFile', 'minSCF', 'minZ', ...
        'version', 'regionName', 'partitionName', ...
        'LongName', 'ShortName', ...
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
        albedo_yr_totalsum = nansum(albedo_yr, doyDim);
        
        % For each partition, find min/max year for sca, albedo
        yr_min = zeros(1, npartitions);
        yr_max = zeros(1, npartitions);
        albedo_yr_min = zeros(1, npartitions);
        albedo_yr_max = zeros(1, npartitions);
        for regIdx=1:npartitions
	    % sca
            [~, indx_sca_sum] = sort(...
                sca_area_km2_yr_totalsum(:, regIdx), 'ascend');
            yr_min(regIdx) = yrs(indx_sca_sum(1));
            yr_max(regIdx) = yrs(indx_sca_sum(end));

	    % albedo
            [~, indx_albedo_sum] = sort(...
                albedo_yr_totalsum(:, regIdx), 'ascend');
            albedo_yr_min(regIdx) = yrs(indx_albedo_sum(1));
            albedo_yr_max(regIdx) = yrs(indx_albedo_sum(end));
        end
        
        save(summaryFile, 'median_sca_area_km2', ...
            'prc25_sca_area_km2', 'prc75_sca_area_km2', ...
            'sca_area_km2_yr_totalsum', 'yr_min', 'yr_max', ...
            'indx_sca_sum', ...
            'median_scd_sum', 'prc25_scd_sum', 'prc75_scd_sum', ...
	    'median_albedo', ...
            'prc25_albedo', 'prc75_albedo', ...
            'albedo_yr_totalsum', 'albedo_yr_min', 'albedo_yr_max', ...
            'indx_albedo_sum', ...
            '-append');
        fprintf(['%s: Appended multi-year, multi-region summary ' ...
            'stats to %s\n'], ...
            mfilename(), summaryFile);
        
    end

end
