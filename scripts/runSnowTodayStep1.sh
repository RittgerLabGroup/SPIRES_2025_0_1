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
# Arguments:
#
# yr: year to update
# mindays: mindays to use for STC cubes
# northZthresh: Northern latitude limit for Zthresh (meters)
# southZthresh: Southern latitude limit for Zthresh (meters)

#SBATCH --qos normal
#SBATCH --partition amilan
#SBATCH --job-name 1SnTo
#SBATCH --account ucb-general
#SBATCH --time 10:00:00
# On Summit, we asked for 24 tasks, but mem is less per task on alpine
# On Alpine try, 32
#SBATCH --ntasks 32
#SBATCH --nodes 1
#SBATCH -o /scratch/alpine/%u/slurm_out_SnowToday/%x-%A_%a.out
# Set the system up to notify upon completion
#SBATCH --mail-type END,FAIL,INVALID_DEPEND,TIME_LIMIT,REQUEUE,STAGE_OUT
#SBATCH --mail-user brodzik@colorado.edu
#SBATCH --array 1-5

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
    echo "Usage: ${PROGNAME} [-h] [-n] [-L LABEL] " 1>&2
    echo "       MINDAYS NORTHZTHRESH SOUTHZTHRESH " 1>&2
    echo "       YEARSTART MONTHSTART YEARSTOP MONTHSTOP" 1>&2
    echo "  Runs Step1 in SnowToday pipeline" 1>&2
    echo "  Job array of each of 5 WesternUS tiles for this time period: " 1>&2
    echo "    Update raw data cubes" 1>&2
    echo "    Update STC (Gap/Interp) data cubes" 1>&2
    echo "  If called by slurm:" 1>&2
    echo "    starts SnowTodayStep2 for today, after job array completes" 1>&2
    echo "Options: "  1>&2
    echo "  -h: display help message and exit" 1>&2
    echo "  -n: no pipeline: suppress starting next pipeline step" 1>&2
    echo "  -L LABEL: string with version label for directories" 1>&2
    echo "     e.g. for operational processing, use -L v2023.x" 1>&2
    echo "Arguments: " 1>&2
    echo "  MINDAYS : mindays to use for STC cubes" 1>&2
    echo "  NORTHZTHRESH : Northern altitude threshold (m)" 1>&2
    echo "  SOUTHZTHRESH : Southern altitude threshold (m)" 1>&2
    echo "  YEARSTART : year to begin" 1>&2
    echo "  MONTHSTART : month to begin" 1>&2
    echo "  YEARSTOP : year to stop" 1>&2
    echo "  MONTHSTOP : month to stop" 1>&2
    echo "Output: " 1>&2
    echo "  Output location is controlled in Matlab scripts and -L LABEL " 1>&2
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

noPipeline=
LABEL=

while getopts "hnL:" opt
do
    case $opt in
	h) usage
	   exit 1;;
	n) noPipeline=1;;
	L) LABEL="$OPTARG";;
	?) printf "Unknown option %s\n" $opt
	   usage
           exit 1;;
	esac
done

shift $(($OPTIND - 1))

[[ "$#" -eq 7 ]] || error_exit "Line $LINENO: Unexpected number of arguments."

if [ $noPipeline ]; then
    echo "${PROGNAME}: noPipeline mode: this script will not continue pipeline"
fi

mindays=$1
northZthresh=$2
southZthresh=$3
yearStart=$4
monthStart=$5
yearStop=$6
monthStop=$7

options=""
if [ $LABEL ]; then
    options="'label', '$LABEL'"
fi

module purge
ml matlab/R2021b

# Start the stopwatch
SECONDS=0

thisHost=$(hostname)
thisDate=$(date)
echo "${PROGNAME}: Begin on hostname=$thisHost on $thisDate for mindays=$mindays"
echo "${PROGNAME}: Start = $yearStart, $monthStart"
echo "${PROGNAME}: Stop  = $yearStop, $monthStop"
echo "${PROGNAME}: SLURM_SCRATCH=$SLURM_SCRATCH"
echo "${PROGNAME}: SLURM_JOB_ID=$SLURM_JOB_ID"
echo "${PROGNAME}: SLURM_ARRAY_JOB_ID=$SLURM_ARRAY_JOB_ID"

