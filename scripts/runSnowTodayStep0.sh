#!/bin/bash
#
# script to run SnowToday Step0:
#   schedule Step0 for tomorrow
#   fetch latest JPL data
#   update the JPL pull report
#   kick off Step1 for today
#
# General notes about SLURM environment variables:
# $SLURM_JOB_ID: system jobID ("process ID")-guaranteed to be unique
#                can be used to get information about a completed
#                job, for e.g. sacct -j <jobID> -o JobID,MaxRSS
#                will display maximum memory used by that job
# $SLURM_SCRATCH: this is supposed to be location of node-specific scratch
#                but occasionally (pretty regularly) I have seen
#                cases where it is not set, so I do not depend on it
#
# The following will only be set for array jobs ("#SBATCH --array=x1-x2")
# $SLURM_ARRAY_JOB_ID: system jobID for a particular array job, this
#                is different from the main jobID
# $SLURM_ARRAY_TASK_ID: integer value of this job array task, so if
#                --array=1-12, then the first one will have
#                $SLURM_ARRAY_TASK_ID set to 1, and so on
#
# For more notes and tricks, see Confluence pages:
# https://nsidc.org/confluence/pages/viewpage.action?pageId=284590088
#

#SBATCH --qos normal
#SBATCH --partition amilan
#SBATCH --job-name 0SnTo
#SBATCH --account ucb-general
#SBATCH --time 05:00:00
#SBATCH --ntasks-per-node 1
#SBATCH --nodes=1
#SBATCH -o /scratch/alpine/%u/slurm_out_SnowToday/%x-%j.out
# Set the system up to notify upon completion
#SBATCH --mail-type FAIL,INVALID_DEPEND,TIME_LIMIT,REQUEUE,STAGE_OUT
#SBATCH --mail-user brodzik@colorado.edu,crumlyd@nsidc.org

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
    echo "Usage: ${PROGNAME} [-h] [-L LABEL] [-n] [-s YYYYMMDD] " 1>&2
    echo "  Runs Step0 in SnowToday pipeline" 1>&2
    echo "    Fetch latest JPL data for 5 WesternUS tiles" 1>&2
    echo "    Update the SnowToday pull report" 1>&2
    echo "  If called by slurm:" 1>&2
    echo "    starts Step1 for today, and" 1>&2
    echo "    schedules Step0 for tomorrow" 1>&2
    echo "Options: "  1>&2
    echo "  -h: display help message and exit" 1>&2
    echo "  -L LABEL: string with version label for directories" 1>&2
    echo "     e.g. for operational processing, use -L v2023.x" 1>&2
    echo "  -n: no pipeline: suppress starting next pipeline step" 1>&2
    echo "  -s YYYYMMDD: optional start day to look for new JPL data" 1>&2
    echo "      overrides default which is 5 days prior to " 1>&2
    echo "      last complete date (all 5 tiles) of data in archive" 1>&2
    echo "Arguments: n/a" 1>&2
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

mail_summary() {

    # $1: string to include in email subject
    
    # Mails the region inventory summary to selected recipients
    # An alternative way to control recipient list would be
    # at command line or with a bash env variable.
    NOTIFYLIST="${USER}@colorado.edu,crumlyd@nsidc.org"

    thisDate=$(date)
    SUBJECT="SnowToday0 archive updated ${thisDate} ${1}"
    FROM="${USER}@colorado.edu"
    SUMMARYFILE="/pl/active/rittger_esp/modis/archive_status/nrt.UpdateReport.westernUS.last.txt"
    
    echo "${PROGNAME}: Mailing inventory summary ${SUMMARYFILE} to ${NOTIFYLIST}"
    # Double-quotes are important on the SUBJECT when it contains spaces
    mailx -s "${SUBJECT}" \
	  -r ${FROM} ${NOTIFYLIST} < ${SUMMARYFILE} || \
	error_exit "Line $LINENO: mail_message error."
    
}

