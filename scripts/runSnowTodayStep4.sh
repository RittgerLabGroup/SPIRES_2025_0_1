#!/bin/bash
#
# script to run SnowToday Step4:
#   push today's SnowToday created plots to NSIDC
#

#SBATCH --qos normal
#SBATCH --job-name 4SnTo
#SBATCH --partition amilan
#SBATCH --account ucb-general
#SBATCH --time 00:15:00
#SBATCH --ntasks-per-node 1
#SBATCH --nodes 1
#SBATCH -o /scratch/alpine/%u/slurm_out_SnowToday/%x-%j.out
# Set the system up to notify upon completion
#SBATCH --mail-type END,FAIL,INVALID_DEPEND,TIME_LIMIT,REQUEUE,STAGE_OUT
#SBATCH --mail-user brodzik@colorado.edu,crumlyd@nsidc.org,karl.rittger@colorado.edu

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
    echo "  Pushes all of today's csvs-to-date and recent geotiffs to NSIDC" 1>&2
    echo "Options: "  1>&2
    echo "  -h: display help message and exit" 1>&2
    echo "  -L LABEL: string with version label for directories" 1>&2
    echo "     e.g. for operational processing, use -L v2023.x" 1>&2
    echo "Arguments: " 1>&2
    echo "  WATERYR: water year to process" 1>&2
    echo "Output: " 1>&2
    echo "  Output location is NSIDC" 1>&2
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

WATERYR=$1

# Start the stopwatch
SECONDS=0

thisHost=$(hostname)
thisDate=$(date +'%Y%m%d')
echo "${PROGNAME}: Begin on hostname=$thisHost on $thisDate for LABEL=$LABEL"

echo "${PROGNAME}: Copying csv files to NSIDC staging directory..."
srcDir="/pl/active/rittger_esp/modis/regional_stats/scagdrfs_csv_${LABEL}/v006/westernUS/WY${WATERYR}/"
destDir="/share/apps/snow-today/incoming/snow-surface-properties/plot_csv/"
cd ${srcDir}
scp -i ~/.ssh/id_rsa_snowToday *.csv snow_today@nusnow.colorado.edu:${destDir}

# DO CSV TRIGGER HERE
touch TRIGGER
scp -i ~/.ssh/id_rsa_snowToday TRIGGER snow_today@nusnow.colorado.edu:${destDir}

echo "${PROGNAME}: Copying geotiffs to NSIDC staging directory..."
srcDir="/pl/active/rittger_esp/modis/variables/scagdrfs_geotiff_${LABEL}/v006/westernUS/EPSG_3857/LZW/"
destDir="/share/apps/snow-today/incoming/snow-surface-properties/tif/"
for f in $(find ${srcDir} -type f -cmin -120); do
    scp -i ~/.ssh/id_rsa_snowToday $f snow_today@nusnow.colorado.edu:${destDir}
done

# DO TRIGGER HERE
touch TRIGGER
scp -i ~/.ssh/id_rsa_snowToday TRIGGER snow_today@nusnow.colorado.edu:${destDir}

# Stop the stopwatch and report elapsed time
elapsedSeconds=$SECONDS
duration=$(TZ=UTC0 printf 'Duration: %(%H:%M:%S)T\n' "$elapsedSeconds")

thisDate=$(date)
echo "${PROGNAME}: Done on hostname=$thisHost on $thisDate [${duration}]"

