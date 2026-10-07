#!/bin/bash
#
# script to get all mod09ga files from DAAC for specific tiles and range of dates.

#   Cancel this one, only available on blanca. SBATCH --constraint=spsc
#SBATCH --export=NONE
#SBATCH --mail-type=FAIL,INVALID_DEPEND,TIME_LIMIT,REQUEUE,ARRAY_TASKS

# Functions.
########################################################################################
usage() {
  read -r -d '' thisUsage << EOM

  Usage: ${PROGNAME}
    [-D yyyy-MM-dd-monthWindow] [-h] [-i] [-I objectId] [-o]
    [-x scratchPath] [-y archivePath]
    Imports mog09ga v6.1 tiles for a region and period.
  Options:
    -D: string waterYearDateString, format yyyy-MM-dd-monthWindow. Date parameters
    allowing to determine override which period the script is run.
    E.g. 2024-03-26-1. The period ends by the date defined by yyyy-MM-dd, here
    2024-03-26, and monthWindow, the number of months before this date covering the
    period: 12: 1 full year period, 1: the month of the date, from 1 to the date,
    0: only the date. Default: date of today with monthWindow = 2. NB: if dd > than
    the last day of the month, then code set it to last day.
    -h: display help message and exit.
    -i: update input data from archive to scratch. Default: no update.
    -I: objectId, id of the tile to import, e.g. 292 for h08v04. Full list in
    toolsRegion.sh. Default: 292. Value of array job overrides the value of this
    option.
    -L inputLabel: string with version label for directories. For mod09ga, is v006 or
    v061, for version 6.0 or version 6.1 of the tiles. NB: v6.0 is deprecated and
    shouldnt be used in this script.
    -o: update output data from scratch to archive. Default: no update.
    -O outputLabel: string with version label for output files.
    If -O not precised, inputLabel is used for both input and output files.
    -R: repeat the job later with same parameters. Default: no repeat. Option -D
    overrides this option and set the job to no repeat.
    -v verbosityLevel: int. Also called log level. Default: 0, all logs. Increased
    values: less logs.
    -x: scratchPath: string, scratch storage location. This temporary location is
    for increased performance in read/write, compared to archive. The output
    files can later be sync back to archive. Logs are also stored in scratch.
    Default: environment variable $espScratchDir.
    NB: the scratchPath is dependent on the cluster alpine or blanca, and each
    cluster cannot access to the scratch of the other cluster.
    -y: archivePath: string, permanent storage location.
    Default: environment variable $espArchiveDir.
    -Z: pipeLineId: if set, indicates that a next script will be launch when the array
    job is achieved in success. The next script and version are determined based on
    the pipelineId. If set to 0, no pipeline. Additionally, indicates the end of the
    list of options for the pipeline parser and MUST always be positioned at the end
    of options.
  Arguments:
    None
  Sbatch parameters:
    --account=${slurmAccount}: string, obligatory. Account used to connect to the
    slurm partitions. Differs from blanca to alpine.
    --constraint=spsc: optional. To avoid allocation on nodes having jumbo internet
    connections 9000 instead of the classic 1500, necessary to connect to the daac
    servers. Doesnt seem necessary on alpine nodes.
    --exclude=xxx. string list, optional. List nodes you dont want your job be
    allocated on. List is of one node, or several nodes stuck and separated with
    commas. Mostly used when some blanca nodes have problems to run your script
    correctly, because those nodes have a more heterogeneous configuration than on
    alpine.
    --export=NONE: to prevent local variables to override your environment variables.
    Important when using blanca to avoid the no matlab module error.
    --job-name=mod09ga-${objectId}-${waterYearDateString}: string. Name of the job.
    Should include the id the object and the date over which the script runs.
    --ntasks-per-node=1: number of cores to be allocated.
    --mail-type=FAIL,INVALID_DEPEND,TIME_LIMIT,REQUEUE,ARRAY_TASKS: sends e-mail when
    job in error or requeued by sys admin. ARRAY_TASKS indicates that one e-mail
    per array task id is sent. If want in all cases, add values BEGIN,END,STAGE_OUT.
    If want no e-mail, replace the full string by NONE.
    --mail-user=xxx@xxx: e-mail addresses to where the e-mails are sent. If not set,
    default to user e-mail.
    --mem=1G: memory to be allocated. On Alpine qos normal, memory is dependent on
    the number of cores, each core having 3.8G, and this parameter can override
    ntasks-per-node. E.g. here if I set --mem 5G, alpine will require 2 cores
    instead of 1. On Blanca qos preemptable, the 2 parameters are independent.
    NB: this mem is the peak of memory you will be allowed. If the script requires
    a higher peak at some point, slurm stops the job with an out of memory error.
    -o=${slurmLogDir}%x-%A_%a.out: string. Location of the log file. %x for the job
    name, %A for the id of the job and %a for the array task id.
    NB: This location should be on the correct scratch of the alpine or blanca
    cluster. Each cluster cannot access to the scratch of the other cluster.
    NB: the directory of the log file MUST exis otherwise slurm doesnt write the
    logs.
    NB: this output log filepath is not transferred to the script as a variable. So
    we have to redefine it in toolStart.sh as $THISSBATCH_OUTPUT. Keep the -o string
    to %x-%A_%a.out, or change both $THISSBATCH_OUTPUT and the -o string.
    --qos=${slurmQos}: string, obligatory. Indicates which pool of nodes you ask your
    allocation for. For alpine --qos=normal, for blanca --qos=preemptable. Other
    qos are also available.
    --time=HH:mm:ss: string format time, obligatory. Indicate the time at which slurm
    will automatically cancel the job.
    --array=292,293: list of objectIds. Ids of the tiles on which the script should
    run. List of ids in toolsRegion.sh. This parameter override the -I script
    option. Variable SLURM_ARRAY_TASK_ID in the script.
  Output:
    Scratch and archive, subfolder modis/input/mod09ga/

EOM
  printf "$thisUsage\n" 1>&2
}

