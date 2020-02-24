function runSummarizeSCA_SCDForLinePlots(regionName, startYr, stopYr, ...
    threshSCF, threshZ, mindays)
% This script summarizes total snow cover fraction and median snow covered
% days for each day of each year for line graphs for multiple years
% It then calculates the interquartile range and median values
%
% Inputs
%   regionName
%   startYr
%   stopYr
%          the follwing inputs control when to count fSCA as a SCD
%   threshSCF: 0-100, fSCA threshold below which to ignore (percent)
%              should default to 10
%   threshZ: elevation threshold (meters) below which to ignore
%              should default to 1200

     % Calculation will be for water years, beginning Oct 1.
     % In early October we should run this for 2001 (beginning of
     % first full water year of MODIS record) to this year.
     % e.g. in early October 2019, do 2001, 2019.
     % For daily updates in current year, startYr == stopYr
     if startYr < stopYr
         yrs = startYr:stopYr;
     elseif startYr == stopYr
         yrs = startYr;
     else
         errorStruct.identifier = ...
             'runSummarizeSCA_SCDForLinePlots:YearError';
         errorStruct.message = sprintf(...
             '%s: startYr=%d should be <= stopYr=%d', ...
             mfilename(), startYr, stopYr);
         error(errorStruct);
     end
     
     MData = MODISData();
     
     % Set the environment to point to location with mosaic files
     myEnv = ESPEnv('Summit');
     
     baseDir = MData.archiveDir;
     zthresh = [1000 1000];
     
     version = 6;
     batchName = 'SnowTodayV00';
     labelName = sprintf( ...
         'mindays%02d_minthresh5_ndsimin0_zthresh10001000', ...
         mindays);
     
     % Daily regional summary files are stored in this hierarchy
     myEnv.SCAGDRFSDir = fullfile(baseDir, ...
         sprintf('scagdrfs_v01.zthresh%04d%04d_mindays%02dadj', ...
         zthresh(1), zthresh(2), mindays));
     
     % Elevation dataset and elevation threshold to use
     elevationFile = myEnv.modisElevationFile(regionName);
     

     % Preallocate vector of snow cover area and days for each
     % year
     maxDaysPerYear = 366;
     sca_area_km2_yr = NaN(length(yrs), maxDaysPerYear);
     scd_sum_yr = NaN(length(yrs), maxDaysPerYear);

     % %Loop and run in parallel opening parpool for historocal
     % if year(date)==yrs(end) && yrs(1)==yrs(end)
     %     %delete(gcp)
     %     parpool(1)%might need modification to run on cluster
     % else
     %     %delete(gcp)
     %     parpool(5);%might need modification to run on cluster
     % end
     
     % If a pool is running already, use it
     % otherwise start a new one
     % Set JobStorageLocation to something that will be
     % unique for each slurm process id and put it on
     % local scratch so ~/.matlab/ doesn't grow indefinitely
     if isempty(gcp('nocreate'))
         myCluster = parcluster('local');
         myCluster.JobStorageLocation = fullfile( ...
             getenv('SLURM_SCRATCH'), ...
             getenv('SLURM_JOB_ID'));
         myPool = parpool(myCluster, myCluster.NumWorkers);
     end

     parfor y=1:length(yrs)
         
         elevationData = load(elevationFile, 'Z');
         
         yr = yrs(y);
         [~, sca_area_km2_yr(y, :), scd_sum_yr(y, :)] = ...
             summarizeSCA_SCDForLinePlots(...
             myEnv, version, batchName, regionName, labelName, ...
             yr, threshSCF, elevationData.Z, threshZ, ...
             MODISData.pixSize_500m, maxDaysPerYear);
     end
     
     % Save all (overwrites previous file)
     % line_plot_annual_SCA_SCD_in_context_line.m
     summaryFile = myEnv.SummarySnowFile(version, batchName, ...
         regionName, yrs(1), yrs(end), threshSCF, threshZ);
     [folder, ~, ~] = fileparts(summaryFile);
     if ~exist(folder, 'dir')
         mkdir(folder);
     end
     save(summaryFile, 'sca_area_km2_yr', 'scd_sum_yr', ...
         'yrs', 'elevationFile', 'threshSCF', 'threshZ', ...
         'version', 'regionName', 'labelName', ...
         'mindays', 'myEnv');
     fprintf('%s: Saved summary to %s\n', mfilename(), summaryFile);
     
     % If it was the historical run, find the median, prctiles, min/max
     if yrs(1) ~= yrs(end)
         
         % snow fraction
         median_sca_area_km2 = median(sca_area_km2_yr);
         prc25_sca_area_km2 = prctile(sca_area_km2_yr, 25);
         prc75_sca_area_km2 = prctile(sca_area_km2_yr, 75);
         sca_area_km2_yr_totalsum = nansum(sca_area_km2_yr, 2);
         
         % Select min/max year for plotting later
         [~, indx_sca_sum] = sort(sca_area_km2_yr_totalsum, 'ascend');
         yr_min = yrs(indx_sca_sum(1));
         yr_max = yrs(indx_sca_sum(end));
         
         % snow cover days
         median_scd_sum = median(scd_sum_yr);
         prc25_scd_sum = prctile(scd_sum_yr, 25);
         prc75_scd_sum = prctile(scd_sum_yr, 75);
         %scd_sum_yr_totalsum=nansum(scd_sum_yr,2);
        
         save(summaryFile, 'median_sca_area_km2', ...
             'prc25_sca_area_km2', 'prc75_sca_area_km2', ...
             'sca_area_km2_yr_totalsum', 'yr_min', 'yr_max', ...
             'indx_sca_sum', ...
             'median_scd_sum', 'prc25_scd_sum', 'prc75_scd_sum', ...
             '-append');
         fprintf('%s: Appended multi-year summary stats to %s\n', ...
             mfilename(), summaryFile);
         
     end

end
