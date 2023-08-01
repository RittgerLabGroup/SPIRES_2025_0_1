#!/bin/bash
#
# script to run SnowToday Step3:
#   update all westernUS SCF_SCD statistics files
#   for region partitions (full region, States, HUC2, etc)
#   for the current year
#   kick off Step4 for today
#   NB: only works for the region westernUS

#SBATCH --qos normal
#SBATCH --partition amilan
#SBATCH --job-name 3SnTo
#SBATCH --account=ucb-general
#SBATCH --time=08:00:00
# Assumes 3.74 GB/per node for total of 89.76 GB RAM
#SBATCH --ntasks-per-node=24
#SBATCH --nodes=1
#SBATCH -o /scratch/alpine/%u/slurm_out_SnowToday/%x-%A_%a.out
# Set the system up to notify upon completion
# Do not set --mail-user, let it default to the caller
# It can also be over-written at the command line
#SBATCH --mail-type FAIL,INVALID_DEPEND,TIME_LIMIT,REQUEUE,STAGE_OUT
#SBATCH --array=10-12

# Functions.
#---------------------------------------------------------------------------------------
usage() {
    echo "" 1>&2
    echo "Usage: ${PROGNAME} [-A LABEL_ANCILLARY] [-h] [-i] [-L LABEL] [-n] [-o] [-t]" 1>&2
    echo "       WATERYR" 1>&2
    echo "  Calculates ST statistics files to date for this WATERYR" 1>&2
    echo "  Job array for each region group (10=westUS, 11=States, 12=HUC2)" 1>&2
    echo "Options: "  1>&2
    echo "  -A LABEL_ANCILLARY: string with version of ancillary data" 1>&2
    echo "     e.g. for operational processing, use -A v3.1 for westernUS " 1>&2
    echo "     or -A v3.2 for USAlaska" 1>&2
    echo "  -h: display help message and exit" 1>&2
    echo "  -i: update input data from archive to scratch" 1>&2    
    echo "  -L LABEL: string with version label for directories" 1>&2
    echo "     e.g. for operational processing, use -L v2023.x" 1>&2
    echo "  -n: no pipeline: suppress starting next pipeline step" 1>&2
    echo "  -o: update output data from scratch to archive" 1>&2 
    echo "  -t: testing pipeline" 1>&2
    echo "      results will not be pushed to NSIDC" 1>&2
    echo "Arguments: " 1>&2
    echo "  WATERYR : stats will be calculated for this WATERYR (begins Oct 1 of WATERYR-1)" 1>&2
    echo "Output: " 1>&2
    echo "  Output location is controlled in Matlab scripts and -L LABEL" 1>&2
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
waterYear=$1
regionName='westernUS'

inputForESPEnv="modisData = modisData"
inputForRegion="'"${regionName}"', partitionName, espEnv, modisData"
inputForWaterYearDate="datetime('today'), region.getFirstMonthOfWaterYear(), "\
"WaterYearDate.yearMonthWindow"

source scripts/toolsMatlab.sh

# Scratch shuffle.
#---------------------------------------------------------------------------------------

# Do the scratch shuffle on daily Mosaics from input water year
# and for historical regional-stats files (to scratch for speed)
if [ $inputFromArchive ]; then
    for dataType in regional_stats/scagdrfs_mat variables/scagdrfs_mat; do
        ${thisScriptDir}/scratchShuffle.sh -b $((${waterYear} - 1)) -e ${waterYear} \
                TO ${dataType}_$LABEL ${regionName} || \
        error_exit "Line $LINENO: scratchShuffle error ${dataType} ${LABEL} ${regionName}"
    done
    echo "${PROGNAME}: Done with shuffle TO scratch..."
fi

# Matlab.
#---------------------------------------------------------------------------------------
# Make the year-to-date Statistics files
# Make the csv versions of the stats in historical context
# (only for main region array=10), make geotiffs for that last available date
matlab -nodesktop -nodisplay -r "clear; "\
"try; "\
"modisData = MODISData(${inputForModisData}); "\
"espEnv = ESPEnv(${inputForESPEnv}); "\
"partitionName = Regions.getPartitionNameFor("${SLURM_ARRAY_TASK_ID}"); "\
"region = Regions(${inputForRegion}); "\
"minSCP = minSCPForLinePlots(); "\
"minZ = minZForLinePlots(); "\
"runStatsForLinePlots(region, ${waterYear}, ${waterYear}, minSCP, minZ); "\
"waterYearDate = WaterYearDate(${inputForWaterYearDate}); "\
"region.runWriteStats(waterYearDate); "\
"if "${SLURM_ARRAY_TASK_ID}" == 10; "\
"mosaic = Mosaic(region); "\
"waterYearDate = WaterYearDate(mosaic.getMostRecentMosaicDt(waterYearDate), "\
"region.getFirstMonthOfWaterYear(), 0); "\
"region.writeGeotiffs(NaN, waterYearDate, region.webGeotiffEPSG); "\
"end; "\
"catch e; "\
"fprintf('%s: %s\n', e.identifier, e.message); "\
"exit(-1); "\
"end; "\
"exit(0);" || error_exit "Line $LINENO: matlab error."

# Scratch shuffle.
#---------------------------------------------------------------------------------------
# Do the scratch shuffle on output regional_stats, csv files and geotiffs  back from scratch
if [ $outputToArchive ]; then
    for dataType in regional_stats/scagdrfs_mat regional_stats/scagdrfs_csv variables/scagdrfs_geotiff; do
        ${thisScriptDir}/scratchShuffle.sh FROM ${dataType}_$LABEL ${regionName} || \
        error_exit "Line $LINENO: scratchShuffle FROM error ${dataType} ${LABEL} ${regionName}"
    done
    echo "${PROGNAME}: Done with shuffle FROM scratch..."
fi

# Launch of next Step of the SnowToday daily process. Not applied for USAlaska now.
#---------------------------------------------------------------------------------------
#schedule next job in pipeline to run after entire job array completes
if [ $isBatch ] && [ ! $noPipeline ] && [ ! $testing ] && [ $regionName == "westernUS" ]; then
    
    # get current slurm info for stdout
    stdoutDir=$( dirname `${thisScriptDir}/getSlurmStdout.sh ${SLURM_JOB_ID}` )

    if [ "$SLURM_ARRAY_TASK_ID" -eq "10" ]; then

        STDOUT_STEP4="${stdoutDir}/4SnTo-%j.out"
        
        #schedule Step 4 to make today's plots after this set of array jobs complete
        sbatch --dependency=afterok:$SLURM_ARRAY_JOB_ID \
               --output=${STDOUT_STEP4} \
               ${thisScriptDir}/runSnowTodayStep4.sh ${nextStepOptions} $waterYear
    fi    
fi

source scripts/toolsStop.sh
