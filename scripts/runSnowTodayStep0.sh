#!/bin/bash
#
# script to run SnowToday Step0:
#   fetch latest JPL data
#   update the JPL pull report
#   kick off Step1 for today
#   schedul Step0 for tomorrow
#

#SBATCH --qos normal
#SBATCH --job-name runSnowTodayStep0
#SBATCH --account=ucb188_summit1
#SBATCH --time=01:00:00
#SBATCH --ntasks-per-node=6
#SBATCH --nodes=1
#SBATCH -o /pl/active/rittger_esp/modis/archive_status/slurm_output/runSnowTodayStep0-%j.out
# Set the system up to notify upon completion
#SBATCH --mail-type=FAIL,REQUEUE,STAGE_OUT
#SBATCH --mail-user=brodzik@nsidc.org

module purge
ml matlab/R2019b
date

mindays=$1
northZthresh=$2
southZthresh=$3

thisHost=$(hostname)
thisDate=$(date)
echo "$0: Begin on hostname=$thisHost on $thisDate"
echo "SLURM_SCRATCH=$SLURM_SCRATCH"
echo "SLURM_JOB_ID=$SLURM_JOB_ID"

#Go here so that correct pathdef.m file is used
cd /projects/brodzik/Documents/MATLAB/esp_SnowToday_ops

#matlab -nodesktop -nodisplay -r "clear; "\
#"tiles=MODISData.tilesFor('westernUS'); "\
#"batchUpdateModisArchive('nrt', tiles, 'startyyyymmdd', '20210730'); "\
#"exit(0);"

matlab -nodesktop -nodisplay -r "clear; "\
"tiles=MODISData.tilesFor('westernUS'); "\
"batchUpdateModisArchive('nrt', tiles); "\
"exit(0);"

#schedule next job in SnowToday pipeline for today
thisYear=$(date +'%Y')
thisMonth=$(date +'%-m')
startMonth=$(( $thisMonth - 2 ))
if (( "$startMonth" < "1" )); then
    startMonth=1
fi
sbatch --dependency=afterok:$SLURM_JOB_ID scripts/runSnowTodayStep1.sh $thisYear $mindays $northZthresh $southZthresh $startMonth $thisMonth

#schedule Step0 for the next time clock strikes noon
sbatch --begin=10:30:00 scripts/runSnowTodayStep0.sh $mindays $northZthresh $southZthresh

thisDate=$(date)
echo "$0: Done on hostname=$thisHost on $thisDate"

