#!/bin/bash
#
# script to run SnowToday Step1:
#   Job array for each of westernUS tiles for time period:
#      update Raw cubes
#      udpate STC (Gap/Interp cubes)
#
# Set up the SBATCH nodes/ntasks-per-node for 1 matlab job that
# may need up to all the tasks on this node.  Current times
# are optimized for 3-month intervals
#

#SBATCH --qos normal
#SBATCH --partition amilan
#SBATCH --job-name 1SnTo
#SBATCH --account ucb-general
#SBATCH --time 03:30:00
# On Summit, we asked for 24 tasks, but mem is less per task on alpine
# On Alpine try, 32
#SBATCH --ntasks 32
#SBATCH --nodes 1
#SBATCH -o /scratch/alpine/%u/slurm_out_SnowToday/%x-%A_%a.out
# Set the system up to notify upon completion
# Do not set --mail-user, let it default to the caller
# It can also be over-written at the command line
#SBATCH --mail-type FAIL,INVALID_DEPEND,TIME_LIMIT,REQUEUE,STAGE_OUT
#SBATCH --array 292,293,328,329,364
#   By default tile ids of the westernUS region. See toolsRegions.sh for their
#   construction. E.g. 292: h08v04. Script updated for Alaska SIER_322.

# Functions.
#---------------------------------------------------------------------------------------
usage() {
    echo "" 1>&2
    echo "Usage: ${PROGNAME} [-A LABEL_ANCILLARY] [-h] [-i] [-L LABEL] [-n] [-o] [-t]" 1>&2
    echo "       BIGREGIONNAME YEAR MONTH MONTHWINDOW" 1>&2
    echo "  Runs Step1 in SnowToday pipeline" 1>&2
    echo "  Job array of each tile of a big region for this time period: " 1>&2
    echo "    Update raw data cubes" 1>&2
    echo "    Update STC (Gap/Interp) data cubes" 1>&2
    echo "  If called by slurm:" 1>&2
    echo "    starts SnowTodayStep2 for today, after job array completes" 1>&2
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
    echo "  BIGREGIONNAME: id of the region which will be transmitted to Step 2, " 1>&2
    echo "      classically westernUS or USAlaska but might be h08v04 too, for testing." 1>&2
    echo "  YEAR : month to stop" 1>&2
    echo "  MONTH : month to stop" 1>&2
    echo "  MONTHWINDOW : number of months to handle before (1 for only current month," 1>&2
    echo "    12 for full waterYear)" 1>&2
    echo "Output: " 1>&2
    echo "  Output location is controlled in Matlab scripts and -L LABEL " 1>&2
    echo "Notes: " 1>&2
    echo "  Scripts stdout/stderr are written to user's scratch " 1>&2
    echo "  where directory /scratch/alpine/$USER/slurm_out_SnowToday/ " 1>&2
    echo "  is assumed to exist" 1>&2
}

# Core script.
#---------------------------------------------------------------------------------------
# Initialize variables, option setting.
# Grab the full path to this script
# depends on whether it's running as sbatch job
scriptId=snoStep1
defaultSlurmArrayTaskId=292
expectedCountOfArguments=4
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
source scripts/toolsRegions.sh
source scripts/toolsStart.sh

# Argument setting
bigRegionName=$1
year=$2
month=$3
monthWindow=$4

regionName=$(get_tile_name_from_tile_id ${SLURM_ARRAY_TASK_ID})

inputForESPEnv="modisData = modisData"
inputForRegion="'"${regionName}"', '"${regionName}"_mask', espEnv, modisData"
inputForWaterYearDate="datetime(${year}, ${month}, eomday(${year}, ${month})), "\
"modisData.getFirstMonthOfWaterYear('"${regionName}"'), ${monthWindow}"
inputForCube="region, waterYearDate"
echo "${PROGNAME}: inputForWaterYearDate: ${inputForWaterYearDate}"

source scripts/toolsMatlab.sh

# Scratch shuffle.
#---------------------------------------------------------------------------------------
# Do the scratch shuffle on NRT MOD09/SCAG/DRFS inputs
# Note that Matlab array indexing is 1-based, but
# bash array indexing is 0-based
# N.B. It is assumed that the item order of this array matches
# the item order in the region_masks files
if [ $inputFromArchive ]; then
    for dataType in mod09ga modscag moddrfs; do
        ${thisScriptDir}/scratchShuffle.sh -b $((year - 1)) -e $year \
                TO ${dataType}/NRT ${regionName} || \
        error_exit "Line $LINENO: scratchShuffle error ${dataType} ${regionName}"
    done
    for dataType in mod09_raw scagdrfs_raw scagdrfs_gap scagdrfs_stc; do
        ${thisScriptDir}/scratchShuffle.sh -b $((year - 1)) -e $year \
                TO intermediary/${dataType}_$LABEL ${regionName} || \
        error_exit "Line $LINENO: scratchShuffle error ${dataType} ${regionName}"
    done
    echo "${PROGNAME}: Done with shuffle TO scratch."
fi

# Matlab.
#---------------------------------------------------------------------------------------
matlab -nodesktop -nodisplay -r "clear; "\
"try; "\
"modisData = MODISData(${inputForModisData}); "\
"espEnv = ESPEnv(${inputForESPEnv}); "\
"region = Regions(${inputForRegion}); "\
"waterYearDate = WaterYearDate(${inputForWaterYearDate}); "\
"rawCube = RawCube(${inputForCube}); "\
"rawCube.build(); "\
"stcCube = StcCube(${inputForCube}); "\
"stcCube.build(); "\
"catch e; "\
"fprintf('%s: %s\n', e.identifier, e.message); "\
"exit(-1); "\
"end; "\
"exit(0);" || error_exit "Line $LINENO: matlab error."

echo "${PROGNAME}: Done with Step1, doing shuffle FROM scratch..."

# Scratch shuffle.
#---------------------------------------------------------------------------------------
# Do the scratch shuffle on Raw/Gap/STC outputs (back from scratch to archive)
if [ $outputToArchive ]; then
    for dataType in mod09_raw scagdrfs_raw scagdrfs_gap scagdrfs_stc; do
        ${thisScriptDir}/scratchShuffle.sh -b $((year - 1)) -e $year \
                FROM intermediary/${dataType}_$LABEL ${regionName} || \
        error_exit "Line $LINENO: scratchShuffle error ${dataType} ${tile}"
    done
    echo "${PROGNAME}: Done with shuffle FROM scratch..."
fi

# Launch of next Step of the SnowToday daily process. Not applied for USAlaska now.
#---------------------------------------------------------------------------------------
if [ $isBatch ] && [ ! $noPipeline ] && [ $regionName == "westernUS" ] \
&& [ $SLURM_ARRAY_TASK_ID -eq 292 ]; then
    STDOUT_STEP2="${stdoutDir}/2SnTo-%A_%a.out"

    # We might be able to speed this processing up by limiting
    # the mosaics to [monthStop - 1, monthStop]

    # schedule next job in pipeline for today
    # Dependency afterok:$SLURM_ARRAY_JOB_ID (and not SLURM_JOB_ID)
    # implies that the next step won't
    # start before all the tile jobs for the big region are done.
    sbatch --dependency=afterok:$SLURM_ARRAY_JOB_ID \
           --output=${STDOUT_STEP2} \
           ${thisScriptDir}/runSnowTodayStep2.sh ${nextStepOptions} \
           $bigRegionName $year $month $monthWindow
else
    echo "${PROGNAME}: Not continuing pipeline."
fi

source scripts/toolsStop.sh
