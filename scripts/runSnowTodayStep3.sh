#!/bin/bash
#
# script to run SnowToday Step3:
#   update all westernUS SCF_SCD statistics files
#   for region paritions (full region, States, HUC2, etc)
#   for the current year
#   kick off Step4 for today
#

#SBATCH --qos normal
#SBATCH --job-name 3_SnowToday
#SBATCH --account=ucb188_summit1
#SBATCH --time=04:00:00
#SBATCH --ntasks-per-node=20
#SBATCH --mem=90G
#SBATCH --nodes=1
#SBATCH -o /scratch/summit/%u/slurm_out_SnowToday/runSnowTodayStep3-%A_%a.out
# Set the system up to notify upon completion
#SBATCH --mail-type=FAIL,REQUEUE,STAGE_OUT
#SBATCH --mail-user=brodzik@nsidc.org
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
    echo "Usage: ${PROGNAME} [-h] [-n] WATERYR " 1>&2
    echo "       MINDAYS NORTHZTHRESH SOUTHZTHRESH" 1>&2
    echo "  Calculates ST statistics files to date for this WATERYR" 1>&2
    echo "  Job array for each region group (10=westUS, 11=States, 12=HUC2)" 1>&2
    echo "Options: "  1>&2
    echo "  -h: display help message and exit" 1>&2
    echo "  -n: no pipeline: suppress starting next pipeline step" 1>&2
    echo "Arguments: " 1>&2
    echo "  THISYR : stats will be calculated for this WATERYR (begins Oct 1)" 1>&2
    echo "  MINDAYS : mindays to use for mosaic directories" 1>&2
    echo "  NORTHZTHRESH : Northern altitude threshold (m) " 1>&2
    echo "  SOUTHZTHRESH : Southern altitude threshold (m) " 1>&2
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

while getopts "h" opt
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

[[ "$#" -eq 4 ]] || error_exit "Line $LINENO: Unexpected number of arguments."

waterYr=$1
mindays=$2
northZthresh=$3
southZthresh=$4

module purge
ml matlab/R2019b

thisHost=$(hostname)
thisDate=$(date)
echo "${PROGNAME}: Begin on hostname=$thisHost on $thisDate for waterYr=$waterYr and mindays=$mindays, zthresh=[$northZthresh $southZthresh]"
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
"minSCP = minSCPForLinePlots(); "\
"minZ = minZForLinePlots(); "\
"runStatsForLinePlots('westernUS', "$SLURM_ARRAY_TASK_ID", "\
"${waterYr}, ${waterYr}, "\
"minSCP, minZ, ${mindays}, "\
"["${northZthresh}" "${southZthresh}"]); "\
"exit(0);" || error_exit "Line $LINENO: matlab error."

#schedule next job in pipeline to run after entire job array completes
if [ $isBatch ] && [ ! $noPipeline ]; then
    
    # get current slurm info for mail-user and stdout
    # Don't assume they are the same as at the top of this file,
    # because they can be overridden at the command line
    MAIL=`${thisScriptDir}/getSlurmMail.sh ${SLURM_JOB_ID}`
    stdoutDir=$( dirname `${thisScriptDir}/getSlurmStdout.sh ${SLURM_JOB_ID}` )

    if [ "$SLURM_ARRAY_TASK_ID" -eq "10" ]; then

	STDOUT_STEP4="${stdoutDir}/runSnowTodayStep4-%A_%a.out"
	
	#schedule Step 4 to make today's plots after this set of array jobs complete
	sbatch --dependency=afterok:$SLURM_ARRAY_JOB_ID \
	       --mail-user=${MAIL} \
	       --output=${STDOUT_STEP4} \
	       ${thisScriptDir}/runSnowTodayStep4.sh \
	       $mindays $northZthresh $southZthresh

    fi
    
fi

#Clean up temporary directory for matlab job storage
echo "${PROGNAME}: Removing TMPDIR=$TMPDIR..."
rm -rf $TMPDIR

thisDate=$(date)
echo "${PROGNAME}: Done on hostname=$thisHost on $thisDate"

