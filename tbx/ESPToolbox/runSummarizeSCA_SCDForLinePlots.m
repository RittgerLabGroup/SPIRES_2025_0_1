function runSummarizeSCA_SCDForLinePlots(startYr, stopYr,
					 regionName, mindays)
% This script summarizes total snow cover fraction and median snow covered
% days for each day of each year for line graphs for multiple years
% It then calculates the interquartile range and median values

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

    % Thresholds for when to count fSCA as a SCD
    threshSCF = 10; % fSCA threshold below which to ignore (percent)
    threshZ = 1200; % Z threshold below which to ignore (meters)

    % Set the environment
    myEnv = ESPEnv('Summit');

    baseDir = MData.archiveDir;
    zthresh = [1000 1000];

    % Daily regional summary files are stored in this hierarchy
    myEnv.SCAGDRFSDir = fullfile(baseDir, ...
	sprintf('scagdrfs_v01.zthresh%04d%04d_mindays%02dadj', ...
		zthresh(1), zthresh(2), mindays));

    version = 6;
    batchName = 'SnowTodayV00';
    labelName = sprintf( ...
       'mindays%02d_minthresh5_ndsimin0_zthresh10001000', ...
        mindays);

    % Input directory (has daily .mat files)
    %dataDir='/pl/active/rittger_esp/modis/scagdrfs_test/v006/SnowTodayV00/westernUS';
    %dataDir='/Users/kari0458/Desktop/Snow-Today/westernUS';
    %dataDir='/Users/kari0458/Desktop/Snow-Today/scagdrfs_v01.zthresh10001000_mindays15ad/westernUS';

    % Output directory
    %outDir='/pl/active/rittger_esp/modis/scagdrfs_test/v006/SnowTodayV00/summaries_of_these_directories';
    %outDir='/Users/kari0458/Desktop/Snow-Today/summaries_of_these_directories';
    %mkdir(outDir)

    % Elevation dataset and threshold to use for 
    elevationFile = myEnv.modisElevationFile('WesternUS');
    load(elevationFile);

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
	     getenv('SLURM_ARRAY_JOB_ID'))
	parpool(myCluster, myCluster.NumWorkers);
    end

    % KR: App memory appeared to be 43GB on 4 cores
    %parfor y=1:length(yrs)
    %for y=1:length(yrs)
    for y=1:1
	yr = yrs(y);
	[datevalsYr, sca_area_km2_yr(y,:), scd_sum_yr(y,:)] = ...
            summarizeSCA_SCDForLinePlots(myEnv, ...
		yr, threshSCF, Z, threshZ, MData.pixSize_500m);
end
clear Z yr y

return();

% Save the data for plotting using
% line_plot_annual_SCA_SCD_in_context_line.m
save([num2str(yrs(1)) '_to_'  num2str(yrs(end)) '_Summary_snow_percent_lt' num2str(threshSCF) '_and_snow_cover_days_above' ...
    num2str(threshZ) 'm.mat'])
% If it was the historical run, find the meadian, prctiles, min/max
if yrs(1)~=yrs(end)
    % snow fraction
    median_sca_area_km2=median(sca_area_km2_yr);
    prc25_sca_area_km2=prctile(sca_area_km2_yr,25);
    prc75_sca_area_km2=prctile(sca_area_km2_yr,75);
    sca_area_km2_yr_totalsum=nansum(sca_area_km2_yr,2);
    
    %Select min/max year for plotting later
    [~,indx_sca_sum]=sort(sca_area_km2_yr_totalsum,'ascend');
    yr_min=yrs(indx_sca_sum(1));
    yr_max=yrs(indx_sca_sum(end));
    
    % snow cover days
    median_scd_sum=median(scd_sum_yr);
    prc25_scd_sum=prctile(scd_sum_yr,25);
    prc75_scd_sum=prctile(scd_sum_yr,75);
    %scd_sum_yr_totalsum=nansum(scd_sum_yr,2);
    
    % Save all (overwrites previous file)
    save([num2str(yrs(1)) '_to_'  num2str(yrs(end)) ...
        '_Summary_snow_percent_lt' num2str(threshSCF) ...
        '_and_snow_cover_days_above' num2str(threshZ) 'm.mat'])
end
