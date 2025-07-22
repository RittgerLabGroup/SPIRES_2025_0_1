#!/bin/bash
#
# Generate background reflectance ancillary data for SPIReS v2025+
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
scriptId=spispiBackg
defaultSlurmArrayTaskId=292
expectedCountOfArguments=
inputDataLabels=(modspiresdailytifsinu modspiresdailymetadatajson)
outputDataLabels=(backgroundreflectanceformodisforwateryear)
filterConfLabel=
mainBashSource=${BASH_SOURCE}
mainProgramName=${BASH_SOURCE[0]}
  # overriden by slurm in toolsStart.sh
beginTime=

# Following can be overriden by pipeling configuration.sh
thisRegionType=0
thisSequence=
thisSequenceMultiplierToIndices=
thisMonthWindow=4

# Matlab package paths added.
matlabPackages=(inpaintNans)

source bash/toolsStart.sh
if [ $? -eq 1 ]; then
  exit 1
fi

# Argument setting.
# None.

source bash/toolsMatlab.sh

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
  ancillary = SpiresAncillary(region);
  ancillary.calculateBackgroundReflectance(waterYearDate.getWaterYear());
  end;
${catchExceptionAndExit}

EOM

# Launch Matlab and terminate bash script.
source bash/toolsStop.sh
