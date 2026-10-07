#!/bin/bash
#
# script to run SnowToday Step3 historical:
#   calculates and save the daily statistics for all the landsubdivisions having a
#   specific source region, e.g. westernUS, for a set of waterYears.
# Read bash/configurationForHelp.sh for all options and arguments.
#
#SBATCH --constraint=spsc
#SBATCH --export=NONE
#SBATCH --mail-type=FAIL,INVALID_DEPEND,TIME_LIMIT,REQUEUE,ARRAY_TASKS

export SLURM_EXPORT_ENV=ALL

# Core script.
########################################################################################
# Main script constants. 
# Can be overriden by pipeline parameters in configuration.sh, itself can be overriden
# by main script options.
scriptId=daStatis
defaultSlurmArrayTaskId=5001
expectedCountOfArguments=
inputDataLabels=(VariablesMatlab spiresdailytifsinu spiresdailymetadatajson)
outputDataLabels=(SubdivisionStatsDailyCsv)
filterConfLabel=
mainBashSource=${BASH_SOURCE}
mainProgramName=${BASH_SOURCE[0]}
  # overriden by slurm in toolsStart.sh
beginTime=

# Following can be overriden by pipeling configuration.sh
thisRegionType=1
thisSequence=001-036
thisSequenceMultiplierToIndices=3
thisMonthWindow=12

source bash/toolsStart.sh
if [ $? -eq 1 ]; then
  error_exit "Exit=1, matlab=no, toolStart.sh failed at some point."
fi

source bash/toolsMatlab.sh

: '
@obsolete.
# Scratch shuffle.
########################################################################################
# Do the scratch shuffle on complete set of input daily Mosaics (to scratch for speed)
if [ $inputFromArchive ]; then
  for dataType in scagdrfs_mat; do
    ${thisScriptDir}/scratchShuffle.sh -b ${yearStart} -e ${stopWaterYr} \
        TO variables/${dataType}_$LABEL ${regionName} || \
    error_exit "Line $LINENO: scratchShuffle error ${dataType} ${LABEL} ${regionName}"
  done
  echo "${PROGNAME}: Done with shuffle TO scratch..."
fi
'

# Matlab.
########################################################################################
read -r -d '' matlabString << EOM

clear;
try;
  ${packagePathInstantiation}
  ${modisDataInstantiation}
  ${waterYearDateInstantiation}
  ${espEnvWOFilterInstantiation}
  espEnvWOFilter.setAdditionalConf('landsubdivision');
  espEnvWOFilter.setAdditionalConf('variablestat');
  espEnvWOFilter.setAdditionalConf('webname');
  espEnv = espEnvWOFilter;
  region = Regions(${inputForRegion});
  if (${parallelWorkersNb} ~= 0);
    espEnvWOFilter.configParallelismPool(${parallelWorkersNb});
  end;
  subdivisionConf = espEnvWOFilter.myConf.landsubdivision( ...
    espEnvWOFilter.myConf.landsubdivision.sourceRegionId == ${objectId}, :);
  lastIndex = ${lastIndex};
  if lastIndex > size(subdivisionConf, 1);
    lastIndex = size(subdivisionConf, 1);
    fprintf('Last index updated from %d to %d.\n\n', ${lastIndex}, lastIndex);
  end;
  if lastIndex < ${firstIndex};
    error('dailyStats:impossibleIndices', ...
      'warning: lastIndex %d < firstIndex %d.', lastIndex, ${firstIndex});
  end;
  subdivisionConf = subdivisionConf(${firstIndex}:lastIndex, :);
  subdivisionIds = subdivisionConf.id(:);
  alaskaMarchToNovemberSubdivisionIds = [26001 3701 3702 3707 3713 11721 12518 12822 12823 12824 12825 12826 12827 12828 12829 15269 15270 15272 15275 15276 15278];
  parfor (subdivisionIdx = 1:size(subdivisionIds, 1), ${parallelWorkersNb});
    subdivisionId = subdivisionIds(subdivisionIdx);
    subdivision = Subdivision(subdivisionId, region);
    if ismember(${thisMode}, [0, 1, 3]);
    subdivision.calcDailyStats(waterYearDate);
    end;
    if ismember(${thisMode}, [0, 2, 3]);
      subdivision.calcAggregates(waterYearDate);
    end;
    if ismember(${thisMode}, [0, 4]);
      if ismember(subdivisionId, alaskaMarchToNovemberSubdivisionIds);
        % The three seasonal Alaska plots are written directly below from the
        % aggregate CSV.  Write all other plot variables normally.
        subdivision.writeStatCsvAndJson(1, excludeVarIds = [55 62 63]);
      else;
        subdivision.writeStatCsvAndJson(1);
      end;
    end;
  end;
  if ismember(${thisMode}, [0, 4]);
    % Temporary Alaska plot season: Mar 1--Nov 15, 2026.  Its JSON is saved
    % in WY 2027 because October--November are in that water year.
    for subdivisionIdx = 1:size(subdivisionIds, 1);
      subdivisionId = subdivisionIds(subdivisionIdx);
      if ismember(subdivisionId, alaskaMarchToNovemberSubdivisionIds);
        subdivision = Subdivision(subdivisionId, region);
        writeAlaskaMarchToNovemberStatJson(subdivision, 2026, 1);
      end;
    end;
  end;
${catchExceptionAndExit}

EOM

# Launch Matlab and terminate bash script.
source bash/toolsStop.sh

# NB: Maybe the geotiff generation per big region (root) is not optimally placed. @checking

# NB: version region should be filled by the version of the tile input and output
# otherwise the code generates an error.

# NB: A waterYearDate mechanism prevents dates in the future.
# dateOfToday = datetime(2023, 4, 15) allows control of today's date for tests or
# when we know that data input has stopped after a specific day.