#Make a unique temporary directory for matlab job storage
#Set TMPDIR/TMP to this location so job array uses it for tmp location
tmpDir=/scratch/alpine/${USER}/matlabTmp/alpine-$SLURM_ARRAY_JOB_ID
mkdir -p $tmpDir
export TMPDIR=$tmpDir
export TMP=$tmpDir

# Go to parent of this script, so that correct pathdef.m file is used
cd "${thisScriptDir}/../"

# Do the scratch shuffle on NRT MOD09/SCAG/DRFS inputs
# Note that Matlab array indexing is 1-based, but
# bash array indexing is 0-based
TILES=(h08v04 h08v05 h09v04 h09v05 h10v04)
idx=$((SLURM_ARRAY_TASK_ID - 1));
for dataType in mod09ga modscag moddrfs; do
    ${thisScriptDir}/scratchShuffle.sh TO -b ${yearStart} -e ${yearStop} \
		    ${dataType}/NRT ${TILES[$idx]} || \
	error_exit "Line $LINENO: scratchShuffle error ${dataType} ${tile}"
done

# Do scratch shuffle for required ancillary data
${thisScriptDir}/scratchShuffleAncillary.sh || \
    error_exit "Line $LINENO: scratchShuffleAncillary error"

# Eventually this string should be an input to this script
regionName='westernUS'

# The default 
matlab -nodesktop -nodisplay -r "clear; "\
"try; "\
"espEnv = ESPEnv(); "\
"mData = MODISData($options); "\
"tiles = mData.tilesFor('"${regionName}"'); "\
"region = Regions('"${regionName}"', '"${regionName}"_mask'], "\
"espEnv, mData); "\
"updateRegionMonthCubes(region, tiles, "$SLURM_ARRAY_TASK_ID", "\
"${yearStart}, ${monthStart}, ${yearStop}, ${monthStop}); "\
"catch e; "\
"fprintf('%s: %s\n', e.identifier, e.message); "\
"exit(-1); "\
"end; "\
"exit(0);" || error_exit "Line $LINENO: matlab error."

# Do the scratch shuffle on Raw/Gap/STC outputs (back from scratch to archive)
for dataType in mod09_raw scagdrfs_raw scagdrfs_gap scagdrfs_stc; do
    ${thisScriptDir}/scratchShuffle.sh FROM -b ${yearStart} -e ${yearStop} \
		    intermediary/${dataType}_$LABEL ${TILES[$idx]} || \
	error_exit "Line $LINENO: scratchShuffle error ${dataType} ${tile}"
done

#schedule next job in pipeline to run after entire job array completes
if [ $isBatch ] && [ ! $noPipeline ]; then
    
    # get current slurm info for mail-user and stdout
    # Don't assume they are the same as at the top of this file,
    # because they can be overridden at the command line
    MAIL=`${thisScriptDir}/getSlurmMail.sh ${SLURM_JOB_ID}`
    stdoutDir=$( dirname `${thisScriptDir}/getSlurmStdout.sh ${SLURM_JOB_ID}` )

    if [ "$SLURM_ARRAY_TASK_ID" -eq "1" ]; then

	STDOUT_STEP2="${stdoutDir}/runSnowTodayStep2-%j.out"

	# schedule next job in pipeline for today
	sbatch --dependency=afterok:$SLURM_ARRAY_JOB_ID \
	       --mail-user=${MAIL} \
	       --output=${STDOUT_STEP2} \
	       ${thisScriptDir}/runSnowTodayStep2.sh \
	       -L $LABEL \
	       $yearStart $monthStart $yearStop $monthStop

    fi

else
    echo "${PROGNAME}: Not continuing pipeline for non-sbatch call."
fi

#Clean up temporary directory for matlab job storage
echo "${PROGNAME}: Removing TMPDIR=$TMPDIR..."
rm -rf $TMPDIR

# Stop the stopwatch and report elapsed time
elapsedSeconds=$SECONDS
TZ=UTC0 printf '${PROGNAME}: Duration: %(%H:%M:%S)T\n' "$elapsedSeconds"

thisDate=$(date)
echo "${PROGNAME}: Done on hostname=$thisHost on $thisDate"

