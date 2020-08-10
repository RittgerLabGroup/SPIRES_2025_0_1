% ESPToolbox
% Version 1.9 (R2019b) 05-Aug-2020
%
% Functions
%
%   getJPLmodis                - getJPLmodis retrieves files from JPL MODSCAG website to a local folder
%   writeRectangleToCsv        - writeRectangleToCsv writes Rectangle shape coords to .csv file
%   saveStudyExtentGeolocation - saveStudyExtentGeolocation saves geotiffs of lat/lon and x,y
%   studyExtent                - studyExtent - information about a named study extent
%   ESPEnv                     - ESPEnv - environment for ESP data directories
%   batchBrowse                - batchBrowse do batch of LandSat/MODIS browse images
%   batchBrowseLandsat         - batchBrowseLandsat do batch of LandSat (RGB/Snow/Masks) browse images
%   batchGetJPLmodis           - batchGetJPLmodis - fetches a batch of JPL MODIS scag/drfs/mod09 files
%   batchReproject             - batchReproject reprojects a batch of typeOfData files to extentName
%   browseLandsat              - browseLandsat makes browse image of Landsat RGB, snow & masks
%   browseLandsatMODIS         - browseLandsatMODIS makes browse image of Landsat & MODIS files
%   landsatFsca                - landsatFsca returns fsca from .mat file
%   contFSCALandsat            - contFSCALandsat returns continuous FSCA from mat file
%   getSaturationFromQcal      - getSaturationFromQcal finds pixels with bands 123 all saturated
%   landsatRGB                 - landsatRGB returns scaled bands 642 RGB from mat file
%   reprojectRaster            - [ B, RB, RRB] = reprojectRaster(A,RA,InStruct,OutStruct,... )
%   reprojectToStudyExtent     - reprojectToStudyExtent returns sensor data reprojected to StudyExtent
%   scale2uint8                - scale2uint8 scales data to uint8 with NaNs set to 255
%   utmMstructFromTmInfo       - utmMstruct creates mstruct from the tmInfo struct
%   cube                       - cube class contains data and metadata for reading a MODIS scag STC cube
%   MODISData                  - MODISData - manages our inventory of MODIS tile data

%   reprojectForestHeight      - batchReproject reprojects a forest height image to extentName
%   reprojectSrtm              - batchReproject reprojects an SRTM DEM file to extentName
%   getFilenameForType         - getFilenameForType finds the filename of the requested filetype
%   FillCubeDate                    - FillCubeDate fill date columns of SCA,Veg,Rock or GS cube w/smoothing spline
%   FillNaN3                        - FillNaN3 fills image cube with NaNs before interpolating
%   FillZero3                       - FillZero3 fills image cube with zeros before interpolating
%   Filter_SCAGDRFS                 - Filter_SCAGDRFS filters cubes to prepare for smoothing and interpolation
%   FixGrainsFast                   - FixGrains, fix drops in grain sizes, Jeff Dozier?, revised by Ned Bair
%   FixSCAFast                      - FixSCAFast fixes spurious drops in fSCA
%   MODIS_SmoothingWeight           - MODIS_SmoothingWeight convert sensor zenith angle to spline smoothing weights
%   SSN_Browse                      - SSN_Browse
%   SSN_BrowseLandsat               - SSN_BrowseLandsat
%   STC_SCAGDRFS_snow               - STC_SCAGDRFS_snow does STC processing for a regionName, year and month
%   adjust_CloudFilter              - adjust_CloudFilter filters NaNs & clouds in snow and grain size cubes, filters NaN in veg and rock cubes
%   batchModisInventory             - batchModisInventory - cleans dupes & makes inventory of type/tiles
%   batchReprojectMosaic            - batchReproject reprojects a batch of typeOfData files to extentName
%   batchUpdateModisArchive         - batchUpdateModisArchive - fetches any recent JPL MODIS scag/drfs/mod09 files
%   batchUpdateModisMonthCubes      - batchUpdateModisMonthCubes - creates/updates Modis month/tile cubes
%   browseMODIS                     - browseMODIS makes browse image of 2 MODIS cubes varNames
%   browsePic                       - browsePic makes browse image of a set of TMscag pic files
%   browseTmscag                    - browseTmscag makes browse image of Landsat TMscag snow/veg/rock
%   checkMOD09GArange               - checkMOD09GArange Check range of specified MOD09GA data
%   cloudMaskForRefl                - cloudMaskForRefl creates a cloud mask by thresholding refl
%   conditionalIDW                  - conditionalIDW - performs conditional inverse-distance weighted interpolation
%   fNaNb                           - Freeze NaN color to black for plotting
%   fNaNg                           - Freeze NaN color to grey for plotting
%   freezeColors                    - freezeColors  Lock colors of plot, enabling multiple colormaps per figure. (v2.3)
%   makePlotLim                     - Preps the limits for xplot,yplot inputs into imagesc.m
%   mosaicTilesDATpad               - mosaicTilesDATpad mosaics the requested variables from input tiles
%   mosaicForestHeight              - mosaicForestHeigh mosaics tiled forest height files.
%   mosaicSubsetMOD09GA             - mosaicSubsetMOD09GA makes a year of MOD09GA space-time cubes
%   mosaicSubsetSCAGDRFS            - mosaicSubsetSCAGDRFS makes a year of SCAGDRFS space-time cubes
%   mosaicTiles234d                 - mosaicTiles234d - makes mosaicked composite from input filenames
%   mosaicTilesMOD09GApad           - mosaicTilesMOD09GApad mosaics the MOD09GA variable from input tiles
%   partitionColorMap               - partitionColorMap partitions cmap with gray/black/white
%   plotAnnualSCA_SCDInContext      - Plot 4 line graphs SCA and SCF for whole year and this month
%   readMOD09day                    - readMOD09day reads requested variable data from the filename
%   readMosaic                      - reads the requested variable from the mosaic file
%   readSCAGDRFSday                 - readSCAGDRFSday reads requested variable data from the filename
%   read_MOD09GA                    - [grid1km grid500m] = read_MOD09GA(filename,datagroups,datasets)
%   updateMosaicFor                 - updateMosaicFor creates daily mosaics with varNames variables
%   read_dat                        - read_dat reads single precision binary .dat file and returns transverse    
%   reprojectMosaic                 - reprojectMosaic
%   scaleRawFractionImage           - scaleRawFractionImage scales raw image to uint8 
%   scale_QC_500m_1                 - Bit info:
%   scale_state_1km                 - scale_state_1km retreives bit flags from State_1km
%   scale_MOD09GA                   - Scale science dataset
%   runSummarizeSCA_SCDForLinePlots - This script summarizes total snow cover fraction and median snow covered
%   showSCF_SCD                     - 
%   subsetMonth                     - subsetMonth subsets (3- or 4-d hypercube) data and dates to a single month
%   subsetToMaskNV                  - subsetToMaskNV sets nodatavalue for masked regions in Big array
%   summarizeSCA_SCDForLinePlots    - summarizeSCA_SCDForLinePlots summarizes total snow cover fraction and median snow covered
%   updateWesternUSMonthCubes       - updateWesternUSMonthCubes - update WesternUS Modis tile/yr cubes
%   updateSTC_SCAGDRFSFor           - updateSTC_SCAGDRFSFor creates regionName STC month cubes for yr
%   updateModisMonthCubesFor        - updateModisMonthCubesFor - creates tileID Modis month cubes for yr
