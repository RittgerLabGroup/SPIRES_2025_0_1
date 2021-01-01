#!/bin/bash
#
# script to run SnowToday Step4:
#   Make today's SnowToday line and map plots
#   kick off Step5 for today
#

#SBATCH --qos normal
#SBATCH --job-name runSnowTodayStep4
#SBATCH --account=ucb188_summit1
#SBATCH --time=02:00:00
#SBATCH --ntasks-per-node=20
#SBATCH --nodes=1
#SBATCH --mem=90G
#SBATCH -o /pl/active/rittger_esp/modis/archive_status/slurm_output/runSnowTodayStep4-%j.out
# Set the system up to notify upon completion
#SBATCH --mail-type=END,FAIL,REQUEUE,STAGE_OUT
#SBATCH --mail-user=brodzik@nsidc.org
#SBATCH --array=10-12

module purge
ml matlab/R2019b
date

mindays=$1
northZthresh=$2
southZthresh=$3
minSCF=$4
minZ=$5

#SCD minimum days to include in the plots
minSCD=14

thisHost=$(hostname)
thisDate=$(date)
echo "$0: Begin on hostname=$thisHost on $thisDate for partitionNum=$SLURM_ARRAY_TASK_ID, yr=$yr and mindays=$mindays"
echo "SLURM_SCRATCH=$SLURM_SCRATCH"
echo "SLURM_JOB_ID=$SLURM_JOB_ID"
echo "SLURM_ARRAY_JOB_ID=$SLURM_ARRAY_JOB_ID"

#Make a unique temporary directory for matlab job storage
mkdir -p $SLURM_SCRATCH/$SLURM_ARRAY_JOB_ID
mkdir -p $SLURM_SCRATCH/$SLURM_ARRAY_JOB_ID/tmp
export TMP=$SLURM_SCRATCH/$SLURM_ARRAY_JOB_ID/tmp
export TMPDIR=$SLURM_SCRATCH/$SLURM_ARRAY_JOB_ID/tmp

#Go here so that correct pathdef.m file is used
cd /projects/brodzik/Documents/MATLAB/esp_staging
matlab -nodesktop -nodisplay -r "clear; "\
"todayDt = datetime; "\
"plotAnnualSCA_SCDInContext('westernUS', "$SLURM_ARRAY_TASK_ID", "\
"todayDt, "\
"${minSCF}, ${minZ}, ${mindays}, "\
"["${northZthresh}" "${southZthresh}"]); "\
"showSCF_SCD('westernUS', "$SLURM_ARRAY_TASK_ID", "\
"todayDt, "\
"${minSCF}, ${minSCD},${minZ}, ${mindays}, "\
"["${northZthresh}" "${southZthresh}"]); "\
"exit(0);"

#use Step 5 to push all plots to NSIDC
#if [ "$SLURM_ARRAY_TASK_ID" -eq "10" ]; then
#    creationDate=$(date +'%Y%m%d')
#    sbatch --dependency=afterok:$SLURM_ARRAY_JOB_ID scripts/runSnowTodayStep5.sh $creationDate $mindays $northZthresh $southZthresh
#fi

#Clean up temporary directory for matlab job storage
rm -rf $SLURM_SCRATCH/$SLURM_ARRAY_JOB_ID

thisDate=$(date)
echo "$0: Done on hostname=$thisHost on $thisDate"

