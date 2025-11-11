#!/bin/bash
#
# script to export landsubdivision metadata, shapefiles, geotiffs and plots to
# SnowToday web-app.
#
# Read bash/configurationForHelp.sh for all options and arguments.
#
#SBATCH --export=NONE
#SBATCH --mail-type=FAIL,INVALID_DEPEND,TIME_LIMIT,REQUEUE,ARRAY_TASKS

export SLURM_EXPORT_ENV=ALL

# Core script.
########################################################################################
# Main script constants.
# Can be overriden by pipeline parameters in configuration.sh, itself can be overriden
# by main script options.
scriptId=webExpSn
defaultSlurmArrayTaskId=5
expectedCountOfArguments=
inputDataLabels=(VariablesGeotiff SubdivisionStatsWebJson SubdivisionStatsWebCsvv20231)
outputDataLabels=
filterConfLabel=
mainBashSource=${BASH_SOURCE}
mainProgramName=${BASH_SOURCE[0]}
  # overriden by slurm in toolsStart.sh
beginTime=

# Following can be overriden by pipeling configuration.sh
thisRegionType=10
thisSequence=
thisSequenceMultiplierToIndices=
thisMonthWindow=12

source bash/toolsStart.sh
if [ $? -eq 1 ]; then
  exit 1
fi

# Argument setting.
# None.


# Create directories for incoming integration data with permissions 777
incoming_dirs=(geotiffs plots regions shapes)
for incoming_dir in ${incoming_dirs[@]}; do
  incoming_dir_path=${espWebExportRootDirForIntegration}snow-surface-properties/${incoming_dir}
  ssh -i ${espWebExportSshKeyFilePath} ${espWebExportUser}@${espWebExportDomain} \
    "mkdir -p ${incoming_dir_path}; chmod 777 ${incoming_dir_path}"
  echo "Created directory $incoming_dir_path"
done

source bash/toolsMatlab.sh

# Matlab.
########################################################################################
read -r -d '' matlabString << EOM

