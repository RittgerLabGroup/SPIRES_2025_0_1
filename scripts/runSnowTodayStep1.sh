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
#SBATCH --job-name 1_SnowToday
#SBATCH --account=ucb188_summit2
#SBATCH --time=06:00:00
#SBATCH --ntasks-per-node=24
#SBATCH --nodes=1
#SBATCH -o /scratch/summit/%u/slurm_out_SnowToday/runSnowTodayStep1-%A_%a.out
# Set the system up to notify upon completion
#SBATCH --mail-type=FAIL,REQUEUE,STAGE_OUT
#SBATCH --mail-user=brodzik@nsidc.org
#SBATCH --array=1-5

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
    echo "Usage: ${PROGNAME} [-h] [-n] MINDAYS NORTHZTHRESH SOUTHZTHRESH " 1>&2
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
    echo "Arguments: " 1>&2
    echo "  MINDAYS : mindays to use for STC cubes, pass to step 2" 1>&2
    echo "  NORTHZTHRESH : Northern altitude threshold (m) to pass to step 2" 1>&2
    echo "  SOUTHZTHRESH : Southern altitude threshold (m) to pass to step 2" 1>&2
    echo "  YEARSTART : year to begin" 1>&2
    echo "  MONTHSTART : month to begin" 1>&2
    echo "  YEARSTOP : year to stop" 1>&2
    echo "  MONTHSTOP : month to stop" 1>&2
    echo "Output: " 1>&2
    echo "  Output location is controlled in Matlab scripts " 1>&2
    echo "Notes: " 1>&2
    echo "  Scripts stdout/stderr are written to user's scratch " 1>&2
    echo "  where directory /scratch/summit/$USER/slurm_out_SnowToday/ " 1>&2
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

while getopts "hn" opt
do
    case $opt in
	h) usage
	   exit 1;;
	n) noPipeline=1;;
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

module purge
ml matlab/R2019b

thisHost=$(hostname)
thisDate=$(date)
echo "${PROGNAME}: Begin on hostname=$thisHost on $thisDate for mindays=$mindays"
echo "${PROGNAME}: Start = $yearStart, $monthStart"
echo "${PROGNAME}: Stop  = $yearStop, $monthStop"
echo "${PROGNAME}: SLURM_SCRATCH=$SLURM_SCRATCH"
echo "${PROGNAME}: SLURM_JOB_ID=$SLURM_JOB_ID"
echo "${PROGNAME}: SLURM_ARRAY_JOB_ID=$SLURM_ARRAY_JOB_ID"

#Make a unique temporary directory for matlab job storage
#Set TMPDIR to this location so job array uses it for tmp location
mkdir -p $SLURM_SCRATCH/$SLURM_ARRAY_JOB_ID
export TMPDIR=$SLURM_SCRATCH/$SLURM_ARRAY_JOB_ID

#Go to parent of this script, so that correct pathdef.m file is used
cd "${thisScriptDir}/../"

matlab -nodesktop -nodisplay -r "clear; "\
"try; "\
"MData = MODISData(); "\
"tiles = MData.tilesFor('westernUS'); "\
"updateRegionMonthCubes(tiles, "$SLURM_ARRAY_TASK_ID", "\
"${yearStart}, ${monthStart}, ${yearStop}, ${monthStop}, "\
"${mindays}, "\
"'zthresh', ["${northZthresh}" "${southZthresh}"]); "\
"catch e; "\
"fprintf('%s: %s\n', e.identifier, e.message); "\
"exit(-1); "\
"end; "\
"exit(0);" || error_exit "Line $LINENO: matlab error."

#schedule next job in pipeline to run after entire job array completes
if [ $isBatch ] && [ ! $noPipeline ]; then
    
    # get current slurm info for mail-user and stdout
    # Don't assume they are the same as at the top of this file,
    # because they can be overridden at the command line
    MAIL=`${thisScriptDir}/getSlurmMail.sh ${SLURM_JOB_ID}`
    stdoutDir=$( dirname `${thisScriptDir}/getSlurmStdout.sh ${SLURM_JOB_ID}` )

    if [ "$SLURM_ARRAY_TASK_ID" -eq "1" ]; then

	STDOUT_STEP2="${stdoutDir}/runSnowTodayStep2-%j.out"

	# schedule next job in Indux regional pipeline for today
	sbatch --dependency=afterok:$SLURM_ARRAY_JOB_ID \
	       --mail-user=${MAIL} \
	       --output=${STDOUT_STEP2} \
	       ${thisScriptDir}/runSnowTodayStep2.sh \
	       $mindays $northZthresh $southZthresh \
	       $yearStart $monthStart $yearStop $monthStop

    fi

else
    echo "${PROGNAME}: Not continuing pipeline for non-sbatch call."
fi

#Clean up temporary directory for matlab job storage
echo "${PROGNAME}: Removing TMPDIR=$TMPDIR..."
rm -rf $TMPDIR

thisDate=$(date)
echo "${PROGNAME}: Done on hostname=$thisHost on $thisDate"

