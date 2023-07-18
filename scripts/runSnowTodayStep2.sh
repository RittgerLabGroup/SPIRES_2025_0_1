#!/bin/bash
#
# script to run SnowToday Step2:
#   update tile and big region daily mosaic files for this year for all variables
#   kick off Step3 for today

#SBATCH --qos normal
#SBATCH --partition amilan
#SBATCH --job-name 2SnTo
#SBATCH --account ucb-general
#SBATCH --time=02:00:00
#SBATCH --ntasks-per-node=20
#SBATCH --nodes=1
#SBATCH -o /scratch/alpine/%u/slurm_out_SnowToday/%x-%A-%a.out
# Set the system up to notify upon completion
# Do not set --mail-user, let it default to the caller
# It can also be over-written at the command line
#SBATCH --mail-type FAIL,INVALID_DEPEND,TIME_LIMIT,REQUEUE,STAGE_OUT
#SBATCH --array=1
#   Unused but keep to 1. Script updated for Alaska SIER_322.

# Functions.
#---------------------------------------------------------------------------------------
usage() {
    echo "" 1>&2
    echo "Usage: ${PROGNAME} [-A LABEL_ANCILLARY] [-h] [-i] [-L LABEL] [-n] [-o] [-t]" 1>&2
    echo "       BIGREGIONNAME YEAR MONTH MONTHWINDOW" 1>&2
    echo "  Runs Step2 in SnowToday pipeline" 1>&2
    echo "  Updates daily mosaic files for all variables" 1>&2
    echo "    and the requested time period" 1>&2
    echo "  If called by slurm:" 1>&2
    echo "    starts SnowTodayStep3 for today" 1>&2
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
    echo "  BIGREGIONNAME: id of the region which tiles to import, classically " 1>&2
    echo "      westernUS or USAlaska but can be h08v04 too, for testing." 1>&2
    echo "  YEAR : month to stop" 1>&2
    echo "  MONTH : month to stop" 1>&2
    echo "  MONTHWINDOW : number of months to handle before (1 for only current month," 1>&2
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
scriptId=snoStep2
defaultSlurmArrayTaskId=1
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
source scripts/toolsStart.sh

# Argument setting
bigRegionName=$1
year=$2
month=$3
monthWindow=$4
bigRegionId=$(get_tile_group_id_from_group_name $bigRegionName)
tiles=${tileArrayForTileGroup${SLURM_ARRAY_TASK_ID}}

inputForESPEnv="modisData = modisData"
inputForBigRegion="'"${bigRegionName}"', '"${bigRegionName}"_mask', espEnv, modisData"
inputForWaterYearDate="datetime(${year}, ${month}, eomday(${year}, ${month})), ${monthWindow}"
echo "${PROGNAME}: inputForWaterYearDate: ${inputForWaterYearDate}"

source scripts/toolsMatlab.sh

# Scratch shuffle.
# Will need so refactoring when introducing other regions.
#---------------------------------------------------------------------------------------
# Do the scratch shuffle on required STC inputs
if [ $inputFromArchive ]; then
    for dataType in scagdrfs_stc scagdrfs_mat; do
        for tile in $tiles; do
        ${thisScriptDir}/scratchShuffle.sh -b $((year - 1)) -e $year \
                TO intermediary/${dataType}_$LABEL ${tile} || \
            error_exit "Line $LINENO: scratchShuffle error ${dataType} ${tile}"
        done
    done
    echo "${PROGNAME}: Done with shuffle TO scratch."
fi

# Matlab.
#---------------------------------------------------------------------------------------
matlab -nodesktop -nodisplay -r "clear; "\
"try; "\
"modisData = MODISData(${inputForModisData}); "\
"espEnv = ESPEnv(${inputForESPEnv}); "\
"region = Regions(${inputForBigRegion}); "\
"waterYearDate = WaterYearDate(${inputForWaterYearDate}); "\
"tileRegions = region.getTileRegions(); "\
"for tileIdx = 1:length(tileRegions); "\
"    mosaic = Mosaic(tileRegions(tileIdx)); "\
"    mosaic.runWriteFiles(waterYearDate); "\
"    variables = Variables(tileRegions(tileIdx)); "\
"    variables.calcAlbedos(waterYearDate); "\
"    variables.calcDaysWithoutObservation(waterYearDate); "\
"end; "\
"mosaic = Mosaic(region); "\
"mosaic.buildTileSet(waterYearDate); "\
"catch e; "\
"fprintf('%s: %s\n', e.identifier, e.message); "\
"exit(-1); "\
"end; "\
"exit(0);" || error_exit "Line $LINENO: matlab error."

# Scratch shuffle.
#---------------------------------------------------------------------------------------
# Do the scratch shuffle on output daily Mosaics (back from scratch to archive)
if [ $outputToArchive ]; then
    for dataType in scagdrfs_mat; do
        for tile in $tiles; do
            ${thisScriptDir}/scratchShuffle.sh -b $((year - 1)) -e $year \
                    FROM intermediary/${dataType}_$LABEL ${tile} || \
                error_exit "Line $LINENO: scratchShuffle error ${dataType} ${tile}"
        done
        ${thisScriptDir}/scratchShuffle.sh -b $((year - 1)) -e $year \
                FROM variables/${dataType}_$LABEL ${bigRegionName} || \
        error_exit "Line $LINENO: scratchShuffle error ${dataType} ${LABEL} ${regionName}"
    done
    echo "${PROGNAME}: Done with shuffle FROM scratch..."
fi

# Launch of next Step of the SnowToday daily process. Not applied for USAlaska now.
#---------------------------------------------------------------------------------------
if [ $isBatch ] && [ ! $noPipeline ] && [ $regionName == "westernUS" ]; then

    STDOUT_STEP3="${stdoutDir}/3SnTo-%A_%a.out"
    waterYear=$year
    if (( "$month" > "9" )); then
	waterYear=$(( $waterYear + 1 ))
    fi
    #schedule Step 3 to update stats
    sbatch --dependency=afterok:$SLURM_JOB_ID \
	   --output=${STDOUT_STEP3} \
	   ${thisScriptDir}/runSnowTodayStep3.sh ${nextStepOptions} \
	   ${waterYear}

else
    echo "${PROGNAME}: Not continuing pipeline for non-sbatch call."
fi

source scripts/toolsStop.sh
