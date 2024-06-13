classdef SpiresInversor < handle
  % Ingest of the mod09ga tiles, cloud determination, and inversion of snow properties
  % from reflectance, solar azimuth and background reflectance using the spires
  % algorithm.
  properties
    region    % Regions obj.
    spiresGriddedInterpolant  % GridInterpolant obj. To allow lookup table search of
      % hyperspectral inversion of reflectance snow properties.
  end
  properties(Constant)
    fminconParameters = struct(startAndRangeOfValues = [[0.5, 0.05, 250., 10.]; ...
      [0., 0., 30., 0.]; [1., 1., 1200, 1000]], A = [1 1 0 0], b = 1);
      % Used in optimization/inversion of reflectance data to obtain using fmincon
      % raw_viewable_snow_fraction_s, shade_fraction_s, grain_size_s, and
      % dust_concentration_s. startAndRangeOfValues(1, :) is the starting value of the
      % variables, (2, :) the minimum value, (3, :) the maximum value. A and b are
      % other arguments of the fmincon() function.
    reflectanceNames = {'reflectance_1_620_670', 'reflectance_2_841_876', ...
      'reflectance_3_459_479', 'reflectance_4_545_565', ...
      'reflectance_5_1230_1250', 'reflectance_6_1628_1652', ...
      'reflectance_7_2105_2155'};
    variableGroupForMode = struct( ...
      mod09ga = [13, 14, 11, 12, 9, 1, 2, 3, 4, 5, 6, 7, 68, 79, 80, 81, 82, 83, ...
        84, 85], ...
      spires = [86, 87, 88, 89, 90, 94, 95, 97, 98], ...
      gap = [77, 78, 91, 67, 92, 93], ...
      smooth = [54, 57, 58, 55], ...
      post = [62, 63, 61]);
