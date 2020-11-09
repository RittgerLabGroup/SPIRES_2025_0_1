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
# northZthresh: Northern latitude limit for Zthresh (meters)
# southZthresh: Southern latitude limit for Zthresh (meters)

#SBATCH --qos normal
#SBATCH --job-name runSnowTodayStep1
#SBATCH --account=ucb135_summit2
#SBATCH --time=06:00:00
#SBATCH --ntasks-per-node=24
#SBATCH --nodes=1
#SBATCH -o /pl/active/rittger_esp/modis/archive_status/slurm_output/runSnowTodayStep1-%A_%a.out
# Set the system up to notify upon completion
#SBATCH --mail-type=END,FAIL,REQUEUE,STAGE_OUT
#SBATCH --mail-user=brodzik@nsidc.org
#SBATCH --array=1-5

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
echo "$0: Begin on hostname=$thisHost on $thisDate for mindays=$mindays"
echo "SLURM_SCRATCH=$SLURM_SCRATCH"
echo "SLURM_JOB_ID=$SLURM_JOB_ID"
echo "SLURM_ARRAY_JOB_ID=$SLURM_ARRAY_JOB_ID"

#Make a unique temporary directory for matlab job storage
mkdir -p $SLURM_SCRATCH/$SLURM_ARRAY_JOB_ID

#Go here so that correct pathdef.m file is used
cd /projects/brodzik/Documents/MATLAB/esp_SnowToday_ops
#cd /projects/brodzik/Documents/MATLAB/esp
matlab -nodesktop -nodisplay -r "clear; "\
"updateWesternUSMonthCubes("$SLURM_ARRAY_TASK_ID", ${yr}, ${mindays}, "\
"'monthStart', ${monthStart}, 'monthStop', ${monthStop}, "\
"'zthresh', ["${northZthresh}" "${southZthresh}"]); "\
"exit(0);"

#schedule next job in SnowToday pipeline to run after entire job array completes
if [ "$SLURM_ARRAY_TASK_ID" -eq "1" ]; then
    sbatch --dependency=afterok:$SLURM_ARRAY_JOB_ID scripts/runSnowTodayStep2.sh $yr $mindays $northZthresh $southZthresh $monthStart $monthStop
fi

#Clean up temporary directory for matlab job storage
rm -rf $SLURM_SCRATCH/$SLURM_ARRAY_JOB_ID

thisDate=$(date)
echo "$0: Done on hostname=$thisHost on $thisDate"

