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
#SBATCH --time 01:00:00
#SBATCH --ntasks-per-node 1
#SBATCH --nodes=1
#SBATCH -o /scratch/alpine/%u/slurm_out_SnowToday/%x-%A_%a.out
# Set the system up to notify upon completion
# Do not set --mail-user, let it default to the caller
# It can also be over-written at the command line
#SBATCH --mail-type FAIL,INVALID_DEPEND,TIME_LIMIT,REQUEUE,STAGE_OUT
#SBATCH --array=1-2
#   1 for westernUS tile group, 2 for USAlaska tile group. 
#   Also called REGIONNAME. id of the region which tiles to import.
#   Script updated for Alaska SIER_322.

# Functions.
#---------------------------------------------------------------------------------------
mail_summary() {
    # $1: bigRegionName: char. Group of tiles or Region name, or tile name if testing
    #   Usually westernUS or USAlaska.
    $duration="[$(TZ=UTC0 printf 'Duration: %(%H:%M:%S)T\n' "${SECONDS}")]"
    if [ ! $testing ]; then
        # Mails the region inventory summary to selected recipients
        # An alternative way to control recipient list would be
        # at command line or with a bash env variable.
        NOTIFYLIST="ops@nsidc.org,\
                karl.rittger@colorado.edu,\
                brodzik@colorado.edu,\
                sebastien.lenard@colorado.edu"
        SUBJECT="SnowToday0 archive updated ${thisDate} ${duration}"
    else
        NOTIFYLIST="${USER}@colorado.edu"
        SUBJECT="TESTING SnowToday0 archive updated ${thisDate} ${duration}"
    fi
	
    thisDate=$(date)
    FROM="${USER}@colorado.edu"
    SUMMARYFILE="/pl/active/rittger_esp/modis/archive_status/nrt.UpdateReport.${1}.last.txt"

    echo "${PROGNAME}: Mailing inventory summary ${SUMMARYFILE} to ${NOTIFYLIST}"
    # Double-quotes are important on the SUBJECT when it contains spaces
    mailx -s "${SUBJECT}" \
	  -r ${FROM} ${NOTIFYLIST} < ${SUMMARYFILE} || \
	error_exit "Line $LINENO: mail_message error."
}
usage() {
    echo "" 1>&2
    echo "Usage: ${PROGNAME} [-A LABEL_ANCILLARY] [-h] [-L LABEL] [-n]" 1>&2
    echo "      [-s YYYYMMDD] [-t] WHICHSET FILLONLY" 1>&2
    echo "  Runs Step0 in SnowToday pipeline" 1>&2
    echo "    Fetch latest JPL data for the tiles composing the region" 1>&2
    echo "    Update the SnowToday pull report" 1>&2
    echo "  If called by slurm:" 1>&2
    echo "    starts Step1 for today, and" 1>&2
    echo "    schedules Step0 for tomorrow" 1>&2
    echo "Options: "  1>&2
    echo "  -A LABEL_ANCILLARY: string with version of ancillary data" 1>&2
    echo "     e.g. for operational processing, use -A v3.1 for westernUS " 1>&2
    echo "     or -A v3.2 for USAlaska" 1>&2
    echo "  -h: display help message and exit" 1>&2
    echo "  -L LABEL: string with version label for directories" 1>&2
    echo "     e.g. for operational processing, use -L v2023.x" 1>&2
    echo "  -n: no pipeline: suppress starting next pipeline step" 1>&2
    echo "  -s YYYYMMDD: optional start day to look for new JPL data" 1>&2
    echo "      overrides default which is 5 days prior to." 1>&2
    echo "      NB: this option is not transmitted to next step0." 1>&2
    echo "  -t: testing pipeline" 1>&2
    echo "      do not initiate Step0 for tomorrow" 1>&2
    echo "      only send success email to caller (ignore NOTIFYLIST)" 1>&2
    echo "      results will not be pushed to NSIDC" 1>&2
    echo "Arguments:" 1>&2
    echo "  WHICHSET: nrt: for near real time, or historic" 1>&2
    echo "  FILLONLY: full: systematic import (longer), " 1>&2
    echo "       fillOnly: only import gaps (shorter)" 1>&2    
    echo "Output: " 1>&2
    echo "  Output location is controlled in Matlab scripts " 1>&2
    echo "Notes: " 1>&2
    echo "  Scripts stdout/stderr are written to user's scratch " 1>&2
    echo "  where directory /scratch/summit/$USER/slurm_out_SnowToday/ " 1>&2
    echo "  is assumed to exist" 1>&2
}

# Core script.
#---------------------------------------------------------------------------------------
# Initialize variables, option setting.
# Grab the full path to this script
# depends on whether it's running as sbatch job.
scriptId=snoStep0
defaultSlurmArrayTaskId=1
expectedCountOfArguments=2
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
whichSet=$1
fillOnly="true"
if [ $2 == "full" ]; then 
    fillOnly="false"
