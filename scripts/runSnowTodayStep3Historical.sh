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
#SBATCH --mail-user brodzik@colorado.edu
#SBATCH --array=10-12

# Grab the full path to this script
# depends on whether it's running as sbatch job
isBatch=
if [[ ${BASH_SOURCE} == *"slurm_script"* ]]; then
    # Running as slurm
    echo "Running as sbatch job..."
    PROGNAME=(`scontrol show job ${SLURM_JOB_ID} | grep Command | tr -s ' ' | cut -d = -f 2`)
    isBatch=1
else
    echo "Not running as sbatch..."
    PROGNAME=${BASH_SOURCE[0]}
fi
thisScriptDir="$( cd "$( dirname "${PROGNAME}" )" && pwd )"

usage() {
    echo "" 1>&2
    echo "Usage: ${PROGNAME} [-h] [-L LABEL] WATERYR" 1>&2
    echo "  Calculates annual updates to ST statistics files prior to WATERYR" 1>&2
    echo "  So for this script to run in Oct 2021, set WATERYR to 2022" 1>&2
    echo "  Job array for each region group (10=westUS, 11=States, 12=HUC2)" 1>&2
    echo "  Run this script once annually, on or after Oct 1" 1>&2
    echo "Options: "  1>&2
    echo "  -h: display help message and exit" 1>&2
    echo "  -L LABEL: string with version label for directories" 1>&2
    echo "     e.g. for operational processing, use -L v2023.x" 1>&2
    echo "Arguments: " 1>&2
    echo "  THISYR : stats will be calculated for 2001 to (THISYR - 1)" 1>&2
    echo "Output: " 1>&2
    echo "  Output location is controlled in Matlab scripts " 1>&2
    echo "Notes: " 1>&2
    echo "  Scripts stdout/stderr are written to user's scratch " 1>&2
    echo "  where directory /scratch/alpine/$USER/slurm_out_SnowToday/ " 1>&2
    echo "  is assumed to exist" 1>&2
}

error_exit() {
    # Use for fatal program error
    # Argument:
    #   optional string containing descriptive error message
    #   if no error message, prints "Unknown Error"

    echo "${PROGNAME}: ERROR: ${1:-"Unknown Error"}" 1>&2
    exit 1
}

LABEL=

while getopts "hL:" opt
do
    case $opt in
	h) usage
	   exit 1;;
	L) LABEL="$OPTARG";;
	?) printf "Unknown option %s\n" $opt
	   usage
           exit 1;;
	esac
done

shift $(($OPTIND - 1))

[[ "$#" -eq 1 ]] || error_exit "Line $LINENO: Unexpected number of arguments."

waterYr=$1

options=""
if [ $LABEL ]; then
    options="'label', '$LABEL'"
fi

module purge
ml matlab/R2021b

# Start the stopwatch
SECONDS=0

startWaterYr=2001
stopWaterYr=$(( $waterYr - 1 ))

thisHost=$(hostname)
thisDate=$(date)
echo "${PROGNAME}: Begin on hostname=$thisHost on $thisDate for array job=$SLURM_ARRAY_TASK_ID and WY=$startWaterYr to $stopWaterYr and options=$options"
echo "${PROGNAME}: SLURM_SCRATCH=$SLURM_SCRATCH"
echo "${PROGNAME}: SLURM_JOB_ID=$SLURM_JOB_ID"
echo "${PROGNAME}: SLURM_ARRAY_JOB_ID=$SLURM_ARRAY_JOB_ID"

#Make a unique temporary directory for matlab job storage
#Set TMPDIR/TMP to this location so job array uses it for tmp location
tmpDir=/scratch/alpine/${USER}/matlabTmp/alpine-$SLURM_ARRAY_JOB_ID
mkdir -p $tmpDir
export TMPDIR=$tmpDir
export TMP=$tmpDir

#Go to parent of this script, so that correct pathdef.m file is used
cd "${thisScriptDir}/../"

# Do the scratch shuffle on complete set of input daily Mosaics (to scratch for speed)
REGIONNAME='westernUS'
yearStart=$(( $startWaterYr - 1 ))
for dataType in scagdrfs_mat; do
    ${thisScriptDir}/scratchShuffle.sh -b ${yearStart} -e ${stopWaterYr} \
		    TO variables/${dataType}_$LABEL ${REGIONNAME} || \
	error_exit "Line $LINENO: scratchShuffle error ${dataType} ${LABEL} ${REGIONNAME}"
done

# Do scratch shuffle for required ancillary data
${thisScriptDir}/scratchShuffleAncillary.sh || \
    error_exit "Line $LINENO: scratchShuffleAncillary error"

echo "${PROGNAME}: Done with shuffle TO scratch..."
    
matlab -nodesktop -nodisplay -r "clear; "\
"try; "\
"espEnv = ESPEnv(); "\
"mData = MODISData($options); "\
"partitionName = Regions.getPartitionNameFor("${SLURM_ARRAY_TASK_ID}"); "\
"region = Regions('"${REGIONNAME}"', partitionName, espEnv, mData); "\
"minSCP = minSCPForLinePlots(); "\
"minZ = minZForLinePlots(); "\
"runStatsForLinePlots(region, ${startWaterYr}, ${stopWaterYr}, minSCP, minZ); "\
"catch e; "\
"fprintf('%s: %s\n', e.identifier, e.message); "\
"exit(-1); "\
"end; "\
"exit(0);"  || error_exit "Line $LINENO: matlab error."

# Do the scratch shuffle on output regional_stats back from scratch
echo "${PROGNAME}: Doing with shuffle FROM scratch..."
for dataType in scagdrfs_mat; do
    ${thisScriptDir}/scratchShuffle.sh \
		    FROM regional_stats/${dataType}_$LABEL ${REGIONNAME} || \
	error_exit "Line $LINENO: scratchShuffle FROM error ${dataType} ${LABEL} ${REGIONNAME}"
done
echo "${PROGNAME}: Done with shuffle FROM scratch..."
						
#Clean up temporary directory for matlab job storage
echo "${PROGNAME}: Removing TMPDIR=$TMPDIR..."
rm -rf $TMPDIR

# Stop the stopwatch and report elapsed time
elapsedSeconds=$SECONDS
duration=$(TZ=UTC0 printf 'Duration: %(%H:%M:%S)T\n' "$elapsedSeconds")

thisDate=$(date)
echo "${PROGNAME}: Done on hostname=$thisHost on $thisDate [${duration}]"
