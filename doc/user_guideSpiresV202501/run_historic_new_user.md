# Run historic pipeline from scratch directory

## 1. Clone repos
- Clone https://github.com/RittgerLabGroup/SPIRES_2025_0_1 to `/projects/$USER/`
- Create directory `/projects/$USER/MATLAB` and clone following repos to that folder:
  - https://github.com/edwardbair/ParBal
  - https://github.com/DozierJeff/RasterReprojection

## 1. Copy inputs and ancillary files to your scratch
`rsync /pl/active/rittger_ops/modis /scratch/alpine/$USER/`
`rsync -avh --progress --mkpath /scratch/alpine/lost1845/mod09ga.061/{h08v04,h08v05,h09v04,h09v05,h10v04,h10v05,h11v04} /scratch/alpine/$USER/modis/input/mod09ga/v006/`
`rsync -avh --progress -mkpath /pl/active/rittger_ops/mod09ga.061/spires/v2025.0.1/int_backgroundreflectance /scratch/alpine/$USER/mod09ga.061/spires/v2025.0.1/`
`rsync /pl/active/rittger_ops/modis_ancillary /scratch/alpine/$USER/`
