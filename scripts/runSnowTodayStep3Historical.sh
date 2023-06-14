#!/bin/bash
#
# script to run SnowToday Step3 historical:
#   update all westernUS multivariate statistics files
#   for region partitions (full region, States, HUC2, etc)
#   for prior history to the current year
#   for westernUS, longest job is 19 states, takes 1h40min
# Job array is set for:
#   10 = full region
#   11 = States
#   12 = HUC2
#

#SBATCH --qos normal
#SBATCH --partition amilan
#SBATCH --job-name 3HistST
#SBATCH --account=ucb-general
#SBATCH --time=12:00:00
# Assumes 3.74 GB/per node for total of 89.76 GB RAM
#SBATCH --ntasks-per-node=24
#SBATCH --nodes=1
#SBATCH -o /scratch/alpine/%u/slurm_out/%x-%A_%a.out
# Set the system up to notify upon completion
#SBATCH --mail-type END,FAIL,INVALID_DEPEND,TIME_LIMIT,REQUEUE,STAGE_OUT
#SBATCH --array=10-12

# Functions.
#---------------------------------------------------------------------------------------
usage() {
    echo "" 1>&2
    echo "Usage: ${PROGNAME} [-A LABEL_ANCILLARY] [-h] [-i] [-L LABEL] [-o]" 1>&2
    echo "       WATERYR" 1>&2
    echo "  Calculates annual updates to ST statistics files prior to WATERYR" 1>&2
    echo "  So for this script to run in Oct 2021, set WATERYR to 2022" 1>&2
    echo "  Job array for each region group (10=westUS, 11=States, 12=HUC2)" 1>&2
    echo "  Run this script once annually, on or after Oct 1" 1>&2
    echo "Options: "  1>&2
    echo "  -A LABEL_ANCILLARY: string with version of ancillary data" 1>&2
    echo "     e.g. for operational processing, use -A v3.1 for westernUS " 1>&2
    echo "     or -A v3.2 for USAlaska" 1>&2
    echo "  -h: display help message and exit" 1>&2
    echo "  -i: update input data from archive to scratch" 1>&2    
    echo "  -L LABEL: string with version label for directories" 1>&2
    echo "     e.g. for operational processing, use -L v2023.x" 1>&2
    echo "  -o: update output data from scratch to archive" 1>&2 
    echo "Arguments: " 1>&2
    echo "  WATERYR : stats will be calculated for 2001 to (WATERYR - 1)" 1>&2
    echo "Output: " 1>&2
    echo "  Output location is controlled in Matlab scripts " 1>&2
    echo "Notes: " 1>&2
    echo "  Scripts stdout/stderr are written to user's scratch " 1>&2
    echo "  where directory /scratch/alpine/$USER/slurm_out_SnowToday/ " 1>&2
    echo "  is assumed to exist" 1>&2
}

# Core script.
#---------------------------------------------------------------------------------------
# Initialize variables, option setting.
scriptId=snoStep3
defaultSlurmArrayTaskId=10
expectedCountOfArguments=1
# Output file. This variable is not transferred from sbatch to bash, so we define it.
# NB: to split a string, don't put indent otherwise there will be two variables.
SBATCH_OUTPUT="/scratch/alpine/${USER}/slurm_out_SnowToday/${SLURM_JOB_NAME}-${SLURM_ARRAY_JOB_ID}_"\
"${SLURM_ARRAY_TASK_ID}.out"

isBatch=
if [[ ${BASH_SOURCE} == *"slurm_script"* ]]; then
    # Running as slurm
    printf "Running as sbatch job...\n"
    PROGNAME=(`scontrol show job ${SLURM_JOB_ID} | grep Command | tr -s ' ' | cut -d = -f 2`)
    isBatch=1
else
    printf "Not running as sbatch...\n"
    PROGNAME=${BASH_SOURCE[0]}
fi
cd "$(dirname "${PROGNAME}")"
thisScriptDir=$(pwd)
printf "Script directory: ${thisScriptDir}\n"
#Go to parent of this script, so that correct pathdef.m file is used
cd ..
source scripts/toolsStart.sh

# Argument setting
waterYr=$1
startWaterYr=2001
stopWaterYr=$(( $waterYr - 1 ))
yearStart=$(( $startWaterYr - 1 ))
regionName='westernUS'

inputForESPEnv="modisData = modisData"
inputForRegion="'"${regionName}"', partitionName, espEnv, modisData"

source scripts/toolsMatlab.sh


# Scratch shuffle.
#---------------------------------------------------------------------------------------
# Do the scratch shuffle on complete set of input daily Mosaics (to scratch for speed)
if [ $inputFromArchive ]; then
    for dataType in scagdrfs_mat; do
        ${thisScriptDir}/scratchShuffle.sh -b ${yearStart} -e ${stopWaterYr} \
                TO variables/${dataType}_$LABEL ${regionName} || \
        error_exit "Line $LINENO: scratchShuffle error ${dataType} ${LABEL} ${regionName}"
    done
    echo "${PROGNAME}: Done with shuffle TO scratch..."
fi

# Matlab.
#---------------------------------------------------------------------------------------   
matlab -nodesktop -nodisplay -r "clear; "\
"try; "\
"modisData = MODISData(${inputForModisData}); "\
"espEnv = ESPEnv(${inputForESPEnv}); "\
"partitionName = Regions.getPartitionNameFor("${SLURM_ARRAY_TASK_ID}"); "\
"region = Regions(${inputForRegion}); "\
"minSCP = minSCPForLinePlots(); "\
"minZ = minZForLinePlots(); "\
"runStatsForLinePlots(region, ${startWaterYr}, ${stopWaterYr}, minSCP, minZ); "\
"catch e; "\
"fprintf('%s: %s\n', e.identifier, e.message); "\
"exit(-1); "\
"end; "\
"exit(0);"  || error_exit "Line $LINENO: matlab error."

# Do the scratch shuffle on output regional_stats back from scratch
if [ $outputToArchive ]; then
    for dataType in scagdrfs_mat; do
        ${thisScriptDir}/scratchShuffle.sh \
                FROM regional_stats/${dataType}_$LABEL ${regionName} || \
        error_exit "Line $LINENO: scratchShuffle FROM error ${dataType} ${LABEL} ${regionName}"
    done
    echo "${PROGNAME}: Done with shuffle FROM scratch..."
fi

source scripts/toolsStop.sh
