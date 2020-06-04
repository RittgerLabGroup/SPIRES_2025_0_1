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
#SBATCH --account=ucb135_summit1
#SBATCH --time=01:00:00
#SBATCH --ntasks-per-node=6
#SBATCH --nodes=1
#SBATCH -o /pl/active/rittger_esp/modis/archive_status/slurm_output/runSnowTodayStep0-%j.out
# Set the system up to notify upon completion
#SBATCH --mail-type=END,FAIL,REQUEUE,STAGE_OUT
#SBATCH --mail-user=brodzik@nsidc.org

module purge
ml matlab
date

mindays=$1

thisHost=$(hostname)
thisDate=$(date)
echo "$0: Begin on hostname=$thisHost on $thisDate"
echo "SLURM_SCRATCH=$SLURM_SCRATCH"
echo "SLURM_JOB_ID=$SLURM_JOB_ID"

#Go here so that correct pathdef.m file is used
cd /projects/brodzik/Documents/MATLAB/esp_SnowToday_ops
#cd /projects/brodzik/Documents/MATLAB/esp

#matlab -nodesktop -nodisplay -r "clear; tiles=MODISData.tilesFor('westernUS'); batchUpdateModisArchiveStub('nrt', tiles, 'startyyyymmdd', '20191220'); exit(0);"
matlab -nodesktop -nodisplay -r "clear; tiles=MODISData.tilesFor('westernUS'); batchUpdateModisArchive('nrt', tiles); exit(0);"

#schedule next job in SnowToday pipeline for today
thisYear=$(date +'%Y')
sbatch --dependency=afterok:$SLURM_JOB_ID scripts/runSnowTodayStep1.sh $thisYear $mindays

#schedule Step0 for the next time clock strikes noon
sbatch --begin=10:30:00 scripts/runSnowTodayStep0.sh $mindays

thisDate=$(date)
echo "$0: Done on hostname=$thisHost on $thisDate"

