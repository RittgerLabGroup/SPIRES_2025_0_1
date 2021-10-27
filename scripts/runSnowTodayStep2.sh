#!/bin/bash
#
# script to run SnowToday Step2:
#   update westernUS daily mosaic files for this year for all variables
#   kick off Step3 for today
#

#SBATCH --qos normal
#SBATCH --job-name 2_SnowToday
#SBATCH --account=ucb188_summit1
#SBATCH --time=02:00:00
#SBATCH --ntasks-per-node=10
#SBATCH --nodes=1
#SBATCH --mem=40G
#SBATCH -o /scratch/summit/%u/slurm_out_SnowToday/runSnowTodayStep2-%j.out
# Set the system up to notify upon completion
#SBATCH --mail-type=FAIL,REQUEUE,STAGE_OUT
#SBATCH --mail-user=brodzik@nsidc.org

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
    echo "Usage: ${PROGNAME} [-h] YR MINDAYS NORTHZTHRESH SOUTHZTHRESH MONTHSTART MONTHSTOP" 1>&2
    echo "  Runs Step2 in SnowToday pipeline" 1>&2
    echo "  Updates WesternUS daily mosaic files for this year for all variables" 1>&2
    echo "  If called by slurm:" 1>&2
    echo "    starts SnowTodayStep3 for today" 1>&2
    echo "Options: "  1>&2
    echo "  -h: display help message and exit" 1>&2
    echo "Arguments: " 1>&2
    echo "  YR : year to update" 1>&2
    echo "  MINDAYS : mindays to use for STC cubes, pass to step 3" 1>&2
    echo "  NORTHZTHRESH : Northern altitude threshold (m) to pass to step 3" 1>&2
    echo "  SOUTHZTHRESH : Southern altitude threshold (m) to pass to step 3" 1>&2
    echo "  MONTHSTART : month to begin" 1>&2
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

while getopts "h" opt
do
    case $opt in
	h) usage
	   exit 1;;
	?) printf "Unknown option %s\n" $opt
	   usage
           exit 1;;
	esac
done

shift $(($OPTIND - 1))

[[ "$#" -eq 6 ]] || error_exit "Line $LINENO: Unexpected number of arguments."

yr=$1
mindays=$2
northZthresh=$3
southZthresh=$4
monthStart=$5
monthStop=$6

module purge
ml matlab/R2019b

thisHost=$(hostname)
thisDate=$(date)
echo "${PROGNAME}: Begin on hostname=$thisHost on $thisDate for yr=$yr and mindays=$mindays"
echo "${PROGNAME}: SLURM_SCRATCH=$SLURM_SCRATCH"
echo "${PROGNAME}: SLURM_JOB_ID=$SLURM_JOB_ID"

#Make a unique temporary directory for matlab job storage
#Set TMPDIR to this location so job array uses it for tmp location
mkdir -p $SLURM_SCRATCH/$SLURM_JOB_ID
export TMPDIR=$SLURM_SCRATCH/$SLURM_JOB_ID

#Go to parent of this script, so that correct pathdef.m file is used
cd "${thisScriptDir}/../"

matlab -nodesktop -nodisplay -r "clear; "\
"varNames={'snow_fraction', 'viewable_snow_fraction', 'grain_size', "\
"'drfs_grnsz', 'deltavis', 'radiative_forcing', "\
"'albedo_mu0', 'albedo_muZ'}; "\
"updateMosaicFor('westernUS', ${yr}, varNames, ${mindays}, "\
"'monthStart', ${monthStart}, 'monthStop', ${monthStop}, "\
"'zthresh', ["${northZthresh}" "${southZthresh}"]); "\
"exit(0);" || error_exit "Line $LINENO: matlab error."

if [ $isBatch ]; then
    
    # get current slurm info for mail-user and stdout
    # Don't assume they are the same as at the top of this file,
    # because they can be overridden at the command line
    MAIL=`${thisScriptDir}/getSlurmMail.sh ${SLURM_JOB_ID}`

    stdoutDir=$( dirname `${thisScriptDir}/getSlurmStdout.sh ${SLURM_JOB_ID}` )
    STDOUT_STEP3="${stdoutDir}/runSnowTodayStep3-%A_%a.out"

    #schedule Step 3 to update stats
    thisMonth=$(date +'%-m')
    waterYr=$yr
    if (( "$thisMonth" > "9" )); then
	waterYr=$(( $waterYr + 1 ))
    fi
    sbatch --dependency=afterok:$SLURM_JOB_ID \
	   --mail-user=${MAIL} \
	   --output=${STDOUT_STEP3} \
	   ${thisScriptDir}/runSnowTodayStep3.sh \
	   $waterYr $mindays $northZthresh $southZthresh

else
    
    echo "${PROGNAME}: Not continuing pipeline for non-sbatch call."

fi


#Clean up temporary directory for matlab job storage
echo "${PROGNAME}: Removing TMPDIR=$TMPDIR..."
rm -rf $TMPDIR

thisDate=$(date)
echo "${PROGNAME}: Done on hostname=$thisHost on $thisDate"