%{
      mod09ga = solar_azimuth, solar_zenith, state_1km, sensor_zenith, QC_500m,
        reflectance_1_620_670, reflectance_2_841_876, reflectance_3_459_479,
        reflectance_4_545_565, reflectance_5_1230_1250, reflectance_6_1628_1652,
        reflectance_7_2105_2155, sensor_azimuth, daily_not_nodata_filter_s,
        daily_zero_filter_s, sensor_and_solar_azimuth_sensor_mask,
        sensor_and_solar_zenith_sensor_mask, reflectance_1_7_sensor_mask,
        canopy_cover_fraction_s, time_interp_weight_s
      spires = raw_viewable_snow_fraction_s, raw_snow_fraction_s, raw_shade_fraction_s,
        raw_grain_size_s, raw_dust_concentration_s, grain_size_and_dust_mask,
        spatial_grain_size_s, spatial_dust_concentration_s
      gap = days_without_observation_s, days_since_last_observation_s,
        gap_viewable_snow_fraction_s, gap_snow_fraction_s, gap_grain_size_s,
        gap_dust_concentration_s,
      smooth = viewable_snow_fraction_s, grain_size_s, dust_concentration_s,
        snow_fraction_s,
      post = albedo_s, radiative_forcing_s, snow_cover_days_s
%}
  end
  methods
    function obj = SpiresInversor(region)
      % Parameters
      % ----------
      % region: Regions obj. Modis tile only.
      thisFunction = 'SpiresInversor.SpiresInversor';
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      obj.region = region;
      obj.spiresGriddedInterpolant = [];

      fprintf(['%s: Created SpiresInversor, region: %s.\n'], ...
        thisFunction, region.name);
    end
    function reset(obj, thisDate, variableList)
      % Create modis spires file with default or reset some variables to default.
      %
      % Parameters
      % ----------
      % thisDate: Datetime. Date on which calculation should be carried out. This
      %   date should be <= today.
      %   Run over several dates should be done outside this method.
      % variableList: cell(char). Indicates which field is reset and/or created if
      %   doesnt exist. Default lists are available in obj.variableGroupForMode.
      thisFunction = 'SpiresInversor.reset';
      espEnv = obj.region.espEnv;
      objectName = obj.region.name;
      dataLabel = 'modisspiresdaily';
      varName = '';
      complementaryLabel = '';

      [filePath, ~, ~, ~] = ...
        espEnv.getFilePathForDateAndVarName(objectName, dataLabel, thisDate, ...
          varName, complementaryLabel);
      fprintf(['%s: Resetting variables in file %s...\n'], thisFunction, ...
        filePath);

      % Creation of the variables.
      [variable, ~, ~] = espEnv.getVariable(dataLabel);
      for varIdx = 1:length(variableList)
        varName = variable(variable.id == variableList(varIdx), :).name{1};
        espEnv.instantiateAndSaveData(objectName, dataLabel, theseDate = thisDate, ...
          varName = varName);
        fprintf(['%s: Reset %d: %s.\n'], ...
          thisFunction, variableList(varIdx), varName);
      end
      % NB: the sensor bits to indicate no data are not set, but the bit field
      % daily_not_nodata_filter_s is set to default value = 1, which indicates absent
      % data.                                                                   @warning

      % Complementary fields.
      % Check because there are also other metaData...                             @todo
      thisFileObj = matfile(filePath, Writable = true);
      theseFieldNames = fieldnames(thisFileObj);
      if ismember(1, variableList)
        metaData = struct();
        metaData.versionOf = struct( ...
            ancillary = espEnv.modisData.versionOf.ancillary);, ...
        metaData.inputFileName = '';
        metaData.inputFileLastEditDate = NaT;
        save(filePath, 'metaData', '-append');
      end

      % Matrices first initialized to zeros core.fillMODIScube() L76.
      % and then overriden by NaN (except weights but those are by default set to 1
      % (0.01) later)
    end
    function getInputAndHyperSpectralInverse(obj, thisDate, varargin)
      % Generate the spires gap data. Gap = without clouds and with inversion
      % of snow properties included, from mod09ga tiles.
      %
      % getInputDataAndCalcMaskForDate:
      % Extract the sensor input, save it in a lower precision, and calculate
      % the (cloud) masks which will later determine the gaps.
      % HyperspectralInverse:
      % Look up snow_fraction and variables values with a lookup in a precalculated
      % table based on hyperspectral reflectance inversion, and calculation of
      % canopy-corrected snow_fraction_s.
      %
      % Parameters
      % ----------
      % thisDate: Datetime. Date on which calculation should be carried out. This
      %   date should be <= today.
      %   Run over several dates should be done outside this method.
      % optim: struct(cellIdx, countOfCellPerDimension, force, logLevel,
      %       parallelWorkersNb).
      %   cellIdx: array(int), optional. [rowCellIdx, columnCellIdx].
      %       Indices of the cell part of a tile. Row indices are counted from
      %       top to bottom, column indices from left to right. Default [1, 1].
      %   countOfCellPerDimension: array(int), optional.
      %       [rowCellCount, columnCellCount]. Number of cells dividing the set of
      %       rows and same for columns. E.g. if we want to divide a 2400x2400
      %       tile in 9 cells, countOfCellPerDimension = [3, 3]. Default [1, 1].
      %   force: int, optional. Default 0: if input filename and its modification
      %       date (lastEditDate) are identic to metaData recorded in output file,
      %       doesnt update any data ( = skip). 1: if input filename and its
      %       modification date (lastEditDate) are identic to metaData recorded in
      %       output file, doesnt update the data directly extracted from the
      %       input (i.e. using espEnv.getAndSaveData(), but update the data
      %       calculated. 10: update everything in any case ( = redo).
      %   logLevel: int, optional. Indicate the density of logs.
      %       Default 0, all logs. The higher the less logs.
      %   parallelWorkersNb: int, optional. If 0 (default), no parallelism.
      %
      % import inpain_nans at some point.                                   @todo

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % Initialize and load variables and filters...
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      thisFunction = 'SpiresInversor.getInputAndHyperSpectralInverse';
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      espEnv = obj.region.espEnv;
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
      fprintf(['%s: Starting, region: %s, thisDate: %s, ', ...
        'cellIdx: [%s], countOfCellPerDimension: [%s], ', ...
        'force: %d, logLevel: %d, ', ...
        'parallelWorkersNd: %d...\n'], thisFunction, obj.region.name, ...
        string(thisDate, 'yyyy-MM-dd'), join(num2str(optim.cellIdx), ', '), ...
        join(num2str(optim.countOfCellPerDimension), ', '), ...
        optim.force, optim.logLevel, optim.parallelWorkersNb);

      tic;
%{
      outputDataLabel = 'mod09ga';
      inputDataLabel = '';
      [inputVariable, ~] = espEnv.getVariable(outputDataLabel, ...
        inputDataLabel = inputDataLabel);
%}
      inputDataLabel = 'mod09ga';
      outputDataLabel = 'modisspiresdaily';
      [outputVariable, ~] = espEnv.getVariable(outputDataLabel, ...
        inputDataLabel = inputDataLabel);

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % Check file existence and if absent/corrupted or if similar to previous
      % update ends.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % NB: if input file has similar name and edit date than in metadata of modisspires
      % file, no update.
      % If input file absent or corrupted, update with no data.
      % If input file present, not corrupted and with different name of different date
      % update.
      varName = '';
      complementaryLabel = '';
      patternsToReplaceByJoker = {'timestampAndNrt'};
      [filePath, fileExists, fileLastEditDate] = ...
        espEnv.getFilePathForDateAndVarName( ...
        objectName, inputDataLabel, thisDate, varName, complementaryLabel, ...
        patternsToReplaceByJoker = patternsToReplaceByJoker);
      % Get the most recent file only.
      if iscell(filePath)
        filePath = filePath{1};
        fileExists = fileExists{1};
        fileLastEditDate = fileLastEditDate{1};
      end
      % Get metaData of the output file, if it exists (metaData empty otherwise).
      varName = 'metaData';
      metaData = espEnv.getDataForDateAndVarName(objectName, ...
        outputDataLabel, thisDate, varName, complementaryLabel);

      % Check input file exists.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      if fileExists == 0
        if isempty(metaData) | ~ismember(optim.force, [0, 1])
          warning(['%s: WARNING, no file, update with no data for region: %s, ', ...
            'thisDate: ', ...
            '%s, cellIdx: [%s], countOfCellPerDimension: [%s], ', ...
            'force: %d, logLevel: %d, ', ...
            'parallelWorkersNd: %d...\n'], thisFunction, obj.region.name, ...
            string(thisDate, 'yyyy-MM-dd'), join(num2str(optim.cellIdx), ', '), ...
            join(num2str(optim.countOfCellPerDimension), ', '), ...
            optim.force, optim.logLevel, optim.parallelWorkersNb);
          obj.reset(thisDate, [obj.variableGroupForMode.mod09ga, ...
            obj.variableGroupForMode.spires, obj.variableGroupForMode.gap, ...
            obj.variableGroupForMode.smooth, obj.variableGroupForMode.post]);
        else
          warning(['%s: WARNING, no file, no update because output file exists for', ...
            ' region: %, thisDate: ', ...
            '%s, cellIdx: [%s], countOfCellPerDimension: [%s], ', ...
            'force: %d, logLevel: %d, ', ...
            'parallelWorkersNd: %d...\n'], thisFunction, obj.region.name, ...
            string(thisDate, 'yyyy-MM-dd'), join(num2str(optim.cellIdx), ', '), ...
            join(num2str(optim.countOfCellPerDimension), ', '), ...
            optim.force, optim.logLevel, optim.parallelWorkersNb);
        end
        return
      else
        
          % NB: if a file exists and doesn't have metadata fields, raise error. @warning
        % Check whether update is required.
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        [~, thisFileName, thisExtension] = fileparts(filePath);
        if ismember(optim.force, [0, 1]) && ~isempty(metaData) && ...
          ismember('inputFileName', fieldnames(metaData)) && ...
          strcmp([thisFileName, thisExtension], metaData.inputFileName) && ...
          fileLastEditDate == metaData.inputFileLastEditDate
          % Dates are saved yyyyMMddhhmmss.
          warning(['%s: No update for region: %s, thisDate: ', ...
          '%s, cellIdx: [%s], countOfCellPerDimension: [%s], ', ...
          'force: %d, logLevel: %d, ', ...
          'parallelWorkersNd: %d...\n'], thisFunction, ...
          obj.region.name, string(thisDate, 'yyyy-MM-dd'), ...
          string(thisDate, 'yyyy-MM-dd'), join(num2str(optim.cellIdx), ', '), ...
          join(num2str(optim.countOfCellPerDimension), ', '), ...
          optim.force, optim.logLevel, optim.parallelWorkersNb);
          return
        else
          % Check whether file is not corrupted.
          %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
          % We try to get some data in the file.
          % NB: should be a distinct method in ESPEnv.                   @todo
          varName = 'reflectance_6_1628_1652';
          complementaryLabel = '';
          thisOptim = optim;
          thisOptim.countOfCellPerDimension = [ ...
            espEnv.modisData.sensorProperties.tiling.rowPixelCount, ...
            espEnv.modisData.sensorProperties.tiling.columnPixelCount];
            % We'll only get the first pixel.
          try
            [varData, ~] = espEnv.getDataForDateAndVarName(...
              objectName, inputDataLabel, thisDate, varName, ...
              complementaryLabel, optim = thisOptim, ...
              patternsToReplaceByJoker = patternsToReplaceByJoker);
          catch thisException
            warning(['%s: WARNING, corrupted file, update with no data ', ...
              'for region: %s, thisDate: ', ...
              '%s, cellIdx: [%s], countOfCellPerDimension: [%s], ', ...
              'force: %d, logLevel: %d, ', ...
              'parallelWorkersNd: %d...\n'], thisFunction, filePath, ...
              obj.region.name, string(thisDate, 'yyyy-MM-dd'), ...
              string(thisDate, 'yyyy-MM-dd'), ...
              join(num2str(optim.cellIdx), ', '), ...
              join(num2str(optim.countOfCellPerDimension), ', '), ...
              optim.force, optim.logLevel, optim.parallelWorkersNb);
            warning(['%s: %s - %s.\n'], thisFunction, ...
              thisException.identifier, thisException.msg);
            obj.reset(thisDate, [obj.variableGroupForMode.mod09ga, ...
              obj.variableGroupForMode.spires, obj.variableGroupForMode.gap, ...
              obj.variableGroupForMode.smooth, obj.variableGroupForMode.post]);
            return;
          end
        end
      end

      % NB: In espEnv.getAndSaveData(), I developed the case force = 10 but didnt
      %   develop the other cases of 0 and 1 when we have to check
      %   the metaData metaData.inputFileName) and
      %   metaData.inputFileLastEditDate and compare them to
      %   the input file. This should be handled at this higher level now.   @todo
      optim.force = 10;
      [outputFilePath, ~, ~] = ...
        espEnv.getFilePathForDateAndVarName( ...
        objectName, outputDataLabel, thisDate, varName, complementaryLabel, ...
        patternsToReplaceByJoker = patternsToReplaceByJoker);
      metaData = struct();
      save(outputFilePath, 'metaData', '-v7.3');
        % We erase previous file. Probably needs to be more flexible/safe.      @warning
      fprintf(['%s: Update of input data from %s to %s will be carried out.\n'], ...
        thisFunction, filePath, outputFilePath);

      % Update starting... daily_nodata_filter_s and metaData.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % NB: In the following code, except if advertized differently, data are
      % of dimensionInfo/shape 20, i.e. 1 dim rowxcolumn (for 1 day).
      %                                                                   @warning
      theseDate = thisDate;
      varName = 'daily_nodata_filter_s';
      force = struct(nodata_value = 0);
      dailyNoDataFilter = espEnv.instantiateData( ...
        objectName, outputDataLabel, ...
        theseDate = theseDate, varName = varName, force = force, optim = optim);
          % daily_nodata_filter: uint8, position 1: hasNoInput, 2: neuralCloud,
          % 3: background reflectance nodata, 4: rareObservation.
          % Default value: 1 for absent file or corrupted file.
          % NB: this field is later updated when for nodata reflectances.
      [~, fileNameWithoutExtension, thisExtension] = fileparts(filePath);
      metaData.inputFileName = ...
        [fileNameWithoutExtension, thisExtension];
      metaData.inputFileLastEditDate = fileLastEditDate;
      fprintf(['%s: Instantiated daily_nodata_filter_s and metaData.\n'], ...
        thisFunction);

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % Sensor_azimuth and solar_azimuth filling, and save.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      varName = 'sensor_azimuth';
      % sensor_azimuth. 1200x1200. Unused.
      force = struct(minMaxCut = 1);
      force.fillMissing = {'inpaint_nans', 4};
        % NB: Can't define in one line, fields mess up.
      [~, sensorAzimuthSensorMask] = espEnv.getAndSaveData( ...
        objectName, inputDataLabel, outputDataLabel, theseDate = theseDate, ...
        varName = varName, force = force, optim = optim, ...
        patternsToReplaceByJoker = patternsToReplaceByJoker);
      varName = 'solar_azimuth';
      % solar_azimuth. 1200x1200. Unused.
      [~, solarAzimuthSensorMask] = espEnv.getAndSaveData( ...
        objectName, inputDataLabel, outputDataLabel, theseDate = theseDate, ...
        varName = varName, force = force, optim = optim, ...
        patternsToReplaceByJoker = patternsToReplaceByJoker);
      % We also save the masks for nodata fillmissed, and pixels with cut values
      % within the range of accepted values.
      varName = 'sensor_and_solar_azimuth_sensor_mask';
      espEnv.saveData(bitshift(solarAzimuthSensorMask, 3) + ...
        sensorAzimuthSensorMask, objectName, outputDataLabel, theseDate = theseDate, ...
        varName = varName, force = force, optim = optim);
        % sensor_and_solar_azimuth_sensor_mask: uint8, position 1:
        %   sensor_azimuth nodata, 2: sensor_azimuth too low, 3: sensor_azimuth
        %   too high. 4: solar_azimuth nodata, 5: solar_azimuth too low, 6:
        %   solar_azimuth too high.
      solarAzimuthSensorMask = [];
      sensorAzimuthSensorMask = [];

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % Initialize weights for later temporal interpolation.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % Temporal smoothing uses weights to give more weight to the reliable
      % observations, and less weight to the observations less reliable.
      % Previous code: MODIS_HDF.weightMOD09().
      % We removed the band weights, which are not used in N. Code.
      % Each criteria gives a positive weight, and without no data (although N.
      % code overchecked this too.

      % Correspondance state/QC values <=> weights.
      % Weight values are stored with divisor 100, and are divided by 100 when
      % used in temporal smoothing.
      valuesAndWeightLinks = struct(state = struct( ...
        cloud = {cast(0:3, 'uint8'), uint8([100 50 50 100])}, ...
        cloudshadow = {cast(0:1, 'uint8'), uint8([100 80])}, ...
        landwater = {cast(0:7, 'uint8'), uint8([80 100 80 80 80 0 0 0])}, ...
        aerosol = {cast(0:3, 'uint8'), uint8([100 100 50 25])}, ...
        cirrus = {cast(0:3, 'uint8'), uint8([100 100 50 25])}), ...
      QC = struct( ...
        modland = {cast(0:3, 'uint8'), uint8([100 50 0 0])}, ...
        atmosCorr = {cast(0:1, 'uint8'), uint8([80 100])}, ...
        adjCorr = {cast(0:1, 'uint8'), uint8([90 100])}));
        % NB: should be in a conf somewhere.                               @todo
        % the attributes with 0/1 value range are originally of type logical.

      varName = 'time_interp_weight_s';
      force = struct(nodata_value = 100, resamplingFactor = 2);
      weight = espEnv.instantiateData(objectName, outputDataLabel, ...
        theseDate = theseDate, varName = varName, force = force, ...
        optim = optim);
        % size of state, 1200x1200. Will be resize when QC_500m included below.
      % isVersion20231027 code was weights single with divisor 1.
      % Here divisor = 100.

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % Solar_zenith filling and angle weight calculation.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      varName = 'solar_zenith';
      % solar_zenith. 1200x1200. Input to determine weight, spires inversion.
      force = struct(minMaxCut = 1);
      force.fillMissing = {'inpaint_nans', 4};
      [solarZenith, solarZenithSensorMask] = espEnv.getAndSaveData( ...
        objectName, inputDataLabel, outputDataLabel, theseDate = theseDate, ...
        varName = varName, force = force, optim = optim, ...
        patternsToReplaceByJoker = patternsToReplaceByJoker);
      % solar zenith resol 1200 int filled (=no nodata) but not redimed to 2400.
      % some solar zenith are erroneously measured above 90. Corrected in
      % getAndSaveData().

      % Weight.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % Previous code: MODIS_HDF.weightMOD09.GetWeightAngles().
      weight = min(weight, ...
        uint8(100 * sqrt(cosd(double(solarZenith)))));
        % NB: we could save a int correspondance table somewhere.          @todo
        % N code was first cosd, second sqrt.
%{
      % Code from previous version I removed.
      % Note that rasterReprojection with single create a negligible difference
      % which can have an impact on inversion/optimisation (5 points for fsca).
      if isVersion20231027
        % core.fillMODIScube() L175.
        solarZenith = rasterReprojection(single(solarZenith), BigRR, ...
          InProj = mstruct, OutProj = mstruct, rasterref = BigRR, ...
          fillvalue = nan);
      end
%}
      % solarZenith = []; Used in inversion with fmincon below.

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % Sensor_zenith filling, angle weight and canopy cover factor calculation.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      varName = 'sensor_zenith';
      % sensor_zenith. 1200x1200. Input to determine weight, vegetation correction
      %   Govgf.
      [sensorZenith, sensorZenithSensorMask] = espEnv.getAndSaveData( ...
        objectName, inputDataLabel, outputDataLabel, theseDate = theseDate, ...
        varName = varName, force = force, optim = optim, ...
        patternsToReplaceByJoker = patternsToReplaceByJoker);
      % sensor zenith resol 1200 filled (=no nodata).
      varName = 'sensor_and_solar_zenith_sensor_mask';
      espEnv.saveData(bitshift(solarZenithSensorMask, 3) + ...
        sensorZenithSensorMask, objectName, outputDataLabel, theseDate = theseDate, ...
        varName = varName, force = force, optim = optim);
        % sensor_and_solar_zenith_sensor_mask: uint8, position 1:
        %   sensor_zenith nodata, 2: sensor_zenith too low, 3: sensor_zenith
        %   too high. 4: solar_zenith nodata, 5: solar_zenith too low, 6:
        %   solar_zenith too high.
      solarZenithSensorMask = [];
      sensorZenithSensorMask = [];

      % NB: In my previous version of code:
      % solar azimuth: (not done in Neds
      % out.(vars{28})(out.(vars{28}) > 180) = NaN; before interpolation
      % solar_zenith (not done in Ned:
      %out.(vars{7})(out.(vars{7}) > 90) = NaN before interpolation;
      % Seb 20240222 Interpolating temporally solarZ.
      % out.(vars{7})(out.(vars{7}) > 90) = NaN;
      %
      % > Here, i just cap.                                                     @warning

      % Weight.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % Previous code: MODIS_HDF.weightMOD09.GetWeightAngles().
      earthRadius = espEnv.modisData.projection.modisSinusoidal. ...
        geoKeyDirectoryTag.GeogSemiMajorAxisGeoKey / 1000;
        % Earth radius in km. 6.371007181e+03
      orbitHeight = espEnv.modisData.sensorProperties.orbitHeight;
        % Orbit height in km. 705.
      sizeForOnePixel = [1, 1];
        % pixel size at nadir, height width in km.
        % RMQ: the exact size is more 463x2 m?                          @tocheck
      [ppl, ppt, ~] = pixelSize(earthRadius, orbitHeight, sizeForOnePixel, ...
        double(sensorZenith));
        % ppl: pixel size in along-track direction, ppt: pixel size in
        % cross-track direction.
        % in function call to sind(sensorZenith) which requires double.
      weight = min(weight, uint8(100 ./ (ppl .* ppt)));
      ppl = [];
      ppt = [];

      % Canopy cover fraction or cc_adj.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % Calculated using GOvgf of Liu et al 2004, Eq 8, DOI: 10.1002/hyp.5802
      % without geometry of slope and with view azimuth = 0. theta_s = 0,
      % phi_s = 0, phi_v = 0, using canopy cover (fraction) and sensor zenith:
      % view zenith. I think that cant be negative.
      % core.smoothSPIREScube() L111.
      force = struct();
      [~, ~, thisSize] = espEnv.getIndicesForCellForDataLabel( ...
        objectName, inputDataLabel, force = force, optim = optim);

      force = struct();
      force.type = 'double';
      force.dimensionInfo = 20;
      varName = 'canopy_cover_fraction_s';
      parameterName = 'snowCanopyMeanVerticalDividedByHorizontalCrownRadius';
      parameterValue = ...
        Tools.valueInTableForThisField( ...
        obj.region.filter.spires, 'lineName', ...
        parameterName, 'minValue');
        % b_R = 2.7 avg vertical crown radius divided by average horizontal
        % crown radius.
      canopyCoverFraction = uint8(100 * (1 - (1 - ...
        double(espEnv.getDataForObjectNameDataLabel( ...
          objectName, 'canopycover')) / 100) .^ ...
          (1 ./ cosd(atand(parameterValue .* ...
            tand(double( ...
              imresize(sensorZenith, 2, 'nearest'))) ...
            )))));
      espEnv.saveData(canopyCoverFraction, ...
        objectName, outputDataLabel, theseDate = theseDate, ...
        varName = varName, force = force, optim = optim);
        % NB: version20231027 had imresize sensorZenith with bicubic.
        % TMP reshape(sensorZenith, [thisSize / 2])                             @tocheck
      % canopyCoverFraction = []; Used below in calculation of corrected snowFraction.
%{
      % Code from previous version I removed.
      % Note that rasterReprojection with single create a negligible difference
      % which can have an impact on inversion/optimisation (5 points for fsca).
      if isVersion20231027
        % core.fillMODIScube() L178.
        sensorZenith = rasterReprojection(single(sensorZenith), BigRR, ...
          InProj = mstruct, OutProj = mstruct, rasterref = BigRR, ...
          fillvalue = nan);
      end
%}
      sensorZenith = [];
      fprintf(['%s: Calculated and saved canopy_cover_fraction_s.\n'], ...
        thisFunction);

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % State_1km m weight calculation and temporary status cloud no saltpan.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      varName = 'state_1km';
      force = struct();
      % state_1km 1200x1200. Input to determine weight, ndsi factor.
      state = espEnv.getAndSaveData(objectName, ...
        inputDataLabel, outputDataLabel, theseDate = theseDate, ...
        varName = varName, force = force, optim = optim, ...
        patternsToReplaceByJoker = patternsToReplaceByJoker);
      state = unpackMOD09state(state);

      % State weights.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % Previous code: MODIS_HDF.weightMOD09.GetWeight1km().
      thisDictOfWeight = valuesAndWeightLinks.state;
      theseFieldNames = fieldnames(thisDictOfWeight);
      for fieldIdx = 1:length(theseFieldNames)
        thisFieldName = theseFieldNames{fieldIdx};
        weight = min(weight, ...
          changem(uint8(state.(thisFieldName)), ...
            thisDictOfWeight(2).(thisFieldName), ...
            thisDictOfWeight(1).(thisFieldName)));
      end
      % state = []; state is used below to exclude some pixels from the MccM neither
      % classification.

      % Temporary status cloud no saltpan.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % Handled below, we keep state_1km as variable.

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % QC_500m and achievement of weight calculation.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      varName = 'QC_500m';
      % QC_500m. 2400x2400. Input to determine weight.
      QC = espEnv.getAndSaveData( ...
        objectName, inputDataLabel, outputDataLabel, theseDate = theseDate, ...
        varName = varName, force = force, optim = optim, ...
        patternsToReplaceByJoker = patternsToReplaceByJoker);
      QC = unpackMOD09QC(QC);

      % QC weights.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % Size 2400x2400.
      % Preivous code: MODIS_HDF.weightMOD09.GetWeightAngles().
      weight = imresize(weight, 2, 'nearest');
        % In isVersion20231027, all imresize are done with parameter
        % [2400 2400], but it won't change with the parameter 2.
        %
        % TMP weight = reshape(imresize(reshape(weight, thisSize / 2), 2, 'nearest'), ...
        % [1, thisSize(1) * thisSize(2)]);                                      @tocheck

      thisDictOfWeight = valuesAndWeightLinks.QC;
      theseFieldNames = fieldnames(thisDictOfWeight);
      for fieldIdx = 1:length(theseFieldNames)
        thisFieldName = theseFieldNames{fieldIdx};
        weight = min(weight, ...
          changem(uint8(QC.(thisFieldName)), ...
            thisDictOfWeight(2).(thisFieldName), ...
            thisDictOfWeight(1).(thisFieldName)));
      end
      QC = [];

      % Weights of day with data cannot be nodata, because of the filling of
      % solar_zenith and sensor_zenith, but they could be 0, we make them = 1
      % (i.e. 0.01 after division) to make sure we have enough weights for
      % temporal smoothing TimeSpace.smoothDataCube() L164.
      weight(weight == 0) = 1;

      % I removed the band weights "bweights" from previous code, since they are
      % calculated but not used in their code.
      force = struct();
      varName = 'time_interp_weight_s'; % spires_interp_weight.
      espEnv.saveData(weight, objectName, outputDataLabel, ...
        theseDate = theseDate, varName = varName, force = force, optim = optim);
        % NB: should take into account isVersion20231027 vs mine?
        % Not necessary, because weight precision has probably no influence @todo

%{
      % Code from previous version I removed.
      % Note that rasterReprojection with single create a negligible difference
      % which can have an impact on inversion/optimisation (5 points for fsca).
      if isVersion20231027
        % MODIS_HDF.weightMOD09().
        weight = single(weight) / 100;
        % core.fillMODIScube() L181.
        weight = rasterReprojection(weight, BigRR, ...
          InProj = mstruct, OutProj = mstruct, rasterref = BigRR, ...
          fillvalue = nan);
      end
%}
      weight = [];
      fprintf(['%s: Calculated and saved time_interp_weight_s.\n'], ...
        thisFunction);

      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % Reflectance 7 bands, neural snow/cloud/other, low NDSI.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      varName = 'reflectance_1_7_sensor_mask';
      reflectanceSensorMask = espEnv.instantiateData(objectName, outputDataLabel, ...
        theseDate = theseDate, varName = varName, force = force, ...
        optim = optim);
      varName = obj.reflectanceNames{1};
      thisOutputVariable = outputVariable(outputVariable.id == 1, :);
        % NB: which has type int16,the type expected by neuralClassication algorithm
        % below.
      reflectance = zeros( ...
        [thisSize(1), thisSize(2), length(obj.reflectanceNames)], ...
        thisOutputVariable.type{1});
        % 3rd dimension represents the band.
        % Reflectance in single and not double (despite ndsi calculation)
        % MODIS_HDF.GetMOD09GA() L68.
        % NB: Contrary to isVersion20231027, we will consider the nodata reflectances as
        % no data, not 0 value,                                                 @tocheck
        % NB: reflectance of 0 yields snow fraction of 0 using the spires inversion.
      force = struct(minMaxCut = 1, nodata_value = 0);
      for varIdx = 1:length(obj.reflectanceNames)
        varName = obj.reflectanceNames{varIdx}; % varIdx from 1 to 7.
        [varData, conversionMask] = ...
          espEnv.getAndSaveData(objectName, ...
            inputDataLabel, outputDataLabel, theseDate = theseDate, ...
            varName = varName,  force = force, optim = optim, ...
            patternsToReplaceByJoker = patternsToReplaceByJoker);
            % NaN = 0 core.fillMODIScube() L125.
        reflectance(:, :, varIdx) = varData;
          % varData expected int16 on 10000.
        reflectanceSensorMask = reflectanceSensorMask + ...
          cast(bitshift(conversionMask, (varIdx - 1) * 3), ...
            class(reflectanceSensorMask));
      end
      varData = [];
      % Reflectance in this code is a series of column vectors, each of them
      % corresponding to a specific band.
      varName = 'daily_nodata_filter_s';
      dailyNoDataFilter = bitset(dailyNoDataFilter, 1, reflectanceSensorMask > 0);

      force = struct();
      varName = 'reflectance_1_7_sensor_mask';
      espEnv.saveData(reflectanceSensorMask, objectName, outputDataLabel, ...
        theseDate = theseDate, varName = varName, force = force, optim = optim);
      reflectanceSensorMask = [];
%{
      % Code from previous version I removed.
      if isVersion20231027
        % MODIS_HDF.GetMOD09GA() L68.
        reflectance = single(data.reflectance) / ...
          thisOutputVariable.divisor(1); % 10000.
        reflectance(data.reflectance < 0) = 0;
      end
%}
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % Cloud mask.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % Using MccM deep learning cloud mask.
      % Take reflectance int16 and 10000 multiplicator (as they are natively
      % in mod09ga.
      % Former MccM.pxFeatures().
      % Mask will be applied to pixels before inversion, and their
      % snow_fraction will be set to no data, so that they be temporally
      % interpolated later.
      %
      % NB: v2024.0c/d uses reflectance with full precision while v2024.0e use only
      % 2 decimals. This impacts ndsi and ndvi, and cloud MccM results are
      % different, either at the margin of clouds/snow or creating no snow patchs in
      % clouds/snows. The pixels with ndsi between 0 and -0.5 are very sensitive
      % to MccM. Since the algorithm set no cloud/no snow to 0, and in very late
      % early season may reduce importantly the area where snow is calculated by
      % spires.
      thisRed = espEnv.modisData.reflectanceBandIds.redspires;
      thisSwir = espEnv.modisData.reflectanceBandIds.swir;

        % similar to round(R, 2) * 100, L. 87 core.run_spires.m.
      if strcmp(espEnv.modisData.versionOf.modisspiresdaily, 'v2024.0e')
        % IMPORTANT: the neural network training has been done on int16 rasters, with
        % reflectance values having 4 decimals precision (and not 2).
        % Keeping 4 decimal precision, converting in single and then into int16 is
        % crucial to reproduce the results of v2024.0c (30000 differences for
        % v2024.0f after else, vs 445 differences for v2024.0e just below for
        % date 2023/10/1).
        %                                                                       @warning
        thatReflectance = single(reflectance) / thisOutputVariable.divisor(1);
        ndsi = (thatReflectance(:, :, thisRed) - ...
          thatReflectance(:, :, thisSwir)) ./ ...
          (thatReflectance(:, :, thisRed) + ...
          thatReflectance(:, :, thisSwir));
        ndvi = (thatReflectance(:, :, 2) - thatReflectance(:, :, 1)) ./ ...
          (thatReflectance(:, :, 2) + thatReflectance(:, :, 1));
        parameterName = 'gapCloudMccMinimalSwir'; % 0.2. MccM.pixFeatures() L5.
        parameterValue = ...
          Tools.valueInTableForThisField( ...
          obj.region.filter.spires, 'lineName', ...
          parameterName, 'minValue');
        swirThresh = thatReflectance(:, :, thisSwir) > ...
          parameterValue / thisOutputVariable.divisor(1);
          % mask as cloud if swir band (6) is > than swir_cloud_thresh=0.2.
          % L.5 MccM.pxFeatures().
        pxNorm = vecnorm(thatReflectance, 2, 3) ./ ...
          vecnorm(ones(1, length(obj.reflectanceNames)));
          %scaled 0-1 relative to max theoretical value.
        neuralClassification = semanticseg( ...
          cast(thisOutputVariable.divisor(1) * cat(3,  ...
            thatReflectance, ndsi, ...
            ndvi, swirThresh, pxNorm), thisOutputVariable.type{1}), ...
          espEnv.getDataForObjectNameDataLabel('', ...
            'cloudsnowneuralnetwork'), ExecutionEnvironment = 'cpu');
          thatReflectance = [];
      else
        thatReflectance = reflectance;
        ndsi = cast(thisOutputVariable.divisor(1) * ...
          single(thatReflectance(:, :, thisRed) - ...
          thatReflectance(:, :, thisSwir)) ./ ...
          single(thatReflectance(:, :, thisRed) + ...
          thatReflectance(:, :, thisSwir)), thisOutputVariable.type{1});
          % ndsi, ndvi and swirThresh were multiplied by 10000 and then cast to int16
          % in v2024.0c code (like here).
        ndvi = cast(thisOutputVariable.divisor(1) * ...
          single(thatReflectance(:, :, 2) - thatReflectance(:, :, 1)) ./ ...
          single(thatReflectance(:, :, 2) + thatReflectance(:, :, 1)), ...
          thisOutputVariable.type{1});
        parameterName = 'gapCloudMccMinimalSwir'; % 0.2. MccM.pixFeatures() L5.
        parameterValue = ...
          Tools.valueInTableForThisField( ...
          obj.region.filter.spires, 'lineName', ...
          parameterName, 'minValue');
        swirThresh = cast(thisOutputVariable.divisor(1) * ...
          thatReflectance(:, :, thisSwir) > parameterValue, ...
          thisOutputVariable.type{1});
          % mask as cloud if swir band (6) is > than swir_cloud_thresh=0.2.
          % L.5 MccM.pxFeatures().
        pxNorm = cast(thisOutputVariable.divisor(1) * ...
          vecnorm(single(thatReflectance), 2, 3) ./ ...
          vecnorm(ones(1, length(obj.reflectanceNames))), thisOutputVariable.type{1});
          %scaled 0-1 relative to max theoretical value.
        neuralClassification = semanticseg( ...
          cat(3, thatReflectance, ndsi, ...
          ndvi, swirThresh, pxNorm), ...
          espEnv.getDataForObjectNameDataLabel('', ...
            'cloudsnowneuralnetwork'), ExecutionEnvironment = 'cpu');
          % GPU runs out of memory. I think we work by default with cpu
          % on the supercomputer.
          % We reshape the input into a series of 2-D images put one in front of
          % the other one in depth, because it's what expects the semanticseg
          % function. We reshape the output into a column vector.
          % L.133-138 core.fillMODIScube(), takes reflectance at x.xxxx, then multiply
          % full argument to semanticseg by 10000. Here, we take reflectance at (x)xx.
        thatReflectance = [];
      end
      % reflectance = []; Used in fmincon below.
      reflectance = uint8(single(reflectance) / 100);
      ndvi = [];
      swirThresh = [];
      pxNorm = [];
      fprintf(['%s: Calculated neuralClassification.\n'], ...
        thisFunction);

      % Update cloud status in daily_not_nodata_filter_s and daily_zero_filter_s.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % No data for classification clouds.
      varName = 'daily_nodata_filter_s';
      dailyNoDataFilter = bitset(dailyNoDataFilter, 2, ...
        neuralClassification == 'cloud');
        % daily_nodata_filter: uint8, position 1: hasNoInput, 2: neuralCloud,
          % 3: background reflectance nodata, 4: rareObservation.
      espEnv.saveData(dailyNoDataFilter, objectName, outputDataLabel, ...
        theseDate = theseDate, varName = varName, force = force, optim = optim);
      fprintf(['%s: Saved daily_nodata_filter_s.\n'], ...
        thisFunction);

      % Zero for classification neither, except when state_1km.cloud is 1 or 2, and
      % including state_1km.saltpan.
      varName = 'daily_zero_filter_s';
      thisVariable = outputVariable(strcmp(outputVariable.name, varName), :);
      dailyZeroFilter = espEnv.instantiateData( ...
        objectName, outputDataLabel, ...
        theseDate = theseDate, varName = varName, force = force, optim = optim);
        % daily_zero_filter: uint8, Bit, position 1: NeuralOther, excluding
        % state_1km.clouds and including state_1km.saltpans, 2: NDSIBelowMinus005,
        % 3: rawSnowBelow10, 4: rawGrainBelow40, 5: lowElevation, 6: waterBody.
      dailyZeroFilter = bitset(dailyZeroFilter, 1, (...
        (ismember(neuralClassification, {'other', 'neither'}) & ...
        ~ismember(imresize(state.cloud, 2, 'nearest'), [1, 2])) | ...
        imresize(state.saltpan, 2, 'nearest')));
      neuralClassification = [];
      state = [];
      fprintf(['%s: Instantiated daily_zero_filter_s.\n'], ...
        thisFunction);

      % Determine low NDSI and status in daily_zero_filter_s.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % Determination of the lowNDSI mask. Snow_fraction will be set to 0
      % in those pixels (core.fillMODIScube() L155 and core.run_spires() L80.
      % These 0 values are taken into account in the temporal interpolation.
      % lowNDSI is true for all pixels without clouds,
      % while in core.fillMODIScube() L155 was also true for clouds.
      %
      parameterName = 'gapSnowMinimalNDSI'; % -0.5.
      parameterValue = ...
        Tools.valueInTableForThisField( ...
        obj.region.filter.spires, 'lineName', ...
        parameterName, 'minValue');
      lowNDSI = ones(thisSize, 'uint8');
      lowNDSI(~dailyZeroFilter) = ndsi(~dailyZeroFilter) <= parameterValue;
      dailyZeroFilter = bitset(dailyZeroFilter, 2, lowNDSI);
      ndsi = [];
      lowNDSI = [];

      % Determine filters for elevation and water in daily_zero_filter_s.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      parameterName = 'snowFractionSetToZeroBelowElevation';
      parameterValue = Tools.valueInTableForThisField( ...
        obj.region.filter.spires, 'lineName', parameterName, 'minValue');
        % el_cutoff, 500 m.
      if parameterValue > 0
        dailyZeroFilter = bitset(dailyZeroFilter, 5, ...
          espEnv.getDataForObjectNameDataLabel(objectName, 'elevationned') < ...
          parameterValue); % L.122-131 core/smoothSPIREScube.m.
      end
      dailyZeroFilter = bitset(dailyZeroFilter, 6, ...
        espEnv.getDataForObjectNameDataLabel(objectName, 'waterned'));
        % L.122-131 core/smoothSPIREScube.m.

      force = struct();
      varName = 'daily_zero_filter_s';
      espEnv.saveData(dailyZeroFilter, objectName, outputDataLabel, ...
        theseDate = theseDate, varName = varName, force = force, optim = optim);
      fprintf(['%s: Updated and saved daily_zero_filter_s.\n'], ...
        thisFunction);
      % NB: contrary to isVersion20231027 code, reflectance are not set to NaN
      % where clouds, and red and swir bands are not directly modified. The
      % SpiresInterpolator rather handle the daily_not_nodata_filter_s bits to
      % know which data to exclude from the interpolation.
%{
      % Code from previous version I removed.
      if isVersion20231027
        % N. Code was reprojecting data. Since initial data are in single, this
        % reprojection make lose some precision,
        % which seems to have a 5 points impact on the inversion results for
        % fsca...
        % Done similarly below for sensor_zenith, solar_zenith, weight.
        BigRR = region.getMapCellsReference();
        mstruct = modisData.mstruct;
        % core.fillMODIScube() L172.
        reflectance = rasterReprojection(reflectance, BigRR, ...
          InProj = mstruct, OutProj = mstruct, rasterref = BigRR, ...
          fillvalue = nan);
      end
%}
      % Get background reflectance and determine the no data mask for
      % daily_nodata_filter_s.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      backgroundReflectance = single( ...
        espEnv.getDataForObjectNameDataLabel(objectName, 'backgroundreflectancened'));

      varName = 'daily_nodata_filter_s';
      dailyNoDataFilter = bitset(dailyNoDataFilter, 3, ...
        sum(backgroundReflectance == intmax('uint8'), 3) > 0);
        % daily_nodata_filter: uint8, position 1: hasNoInput, 2: neuralCloud,
          % 3: background reflectance nodata, 4: rareObservation.
      espEnv.saveData(dailyNoDataFilter, objectName, outputDataLabel, ...
        theseDate = theseDate, varName = varName, force = force, optim = optim);
      fprintf(['%s: Saved daily_nodata_filter_s.\n'], ...
        thisFunction);
        % L.84 core.run_spires.m. background reflectance is occasionally no data in
        % ned's files.

      % Group pixels having close values of reflectance, background reflectance and
      % solar zenith.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % Was in core.run_spires(), core.speedyinvert().

      % Restrict the pixels to be calculated.
      isToComputeIndices = find(reshape(~dailyNoDataFilter & ...
        ~bitget(dailyZeroFilter, 1) & ~bitget(dailyZeroFilter, 2) & ...
        ~bitget(dailyZeroFilter, 6), [1, thisSize(1) * thisSize(2)]));
        % no data includes clouds (reflectance nodata in v2024.0c),
        % background reflectance nodata, and reflectance nodata (which are ndsi = 0/0
        % = nodata in v2024.0c).
        % Zero includes the classification neither different from state_1km.cloud 1 or 2
        % and saltpan, and also cells snow or state_1km.cloud 1 or 2 with low ndsi <
        % -0.5.
        % We exclude here the elevation threshold, to fit v2024.0c at this stage of
        % calculation.

        % removed all(~isnan(thisR),2) and ~isnan(thissolarZ) because reflectance is set
        % to 0 when NaN and then used to be set to nan where there's cloud ( we use
        % the isCloud mask instead), and solar zenith is filled.
        %
        % lowNDSI pixels fsca are observations and will be set to 0.
        %
        % in isVersion20231027, lowElevation fsca is set to 0
        % core.smoothSPiREScube() L130, but excluded from interpolation = is
        % considered as nodata in the function TimeSpace.smoothDataCube() L178
        % parameter t.

      % Grouping and determine which reference pixels are to be calculated for each
      % group (the pixel which has the lowest values for each group).
      parameterName = 'spiresGroupingToleranceValue';
      parameterValue = Tools.valueInTableForThisField( ...
        obj.region.filter.spires, 'lineName', parameterName, 'minValue');
        % tolval, 5 (formerly 0.05*100 on reflectance x.xx).
      if parameterValue > 0
        [referenceValuesInToleranceGroup, referenceIndices, ...
          indicesOfReferenceValuesForEachOriginalIdx] = uniquetol( ...
          Tools.valueAt([single(reshape(reflectance, ...
              [thisSize(1) * thisSize(2), length(obj.reflectanceNames)])), ...
            single(reshape(backgroundReflectance, ...
              [thisSize(1) * thisSize(2), length(obj.reflectanceNames)])), ...
            single(reshape(imresize(solarZenith, 2, 'nearest'), ...
              [thisSize(1) * thisSize(2), 1])) ...
          ], isToComputeIndices, ':'), ...
          parameterValue, DataScale = 1, ByRows = true);
          % c = M(im, :); M is in rows, m is a cell array, each cell contains the list
          % of indices for the values of M corresponding to the cell
          % DataScale = 1: indicate that tolerance is absolute (not relative).
          % I removed the OutputAllIndices = true option.
          % The default for occurrence is 'lowest', which selects the lowest value as
          % being unique.
          %  [c, im, ~]  =
          % referenceValuesInToleranceGroup, referenceIndices,
          % indicesOfReferenceValuesForEachOriginalIdx: C, IA, IC
          %
          % solar zenith resol 1200 int filled (=no nodata) and redimed to 2400.
          % some solar zenith are erroneously measured above 90. Corrected in
          % getAndSaveData().], isToComputeIndices, ':'), ...
          %
          % NB: we round here reflectance (which is in percent) as in v2024.0c.
      else
        referenceValuesInToleranceGroup = Tools.valueAt( ...
          [single(reshape(reflectance, ...
            [thisSize(1) * thisSize(2), length(obj.reflectanceNames)])), ...
          single(reshape(backgroundReflectance, ...
            [thisSize(1) * thisSize(2), length(obj.reflectanceNames)])), ...
          single(reshape(imresize(solarZenith, 2, 'nearest'), ...
            [thisSize(1) * thisSize(2), 1])) ...
          ], isToComputeIndices, ':');
        referenceIndices = 1:length(isToComputeIndices);
        indicesOfReferenceValuesForEachOriginalIdx = referenceIndices;
      end
      reflectance = referenceValuesInToleranceGroup(:, 1:length(obj.reflectanceNames))';
      backgroundReflectance = ...
        referenceValuesInToleranceGroup(:, (length(obj.reflectanceNames) + 1): ...
          2 * length(obj.reflectanceNames))';
      solarZenith = referenceValuesInToleranceGroup(:, end)';
        % columns.
      referenceValuesInToleranceGroup = [];
      referenceIndices = referenceIndices';
      indicesOfReferenceValuesForEachOriginalIdx = ...
        indicesOfReferenceValuesForEachOriginalIdx';

      % Inverse viewableSnowFraction, shadeFraction, grainSize and dustConcentration
      % from reflectances using a lookup table based on the spires hyperspectral
      % analysis. (= solving)
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % We only inverse the reference pixels, and will update all pixels later.
      % Was in core.run_spires(), core.speedyinvert().
      thisOutputVariable = outputVariable(outputVariable.id == 86, :);
      referenceViewableSnowFraction = thisOutputVariable.nodata_value(1) * ...
        ones(size(referenceIndices), thisOutputVariable.type{1});
      thisOutputVariable = outputVariable(outputVariable.id == 88, :);
      referenceShadeFraction = referenceViewableSnowFraction;
      thisOutputVariable = outputVariable(outputVariable.id == 89, :);
      referenceGrainSize = thisOutputVariable.nodata_value(1) * ...
        ones(size(referenceIndices), thisOutputVariable.type{1});
      thisOutputVariable = outputVariable(outputVariable.id == 90, :);
      referenceDustConcentration = thisOutputVariable.nodata_value(1) * ...
        ones(size(referenceIndices), thisOutputVariable.type{1});

      if isempty(obj.spiresGriddedInterpolant)
        obj.spiresGriddedInterpolant = ...
          espEnv.getDataForObjectNameDataLabel('', 'spiresmodelformodisned');
          % griddedInterpolant object that produces reflectances in percent (while
          % core.speedyinvert used fraction x.xx)
          % for each band for a specific sensor, e.g. LandSat 8 OLI or MODIS.
          % griddedInterpolant with 4 inputs: radius (um),
          % dust (ppm), solarZ (deg).
          % WARNING: this grid has to be full double and reflectance set to fraction .xx
          % and not percent to fully reproduce results from previous version.
          % The fmincon function seems to be very sensitive to negligible variations
          % and it's unclear if the solution is stable and if there's only 1 solution
          % per reflectance set.                                                @WARNING
          %                                                               @toinvestigate
      end

      thisReflectance = [];
      thisBackgroundReflectance = [];
      thisSolarZenith = [];

      parfor referenceIdx = 1:length(referenceIndices)

        thisReflectance = double(reflectance(:, referenceIdx)) / 100;
        thisReflectance = thisReflectance / max(1, max(thisReflectance));
          % normalize to 1.
          % NB: 2024-05-02. Why is it not done for R0/background reflectance.
        thisBackgroundReflectance = ...
          double(backgroundReflectance(:, referenceIdx)) / 100;
        thisSolarZenith = double(solarZenith(referenceIdx));

        X = NaN([4, 1], 'double');
          % fsca, fshade, grain radius (um), and dust conc (ppm) solution.
        try
          % Background solution.
          [X, ~] = fmincon(@(x) obj.hyperspectralLookup(x, ...
              thisReflectance, thisBackgroundReflectance, thisSolarZenith), ...
            obj.fminconParameters.startAndRangeOfValues(1, :), ...
            obj.fminconParameters.A, obj.fminconParameters.b, ...
            [], [], obj.fminconParameters.startAndRangeOfValues(2, :), ...
            obj.fminconParameters.startAndRangeOfValues(3, :), [], ...
            optimoptions('fmincon', Display = 'none', Algorithm = 'sqp'));
          % Try a no background solution.
          [XForNoBackground, ~] = fmincon(@(x) obj.hyperspectralLookup(x, ...
              thisReflectance, thisBackgroundReflectance, thisSolarZenith), ...
            obj.fminconParameters.startAndRangeOfValues(1, :), ...
            obj.fminconParameters.A, obj.fminconParameters.b, ...
            obj.fminconParameters.A, obj.fminconParameters.b, ...
            obj.fminconParameters.startAndRangeOfValues(2, :), ...
            obj.fminconParameters.startAndRangeOfValues(3, :), [], ...
            optimoptions('fmincon', Display = 'none', Algorithm = 'sqp'));

          % if fsca (= X(1)) is similar, use no background solution
          parameterName = 'spiresSnowFractionDifferenceBackgroundNoBackground';
          parameterValue = ...
            Tools.valueInTableForThisField( ...
            obj.region.filter.spires, 'lineName', ...
            parameterName, 'minValue');
            % 0.02 core/speedyinvert() L. 72.
          if abs(X(1) - XForNoBackground(1)) < parameterValue
              X = XForNoBackground;
          end
        catch ME
          warning([ME.message,' solver crashed, skipping']);
        end
        thisOutputVariable = outputVariable(outputVariable.id == 86, :);
        referenceViewableSnowFraction(referenceIdx) = ...
          cast(X(1) * thisOutputVariable.divisor(1), thisOutputVariable.type{1});
        thisOutputVariable = outputVariable(outputVariable.id == 88, :);
        referenceShadeFraction(referenceIdx) = ...
          cast(X(2) * thisOutputVariable.divisor(1), thisOutputVariable.type{1});
        thisOutputVariable = outputVariable(outputVariable.id == 89, :);
        referenceGrainSize(referenceIdx) = ...
          cast(X(3) * thisOutputVariable.divisor(1), thisOutputVariable.type{1});
        thisOutputVariable = outputVariable(outputVariable.id == 90, :);
        referenceDustConcentration(referenceIdx) = ...
          cast(X(4) * thisOutputVariable.divisor(1), thisOutputVariable.type{1});
      end  % parfor referenceIdx
      reflectance = [];
      backgroundReflectance = [];
      solarZenith = [];

      % Repatriate of reference viewableSnowFraction values to each pixel and save.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % NB: the set of nodata (=not computed) to 0 is done during the
      % interpolating part while in v2024.0c, it is done L.190 of core.run_spires().
      % This way, raw_viewable_snow_fraction can be no data while the presmoothed value
      % will be set to 0.
      thisOutputVariable = outputVariable(outputVariable.id == 86, :);
      viewableSnowFraction = thisOutputVariable.nodata_value(1) * ...
        ones(thisSize, thisOutputVariable.type{1});
      viewableSnowFraction(isToComputeIndices) = ...
        referenceViewableSnowFraction(indicesOfReferenceValuesForEachOriginalIdx);
      referenceViewableSnowFraction = [];

      varName = 'raw_viewable_snow_fraction_s';
      espEnv.saveData(viewableSnowFraction, objectName, outputDataLabel, ...
        theseDate = theseDate, varName = varName, force = force, optim = optim);
      fprintf(['%s: Updated and saved raw_viewable_snow_fraction_s.\n'], thisFunction);

      % Determine Snow Fraction zero for low snow fraction.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % We assume that viewableSnowFraction will always be lower than (corrected)
      % SnowFraction.
      % NB: low snow fraction apply even if ice Fraction between 0 and
      % snowFractionSetToZeroBelowThisValue (10), L.168 core.smoothSPIREScube().
      parameterName = 'snowFractionSetToZeroBelowThisValue';
      parameterValue = ...
        Tools.valueInTableForThisField( ...
        obj.region.filter.spires, 'lineName', ...
        parameterName, 'minValue');
        % fsca_thresh, 0.1.
      dailyZeroFilter = bitset(dailyZeroFilter, 3, ...
        viewableSnowFraction <= parameterValue);
      % TMP. dailyZeroFilter = bitset(dailyZeroFilter, 3,
      % ~bitget(dailyNotNoDataFilter, 1) && ~bitget(dailyNotNoDataFilter, 2) &&
      % ~bitget(dailyZeroFilter, 1) && ~bitget(dailyZeroFilter, 1) &&
      % viewableSnowFraction <= parameterValue);

      % L.97, core/smoothSPIREScube, (was done before moving persist)
      fprintf(['%s: Updated snowFractionSetToZeroBelowThisValue.\n'], thisFunction);

      % Determine pixels which has a too low viewableSnowFraction to trust inversion
      % results of grainSize and dustConcentration.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      varName = 'daily_grain_size_dust_s';
      force = struct(nodata_value = 0);
      dailyGrainSizeDustFilter = espEnv.instantiateData( ...
        objectName, outputDataLabel, ...
        theseDate = theseDate, varName = varName, force = force, optim = optim);
          % daily_grain_size_dust_s: uint8, position 1: spatial interpolation of grain
          % size, 2: grain size nodata because below min, 3: grain size nodata because
          % above max, 4: spatial interpolation of dust concentration, 5: dust
          % concentration nodata because below min, 6: dust concentration nodata because
          % above max.
      %fsca too low for grain size, set for interpolation
      parameterName = 'spatialInterpSnowFractionBelowWhichGrainSizeInterpIsDone';
        % grain_thresh, 0.3.
      parameterValue = ...
        Tools.valueInTableForThisField( ...
        obj.region.filter.spires, 'lineName', ...
        parameterName, 'minValue');
      dailyGrainSizeDustFilter = bitset(dailyGrainSizeDustFilter, 1, ...
        viewableSnowFraction < parameterValue);

      %fsca too low or too dark for dust
      parameterName = 'spatialInterpSnowFractionBelowWhichDustInterpIsDone';
        % dust_thresh, 0.9.
      parameterValue = ...
        Tools.valueInTableForThisField( ...
        obj.region.filter.spires, 'lineName', ...
        parameterName, 'minValue');
      dailyGrainSizeDustFilter = bitset(dailyGrainSizeDustFilter, 4, ...
        viewableSnowFraction < parameterValue);
      fprintf(['%s: Updated grain_size and dust spatial interpolation', ...
        ' parameters.\n'], thisFunction);

      % Repatriate of reference shadeFraction values to each pixel and save.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      thisOutputVariable = outputVariable(outputVariable.id == 88, :);
      shadeFraction = thisOutputVariable.nodata_value(1) * ...
        ones(thisSize, thisOutputVariable.type{1});
      shadeFraction(isToComputeIndices) = ...
        referenceShadeFraction(indicesOfReferenceValuesForEachOriginalIdx);
      referenceShadeFraction = [];

      varName = 'raw_shade_fraction_s';
      force = struct();
      espEnv.saveData(shadeFraction, objectName, outputDataLabel, ...
        theseDate = theseDate, varName = varName, force = force, optim = optim);
      fprintf(['%s: Updated and saved raw_shade_fraction_s.\n'], thisFunction);

      % Calculate (corrected) snowFraction based on canopy cover, shade, and ice.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % previously done in L.111 core.smoothSPIREScube().
      % NB: we should call the type/nodata in versionvariable                   @warning
      notNoData = viewableSnowFraction ~= intmax('uint8');
      shadeFraction(notNoData) = shadeFraction(notNoData) + ...
        canopyCoverFraction(notNoData);
      canopyCoverFraction = [];
      iceFraction = espEnv.getDataForObjectNameDataLabel(objectName, 'icened');
        % no nodata (are = 0).
      thisOutputVariable = outputVariable(outputVariable.id == 87, :);
      snowFraction = thisOutputVariable.nodata_value(1) * ...
        ones(thisSize, thisOutputVariable.type{1});
      snowFraction(notNoData) = ...
        cast(max(uint8(min(100, ...
          100 * cast(viewableSnowFraction(notNoData), 'single') ./ ...
          cast(100 - min(shadeFraction(notNoData) + iceFraction(notNoData), 99), ...
          'single'))), iceFraction(notNoData)), 'uint8');
        % L.118 core.smoothSPIREScube(). NB: Because shade is not negative,
        % snowFraction cannot be smaller than 0.
        % NB: here, we set snowFraction = iceFraction at minimum before smoothing,
        % compared to L.167 core.smoothSPIREScube() where it was done after.
      viewableSnowFraction = [];
      iceFraction = [];
      notNoData = [];
      shadeFraction = [];
      varName = 'raw_snow_fraction_s';
      espEnv.saveData(snowFraction, objectName, outputDataLabel, ...
        theseDate = theseDate, varName = varName, force = force, optim = optim);
      snowFraction = [];
      fprintf(['%s: Updated and saved raw_snow_fraction_s.\n'], thisFunction);

      % Spatial interpolation of pixels which has a too low viewableSnowFraction to
      % trust inversion results of grainSize.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % Calculation of spatial weight big window (that will move of each referenceIdx
      % to recalculate.

      row = repmat([1:(thisSize(2) * 2 + 1)]', [1, (thisSize(1) * 2 + 1)]);
      rowCenter = thisSize(2) + 1;
      column = repmat([1:(thisSize(1) * 2 + 1)], [(thisSize(2) * 2 + 1), 1]);
      columnCenter = thisSize(1) + 1;
      spatialWeight = reshape(single(1 ./ pdist2([ ...
        reshape(row, [size(row, 1) * size(row, 2), 1]), ...
        reshape(column, [size(column, 1) * size(column, 2), 1])], ...
        [rowCenter, columnCenter])), size(row));
      row = [];
      column = [];

      grainSize = NaN(thisSize, 'single');
      grainSize(isToComputeIndices(referenceIndices)) = single(referenceGrainSize);
      referenceGrainSize = [];
      %fsca too low for grain size, set for interpolation
      grainSize(logical(bitget(dailyGrainSizeDustFilter, 1))) = NaN;
      isNoData = isnan(grainSize);

      indicesToInterpolate = intersect( ...
        find(bitget(dailyGrainSizeDustFilter, 1)), ...
        isToComputeIndices(referenceIndices));
      thisOutputVariable = outputVariable(outputVariable.id == 89, :);
      interpolatedGrainSize = thisOutputVariable.nodata_value(1) * ...
        ones(size(indicesToInterpolate), thisOutputVariable.type{1});

      % Interpolate for each pixel to interpolate.
      parfor interpolateIdx = 1:length(indicesToInterpolate)
        [thisRowForIdx, thisColumnForIdx] = ind2sub(thisSize, ...
          indicesToInterpolate(interpolateIdx));
        windowTopRow = thisSize(1) + 1 - thisRowForIdx + 1;
        windowLeftColumn = thisSize(2) + 1 - thisColumnForIdx + 1;
        thisSpatialWeight = spatialWeight( ...
          windowTopRow:windowTopRow + thisSize(1) - 1, ...
          windowLeftColumn:windowLeftColumn + thisSize(2) - 1);
        thisSpatialWeight(isNoData) = 0;
        thatGrainSize = (sum( ...
          thisSpatialWeight .* grainSize, 'all', 'omitnan')) ./ ...
          sum(thisSpatialWeight, 'all');

        interpolatedGrainSize(interpolateIdx) = ...
          cast(thatGrainSize, thisOutputVariable.type{1});
      end % parfor interpolateIdx grainSize.

      grainSize = cast(fillmissing( ...
        grainSize, constant = thisOutputVariable.nodata_value(1)), ...
        thisOutputVariable.type{1});
      spatialGrainSize = grainSize;
      spatialGrainSize(indicesToInterpolate) = interpolatedGrainSize;
      interpolatedGrainSize = [];
      referenceGrainSize = grainSize(isToComputeIndices(referenceIndices));
      grainSize(isToComputeIndices) = ...
        referenceGrainSize(indicesOfReferenceValuesForEachOriginalIdx);
        % NB: Here, grainSize is in the 30-1200 range and not capped to 40-1190.
        % NB: Later, for gap, grainSize in 30-40 will be set to No data (snow set to 0).
      
      varName = 'raw_grain_size_s';
      force = struct();
      espEnv.saveData(grainSize, objectName, outputDataLabel, ...
        theseDate = theseDate, varName = varName, force = force, optim = optim);
      grainSize = [];
      
      referenceGrainSize = spatialGrainSize(isToComputeIndices(referenceIndices));
      spatialGrainSize(isToComputeIndices) = ...
        referenceGrainSize(indicesOfReferenceValuesForEachOriginalIdx);
      referenceGrainSize = [];

      % Below and above min/max detect.
      dailyGrainSizeDustFilter = bitset(dailyGrainSizeDustFilter, 2, ...
        spatialGrainSize < thisOutputVariable.min(1));
      dailyGrainSizeDustFilter = bitset(dailyGrainSizeDustFilter, 3, ...
        spatialGrainSize > thisOutputVariable.max(1));

      % Determine Snow Fraction zero for low grain size below 40.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % L.97 core.smoothSPIREScube().
      dailyZeroFilter = bitset(dailyZeroFilter, 4, bitget(dailyGrainSizeDustFilter, 2));

      force = struct();
      varName = 'daily_zero_filter_s';
      espEnv.saveData(dailyZeroFilter, objectName, outputDataLabel, ...
        theseDate = theseDate, varName = varName, force = force, optim = optim);
      fprintf(['%s: Updated and saved daily_zero_filter_s.\n'], ...
        thisFunction);
      dailyZeroFilter = [];

      % Spatial interpolation of pixels which has a too low viewableSnowFraction to
      % trust inversion results of dustConcentration.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % NB: in v2024.0c, I by mistake multiply by 100, rather than 10 the dust output
      % of spires inversion.
      dustConcentration = NaN(thisSize, 'single');
      dustConcentration(isToComputeIndices(referenceIndices)) = ...
        single(referenceDustConcentration);
      referenceDustConcentration = [];
      %fsca too low for grain size, set for interpolation
      dustConcentration(logical(bitget(dailyGrainSizeDustFilter, 4))) = NaN;
      isNoData = isnan(dustConcentration);
      indicesToInterpolate = intersect( ...
        find(bitget(dailyGrainSizeDustFilter, 4)), ...
        isToComputeIndices(referenceIndices));
      thisOutputVariable = outputVariable(outputVariable.id == 90, :);
      interpolatedDustConcentration = thisOutputVariable.nodata_value(1) * ...
        ones(size(indicesToInterpolate), thisOutputVariable.type{1});

      % Interpolate for each pixel to interpolate.
      parfor interpolateIdx = 1:length(indicesToInterpolate)
        [thisRowForIdx, thisColumnForIdx] = ind2sub(thisSize, ...
          indicesToInterpolate(interpolateIdx));
        windowTopRow = thisSize(1) + 1 - thisRowForIdx + 1;
        windowLeftColumn = thisSize(2) + 1 - thisColumnForIdx + 1;
        thisSpatialWeight = spatialWeight( ...
          windowTopRow:windowTopRow + thisSize(1) - 1, ...
          windowLeftColumn:windowLeftColumn + thisSize(2) - 1);
        thisSpatialWeight(isNoData) = 0;
        thatDustConcentration = (sum( ...
          thisSpatialWeight .* dustConcentration, 'all', 'omitnan')) ./ ...
          sum(thisSpatialWeight, 'all');

        interpolatedDustConcentration(interpolateIdx) = ...
          cast(thatDustConcentration, 'uint16');
      end % parfor interpolateIdx dustConcentration.
      spatialWeight = [];
      isNoData = [];

      dustConcentration = cast( ...
        fillmissing(dustConcentration, ...
        constant = thisOutputVariable.nodata_value(1)), thisOutputVariable.type{1});
      spatialDustConcentration = dustConcentration;
      dustConcentration(indicesToInterpolate) = interpolatedDustConcentration;
      interpolatedDustConcentration = [];
      referenceDustConcentration = ...
        dustConcentration(isToComputeIndices(referenceIndices));
      dustConcentration(isToComputeIndices) = referenceDustConcentration( ...
        indicesOfReferenceValuesForEachOriginalIdx);
        % NB: Here, dustConcentration is in the 0-1000 range and not capped to 0-950.
      
      varName = 'raw_dust_concentration_s';
      force = struct();
      espEnv.saveData(dustConcentration, objectName, outputDataLabel, ...
        theseDate = theseDate, varName = varName, force = force, optim = optim);
      dustConcentration = [];
      
      referenceDustConcentration = ...
        spatialDustConcentration(isToComputeIndices(referenceIndices));
      spatialDustConcentration(isToComputeIndices) = referenceDustConcentration( ...
        indicesOfReferenceValuesForEachOriginalIdx);
      referenceDustConcentration = [];

      % Below and above min/max detect.
      dailyGrainSizeDustFilter = bitset(dailyGrainSizeDustFilter, 5, ...
        spatialDustConcentration < thisOutputVariable.min(1));
      dailyGrainSizeDustFilter = bitset(dailyGrainSizeDustFilter, 6, ...
        spatialDustConcentration > thisOutputVariable.max(1));
        % dust has been multiplied by 10 already above.

      % Set to nodata above/below min max and save grainSize/dustConcentration.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      setToNoData = bitget(dailyGrainSizeDustFilter, 2) | ...
        bitget(dailyGrainSizeDustFilter, 3) | bitget(dailyGrainSizeDustFilter, 5) | ...
        bitget(dailyGrainSizeDustFilter, 6);
      force = struct();
      varName = 'daily_grain_size_dust_s';
      espEnv.saveData(dailyGrainSizeDustFilter, objectName, outputDataLabel, ...
        theseDate = theseDate, varName = varName, force = force, optim = optim);
      dailyGrainSizeDustFilter = [];
      fprintf(['%s: Updated and saved daily_grain_size_dust_s.\n'], thisFunction);

      thisOutputVariable = outputVariable(outputVariable.id == 97, :);
      spatialGrainSize(setToNoData) = thisOutputVariable.nodata_value(1);
      varName = 'spatial_grain_size_s';
      force = struct();
      espEnv.saveData(spatialGrainSize, objectName, outputDataLabel, ...
        theseDate = theseDate, varName = varName, force = force, optim = optim);
      spatialGrainSize = [];
%{
      % previously:
      force = struct(minMaxCut = 2);
        % below and above min are saved as no data.
      [~, conversionMask] = espEnv.saveData(grainSize, objectName, outputDataLabel, ...
        theseDate = theseDate, varName = varName, force = force, optim = optim);
      grainSize = [];
      dailyGrainSizeDustFilter = bitset(dailyGrainSizeDustFilter, 2, ...
        bitget(conversionMask, 2));
      dailyGrainSizeDustFilter = bitset(dailyGrainSizeDustFilter, 3, ...
        bitget(conversionMask, 3));
%}
      fprintf(['%s: Updated and saved raw_grain_size_s.\n'], thisFunction);

      thisOutputVariable = outputVariable(outputVariable.id == 98, :);
      spatialDustConcentration(setToNoData) = thisOutputVariable.nodata_value(1);
      varName = 'spatial_dust_concentration_s';
      espEnv.saveData(spatialDustConcentration, objectName, ...
        outputDataLabel, ...
        theseDate = theseDate, varName = varName, force = force, optim = optim);
      fprintf(['%s: Updated and saved raw_dust_concentration_s.\n'], thisFunction);
      spatialDustConcentration = [];
      setToNoData = [];
%{
      % previously:
      force = struct(minMaxCut = 2);
      [~, conversionMask] = espEnv.saveData(dustConcentration, objectName, ...
        outputDataLabel, ...
        theseDate = theseDate, varName = varName, force = force, optim = optim);
      dustConcentration = [];
      fprintf(['%s: Updated and saved raw_dust_concentration_s.\n'], thisFunction);

      dailyGrainSizeDustFilter = bitset(dailyGrainSizeDustFilter, 5, ...
        bitget(conversionMask, 2));
      dailyGrainSizeDustFilter = bitset(dailyGrainSizeDustFilter, 6, ...
        bitget(conversionMask, 3));
%}
      % Instantiate/Save additional variables, calculated in other methods/later in the
      % process
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      obj.reset(thisDate, [obj.variableGroupForMode.gap, ...
          obj.variableGroupForMode.smooth, obj.variableGroupForMode.post]);
      
      % Saving metadata.
      %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
      % NB: this field indicate that the method has achieved correctly.
      save(outputFilePath, 'metaData', '-append');
      fprintf(['%s: Done update of input data from %s to %s.\n'], ...
        thisFunction, filePath, outputFilePath);

% WAS IN SMOOTHING BUT THERE S NO REASON NOT TO DO IT DAILY
% 3. - Load sensor_zenith,
  % - Calculate canopy correction factor with canopy cover, sensor_zenith, using GOvgf
  %   function (same function as for STC).
  % - save sensorZ. NB: sensorZ was never interpolated.
  % - load ice, fshade.
  % - apply ice, fshda + canopy correction to fsca.
  % - set fsca = 1 if out of 0-1 range and = 0 if initially fsca was 0.
  % - set fsca and fsca_raw = 0 if < 500 m or water.
  % - load weights, and set weights = 0 where fsca = 0.
  % - smoothDataCube using smoothingspline() and weights of fsca, fsca_raw and fshade
  % - set their values to 0 where initial fsca/fsca_raw < 0.1.
  % - save fsca_raw and fshade.
  % - set fsca = fice, except where fsca < 0.1.
  % - load dust, and set dust/grainradius = NaN if out of expected ranges and
  %   dust = NaN if fsca = 0.
  % - set weights = 0 where grainradius = NaN, save original weights.
  % - interpolate each pixel and their temporal series for grainradius and dust.
  % - cap grainradius/dust to the expected range and set to NaN where fsca = 0.
  % - save fsca, grainradius, dust.
  % - [seb] ongoing work to add solar_zenith FillCubeDateLinear() and save (for albedo calculation)

  %% If the matrix contains any NaNs, do linear interpolation
  %% along dimension 3 (across missing slices), also fills
  %% missing end values with nearest non-NaN.
  % fillmissing() doesn't need double precision and we use only single precision.

    end
    % Function to optimize between modeled reflectance and observed reflectance.
    function reflectanceDifference = hyperspectralLookup(obj, x, thisReflectance, ...
      thisBackgroundReflectance, thisSolarZenith)
      % x is the set of values snowFraction, shadeFraction, grainSize,
      % dustConcentration
      modelReflectance = zeros(length(thisReflectance), 1);
      %x is x(1) = fsca, x(2) = fshade, x(3) = radius, x(4) = dust.
      for i=1:length(thisReflectance)
        %use radius,dust,solarZenith, and band # for look up
        modelReflectance(i) = ...
          obj.spiresGriddedInterpolant([x(3), x(4), thisSolarZenith, i]);
      end
        modelReflectance = x(1) .* modelReflectance + ...
          (1 - x(1) - x(2)) .* thisBackgroundReflectance;
        reflectanceDifference = double(norm(thisReflectance - modelReflectance));
          % double type required by fmincon.
    end
  end
end
