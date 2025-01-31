classdef SpiresConverterMatToTif
  properties
    region  % Regions obj.
  end
  methods
    function obj = SpiresConverterMatToTif(region)
      obj.region = region;
    end
    function run(obj, waterYearDate)
      espEnv = obj.region.espEnv;
      objectName = obj.region.name;
      inputDataLabel = 'modspiresdaily';
      outputDataLabel = 'spiresdailytifsinu';
      metaDataLabel = 'spiresdailymetadatajson';
      theseDate = waterYearDate.getDailyDatetimeRange();
      imresizeMethod = 'nearest';
      variable = espEnv.getVariable(inputDataLabel, inputDataLabel = inputDataLabel);
      complementaryLabel = '';
      logFilePath = ['logConverToTif_', objectName, '_', char(datetime('now'), 'yyyyMMddHHmmss'), '.out'];
      
      inputFilePath = '';  
      

      mapCellsReference = obj.region.getMapCellsReference();
      mapCellsReference2 = obj.region.getMapCellsReference(resamplingFactor = 2);
      espEnv.myConf.region( ...
        strcmp(espEnv.myConf.region.name, objectName), :).versionOfAncillary = {'v3.2'};
      
      parfor dateIdx = 1:length(theseDate)
        tic;
        thisDate = theseDate(dateIdx);
        zz = [];
        
        metaDataFilePath = espEnv.getFilePath(objectName, metaDataLabel, ...
              thisDate = thisDate); 
        if isfile(metaDataFilePath)
          fprintf('%s: Already generated.\n', metaDataFilePath);
          continue;
        end
        
        inputFilePath = espEnv.getFilePath(objectName, inputDataLabel, thisDate = thisDate); 
        
        if ~isfile(inputFilePath)
          fprintf('%s: Absent file.\n', inputFilePath);
          continue;
        end
        
        varName = '';
        try
          zz = load(inputFilePath);
          if ~isstruct(zz)
            fprintf('%s: Not a structure.\n', inputFilePath);
            logFileId= fopen(logFilePath, 'a');
            fprintf(logFileId, '%s: Not a structure.\n', inputFilePath);
            fclose(logFileId);
            continue;
          end
          inputFieldNames = fieldnames(zz);
          
          thisSize = mapCellsReference.RasterSize;
          zz.reflectance_rgb = zeros( ...
            [thisSize(1:2), length(DailyDataVisualizer.reflectanceBandsForRGB)], ...
            'uint8');
          
          for varIdx = 1:height(variable)
            varName = variable.name{varIdx};
            if ismember(varName, {'metaData', 'days_since_last_observation_s'}) || ~ismember(varName, inputFieldNames)
              continue;
            end
            if ~ismember(varName, fieldnames(zz))
              logFileId= fopen(logFilePath, 'a');
              fprintf(logFileId, '%s: %s absent.\n', inputFilePath, varName);
              continue;
            end
            if ~ismember(size(zz.(varName), 1), [2400, 1200])
              fprintf('%s: %s size %d.\n', inputFilePath, varName, size(zz.(varName), 1));
              logFileId= fopen(logFilePath, 'a');
              fprintf(logFileId, '%s: %s size %d.\n', inputFilePath, varName, size(zz.(varName), 1));
              fclose(logFileId);
              continue;
            end
            [~, idx] = ismember(varName, DailyDataVisualizer.reflectanceBandsForRGB);
            if ~isempty(idx) && idx ~= 0
              zz.reflectance_rgb(:, :, idx) = ...
                imresize(min(zz.(varName), ...
                  DailyDataVisualizer.maximalReflectanceValueForRGB), ...
                  thisSize(1:2), imresizeMethod);
            end
            % varData expected uint8 from 0 to 160.
            % maximalReflectanceValueForRGB used to adjust for contrast.
            % reflectance > 100 corresponds to extremely reflective material.
            % imresize used for viirs M 1km bands 3, 4, 5, 7 with 1, 2, 6 I 500m bands.
                
            imageDescription = ['id: ', num2str(variable.id(varIdx)), ...
              '; name: ', variable.name{varIdx}, ...
              '; divisor: ', sprintf('%.6f', variable.divisor(varIdx)), ...
              '; min: ', num2str(variable.min(varIdx)), ...
              '; max: ', num2str(variable.max(varIdx)), ...
              '; nodata: ', num2str(variable.nodata_value(varIdx)), ...
              '; unit: ', variable.unit{varIdx}, ...
              '; multiplicator: ', ...
                sprintf('%.6f', variable.multiplicator_for_mosaics(varIdx)), ...
              '; resamplingFactor: ', num2str(variable.resamplingFactor(varIdx)), ...
              '; sourceFile: ', zz.metaData.inputFileName, ...
              '; code: https://github.com/sebastien-lenard/snow-today', ...
              '; citation: Rittger, K., S. J. P. Lenard, Ross T. Palomaki. ', num2str(year(now)), '. MODIS/Terra L3 Daily 500m SIN Grid SPIReS Snow Cover, Snow Albedo, and Snow Surface Properties, Version v2025.nrt. INSTAAR, University of Colorado, Boulder, CO, USA. Digital Media.'];
            outputFilePath = espEnv.getFilePath(objectName, outputDataLabel, ...
              thisDate = thisDate, varName = varName); 
            [~, outputFileName, ~] = fileparts(outputFilePath);
            thatMapCellsReference = mapCellsReference;
            if variable.resamplingFactor(varIdx) == 2
              thatMapCellsReference = mapCellsReference2;
            end
            if ~isequal(size(zz.(varName)), thatMapCellsReference.RasterSize) || size(zz.(varName), 1) ~= size(zz.(varName), 2)
              fprintf('%s: %s size %d, %d.\n', inputFilePath, varName, size(zz.(varName), 1), size(zz.(varName), 2));
              logFileId= fopen(logFilePath, 'a');
              fprintf(logFileId, '%s: %s size %d.\n', inputFilePath, varName, size(zz.(varName), 1));
              fclose(logFileId);
              continue;
    %{
              elseif size(zz.(varName), 1) == 2400
                thatMapCellsReference = mapCellsReference;
              else
                thatMapCellsReference = mapCellsReference2;
              end
    %}
            end
            geotiffwrite(outputFilePath, zz.(varName), thatMapCellsReference, ...
              GeoKeyDirectoryTag = ...
                espEnv.modisData.projection.modisSinusoidal.geoKeyDirectoryTag, ...
              TiffTags = struct(Compression = 'LZW', ...
                DocumentName = outputFileName, ...
                ImageDescription = imageDescription, ...
                Artist = ['Sebastien Lenard, Karl Rittger, Ross Palomaki, ', ...
                  num2str(year(now))] ...
                ));
          end
          varName = 'reflectance_rgb'; 
          if unique(zz.reflectance_rgb) < 3
            fprintf('%s: %s size %d.\n', inputFilePath, 'reflectance_rgb', 1);
            logFileId= fopen(logFilePath, 'a');
            fprintf(logFileId, '%s: %s size %d.\n', inputFilePath, varName, size(zz.(varName), 1));
            fclose(logFileId);
          else
            varIdx2 = find(variable.id == 112);
            varIdx2 = varIdx2(1);
            varName = variable.name{varIdx2};
            imageDescription = ['id: ', num2str(variable.id(varIdx2)), ...
              '; name: ', variable.name{varIdx2}, ...
              '; divisor: ', sprintf('%.6f', variable.divisor(varIdx2)), ...
              '; min: ', num2str(variable.min(varIdx2)), ...
              '; max: ', num2str(variable.max(varIdx2)), ...
              '; nodata: ', num2str(variable.nodata_value(varIdx2)), ...
              '; unit: ', variable.unit{varIdx2}, ...
              '; multiplicator: ', ...
                sprintf('%.6f', variable.multiplicator_for_mosaics(varIdx2)), ...
              '; resamplingFactor: ', num2str(variable.resamplingFactor(varIdx2)), ...
              '; sourceFile: ', zz.metaData.inputFileName, ...
              '; code: https://github.com/sebastien-lenard/snow-today', ...
              '; reference: Rittger, K., S. J. P. Lenard, Ross T. Palomaki. ', num2str(year(now)), '. MODIS/Terra L3 Daily 500m SIN Grid SPIReS Snow Cover, Snow Albedo, and Snow Surface Properties, Version v2025.nrt. INSTAAR, University of Colorado, Boulder, CO, USA. Digital Media.'];
            outputFilePath = espEnv.getFilePath(objectName, outputDataLabel, ...
              thisDate = thisDate, varName = varName); 
            [~, outputFileName, ~] = fileparts(outputFilePath);
            thatMapCellsReference = mapCellsReference;
            if variable.resamplingFactor(varIdx2) == 2
              thatMapCellsReference = mapCellsReference2;
            end
            
            geotiffwrite(outputFilePath, zz.reflectance_rgb, thatMapCellsReference, ...
              GeoKeyDirectoryTag = ...
                espEnv.modisData.projection.modisSinusoidal.geoKeyDirectoryTag, ...
              TiffTags = struct(Compression = 'LZW', ...
                DocumentName = outputFileName, ...
                ImageDescription = imageDescription, ...
                Artist = ['Sebastien Lenard, Karl Rittger, Ross Palomaki, ', ...
                  num2str(year(now))] ...
                ));
             
            text = jsonencode(zz.metaData, "PrettyPrint", true);
            text = replace(text, {'%'}, {'%%'});
            fileID = fopen(metaDataFilePath, 'w');
            fprintf(fileID, text);
            fclose(fileID);
          end
        catch thisE
          thatSize = 1;
          if isstruct(zz)
            theseFieldNames = fieldnames(zz);
            if ismember(varName, theseFieldNames)
              thatSize = size(zz.(varName), 1);
            end
          end
          fprintf('%s, %s, %s, %s, %d.\n', inputFilePath, objectName, varName, char(thisDate, 'yyMMdd'), thatSize);
          rethrow(thisE)
        end
        fprintf('%s for %s in %.2f.\n', char(thisDate, 'yyyyMMdd'), objectName, toc / 60);
      end
    end
  end
end