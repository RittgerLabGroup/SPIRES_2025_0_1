#!/bin/bash
#
# Initialize configuration parameters specific to generation of historics for SPIReS v2024.1.0.

# Script/Step-specific constants.
########################################################################################
# defaultBigRegionId=5
defaultControlTime=12:59:00
defaultInputProductAndVersion="mod09ga.061"
authorizedScriptIds=(mod09gaI spiInges spiBackg spiInver spiTimeI moSpires daNetCDF daStatis)
: '
  - mod09gaI: Download mod09ga.
  - spiInges: Pre-ingestion of the input files.
  - spiBackg: Generate background reflectances.
  - spiInver: Generate intermediary gap files from mod09ga input using SPIReS
    spectral unmixing.
  - spiTimeI: Generate gap-filled data files (without false positives) + 
    temporal interpolation + snow cover day calculation.
  - moSpires: Generate daily .mat files (dubbed mosaics) + albedo calculations using
    ParBal.
  - daNetCDF: Generate output netcdf files.
  - daStatis: Generate .csv daily statistic files
'

submitScriptIdJobNames=(sMod sSIg sSBa sSIn sSTi sMoS sNet sSta)
scriptIdJobNames=(mod0 sIng sBac sInv sTim moSp netC stat)
scriptInputLabels=(v061 v061 v2025.0.1 v061 v2025.0.1 v2025.0.1 v2025.0.1 v2025.0.1)
scriptOutputLabels=(v061 v2025.0.1 v2025.0.1 v2025.0.1 v2025.0.1 v2025.0.1 v2025.0.1 v2025.0.1)
scriptModes=(0 11 0 0 0 0 0 1)
scriptRegionTypes=(0 0 0 0 0 0 0 1)
  # 0: tile, 1: big region, 10: all regions.
scriptSequences=(0 0 0 0 001-036 0 0 999) # 999 = number of jobs submitted is based on number of subdivisions
# temp change 999 to 007 for daStatis
scriptSequenceMultiplierToIndices=(1 1 1 1 1 1 1 3)
scriptParallelWorkersNbs=(0 16 16 16 10 40 2 1)

# sbatch parameters
sbatchNTasksPerNodes=(1 16 16 16 10 40 2 1)
sbatchMems=(1G 44G 60G 44G 60G 160G 5G 24G)
sbatchTimes=(04:00:00 03:00:00 04:00:00 15:00:00 04:30:00 08:00:00 05:00:00 06:00:00)
# for: 3-months 4-months 4-months 3-months 12-months(wateryear) 12-months(wateryear) 12-months(wateryear) 12-months(wateryear).
# NB: spiInver step can be particularly long, notably for some Alaskan tiles.
