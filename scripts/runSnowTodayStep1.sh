#!/bin/bash
#
# script to run SnowToday Step1:
#   Job array for each of westernUS tiles for this year:
#      update Raw cubes
#      udpate STC (Gap/Interp cubes)
#
# Set up the SBATCH nodes/ntasks-per-node for 1 matlab job that
# may need up to all the tasks on this node.
#
# Arguments:
#
# yr: year to update
# mindays: mindays to use for STC cubes

#SBATCH --qos normal
#SBATCH --job-name runSnowTodayStep1
#SBATCH --account=ucb135_summit1
#SBATCH --time=00:05:00
# FOR REAL PROCESSING ntasks-per-node SHOULD BE 20
#SBATCH --ntasks-per-node=1
#SBATCH --nodes=1
#SBATCH -o /pl/active/rittger_esp/modis/archive_status/slurm_output/runSnowTodayStep1-%A_%a.out
# Set the system up to notify upon completion
#SBATCH --mail-type=END,FAIL,REQUEUE,STAGE_OUT
#SBATCH --mail-user=brodzik@nsidc.org
#SBATCH --array=1-5

yr=$1
mindays=$2

module purge
ml matlab

thisHost=$(hostname)
thisDate=$(date)
echo "$0: Begin on hostname=$thisHost on $thisDate for mindays=$mindays"
echo "SLURM_SCRATCH=$SLURM_SCRATCH"
echo "SLURM_JOB_ID=$SLURM_JOB_ID"
echo "SLURM_ARRAY_JOB_ID=$SLURM_ARRAY_JOB_ID"

#Make a unique temporary directory for matlab job storage
mkdir -p $SLURM_SCRATCH/$SLURM_ARRAY_JOB_ID

#Go here so that correct pathdef.m file is used
# cd /projects/brodzik/Documents/MATLAB/esp_SnowToday_ops
cd /projects/brodzik/Documents/MATLAB/esp
matlab -nodesktop -nodisplay -r "clear; updateWesternUSMonthCubesStub("$SLURM_ARRAY_TASK_ID", ${yr}, ${mindays}); exit(0);"

#Clean up temporary directory for matlab job storage
rm -rf $SLURM_SCRATCH/$SLURM_ARRAY_JOB_ID

#schedule next job in SnowToday pipeline
#sbatch --dependency=afterok:$SLURM_JOB_ID scripts/runSnowTodayStep1.sh

thisDate=$(date)
echo "$0: Done on hostname=$thisHost on $thisDate"