clear;
try;
  % Generate the landsubdivision metadata to be transferred to SnowToday web-app.
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  % NB: the shapefiles are not generated here (but aside, occasionally, with a qgis
  % routine.
  toBeUsedFlag = 1; % Use a higher value when you want to export a restricted set of
    % subdivisions, based on isUsed field in espEnv.myConf.landsubdivision and
    % espEnv.myConf.landsubdivisionlink.
  uncondensedJson = 1;
  includeSubdivisionTypeInJson = 0;
  ${packagePathInstantiation}
  ${modisDataInstantiation}
  ${waterYearDateInstantiation}
  ${espEnvWOFilterInstantiation}
  dateOfToday = datetime(${dateOfTodayString});

  % Get the subdivision names and source regions (to get ancillary version) and
  % the hierarchy from the configuration.
  espEnvWOFilter.setAdditionalConf('landsubdivision', ...
    confFieldNames = {'name', 'id', 'code', 'subdivisionType', 'sourceRegionId', ...
    'sourceRegionName', 'used', 'root', 'CRS', 'firstMonthOfWaterYear', ...
    'version', 'versionOfAncillary'});
  espEnvWOFilter.setAdditionalConf('landsubdivisionlink');
  espEnvWOFilter.setAdditionalConf('landsubdivisiontype');
  espEnvWOFilter.setAdditionalConf('webname');

  ancillaryOutput = AncillaryOutput(espEnvWOFilter, ...
    includeSubdivisionTypeInJson = includeSubdivisionTypeInJson, ...
    toBeUsedFlag = toBeUsedFlag, uncondensedJson = uncondensedJson);

  ancillaryOutput.writeSubdivisionTypes();
  % No ancillaryOutput.writeVariables() because variables are stored in static (github).
  rootSubdivisionTable = ancillaryOutput.writeRootSubdivisions(dateOfToday = dateOfToday);
    % NB: Dont forget to update configuration_of_landsubdivisions with the correct
    % version (e.g. v2025.0.1) for the root subdivisions.                       @warning
  subdivisionTable = ancillaryOutput.writeSubdivisionLinks();
  ancillaryOutput.writeSubdivisionMetadata(subdivisionTable);

  % Transfer the metadata and shapefiles to SnowToday web-app.
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  versionOfAncillariesToExport = {'v3.1', 'v3.2'}; % all these versions are exported.
  dataLabels = {'landsubdivisioninjson', ...
    'landsubdivisionlinkinjson', 'landsubdivisionrootinjson', ...
    'landsubdivisionshapeingeojson', 'landsubdivisiontypeinjson'};
      % 'webvariableconfinjson' not necessary because
      % stored as a static file.
  thisDate = '';
  varName = '';
  complementaryLabel = '';
  % setenv('espWebExportRootDir', getenv('espWebExportRootDirForIntegration'));
  % setenv('espWebExportRootDir', getenv('espWebExportRootDirForQA'));
  % setenv('espWebExportRootDir', getenv('espWebExportRootDirForProd'));
  exporter = ExporterToWebsite(espEnvWOFilter, versionOfAncillariesToExport, ...
    toBeUsedFlag = toBeUsedFlag);
  for dataLabelIdx = 1:length(dataLabels);
    dataLabel = dataLabels{dataLabelIdx};
    exporter.exportFileForDataLabelDateAndVarName(dataLabel, thisDate, varName, ...
      complementaryLabel);
  end;

  for rootIdx = 1:height(rootSubdivisionTable);
    % Transfer the geotiffs to SnowToday web-app.
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Don't forget to generate the geotiffs and stats before.
    % NB: some root subdivisions share the same geotiffs (USAlaska and Western Canada).
    % NB: Automatically transfer the last available geotiffs. The root region json file
    % also has its last date of data set to the data date of the last available
    % geotiffs.

    complementaryLabel = ['EPSG_', num2str(Regions.webGeotiffEPSG)];
    regionName = '';
    originalEspEnv = exporter.espEnv;
    version = rootSubdivisionTable.version{rootIdx};
    versionOfAncillary = rootSubdivisionTable.versionOfAncillary{rootIdx};

    thisEspEnv = ESPEnv.getESPEnvForRegionNameFromESPEnv(regionName, ...
      originalEspEnv, version = version, ...
      versionOfAncillary = versionOfAncillary);
    if ismember(thisEspEnv.modisData.versionOf.VariablesGeotiff, {'v2024.0d', 'v2024.1.0'});
      dataLabel = 'VariablesGeotiff';
    else;
      dataLabel = 'spiresdailytifproj';
    end;
    thisExporter = ExporterToWebsite(thisEspEnv, versionOfAncillariesToExport, ...
      toBeUsedFlag = toBeUsedFlag);
    varNames = unique(thisEspEnv.myConf.variableregion( ...
      thisEspEnv.myConf.variableregion.writeGeotiffs == 1, :).output_name);

    for varIdx = 1:length(varNames);
      varName = varNames{varIdx};
      thisExporter.exportFileForDataLabelDateAndVarName(dataLabel, thisDate, ...
          varName, complementaryLabel);
    end;

    % Transfer the .json plots to SnowToday web-app.
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    dataLabel = 'SubdivisionStatsWebJson';
    complementaryLabel = '';
    varNames = unique(thisEspEnv.myConf.variableregion( ...
        thisEspEnv.myConf.variableregion.writeStats == 1, :).output_name);
    for varIdx = 1:length(varNames);
      varName = varNames{varIdx};
      thisExporter.exportFileForDataLabelDateAndVarName(dataLabel, thisDate, ...
        varName, complementaryLabel);
    end;
  end;

  % Trigger web-app ingest.
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  exporter.generateAndExportTrigger(); % Beware this will launch ingestion.

${catchExceptionAndExit}

EOM

# Launch Matlab and terminate bash script.
source bash/toolsStop.sh
