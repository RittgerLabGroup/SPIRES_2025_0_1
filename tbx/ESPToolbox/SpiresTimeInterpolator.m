classdef SpiresTimeInterpolator < handle
  % Handle temporal detection of valid observations and temporal interpolating of the
  % gap data.
  properties
    pixelIsInterpolated % int. array of progress of interpolating pixels,
      % 0: not interpolated, 1: interpolated.
    region  % Regions Obj.
  end
  properties(Constant)
    dataLabels = struct(mod09ga = 'modspirestimebycell', ...
        vnp09ga = 'vnpspirestimebycell');
  end
  methods
    function obj = SpiresTimeInterpolator(region)
      % Parameters
      % ----------
      % region: Regions obj. Modis tile only.
      thisFunction = 'SpiresTimeInterpolator.SpiresTimeInterpolator';
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      obj.region = region;

      fprintf(['%s: Created SpiresTimeInterpolator, region: %s.\n'], ...
        thisFunction, region.name);
    end
    function interpolate(obj, waterYearDate, monthWindows, varargin)
      % Detection of valid observations and temporal interpolation of
      % viewable_snow_fraction, (corrected) snow_fraction, grain_size and
      % dust_concentration over the waterYear.
      % For the start of the waterYear, uses data of the late previous water year.
      %
      % NB: script derived from Ned's smoothSPIREScube.m
      %
      % Parameters
      % ----------
      % waterYearDate: WaterYearDate obj.
      % monthWindows: [int, int]. Number of months before and
      %   after the start and end dates of waterYearDate that are used for interpolation
      %   (but the results for these days are not saved). E.g. [3, 0] for include the 3
      %   previous months but nothing after waterYearDate.
      % optim: struct(cellIdx, countOfCellPerDimension, force, logLevel,
      %       parallelWorkersNb).
      %   cellIdx: array(int), optional. [rowCellIdx, columnCellIdx].
      %       Indices of the cell part of a tile. Row indices are counted from
      %       top to bottom, column indices from left to right. Default [1, 1].
      %   countOfCellPerDimension: array(int), optional.
      %       [rowCellCount, columnCellCount]. Number of cells dividing the set of
      %       rows and same for columns. E.g. if we want to divide a 2400x2400
      %       tile in 9 cells, countOfCellPerDimension = [3, 3]. Default [1, 1].
      %   force: int, optional. Default 0. Unused.
      %   logLevel: int, optional. Indicate the density of logs.
      %       Default 0, all logs. The higher the less logs.
      %   parallelWorkersNb: int, optional. If 0 (default), no parallelism.
      thisTimer = tic;
      thisFunction = 'SpiresTimeInterpolator.interpolate';
      thisFunctionCode = 'spiTimeI';
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      logger = Logger('spiTimeI');
      logger.printDurationAndMemoryUse(dbstack);
      espEnv = obj.region.espEnv;
      modisData = espEnv.modisData;
      objectName = obj.region.name;

      defaultOptim = struct(cellIdx = [1, 1], ...
        countOfCellPerDimension = [1, 1], force = 0, logLevel = 0, ...
        parallelWorkersNb = 0);

      p = inputParser;
      addParameter(p, 'optim', struct());
      p.StructExpand = false;
      parse(p, varargin{:});
      optim = p.Results.optim;

      optimFieldNames = fieldnames(defaultOptim);
      for fieldIdx = 1:length(optimFieldNames)
        thisFieldName = optimFieldNames{fieldIdx};
        if ~ismember(thisFieldName, fieldnames(optim))
          optim.(thisFieldName) = defaultOptim.(thisFieldName);
        end
      end % fieldIx
      fprintf(['%s %s: STARTING, region: %s, waterYearDate: %s, ', ...
        'monthWindows: [%s], cellIdx: [%s], countOfCellPerDimension: [%s], ', ...
        'force: %d, logLevel: %d, ', ...
        'parallelWorkersNd: %d...\n'], thisFunction, thisFunctionCode, objectName, ...
        waterYearDate.toChar(), join(num2str(monthWindows), ', '), ...
        join(num2str(optim.cellIdx), ', '), ...
        join(num2str(optim.countOfCellPerDimension), ', '), ...
        optim.force, optim.logLevel, optim.parallelWorkersNb);

      % Determination of the time window for valid observation detection and
      % interpolation, based on raw_viewable_snow_fraction_s data.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      waterYear = waterYearDate.getWaterYear();
      theseDates = waterYearDate.getDailyDatetimeRange();
      inputWaterYearDate = WaterYearDate(waterYearDate.thisDatetime + ...
        calmonths(monthWindows(2)), ...
        waterYearDate.firstMonth, waterYearDate.monthWindow + ...
          monthWindows(1) + monthWindows(2), ...
        dateOfToday = waterYearDate.dateOfToday, overlapOtherYear = 1);

      inputDataLabel = SpiresInversor.dataLabels.(modisData.inputProduct);
      outputDataLabel = obj.dataLabels.(modisData.inputProduct);
      varName = 'raw_viewable_snow_fraction_s';
      outputVarName = 'viewable_snow_fraction_s';

      [varData, waterYearDateInFiles] = espEnv.getDataForWaterYearDateAndVarName( ...
        objectName, inputDataLabel, inputWaterYearDate, varName, optim = optim);
      thisSize = size(varData);
      d_viewable_snow_fraction_s = varData;
      d_viewable_snow_fraction_s = reshape(d_viewable_snow_fraction_s, ...
        [thisSize(1) * thisSize(2), thisSize(3)]); % 1st dim: pixelIdx, 2nd dim: time.
      varData = [];
      inputDates = waterYearDateInFiles.getDailyDatetimeRange();
      dateIndicesToSave = find(ismember(inputDates, theseDates));
        % only these days will be saved in the output file.

      % Determination of the pixels to interpolate.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

      varName = 'daily_nodata_filter_s';
      dailyNoDataFilter = reshape(espEnv.getDataForWaterYearDateAndVarName( ...
        objectName, inputDataLabel, waterYearDateInFiles, varName, ...
        optim = optim), [thisSize(1) * thisSize(2), thisSize(3)]);
        % daily_nodata_filter: uint8, position 1: hasNoInput, 2: neuralCloud,
        % 3: background reflectance nodata, 4: rareObservation. 5: STC cloud.
        % 6: Cloud extension. 7: Saltpan and isolated.
      if ~strcmp(modisData.inputProduct, 'mod09ga')
        dailyNoDataFilter = bitset(dailyNoDataFilter, 2, 0);
      end % Neural cloud doesnt work for viirs.
      dailyNoDataFilter = bitset(dailyNoDataFilter, 4, 0);
        % Remove of any previous setting of the rare observation flag.
      varName = 'daily_zero_filter_s';
      dailyZeroFilter = reshape(espEnv.getDataForWaterYearDateAndVarName( ...
        objectName, inputDataLabel, waterYearDateInFiles, varName, ...
        optim = optim), [thisSize(1) * thisSize(2), thisSize(3)]);
        % daily_zero_filter: uint8, Bit, position 1: NeuralNeither, excluding
        % state_1km.clouds and including state_1km.saltpans, 2: NDSIBelowMinus005,
        % 3: rawSnowBelow10, 4: rawGrainBelow40, 5: lowElevation, 6: waterBody,
        % 7: rawSnowEquals0.
      if ~strcmp(modisData.inputProduct, 'mod09ga')
        dailyZeroFilter = bitset(dailyZeroFilter, 1, 0);
      end % Neural cloud doesnt work for viirs.

      % Definition of no data before interpolation.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      parameterName = 'noDataDefinitionBeforeSmoothing';
      noDataDefinitionBeforeSmoothing = ...
        Tools.valueInTableForThisField( ...
        obj.region.filter.spires, 'lineName', ...
        parameterName, 'minValue');
        % 0 for v2024.1.0/v2025.0.0, 1 for higher versions.

      if noDataDefinitionBeforeSmoothing == 0
        % v2024.1.0/v2025.0.0.
        snowIsNoData = ( ...
          dailyNoDataFilter | bitget(dailyZeroFilter, 6) ...
          ) ...
          & ~bitget(dailyZeroFilter, 5);
      else
        snowIsNoData = ( ...
          dailyNoDataFilter | ...
            ( ...
              (bitget(dailyZeroFilter, 3) | bitget(dailyZeroFilter, 4)) & ...
              ~bitget(dailyZeroFilter, 1) & ~bitget(dailyZeroFilter, 2) & ...
              ~bitget(dailyZeroFilter, 7) ...
            ) ...
          ) ...
          & ~bitget(dailyZeroFilter, 5) & ~bitget(dailyZeroFilter, 6);
        % We consider a pixel as nodata when:
        % - no input, no background reflectance (only Neds files), cloud, or saltpan.
        % - viewable_snow_fraction <= 10 or grain_size <= 40, except if detected as 0
        %   by neural network or ndsi or by spires inversion.
        % - the 2 previous except if the pixel is water or below an elevation threshold
        %   (this last only for v2024.0d (v2024.1.0 and earlier).
      end
      d_daily_nodata_filter_s = dailyNoDataFilter;
      dailyNoDataFilter = [];

      % Definition of zero snow fraction before interpolation.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      parameterName = 'zeroDefinitionBeforeSmoothing';
        zeroDefinitionBeforeSmoothing = ...
      Tools.valueInTableForThisField( ...
      obj.region.filter.spires, 'lineName', ...
      parameterName, 'minValue');
      % 0 for v2024.1.0/v2025.0.0, 1 for higher versions.

      if zeroDefinitionBeforeSmoothing == 0
        % v2024.1.0/v2025.0.0.
        snowIsZero = ( ...
          bitget(dailyZeroFilter, 1) | bitget(dailyZeroFilter, 2) | ...
          bitget(dailyZeroFilter, 3) | bitget(dailyZeroFilter, 4) | ...
          bitget(dailyZeroFilter, 5) | bitget(dailyZeroFilter, 7) ...
          ) ...
          & ~snowIsNoData;
        fprintf('Starting moving persist...\n');
        parameterName = 'gapRareObservationSlidingWindowHalfSize';
        gapRareObservationSlidingWindowHalfSize = ...
          Tools.valueInTableForThisField( ...
          obj.region.filter.spires, 'lineName', ...
          parameterName, 'minValue');
          % 40 in v2024.1.0, former windowSize.

        parameterName = 'gapRareObservationMinDayWithObservationAboveMinValue';
        gapRareObservationSlidingWindowHalfSize = ...
          Tools.valueInTableForThisField( ...
          obj.region.filter.spires, 'lineName', ...
          parameterName, 'minValue');
          % 20 in v2024.1.0, former windowThresh.
        isValidObservedSnow = ~bitget(dailyZeroFilter, 3) & ...
          ~bitget(dailyZeroFilter, 4) & ~snowIsNoData & ~snowIsZero;
          % snow fraction above 10 and grain size above 40.
        isNotRareObservation = obj.movingPersist(isValidObservedSnow, ...
          windowSize, windowThresh);
        dailyNoDataFilter = bitset(dailyNoDataFilter, 4, ...
          ~isNotRareObservation & isValidObservedSnow);
          % output of movingPersist() saved as the rare observation flag. This flag
          % is set with another method below for versions higher than v2025.0.0.
        snowIsZero = snowIsZero | bitget(dailyNoDataFilter, 4);
      else
        % v2025.0.1+.
        snowIsZero = ( ...
          bitget(dailyZeroFilter, 1) | bitget(dailyZeroFilter, 2) | ...
          bitget(dailyZeroFilter, 5) | bitget(dailyZeroFilter, 6) | ...
          bitget(dailyZeroFilter, 7) ...
          ) ...
          & ~snowIsNoData;
      end
      dailyZeroFilter = [];
      d_viewable_snow_fraction_s(snowIsNoData) = intmax('uint8');
      d_viewable_snow_fraction_s(snowIsZero) = 0;

      % Loading of the other variables.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      varName = 'raw_snow_fraction_s';
      outputVarName = 'snow_fraction_s';
      d_snow_fraction_s = reshape(espEnv.getDataForWaterYearDateAndVarName( ...
        objectName, inputDataLabel, waterYearDateInFiles, varName, ...
        optim = optim), [thisSize(1) * thisSize(2), thisSize(3)]);
      d_snow_fraction_s(snowIsNoData) = intmax('uint8');
      d_snow_fraction_s(snowIsZero) = 0;

      varName = 'snow_cover_days_s';
      % TEMPORARY dirty, to remove once all daily tif files ok, in production. 20240912.
      d_snow_cover_days_s = zeros(thisSize, 'uint16');
      waterYearDateInFilesTMP = waterYearDateInFiles.copy();
      tmpData = espEnv.getDataForWaterYearDateAndVarName( ...
        objectName, inputDataLabel, waterYearDateInFilesTMP, varName, ...
        optim = optim);
      d_snow_cover_days_s(:, :, 1:size(tmpData, 3)) = tmpData;
      tmpData = [];
      d_snow_cover_days_s = reshape(d_snow_cover_days_s, ...
        [thisSize(1) * thisSize(2), thisSize(3)]);
%{
      % TO REINSTORE:
      d_snow_cover_days_s = reshape(espEnv.getDataForWaterYearDateAndVarName( ...
        objectName, inputDataLabel, waterYearDateInFiles, varName, ...
        optim = optim), [thisSize(1) * thisSize(2), thisSize(3)]);
%}
      % END TEMPORARY.
      % Check to be certain that the calculation take the value of snow cover day
      % of the eve of the starting day of waterYearDate, or if first date of waterYear
      % start at zero.
      firstDateOfWaterYear = waterYearDate.getFirstDatetimeOfWaterYear();
      if ismember(firstDateOfWaterYear, inputDates)
        firstDateOfWaterYearIdx = find(inputDates == firstDateOfWaterYear);
        d_snow_cover_days_s(:, 1:firstDateOfWaterYearIdx - 1) = 0;
      end

      varName = 'spatial_grain_size_s';
      outputVarName = 'grain_size_s';
      d_grain_size_s = reshape(espEnv.getDataForWaterYearDateAndVarName( ...
        objectName, inputDataLabel, waterYearDateInFiles, varName, ...
        optim = optim), [thisSize(1) * thisSize(2), thisSize(3)]);

      varName = 'spatial_dust_concentration_s';
      outputVarName = 'dust_concentration_s';
      d_dust_concentration_s = reshape(espEnv.getDataForWaterYearDateAndVarName( ...
        objectName, inputDataLabel, waterYearDateInFiles, varName, ...
        optim = optim), [thisSize(1) * thisSize(2), thisSize(3)]);

      % Resampling of weights for viirs.
      parameterName = 'imresizeInterpolationMethod';
      parameterValue = ...
        Tools.valueInTableForThisField( ...
        obj.region.filter.spires, 'lineName', ...
        parameterName, 'minValue');
        % 1: nearest, 2: bilinear, 3: bicubic.
      thoseImresizeMethod = {'nearest', 'bilinear', 'bicubic'};
      resamplingMethod = thoseImresizeMethod{parameterValue};
      force = struct( ...
        resamplingFactor = 1, resamplingMethod = resamplingMethod);
      varName = 'time_interp_weight_s';
      weight = reshape(espEnv.getDataForWaterYearDateAndVarName( ...
        objectName, inputDataLabel, waterYearDateInFiles, varName, ...
        force = force, optim = optim), [thisSize(1) * thisSize(2), thisSize(3)]);

      d_days_with_snow_observed_s = ...
          zeros([thisSize(1) * thisSize(2), thisSize(3)], 'uint16');
      d_days_with_absent_snow_observed_s = d_days_with_snow_observed_s;
      d_days_without_observation_s = d_days_with_snow_observed_s;


      % Configuration parameters.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      setToNoObservationBelowThisNumberOfDaysOfSnow = ...
        Tools.valueInTableForThisField( ...
        obj.region.filter.spires, 'lineName', ...
        'setToNoObservationBelowThisNumberOfDaysOfSnow', 'minValue'); % 3.
      setToNoObservationBelowThisNumberOfDaysOfAbsentSnow = ...
        Tools.valueInTableForThisField( ...
        obj.region.filter.spires, 'lineName', ...
        'setToNoObservationBelowThisNumberOfDaysOfAbsentSnow', 'minValue'); % 3.
      setToNoObservationBelowThisValueOfRawSnowFraction = ...
        Tools.valueInTableForThisField( ...
        obj.region.filter.spires, 'lineName', ...
        'setToNoObservationBelowThisValueOfRawSnowFraction', 'minValue'); % 10 per cent.
      setToNoObservationBelowThisValueOfSpatialGrainSize = ...
        Tools.valueInTableForThisField( ...
        obj.region.filter.spires, 'lineName', ...
        'setToNoObservationBelowThisValueOfSpatialGrainSize', 'minValue'); % 40 microns.
      smoothingSplineParamForSnowAndDust = ...
        Tools.valueInTableForThisField( ...
        obj.region.filter.spires, 'lineName', ...
        'smoothingSplineParamForSnowAndDust', 'minValue'); % 0.1.
      smoothingSplineParamForGrainSize = ...
        Tools.valueInTableForThisField( ...
        obj.region.filter.spires, 'lineName', ...
        'smoothingSplineParamForGrainSize', 'minValue'); % 0.8.
      snowCoverDayIsSetToZeroIfSnowFractionBelowThisValue = ...
        Tools.valueInTableForThisField( ...
        obj.region.filter.spires, 'lineName', ...
        'snowCoverDayIsSetToZeroIfSnowFractionBelowThisValue', 'minValue'); % 10.
      smoothingDustSetToZeroBeforeGrainSizeMaxWhenBelowGrainSizeValue = ...
        Tools.valueInTableForThisField( ...
        obj.region.filter.spires, 'lineName', ...
        'smoothingDustSetToZeroBeforeGrainSizeMaxWhenBelowGrainSizeValue', ...
        'minValue'); % 300 (microns).
      timeDetectionMethodForFalsePositive = ...
        Tools.valueInTableForThisField( ...
        obj.region.filter.spires, 'lineName', ...
        'timeDetectionMethodForFalsePositive', ...
        'minValue'); % 1 for v2025.0.1, 0 before.

      % Fixing peak of grain/size at the end of the season or not.
      minMonthWindowForFixPeak = ...
        Tools.valueInTableForThisField( ...
        obj.region.filter.spires, 'lineName', ...
        'minMonthWindowForFixPeak', 'minValue'); % 8, fix peak carried out starting
        % in may for north hemisphere.
      if waterYearDate.monthWindow < minMonthWindowForFixPeak
        peakGrainSizeIsToFix = 0;
      else
        peakGrainSizeIsToFix = 1;
      end
      if length(theseDates) < 365
        peakFixingDayWithoutCorrection = 0;
      else
        peakFixingDayWithoutCorrection = ...
          Tools.valueInTableForThisField( ...
          obj.region.filter.spires, 'lineName', ...
          'minMonthWindowForFixPeak', 'minValue'); % 7. the last days decrease to 0
          % in may for north hemisphere.
      end
      peakFixingMaximalDurationInDay = ...
        Tools.valueInTableForThisField( ...
        obj.region.filter.spires, 'lineName', ...
        'peakFixingMaximalDurationInDay', 'minValue'); % 40 days.
      [outputVariable, ~] = espEnv.getVariable(outputDataLabel, ...
        inputDataLabel = inputDataLabel);
        % NB: here the input and output data are in application of same class and
        % nodata, min, max.
      iceFraction = reshape( ...
        espEnv.getDataForObjectNameDataLabel(objectName, 'icened', optim = optim), ...
        [1, thisSize(1) * thisSize(2)]);

      tic
      fprintf(['Start of the calculation of temporal filter and interpolation of', ...
        ' variables for each pixel...\n']);
      thisDataQueue = parallel.pool.DataQueue;
      obj.pixelIsInterpolated = ...
        zeros([1, size(d_viewable_snow_fraction_s, 1)], 'uint32');
      afterEach(thisDataQueue, @obj.printPixelIsInterpolated);

      parfor pixelIdx = 1:size(d_viewable_snow_fraction_s, 1)
        espEnv.checkSlurmJobStatus();
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % Temporal sliding window to determine if we have enough pixels for smoothing
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % fprintf('Temporal filter to filter periods with enough observations...\n');
        % If not enough pixels, suggest cloudy period.
        thisViewableSnowFraction = d_viewable_snow_fraction_s(pixelIdx, :)';
        thisIsData = ones(size(thisViewableSnowFraction), 'int16');
        thisIsData(thisViewableSnowFraction == intmax('uint8')) = intmax('int16');
        thisIsData(thisViewableSnowFraction == 0) = 0;
        % Periods of days with snow observed.
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        thisDaySinceObservationZero  = ones(size(thisIsData), 'int16');
          % int16 to make diff, which can be negative.
        thisDaySinceObservationZero(thisIsData == intmax('int16') | thisIsData ~= 0) = 0;

        indicesForPeriods = cumsum([1; abs(diff(thisDaySinceObservationZero, 1, 1))]);

        isEqualSuccessiveIndicesForPeriods = ...
          int16([1; indicesForPeriods(1:end - 1, :)] == indicesForPeriods);

        thisDaySinceObservationZeroWithOne = thisIsData; % zeros(size(z));
        thisDaySinceObservationZeroWithOne(thisDaySinceObservationZeroWithOne == intmax('int16')) = 0; % thisDaySinceObservationZeroWithOne(1) = isnan(z(1)) | z(1) ~= 0;
        for rowIdx = 2:size(thisDaySinceObservationZeroWithOne, 1)
          thisDaySinceObservationZeroWithOne(rowIdx) = ...
            thisDaySinceObservationZeroWithOne(rowIdx) ...
            + isEqualSuccessiveIndicesForPeriods(rowIdx) * ...
            thisDaySinceObservationZeroWithOne(rowIdx -1);
          %thisDaySinceObservationZeroWithOne(rowIdx) = isEqualSuccessiveIndicesForPeriods(rowIdx) ...
          %   .* thisIsData(rowIdx) + isEqualSuccessiveIndicesForPeriods(rowIdx) * thisDaySinceObservationZeroWithOne(rowIdx -1);
        end

        thisDayWithSnowObserved = thisDaySinceObservationZeroWithOne;
        for rowIdx = size(thisDayWithSnowObserved, 1) - 1: -1: 1
          thisDayWithSnowObserved(rowIdx) = ...
            isEqualSuccessiveIndicesForPeriods(rowIdx + 1) ...
            .* thisDayWithSnowObserved(rowIdx + 1) + ...
            int16(~isEqualSuccessiveIndicesForPeriods(rowIdx + 1)) ...
            .* thisDayWithSnowObserved(rowIdx);
        end
        d_days_with_snow_observed_s(pixelIdx, :) = uint16(thisDayWithSnowObserved)';

        % Periods with absent snow observed.
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        thisDaySinceObservationSnow  = ones(size(thisIsData), 'int16');
          % int16 to make diff, which can be negative.
        thisDaySinceObservationSnow(thisIsData == intmax('int16') | thisIsData ~= 1) = 0;

        indicesForPeriods = cumsum([1; abs(diff(thisDaySinceObservationSnow, 1, 1))]);

        isEqualSuccessiveIndicesForPeriods = ...
          int16([1; indicesForPeriods(1:end - 1, :)] == indicesForPeriods);

        thisDaySinceObservationSnowWithAbsent = zeros(size(thisIsData));
        thisDaySinceObservationSnowWithAbsent(thisIsData == 0) = 1;
        thisDaySinceObservationSnowWithAbsent(thisIsData == 1) = 0;
        thisDaySinceObservationSnowWithAbsent(thisIsData == intmax('int16')) = 0;
        for rowIdx = 2:size(thisDaySinceObservationSnowWithAbsent, 1)
          thisDaySinceObservationSnowWithAbsent(rowIdx) = ...
            thisDaySinceObservationSnowWithAbsent(rowIdx) + ...
            isEqualSuccessiveIndicesForPeriods(rowIdx) * ...
            thisDaySinceObservationSnowWithAbsent(rowIdx -1);
        end

        thisDayWithAbsentSnowObserved = thisDaySinceObservationSnowWithAbsent;
        for rowIdx = size(thisDayWithAbsentSnowObserved, 1) - 1: -1: 1
          thisDayWithAbsentSnowObserved(rowIdx) = ...
            isEqualSuccessiveIndicesForPeriods(rowIdx + 1) ...
            .* thisDayWithAbsentSnowObserved(rowIdx + 1) + ...
            int16(~isEqualSuccessiveIndicesForPeriods(rowIdx + 1)) ...
            .* thisDayWithAbsentSnowObserved(rowIdx);
        end
        d_days_with_absent_snow_observed_s(pixelIdx, :) = ...
          uint16(thisDayWithAbsentSnowObserved)';

        % Periods with no observation.
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        thisDaySince = ones(size(thisIsData), 'int16');

        % Determine which day is without observation.
        thisDaySince(thisIsData ~= intmax('int16')) = 0;

        indicesForPeriods = cumsum([1; abs(diff(thisDaySince, 1, 1))]);
        isEqualSuccessiveIndicesForPeriods = ...
          int16([1; indicesForPeriods(1:end - 1, :)] == indicesForPeriods);
        indicesForPeriods = [];

        for rowIdx = 2:size(thisDaySince, 1)
          thisDaySince(rowIdx) = isEqualSuccessiveIndicesForPeriods(rowIdx) ...
            .* thisDaySince(rowIdx - 1) + thisDaySince(rowIdx);
        end

        thisDayWithout = thisDaySince;
        for rowIdx = size(thisDayWithout, 1) - 1: -1: 1
          thisDayWithout(rowIdx) = ...
            isEqualSuccessiveIndicesForPeriods(rowIdx + 1) ...
            .* thisDayWithout(rowIdx + 1) + ...
            int16(~isEqualSuccessiveIndicesForPeriods(rowIdx + 1)) ...
            .* thisDayWithout(rowIdx);
        end
        d_days_without_observation_s(pixelIdx, :) = ...
          uint16(thisDayWithout)';

        if timeDetectionMethodForFalsePositive == 1
          fprintf(['Set rare observation flag with method based on days without ',...
            'observations...\n']);
          % 2. take the number of days with observations how many observations > 10
          % after the last 0 observed do we have in the last weeks.
            % for each day, calculate the number of days with snow between 2 zeros.
            % NB: in Ned's model, all these pixels are set to 0, including those with
            % ice clouds
          % No application of moving Window as a test but let appear a lot of snow which
          % are actually clouds. Seb 20241026.
          thisDayWithinRareObservations = thisDayWithSnowObserved < ...
            setToNoObservationBelowThisNumberOfDaysOfSnow & ...
            thisDayWithSnowObserved > 0;
            % all periods when there are less than 5 days of observed snow are set to no
            % data.
          thisDayWithinRareObservations = thisDayWithinRareObservations | ...
            (thisDayWithAbsentSnowObserved < ...
            setToNoObservationBelowThisNumberOfDaysOfAbsentSnow & ...
            thisDayWithAbsentSnowObserved > 0);
            % all periods when there are less than 3 days of observed absent snow are
            % set to no data.
            % NB: There's a problem here with false absent snow linked to the
            % application of ndsi, which doesnt work well with reflectance below 10.
            % NB: This filter forces a reset of snow when there's only one zero in a
            % series. It would be nice to correct that behavior.
          thisDailyNoDataFilter = d_daily_nodata_filter_s(pixelIdx, :)';
          thisDailyNoDataFilter = bitset(thisDailyNoDataFilter, 4, ...
            thisDayWithinRareObservations);
          d_daily_nodata_filter_s(pixelIdx, :) = thisDailyNoDataFilter';

          thisViewableSnowFraction(thisDayWithinRareObservations) = intmax('uint8');
        end
        thisDayWithout = [];
        thisDayWithSnowObserved = [];
        thisDayWithAbsentSnowObserved = [];

        thisSnowIsNoData = thisViewableSnowFraction == intmax('uint8');
        thisSnowIsZero = thisViewableSnowFraction == 0;

        % Handling of the pixels without observation over the full period.
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % NB: Contrary to Ned, all pixels in water are set to 0, and not nodata.
        % NB: to smooth using the fit function, we need at least two observations.
        if sum(~thisSnowIsNoData & ~thisSnowIsZero) < ...
          max(setToNoObservationBelowThisNumberOfDaysOfSnow, 2)
          d_viewable_snow_fraction_s(pixelIdx, :) = 0;
          d_snow_fraction_s(pixelIdx, :) = 0;
          d_snow_cover_days_s(pixelIdx, :) = 0;
          d_grain_size_s(pixelIdx, :) = intmax('uint16');
          d_dust_concentration_s(pixelIdx, :) = intmax('uint16');
          continue;
        end

        % Interpolation of viewable_snow_fraction_s.
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        thisOutputVariable = outputVariable(outputVariable.id == 54, :);
        x = (1:size(thisViewableSnowFraction, 1))';
        y = thisViewableSnowFraction;
        thisWeight = weight(pixelIdx, :)';
        F = fit(x, double(y), 'smoothingspline', ...
          weights = double(thisWeight), ...
          exclude = thisSnowIsNoData, ...
          SmoothingParam = smoothingSplineParamForSnowAndDust);
        y = uint8(max(min(F(x), thisOutputVariable.max(1)), thisOutputVariable.min(1)));
        y(y <= setToNoObservationBelowThisValueOfRawSnowFraction) = 0;
        % As for STC, 20241107.
        % For any fitted values past the last date with a
        % measured value, the spline can produce a large "bullwhip"
        % artifact
        % Find fitted values after the last date with a measured value
        % and propagate the last "believable" fitted value to end
        % This overwrites the spline "bullwhip"
        lastIdxWithObservation = find(thisSnowIsNoData == 0, 1, 'last');
        y(lastIdxWithObservation:length(y)) = y(lastIdxWithObservation);
        d_viewable_snow_fraction_s(pixelIdx, :) = y';
        thisViewableSnowFraction = d_viewable_snow_fraction_s(pixelIdx, :)';

        % Interpolation of snow_fraction_s.
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        thisOutputVariable = outputVariable(outputVariable.id == 54, :);
        y = d_snow_fraction_s(pixelIdx, :)';
        F = fit(x, double(y), 'smoothingspline', ...
          weights = double(thisWeight), ...
          exclude = thisSnowIsNoData, ...
          SmoothingParam = smoothingSplineParamForSnowAndDust);
        y = uint8(max(min(F(x), thisOutputVariable.max(1)), ...
          double(iceFraction(pixelIdx))));
        y(thisViewableSnowFraction ...
          <= setToNoObservationBelowThisValueOfRawSnowFraction) = 0;
          % NB: Apparently this also helps to remove the small bumps close to zero
          % of the spline that doesn't correspond to any data, e.g. h09v05 pixel 3,
          % november 2024.
        y(lastIdxWithObservation:length(y)) = y(lastIdxWithObservation);
        d_snow_fraction_s(pixelIdx, :) = y';

        thisSnowIsAboveMinimum = ...
          y > snowCoverDayIsSetToZeroIfSnowFractionBelowThisValue;

        % Calculation of snowCoverDays.
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % NB: no elevation threshold.
        varName = 'snow_cover_days_s';
        thisSnowCoverDay = d_snow_cover_days_s(pixelIdx, :)';
        thisSnowCoverDay(dateIndicesToSave) = ...
          uint16(thisSnowIsAboveMinimum(dateIndicesToSave));
        thisSnowCoverDay = cumsum(thisSnowCoverDay);
        d_snow_cover_days_s(pixelIdx, :) = thisSnowCoverDay';

        % Interpolation of grain_size_s and dust_concentration_s.
        % (if snow fraction above 10).
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        % NB: in Ned's version, there doesnt seem to be a restriction for grain size
        % on snow fraction below 10.
        thisGrainSize = d_grain_size_s(pixelIdx, :)';
        thisDustConcentration = d_dust_concentration_s(pixelIdx, :)';
        grainSizeOutputVariable = outputVariable(outputVariable.id == 57, :);
        dustConcentrationOutputVariable = outputVariable(outputVariable.id == 58, :);
        grainSizeSetToNoData = thisSnowIsNoData | thisSnowIsZero | ...
          thisGrainSize < setToNoObservationBelowThisValueOfSpatialGrainSize | ...
          thisGrainSize > grainSizeOutputVariable.max(1) | ...
          (thisDustConcentration > dustConcentrationOutputVariable.max(1) & ...
          thisDustConcentration ~= intmax('uint16'));
          % NB: ~thisSnowIsAboveMinimum includes thisSnowIsNoData and thisSnowIsZero
        dustConcentrationSetToNoData = ...
          grainSizeSetToNoData | thisDustConcentration == intmax('uint16');
        if sum(~grainSizeSetToNoData) < 2
          d_grain_size_s(pixelIdx, :) = intmax('uint16');
          d_dust_concentration_s(pixelIdx, :) = intmax('uint16');
          continue;
        end
          % We assume here that by default when there's not enough grain size valid,
          % there'll be even less dust concentration valids (because the higher snow
          % fraction threshold.

        thisGrainSize(grainSizeSetToNoData) = intmax('uint16');
        thisDustConcentration(dustConcentrationSetToNoData) = intmax('uint16');

        % Near real time early season.
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        if ~peakGrainSizeIsToFix
          % Interpolation of grain_size_s.
          %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
          y = thisGrainSize;
          y(1) = 0; % to avoid high values at start of the season. Doesnt work that much
            % because of the spline nature.
          F = fit(x, double(y), 'smoothingspline', ...
            weights = double(thisWeight), ...
            exclude = [0; grainSizeSetToNoData(2:end)], ...
            SmoothingParam = smoothingSplineParamForGrainSize);
          y = F(x);
          y(lastIdxWithObservation:length(y)) = y(lastIdxWithObservation);
          thisGrainSize = y;

          % Interpolation of dust_concentration_s.
          %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
          if sum(~dustConcentrationSetToNoData) >= 2
            thisDustConcentration(thisGrainSize <= ...
              smoothingDustSetToZeroBeforeGrainSizeMaxWhenBelowGrainSizeValue) = 0;
              % 300 mic.
              % Here we restrict a lot the observations, which make the fit very
              % impacted only by a few observations...                          @warning
            y = thisDustConcentration;
            y(1) = 0; % to avoid high values at start of the season.
            F = fit(x, double(y), 'smoothingspline', ...
                weights = double(thisWeight), ...
                exclude = [0; dustConcentrationSetToNoData(2:end)], ...
                SmoothingParam = smoothingSplineParamForSnowAndDust);
            y = F(x);
            y(lastIdxWithObservation:length(y)) = y(lastIdxWithObservation);
            thisDustConcentration = y;
          else
            thisDustConcentration = ...
              intmax('uint16') * ones(size(thisDustConcentration), 'uint16');
          end
          % Near real time spring and late season, or historic full wateryear.
          % Seb 2024-05-23: peak for NRT. Cannot work as for historic because when
          % there is still snow on the last day of NRT record, we don't know if it's
          % the last day of snow.
          % NB: This corrrection is done because as snow recedes, some mixed pixels
          % artificially get lower grain size with the unmixing, because soil and
          % vegetation are uncovered.
          %
        else % if ~peakGrainSizeIsToFix
          % Grain size.
          %%%%%%%%%%%%%

          % set values after peak grain radius to peak
          thisGrainSize = double(thisGrainSize);
          thisGrainSize(grainSizeSetToNoData) = NaN;
          thisGrainSize = hampel(thisGrainSize, 2, 2);
          thisGrainSize(grainSizeSetToNoData) = NaN;

            % remove spikes and drops.
          lastIdxWithObservation = find(grainSizeSetToNoData == 0, 1, 'last');
            % meltOutday. If no obs, we shouldn't be there.
          [valueOfLastDayWithMaximum, lastDayWithMaximum] = ...
            max([repmat(NaN, [lastIdxWithObservation - ...
            peakFixingMaximalDurationInDay, 1]); ...
            double(thisGrainSize( ...
              max(1, lastIdxWithObservation - ...
              peakFixingMaximalDurationInDay + 1):end))]);
            % Day when grain size reached the peak just before melting.

          % We only interpolate the pixels having enough data until the last day with
          % maximum included.
          if lastDayWithMaximum > 2 && ...
            sum(~grainSizeSetToNoData(1:lastDayWithMaximum)) >= 2

            % Set 1st day to min, helps with keeping spline in check.
            thisGrainSize(1) = grainSizeOutputVariable.min(1);
            thisWeight(1) = 1;

            % a. From start to day before max grain size.
            % NB: to obtain F, we include the lastDayWithMaximum, to be sure to have
            % at least 2 days with data.
            x = (1:lastDayWithMaximum - 1)';
            y = thisGrainSize(1:lastDayWithMaximum);
            F = fit([x; lastDayWithMaximum], y, 'smoothingspline', ...
                weights = double(thisWeight([x; lastDayWithMaximum])), ...
                exclude = [0; grainSizeSetToNoData(2:lastDayWithMaximum - 1)], ...
                SmoothingParam = smoothingSplineParamForGrainSize);
            thisGrainSize(x) = F(x);

            % b. From max grain size to 7 days before end of record or the end of record
            % if not full water year.
            % set those days to (near) max grain size.
            thisGrainSize(lastDayWithMaximum: ...
              (length(thisGrainSize) - peakFixingDayWithoutCorrection)) = ...
              valueOfLastDayWithMaximum;

            %c. last 7 days of record, if full water year, are splined from max to min.
            if peakFixingDayWithoutCorrection ~= 0
              x = [length(thisGrainSize) - peakFixingDayWithoutCorrection, ...
                length(thisGrainSize)];
              y = [0, valueOfLastDayWithMaximum, grainSizeOutputVariable.min(1), 0];
              F = spline(x, y);
              thisGrainSize(x(1):x(2)) = fnval(F, x(1):x(2));
            end
            thisGrainSize = uint16(max(min(thisGrainSize, ...
              grainSizeOutputVariable.max(1)), ...
              grainSizeOutputVariable.min(1)));

            % Dust concentration.
            %%%%%%%%%%%%%%%%%%%%%
            % We only interpolate the pixels having enough data until the last day with
            % maximum included.
            if sum(~dustConcentrationSetToNoData(1:lastDayWithMaximum)) >= 2
            % Set to 0 all dust concentrations for days with low grain size before the
            % day of max grain size.
              thisDustConcentration((thisGrainSize <= ...
                smoothingDustSetToZeroBeforeGrainSizeMaxWhenBelowGrainSizeValue) & ...
                [ones([lastDayWithMaximum - 1, 1]); ...
                zeros([length(thisDustConcentration) - lastDayWithMaximum + 1, 1])]) = 0;
              %set dust to zero on day 1
              thisDustConcentration(1) = 0;
              thisWeight(1) = 1;

              % a. From start to day before max grain size.
              x = (1:lastDayWithMaximum - 1)';
              y = thisDustConcentration(1:lastDayWithMaximum);
              F = fit([x; lastDayWithMaximum] , double(y), 'smoothingspline', ...
                weights = double(thisWeight([x; lastDayWithMaximum])), ...
                exclude = ...
                  [0; dustConcentrationSetToNoData(2:lastDayWithMaximum)], ...
                SmoothingParam = smoothingSplineParamForSnowAndDust);
              thisDustConcentration(x) = F(x);

              % b. From max grain size to 7 days before end of record or the end of record
              % if not full water year.
              thisDustConcentration(lastDayWithMaximum: ...
                (length(thisDustConcentration) - peakFixingDayWithoutCorrection)) = ...
                thisDustConcentration(lastDayWithMaximum);
                % NB: Warning: if there's not many pixels with snow > 90 that date,
                % this value will be probably nodata...                           @warning
              if thisDustConcentration(lastDayWithMaximum) == intmax('uint16')
                thisDustConcentration(lastDayWithMaximum: ...
                (length(thisDustConcentration) - peakFixingDayWithoutCorrection)) = ...
                  thisDustConcentration( ...
                  find(dustConcentrationSetToNoData(1:lastDayWithMaximum - 1) == 0, ...
                  1, 'last'));
              end

              %c. last 7 days of record, if full water year, are splined from max to min.
              if peakFixingDayWithoutCorrection ~= 0
                x = ...
                  [length(thisDustConcentration) - peakFixingDayWithoutCorrection, ...
                  length(thisDustConcentration)];
                y = [0, valueOfLastDayWithMaximum, ...
                  dustConcentrationOutputVariable.min(1), 0];
                F = spline(x, y);
                thisDustConcentration(x(1):x(2)) = fnval(F, x(1):x(2));
              end
              thisDustConcentration = uint16(max(min(thisDustConcentration, ...
                dustConcentrationOutputVariable.max(1)), ...
                dustConcentrationOutputVariable.min(1)));
            else
              thisDustConcentration = ...
                intmax('uint16') * ones(size(thisDustConcentration), 'uint16');
            end % if sum(dustConcentrationSetToNoData(1:lastDayWithMaximum)) >= 2
          else % if sum(grainSizeSetToNoData(1:lastDayWithMaximum)) >= 2
            thisGrainSize = ...
              intmax('uint16') * ones(size(thisGrainSize), 'uint16');
            thisDustConcentration = ...
              intmax('uint16') * ones(size(thisDustConcentration), 'uint16');
          end % sum(grainSizeSetToNoData(1:lastDayWithMaximum)) >= 2
        end % ~peakGrainSizeIsToFix

        thisGrainSize(thisGrainSize ~= intmax('uint16')) = uint16(max( ...
          min(thisGrainSize(thisGrainSize ~= intmax('uint16')), ...
            grainSizeOutputVariable.max(1)), ...
            grainSizeOutputVariable.min(1)));
        thisGrainSize(~thisSnowIsAboveMinimum) = intmax('uint16');
        thisDustConcentration(thisDustConcentration ~= intmax('uint16')) = ...
          uint16(max( ...
          min(thisDustConcentration(thisDustConcentration ~= intmax('uint16')), ...
            dustConcentrationOutputVariable.max(1)), ...
            dustConcentrationOutputVariable.min(1)));
        thisDustConcentration(~thisSnowIsAboveMinimum) = intmax('uint16');

        d_grain_size_s(pixelIdx, :) = thisGrainSize';
        d_dust_concentration_s(pixelIdx, :) = thisDustConcentration';
      end % parfor pixelIdx = 1:size(d_viewable_snow_fraction_s, 1)

      fprintf(['Done the calculation of temporal filter and interpolation of', ...
        ' variables for each pixel in %.2f mins.\n'], toc / 60);

      tic
      varName = '';
      complementaryLabel = '';
      optim.cellIdx(3) = 1;
      optim.countOfCellPerDimension(3) = 1;

      [outputFilePath, outputFileExists, ~, ~] = ...
        espEnv.getFilePathForWaterYearDate(objectName, outputDataLabel, ...
        waterYearDate, optim = optim);
        % NB: cell-split file. Yes the call to getFilePathForDateAndVarName for a
        % waterYearDate file is counter-intuitive.
      outputFilePath = outputFilePath{1};
      fprintf('Saving the calculations in %s...\n', outputFilePath);
      if outputFileExists(1)
        delete(outputFilePath);
      end
      theseDates = inputDates(dateIndicesToSave);
      save(outputFilePath, 'theseDates', '-v7.3');
      varName = 'days_without_observation_s';
      espEnv.saveData(reshape(d_days_without_observation_s(:, dateIndicesToSave), ...
        [thisSize(1), thisSize(2), length(theseDates)]), objectName, ...
        outputDataLabel, waterYearDate = waterYearDate, varName = varName, ...
        optim = optim);
      d_days_without_observation_s = [];
      varName = 'days_with_snow_observed_s';
      espEnv.saveData(reshape(d_days_with_snow_observed_s(:, dateIndicesToSave), ...
        [thisSize(1), thisSize(2), length(theseDates)]), objectName, ...
        outputDataLabel, waterYearDate = waterYearDate, varName = varName, ...
        optim = optim);
      d_days_with_snow_observed_s = [];
      varName = 'days_with_absent_snow_observed_s';
      espEnv.saveData( ...
        reshape(d_days_with_absent_snow_observed_s(:, dateIndicesToSave), ...
        [thisSize(1), thisSize(2), length(theseDates)]), objectName, ...
        outputDataLabel, waterYearDate = waterYearDate, varName = varName, ...
        optim = optim);
      d_days_with_absent_snow_observed_s = [];
      varName = 'daily_nodata_filter_s';
      espEnv.saveData(reshape(d_daily_nodata_filter_s(:, dateIndicesToSave), ...
        [thisSize(1), thisSize(2), length(theseDates)]), objectName, ...
        outputDataLabel, waterYearDate = waterYearDate, varName = varName, ...
        optim = optim);
      d_daily_nodata_filter_s = [];
      varName = 'viewable_snow_fraction_s';
      espEnv.saveData(reshape(d_viewable_snow_fraction_s(:, dateIndicesToSave), ...
        [thisSize(1), thisSize(2), length(theseDates)]), objectName, ...
        outputDataLabel, waterYearDate = waterYearDate, varName = varName, ...
        optim = optim);
      d_viewable_snow_fraction_s = [];
      varName = 'snow_fraction_s';
      espEnv.saveData(reshape(d_snow_fraction_s(:, dateIndicesToSave), ...
        [thisSize(1), thisSize(2), length(theseDates)]), objectName, ...
        outputDataLabel, waterYearDate = waterYearDate, varName = varName, ...
        optim = optim);
      d_snow_fraction_s = [];
      varName = 'snow_cover_days_s';
      espEnv.saveData(reshape(d_snow_cover_days_s(:, dateIndicesToSave), ...
        [thisSize(1), thisSize(2), length(theseDates)]), objectName, ...
        outputDataLabel, waterYearDate = waterYearDate, varName = varName, ...
        optim = optim);
      d_snow_cover_days_s = [];
      varName = 'grain_size_s';
      espEnv.saveData(reshape(d_grain_size_s(:, dateIndicesToSave), ...
        [thisSize(1), thisSize(2), length(theseDates)]), objectName, ...
        outputDataLabel, waterYearDate = waterYearDate, varName = varName, ...
        optim = optim);
      d_grain_size_s = [];
      varName = 'dust_concentration_s';
      espEnv.saveData(reshape(d_dust_concentration_s(:, dateIndicesToSave), ...
        [thisSize(1), thisSize(2), length(theseDates)]), objectName, ...
        outputDataLabel, waterYearDate = waterYearDate, varName = varName, ...
        optim = optim);
      d_dust_concentration_s = [];
      fprintf(['Done the saving of temporal filter and interpolation of', ...
      ' variables for each pixel in %.2f min.\n'], toc / 60);

      fprintf('%s: Done in %.2f mins.\n\n', ...
          thisFunctionCode, toc(thisTimer) / 60);
    end % function interpolate().
    function printPixelIsInterpolated(obj, pixelIdx)
      obj.pixelIsInterpolated(pixelIdx) = 1;
      sumOfPixelIsDone = sum(obj.pixelIsInterpolated);
      if mod(sumOfPixelIsDone, 500) == 0
        fprintf(['%s - %d/%d interpolated...\n'], char(datetime(), 'HH:mm:ss'), ...
          sumOfPixelIsDone, length(obj.pixelIsInterpolated));
      end
    end
    function Xout = movingPersist(X, N, thresh)
      % Ned's v2024.1.0 movingPersist method to temporally remove false positives.
      % moving threshold function
      % works along the 2nd (usually time) dimension of a cube and sets values to
      % false if their sum is below a threshold
      % input
      % X: logical cube mn x t
      % N: windows size, integer
      % thresh: threshold count
      % output: Xout
      % logical cube where X is set to false for each pixel at each slice (3rd
      % dim) that failed
      Xout = false(size(X));
      for i = 1:size(X, 2)
        nstart = max(1, i-N);
        nend = min(size(X, 2), i + N);
        st = sum(X(:, nstart:nend), 2);
        tt = false(size(st));
        %scale  threshold such that it is 1 * thresh for full window
        %and 0.5 * thresh at start or end positions
        tval = (nend - nstart) / (2 * N) * thresh;

        tt(st >= tval) = true;
        Xout(:, i) = tt;
      end
    end
  end % methods.
end