module purge
ml matlab/R2021b
date

# Start the stopwatch
SECONDS=0

startyyyymmdd=
noPipeline=

while getopts "hL:ns:" opt
do
    case $opt in
	s) startyyyymmdd="$OPTARG";;
	L) LABEL="$OPTARG";;
	n) noPipeline=1;;
	h) usage
	   exit 1;;
	?) printf "Unknown option %s\n" $opt
	   usage
           exit 1;;
	esac
done

shift $(($OPTIND - 1))

[[ "$#" -eq 0 ]] || error_exit "Line $LINENO: Unexpected number of arguments."

modisdata_option=""
s1_label=""
if [ $LABEL ]; then
    modisdata_option="'label', '$LABEL'"
    s1_label="-L $LABEL"
fi

update_option=""
if [ $startyyyymmdd ]; then
    update_option="'startyyyymmdd', '$startyyyymmdd', "
fi

thisHost=$(hostname)
thisDate=$(date)
echo "${PROGNAME}: Begin on hostname=$thisHost on $thisDate"
echo "${PROGNAME}: SLURM_SCRATCH=$SLURM_SCRATCH"
echo "${PROGNAME}: SLURM_JOB_ID=$SLURM_JOB_ID"

if [ $noPipeline ]; then
    
    echo "${PROGNAME}: noPipeline mode: this script will not continue pipeline"

else

    # schedule Step0 for the next time clock strikes daily start time
    # do this first, so that it doesn't depend on success of today's
    # Step0 processing
    if [ $isBatch ]; then
    
       # get current slurm info for mail-user and stdout
       # Don't assume they are the same as at the top of this file,
       # because they can be overridden at the command line
       MAIL=`${thisScriptDir}/getSlurmMail.sh ${SLURM_JOB_ID}`

       stdoutDir=$( dirname `${thisScriptDir}/getSlurmStdout.sh ${SLURM_JOB_ID}` )
       STDOUT_STEP0="${stdoutDir}/runSnowTodayStep0-%j.out"

       # Assume that startyyyymmdd should be ignored and tomorrow's
       # Step0 will default to most recent data
       sbatch --begin=04:30:00 \
	      --mail-user=${MAIL} \
	      --output=${STDOUT_STEP0} \
	      ${thisScriptDir}/runSnowTodayStep0.sh ${s1_label}

    fi

fi

#Go to parent of this script, so that correct pathdef.m file is used
cd "${thisScriptDir}/../"

WHICHSET="nrt"
REGIONNAME="westernUS"

#fillOnly==true will only try to fill holes in inventory
#fillOnly==false will try to re-pull data for every date
matlab -nodesktop -nodisplay -r "clear; "\
"try; "\
"espEnv = ESPEnv(); "\
"mData = MODISData($modisdata_option); "\
"region = Regions('"${REGIONNAME}"', '"${REGIONNAME}"_mask', espEnv, mData); "\
"batchUpdateModisArchive('"${WHICHSET}"', region, "\
"$update_option "\
"'fillOnly', false); "\
"catch e; "\
"fprintf('%s: %s\n', e.identifier, e.message); "\
"exit(-1); "\
"end; "\
"exit(0);" || error_exit "Line $LINENO: matlab error."

# FORCING NO STEP 1 FOR NOW
noPipeline=1

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
	   ${thisScriptDir}/runSnowTodayStep1.sh ${s1_label} \
	   $yearStart $monthStart $yearStop $monthStop

fi

# Stop the stopwatch and report elapsed time
elapsedSeconds=$SECONDS
duration=$(TZ=UTC0 printf 'Duration: %(%H:%M:%S)T\n' "$elapsedSeconds")

#Send inventory summary to interested observers
mail_summary "[${duration}]"

thisDate=$(date)
echo "${PROGNAME}: Done on hostname=$thisHost on $thisDate [${duration}]"