function downloadTileFromDaacURLToLocal() {
    # Download matching DAAC files and validate every completed HDF with gdalinfo.
    # Invalid files are removed and downloaded again, up to three total attempts.
    local regionName="$1"
    local remoteDirectoryUrl="$2"
    local localDirectoryPath="$3"
    local remoteFilename localFilePath attempt httpStatus curlExit
    local downloadFailed=0

    if ! command -v gdalinfo >/dev/null 2>&1; then
        echo "ERROR: gdalinfo is required to validate MOD09GA downloads." >&2
        return 1
    fi
    mkdir -p "$localDirectoryPath" || return 1

    # Check the daily directory first so an expected 404 can be reported as data
    # that has not been published yet, rather than as a curl error.
    httpStatus=$(curl --silent --output /dev/null --write-out '%{http_code}' \
        -b ~/.urs_cookies -L -n "$remoteDirectoryUrl")
    curlExit=$?
    if [ "$curlExit" -ne 0 ]; then
        echo "ERROR: Unable to check remote directory ${remoteDirectoryUrl}." >&2
        return 1
    fi
    if [ "$httpStatus" = "404" ]; then
        echo "Data not yet available at ${remoteDirectoryUrl} (checked $(date '+%Y-%m-%d %H:%M:%S %Z'))."
        return 0
    fi
    if [ "$httpStatus" -lt 200 ] || [ "$httpStatus" -ge 300 ]; then
        echo "ERROR: Remote directory ${remoteDirectoryUrl} returned HTTP ${httpStatus}." >&2
        return 1
    fi

    while read -r full_url; do
        [ -n "$full_url" ] || continue
        remoteFilename="${full_url##*/}"
        localFilePath="${localDirectoryPath}${remoteFilename}"

        if [ -f "$localFilePath" ] && gdalinfo "$localFilePath" >/dev/null 2>&1; then
            echo "Skipping ${remoteFilename}: existing file passes gdalinfo validation."
            continue
        fi
        if [ -f "$localFilePath" ]; then
            echo "Existing file ${localFilePath} fails gdalinfo validation; removing it."
            rm -f "$localFilePath"
        fi

        for attempt in 1 2 3; do
            echo "Downloading ${remoteFilename} (attempt ${attempt} of 3)..."
            # The file is removed after every failed attempt, so downloads are fresh.
            if curl --fail --show-error -b ~/.urs_cookies -L -n \
                "${remoteDirectoryUrl}${remoteFilename}" -o "$localFilePath" \
                && gdalinfo "$localFilePath" >/dev/null 2>&1; then
                echo "Download successful and ${localFilePath} passes gdalinfo validation."
                break
            fi
            echo "Download of ${remoteFilename} failed validation or transfer; deleting it." >&2
            rm -f "$localFilePath"
        done

        if [ ! -f "$localFilePath" ] || ! gdalinfo "$localFilePath" >/dev/null 2>&1; then
            echo "ERROR: ${remoteFilename} is still invalid after 3 download attempts." >&2
            downloadFailed=1
        fi
    # The directory was checked above; this fetch obtains its file listing.
    done < <(curl --fail --silent -b ~/.urs_cookies -L -n "$remoteDirectoryUrl" | \
        grep -oP '(?<=href=")[^"]*\.hdf' | grep "$regionName" | sort -u)

    return "$downloadFailed"
}