fi
regionName=${tileGroupNames[${SLURM_ARRAY_TASK_ID} - 1]}
bigRegionName=${regionName}

inputForESPEnv="modisData = modisData"
inputForRegion="'"${regionName}"', '"${regionName}"_mask', espEnv, modisData"
inputForMain="'"${whichSet}"', region, fillOnly = "${fillOnly}
echo "inputForMain: "$inputForMain
#fillOnly==true will only try to fill holes in inventory
#fillOnly==false will try to re-pull data for every date
if [ ! -z ${startyyyymmdd} ]; then
    inputForMain="${inputForMain}, startyyyymmdd = '${startyyyymmdd}'"
fi

source scripts/toolsMatlab.sh

matlab -nodesktop -nodisplay -r "clear; "\
"try; "\
"modisData = MODISData(${inputForModisData}); "\
"if ismember('"${regionName}"', {'AMAndes'}); "\
" modisData.endDateOfHistoricJPLFiles = datetime(2017, 1, 1); end; "\
"espEnv = ESPEnv(${inputForESPEnv}); "\
"region = Regions(${inputForRegion}); "\
"batchUpdateModisArchive(${inputForMain}); "\
"catch e; "\
"fprintf('%s: %s\n', e.identifier, e.message); "\
"exit(-1); "\
"end; "\
"exit(0);" || error_exit "Line $LINENO: matlab error."

# SIER_390. Quick/dirty patch for modisData.endDateOfHistoricJPLFiles
# SIER_335. Putting aside anomalous mod09ga files.
anomalousMod09gaFiles=$(find /pl/active/rittger_esp/modis/mod09ga/NRT/ -type f -size -1000c | grep .hdf | grep -v "ano.MOD")
for f in $anomalousMod09gaFiles; do mv $f $(echo $f | sed 's/\/MOD/\/ano.MOD/g'); echo "renamed anomalous ${f}"; done
anomalousMod09gaFiles=$(find /scratch/alpine/${USER}/modis/mod09ga/NRT/ -type f -size -1000c | grep .hdf | grep -v "ano.MOD")
for f in $anomalousMod09gaFiles; do mv $f $(echo $f | sed 's/\/MOD/\/ano.MOD/g'); echo "renamed anomalous ${f}"; done

# Stop the stopwatch and report elapsed time
duration=
#Send inventory summary to interested observers
mail_summary $bigRegionName

# Launch of next Step of the SnowToday daily process. Not applied for USAlaska now.
#---------------------------------------------------------------------------------------
if [ $isBatch ] && [ ! $noPipeline ] && [ $regionName == "westernUS" ]; then
    # use the stdoutDir settings from above.
    STDOUT_STEP1="${stdoutDir}/1SnTo-%A_%a.out"
    varname=$(echo "tileArrayStringForTileGroup${SLURM_ARRAY_TASK_ID}")

    # send to --array the tile ids corresponding to the tile group SLURM_ARRAY_TASK_ID.
    arrayStringVarName=$(echo "tileArrayStringForTileGroup${SLURM_ARRAY_TASK_ID}")
    arrayStringValue=${!arrayStringVarName}
    # schedule next job in Snow Today pipeline for today
    # back up the cubes to be updated to this month - 2
    # NB: dependency afterok:$SLURM_JOB_ID implies that the 2 runSnowToday chains run
    # independently and if the import of USAlaska tile fails it doesn't impact 
    # westernUS. Will probably need to be changed when dealing with Canada tiles.

    echo "--output=${STDOUT_STEP1}"
    echo "--araay=${arrayStringValue}"

    echo "${PROGNAME}: Continuing pipeline with Step1..."
    echo ${nextStepOptions} $(get_start_stop_date_string)
    sbatch --dependency=afterok:$SLURM_JOB_ID \
	   --mail-user=${MAIL} \
	   --output=${STDOUT_STEP1} \
       --array=${arrayStringValue} \
	   ${thisScriptDir}/runSnowTodayStep1.sh ${nextStepOptions} \
	   $(get_start_stop_date_string) ${bigRegionName}
fi

# Programming of the next launch of this script tomorrow.
#---------------------------------------------------------------------------------------
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
       STDOUT_STEP0="${stdoutDir}/0SnTo-%A_%a.out"

       # Assume that startyyyymmdd should be ignored and tomorrow's
       # Step0 will default to most recent data
       # Array is same to the SLURM_ARRAY_TASK_ID of this subjob.
       sbatch --begin=04:30:00 \
	      --output=${STDOUT_STEP0} \
          --array=${SLURM_ARRAY_TASK_ID} \
	      ${thisScriptDir}/runSnowTodayStep0.sh ${nextStepOptions} \
          $whichSet
    fi
fi

source scripts/toolsStop.sh
