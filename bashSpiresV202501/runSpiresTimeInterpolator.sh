#!/bin/bash
#
# Generate and interpolate spires gap filled cubes for a given tile
# and water year.
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
scriptId=spiTimeI
defaultSlurmArrayTaskId=292001
expectedCountOfArguments=
inputDataLabels=(modspiresdaily vnpspiresdaily spiresdailytifsinu spiresdailymetadatajson)
# RTP comment out outputDataLabels and set them in toolsStart line ~800
# outputDataLabels=(modspirestimebycell vnpspirestimebycell)
filterConfLabel=
mainBashSource=${BASH_SOURCE}
mainProgramName=${BASH_SOURCE[0]}
  # overriden by slurm in toolsStart.sh
beginTime=

# Following can be overriden by pipeling configuration.sh
thisRegionType=0
thisSequence=001-036
thisSequenceMultiplierToIndices=1
thisMonthWindow=12

source bash/toolsStart.sh
if [ $? -eq 1 ]; then
  exit 1
fi

# Argument setting.
# None.

source bash/toolsMatlab.sh

# Variables for Matlab code.
########################################################################################

#machine specific parameters.

# Matlab.
########################################################################################

read -r -d '' matlabString << EOM

clear;
try;
  ${packagePathInstantiation}
  ${modisDataInstantiation}
  ${waterYearDateInstantiation}
  ${espEnvInstantiation}
  ${optimInstantiation}
  espEnv.configParallelismPool(${parallelWorkersNb});
  region = Regions(${inputForRegion});
  spiresTimeInterpolator = SpiresTimeInterpolator(region);
  if strcmp(espEnv.waterYearDate.getNrtOrHist(), 'hist');
    monthWindows = [3, 3];
  else;
    monthWindows = [3, 0];
  end;
  spiresTimeInterpolator.interpolate(waterYearDate, monthWindows, optim = optim);
${catchExceptionAndExit}

EOM

# Launch Matlab and terminate bash script.
source bash/toolsStop.sh

# "if ${nbDays} ~= 0; theseDates = theseDates((end - ${nbDays}):end); end; "