export SLURM_EXPORT_ENV=ALL

# Core script.
########################################################################################
# Main script constants. 
# Can be overriden by pipeline parameters in configuration.sh, itself can be overriden
# by main script options.
scriptId=mod09gaI
defaultSlurmArrayTaskId=292
expectedCountOfArguments=
inputDataLabels=(mod09ga)
outputDataLabels=(mod09ga)
filterConfLabel=
mainBashSource=${BASH_SOURCE}
mainProgramName=${BASH_SOURCE[0]}
  # overriden by slurm in toolsStart.sh
beginTime=(19:45:00)

# Following can be overriden by pipeling configuration.sh
thisRegionType=0
thisSequence=
thisSequenceMultiplierToIndices=
thisMonthWindow=2

source bash/toolsStart.sh
if [ $? -eq 1 ]; then
  exit 1
fi

# Argument setting.
# None.

log_level_1 "start"

# Launch the ingest.
########################################################################################

# 0. Constants
scienceBaseDirectoryUrl=https://ladsweb.modaps.eosdis.nasa.gov/archive/allData/61/MOD09GA/ # needs to give access to LAADS Web in https://urs.earthdata.nasa.gov/users/${meAsAUser}/authorized_apps
nrtBaseDirectoryUrl=https://nrt3.modaps.eosdis.nasa.gov/api/v2/content/archives/allData/61/MOD09GA/ # apparently doesn't need a token any more?

# Token personal to user, in environment variable in .~/.bshrc
# nrtDownloadToken=$nrt3ModapsEosdisNasaGovToken # Unused as of 2025-08-20.

# 1. Variables
# regionName=h08v04 # RegionName set by toolsStart.sh
directoryPath=${scratchPath}modis/input/mod09ga/v006/ # scratchPath set by toolsStart.sh through option -x
printf "Import to ${directoryPath}...\n"

theseDates=$(seq  $(date -d "$startDate" +%s) 86400 $(date -d "$endDate + 1 day" +%s))
# I dont know why seq doesnt include the $endDate and we need to add a day for that.
# If we want an array, we add outer (), like ($(seq  $(date -d "$startDate" +%s) 86400 $(date -d "$endDate" +%s)))
# But in that case we cannot use for in anymore.


# Core.
########################################################################################
# Debug only (easier to handle arrays vs sequences):
# theseDates=(${theseDates[@]})
# thisDate=${theseDates[0]}
thoseDates=(${theseDates[@]})
echo "Downloading date: ${thoseDates[0]} - $(date -d @"${thoseDates[0]}" +%Y-%m-%d) - $(date -d @"${thoseDates[0]}" +%Y%j) to date: ${thoseDates[-1]} - $(date -d @"${thoseDates[-1]}" +%Y-%m-%d) - $(date -d @"${thoseDates[-1]}" +%Y%j)"

hasDownloadError=0

for thisDate in $theseDates; do

  localDirectoryPath="${directoryPath}${regionName}/$(date -d @"$thisDate" +%Y)/"
    # Local download directory

  # 2. download of the nrt product for the last 7 days
  nrtIsAvailable=$([[ $thisDate -ge $(date --date "7 days ago" +'%s') ]] && echo 1 || echo 0)
  nrtDirectoryUrl="${nrtBaseDirectoryUrl}$(date -d @"$thisDate" +%Y)/$(date -d @"$thisDate" +%j)/"

  if [[ $nrtIsAvailable -eq 1 ]]; then
      downloadTileFromDaacURLToLocal $regionName $nrtDirectoryUrl $localDirectoryPath || hasDownloadError=1
  fi

  # 3. download of the science (=archive) product
  # Base URL of the directory
  scienceDirectoryUrl="${scienceBaseDirectoryUrl}$(date -d @"$thisDate" +%Y)/$(date -d @"$thisDate" +%j)/"

  downloadTileFromDaacURLToLocal $regionName $scienceDirectoryUrl $localDirectoryPath || hasDownloadError=1
done

source bash/toolsStop.sh

if [[ $hasDownloadError -ne 0 ]]; then
  echo "ERROR: One or more MOD09GA downloads could not be validated after 3 attempts." >&2
  exit 1
fi
