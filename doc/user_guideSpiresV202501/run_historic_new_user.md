# Run historic pipeline from scratch directory

## 1. Clone repos
- Clone https://github.com/RittgerLabGroup/SPIRES_2025_0_1 to `/projects/$USER/`
- Create directory `/projects/$USER/MATLAB` and clone following repos to that folder:
  - https://github.com/edwardbair/ParBal
  - https://github.com/DozierJeff/RasterReprojection

## 2. Copy inputs and ancillary files to your scratch
Lookup tables: 
```bash
rsync /pl/active/rittger_ops/modis /scratch/alpine/$USER/
``` 
MODIS hdf files: 
```bash
rsync -avh --progress --mkpath /scratch/alpine/lost1845/mod09ga.061/{h08v04,h08v05,h09v04,h09v05,h10v04,h10v05,h11v04} /scratch/alpine/$USER/modis/input/mod09ga/v006/
```
Background reflenctance:
```bash
rsync -avh --progress -mkpath /pl/active/rittger_ops/mod09ga.061/spires/v2025.0.1/int_backgroundreflectance /scratch/alpine/$USER/mod09ga.061/spires/v2025.0.1/
```
Ancillary files:
```bash
rsync /pl/active/rittger_ops/modis_ancillary /scratch/alpine/$USER/
```

## 3. Edit .bashrc and .matlabEnvironmentVariableFiles
Copy `/projects/lost1845/SPIRES_2025_0_1/home/.bashrc` and `/projects/lost1845/SPIRES_2025_0_1/home/.matlabEnvironmentVariables` to `/home/$USER`

`.matlabEnvironmentVariables` does not need to be edited. 

Edit `.bashrc` to:

```bash
# Supercomputer environment parameters.
export level3User=$USER
export archiveDir=
export archiveDir1=
export archiveDir2=/pl/active/rittger_nrt/ 
export archiveDir3=/pl/active/rittger_ops/ 
export myHome=/home/lost1845/
export projectDir=/projects/$level3user/
export slurmName1=blanca
export slurmName2=blanca
export slurmAccount1=blanca-rittger
export slurmAccount2=blanca-rittger
export slurmAccount3=blanca-rittger
export slurmPartition1=
export slurmPartition2=
export slurmQos1=preemptable
export slurmQos2=preemptable
export slurmAlternativeQos2=
export slurmScratchDir1=/scratch/alpine/$level3user/
export slurmAlternativeScratchDir1=/scratch/alpine/level3user/
# @obsolete. export slurmScratchDir2=
export slurmScratchDirForLevel3=/scratch/alpine/$level3user/
export loginNodeDomain=login.rc.colorado.edu
```

## 4. Run historic pipeline
Run steps in `run_historic_step.md` starting at step `spiInver` (spectral unmixing). \
All `spiInver` jobs can be submitted at the same time (2 jobs per water year + 1 job for June to September, 2000) \

IMPORTANT: Add argument `-y $espScratchDir` to every submission command to use files from your scratch instead of `rittger_nrt`

For subsequent steps, 1 job is submitted for each water year and all water years can be submitted simultaneously.

Subsequent steps:
  - `spiTimeI`
  - `moSpires`
  - `daNetCDF`

