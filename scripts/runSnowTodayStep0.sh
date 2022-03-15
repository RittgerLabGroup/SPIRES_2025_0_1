#!/bin/bash
#
# script to run SnowToday Step0:
#   schedule Step0 for tomorrow
#   fetch latest JPL data
#   update the JPL pull report
#   kick off Step1 for today
#

#SBATCH --qos normal
#SBATCH --job-name 0_SnowToday
#SBATCH --account=ucb188_summit2
#SBATCH --time=05:00:00
#SBATCH --ntasks-per-node=6
#SBATCH --nodes=1
#SBATCH -o /scratch/summit/%u/slurm_out_SnowToday/runSnowTodayStep0-%j.out
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
    echo "Usage: ${PROGNAME} [-h] [-n] [-s YYYYMMDD] " 1>&2
    echo "       MINDAYS NORTHZTHRESH SOUTHZTHRESH" 1>&2
    echo "  Runs Step0 in SnowToday pipeline" 1>&2
    echo "    Fetch latest JPL data for 5 WesternUS tiles" 1>&2
    echo "    Update the SnowToday pull report" 1>&2
    echo "  If called by slurm:" 1>&2
    echo "    starts Step1 for today, and" 1>&2
    echo "    schedules Step0 for tomorrow" 1>&2
    echo "Options: "  1>&2
    echo "  -h: display help message and exit" 1>&2
    echo "  -n: no pipeline: suppress starting next pipeline step" 1>&2
    echo "  -s YYYYMMDD: optional start day to look for new JPL data" 1>&2
    echo "      overrides default which is 5 days prior to " 1>&2
    echo "      last complete date (all 5 tiles) of data in archive" 1>&2
    echo "Arguments: " 1>&2
    echo "  MINDAYS : mindays threshold to pass to step 1" 1>&2
    echo "  NORTHZTHRESH : Northern altitude threshold (m) to pass to step 1" 1>&2
    echo "  SOUTHZTHRESH : Southern altitude threshold (m) to pass to step 1" 1>&2
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

module purge
ml matlab/R2019b
date

startyyyymmdd=

noPipeline=

while getopts "hns:" opt
do
    case $opt in
	s) startyyyymmdd="$OPTARG";;
	n) noPipeline=1;;
	h) usage
	   exit 1;;
	?) printf "Unknown option %s\n" $opt
	   usage
           exit 1;;
	esac
done

shift $(($OPTIND - 1))

[[ "$#" -eq 3 ]] || error_exit "Line $LINENO: Unexpected number of arguments."

mindays=$1
northZthresh=$2
southZthresh=$3

options=""
if [ $startyyyymmdd ]; then
    options="'startyyyymmdd', '$startyyyymmdd', "
fi

thisHost=$(hostname)
thisDate=$(date)
echo "${PROGNAME}: Begin on hostname=$thisHost on $thisDate"
echo "${PROGNAME}: SLURM_SCRATCH=$SLURM_SCRATCH"
echo "${PROGNAME}: SLURM_JOB_ID=$SLURM_JOB_ID"

if [ $noPipeline ]; then
    
    echo "${PROGNAME}: noPipeline mode: this script will not continue pipeline"

else

    # schedule Step0 for the next time clock strikes 04:30
    # do this first, so that it doesn't depend on success of today's
    # Step0 processing
    if [ $isBatch ]; then
    
       # get current slurm info for mail-user and stdout
       # Don't assume they are the same as at the top of this file,
       # because they can be overridden at the command line
       MAIL=`${thisScriptDir}/getSlurmMail.sh ${SLURM_JOB_ID}`

       stdoutDir=$( dirname `${thisScriptDir}/getSlurmStdout.sh ${SLURM_JOB_ID}` )
       STDOUT_STEP0="${stdoutDir}/runSnowTodayStep0-%j.out"

       sbatch --begin=04:30:00 \
	      --mail-user=${MAIL} \
	      --output=${STDOUT_STEP0} \
	      ${thisScriptDir}/runSnowTodayStep0.sh \
	      $mindays $northZthresh $southZthresh

    fi

fi

#Go to parent of this script, so that correct pathdef.m file is used
cd "${thisScriptDir}/../"

#fillOnly==true will only try to fill holes in inventory
#fillOnly==false will try to re-pull data for every date
matlab -nodesktop -nodisplay -r "clear; "\
"try; "\
"tiles=MODISData.tilesFor('westernUS'); "\
"batchUpdateModisArchive('nrt', tiles, "\
"$options "\
"'fillOnly', false); "\
"catch e; "\
"fprintf('%s: %s\n', e.identifier, e.message); "\
"exit(-1); "\
"end; "\
"exit(0);" || error_exit "Line $LINENO: matlab error."

if [ $isBatch ] && [ ! $noPipeline ]; then
    
    # use the MAIL and stdoutDir settings from above
    STDOUT_STEP1="${stdoutDir}/runSnowTodayStep1-%A_%a.out"

    # schedule next job in Snow Today pipeline for today
    # back up the cubes to be updated to this month - 2
    yearStop=$(date +'%Y')
    monthStop=$(date +'%-m')
    monthStart=$(( $monthStop - 2 ))
    if (( "$monthStart" < "1" )); then
	monthStart=$(( $monthStart + 12 ))
	yearStart=$(( $yearStop - 1 ))
    else
	yearStart=$yearStop
    fi

    echo "${PROGNAME}: Continuing pipeline with Step1..."
    sbatch --dependency=afterok:$SLURM_JOB_ID \
	   --mail-user=${MAIL} \
	   --output=${STDOUT_STEP1} \
	   ${thisScriptDir}/runSnowTodayStep1.sh \
	   $mindays $northZthresh $southZthresh \
	   $yearStart $monthStart $yearStop $monthStop

fi

thisDate=$(date)
echo "${PROGNAME}: Done on hostname=$thisHost on $thisDate"

