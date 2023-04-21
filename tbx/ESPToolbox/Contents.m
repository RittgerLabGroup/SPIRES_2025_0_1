% ESPToolbox
% Version 1.9 (R2019b) 05-Aug-2020
%
% Functions
%
%   getJPLmodis                - getJPLmodis retrieves files from JPL MODSCAG website to a local folder   | snowToday | batchGetJPLmodis.m , batchUpdateModisArchive.m |
%   writeRectangleToCsv        - writeRectangleToCsv writes Rectangle shape coords to .csv file             | obsolete |  |
%   saveStudyExtentGeolocation - saveStudyExtentGeolocation saves geotiffs of lat/lon and x , y             | obsolete? |  |
%   studyExtent                - studyExtent - information about a named study extent                   | snowToday | batchReproject.m , batchReprojectMosaic.m , reprojectMosaic.m , reprojectSrtm.m, reprojectToStudyExtent.m |
%   ESPEnv                     - ESPEnv - environment for ESP data directories                           | snowToday | *IMPORTANT* | 
%   batchBrowse                - batchBrowse do batch of LandSat/MODIS browse images                     |  |  | 
%   batchBrowseLandsat         - batchBrowseLandsat do batch of LandSat (RGB/Snow/Masks) browse images   |  |  | 
%   batchGetJPLmodis           - batchGetJPLmodis - fetches a batch of JPL MODIS scag/drfs/mod09 files   | snowToday | batchUpdateModisArchive.m | 
%   batchReproject             - batchReproject reprojects a batch of typeOfData files to extentName     | snowToday? | batchReprojectMosaic.m , reprojectForestHeight.m , reprojectSrtm.m | 
%   browseLandsat              - browseLandsat makes browse image of Landsat RGB ,  snow & masks           | snowToday | MedTest_Browse , MedTest_BrowseLandsat , SSN_Browse , SSN_BrowseLandsat , batchBrowse , batchBrowseLandsat , browseLandsat , browseLandsatMODIS , getFilenameForType | 
%   browseLandsatMODIS         - browseLandsatMODIS makes browse image of Landsat & MODIS files              | snowToday | MedTest_Browse.m , SSN_Browse.m , batchBrowse.m , browseLandsatMODIS.m | 
%   landsatFsca                - landsatFsca returns fsca from .mat file                                     | obsolete |  | 
%   contFSCALandsat            - contFSCALandsat returns continuous FSCA from mat file                       | snowToday? | landsatFsca.m | 
%   convertSCAGtov03           -                                                                             | work |  | 
%   getSaturationFromQcal      - getSaturationFromQcal finds pixels with bands 123 all saturated             | snowToday | landsatFsca.m |
%   landsatRGB                 - landsatRGB returns scaled bands 642 RGB from mat file                       | obsolete |  |
%   reprojectRaster            - [ B ,  RB ,  RRB] = reprojectRaster(A , RA , InStruct , OutStruct , ... )
%   reprojectToStudyExtent     - reprojectToStudyExtent returns sensor data reprojected to StudyExtent       | snowtoday? | batchReproject , reprojectMosaic |
%   scale2uint8                - scale2uint8 scales data to uint8 with NaNs set to 255                       | obsolete? |  |
%   utmMstructFromTmInfo       - utmMstruct creates mstruct from the tmInfo struct                           | obsolete |  |
%   cube                       - cube class contains data and metadata for reading a MODIS scag STC cube     | obsolete |  |
%   MODISData                  - MODISData - manages our inventory of MODIS tile data                       | snowToday | *IMPORTANT* | 

%   reprojectForestHeight      - batchReproject reprojects a forest height image to extentName               | obsolete? |  |
%   reprojectSrtm              - batchReproject reprojects an SRTM DEM file to extentName                    | obsolete? |  |
%   getFilenameForType         - getFilenameForType finds the filename of the requested filetype             | snowToday | browseLandsat.m |
%   FillCubeDate                    - FillCubeDate fill date columns of SCA , Veg , Rock or GS cube w/smoothing spline   | snowToday | FillCubeDateLinear.m , STC_SCAGDRFS_snow.m , updateSTC_SCAGDRFSFor.m | 
%   FillCubeDateLinear              -                                                                        | snowToday | STC_SCAGDRFS_snow.m | 
%   FillNaN3                        - FillNaN3 fills image cube with NaNs before interpolating               | snowToday | Filter_SCAGDRFS.m |
%   FillZero3                       - FillZero3 fills image cube with zeros before interpolating             | snowToday | Filter_SCAGDRFS.m |
%   Filter_SCAGDRFS                 - Filter_SCAGDRFS filters cubes to prepare for smoothing and interpolation  | snowToday | STC_SCAGDRFS_snow.m |
%   FixGrainsFast                   - FixGrains ,  fix drops in grain sizes ,  Jeff Dozier? ,  revised by Ned Bair  | snowToday | Filter_SCAGDRFS.m |
%   FixSCAFast                      - FixSCAFast fixes spurious drops in fSCA                                       | snowToday | Filter_SCAGDRFS.m |
%   MODIS_SmoothingWeight           - MODIS_SmoothingWeight convert sensor zenith angle to spline smoothing weights | snowToday | STC_SCAGDRFS_snow.m |
%   SSN_Browse                      - SSN_Browse                                                             | obsolete? | SSN_BrowseLandsat.m |
%   SSN_BrowseLandsat               - SSN_BrowseLandsat                                                      | obsolete? |  |
%   STC_SCAGDRFS_snow               - STC_SCAGDRFS_snow does STC processing for a regionName ,  year and month  | snowToday | updateSTC_SCAGDRFSFor.m |
%   addAnnotation                   -                                                                        | obsolete |  | 
%   addPatchNote                    -                                                                        | obsolete |  |    
%   adjust_CloudFilter              - adjust_CloudFilter filters NaNs & clouds in snow and grain size cubes ,  filters NaN in veg and rock cubes   | snowToday | Filter_SCAGDRFS , updateSTC_SCAGDRFSFor | 
%   assigninHere                    -                                                                        | snowToday | mosaicSubsetSCAGDRFS.m | 
%   batchMakeGrsizeFscaConsistent   -                                                                        | obsolete |  | 
%   batchModisInventory             - batchModisInventory - cleans dupes & makes inventory of type/tiles     | snowToday | batchGetJPLmodis.m | 
%   batchReprojectMosaic            - batchReproject reprojects a batch of typeOfData files to extentName    | snowToday? | runReprojectMosaic.sh | 
%   batchUpdateModisArchive         - batchUpdateModisArchive - fetches any recent JPL MODIS scag/drfs/mod09 files   | snowToday | cronBatchUpdateModisArchive.sh , runAKTodayStep0.sh , runBatchModisArchive.sh , runFetchTile.sh , runHMATodayStep0.sh , runSnowTodayStep0.sh | 
%   batchUpdateModisMonthCubes      - batchUpdateModisMonthCubes - creates/updates Modis month/tile cubes    | absent |  |
%   browseMODICE                    -                                                                        | obsolete |  | 
%   browseMODIS                     - browseMODIS makes browse image of 2 MODIS cubes varNames               | obsolete |  | 
%   browseMosaic                    -                                                                        | obsolete |  |
%   browseMosaicVars                -                                                                        | obsolete |  |
%   browseOLIscagCloud              -                                                                        | obsolete |  |
%   browsePic                       - browsePic makes browse image of a set of TMscag pic files              | obsolete |  |
%   browseTmscag                    - browseTmscag makes browse image of Landsat TMscag snow/veg/rock        | obsolete |  |
%   browseTmscagDiff                -                                                                        | obsolete |  |
%   browseTmscagOptions             -                                                                        | obsolete |  |
%   calculateAlbedo                 - contains developments on albedos & layers broadband ... which are to be put in production at an undetermined time                                                                      | work |  | 
%   canopyAdjustFsca                -                                                                        | snowToday? | batchReproject.m | 
%   checkMOD09GArange               - checkMOD09GArange Check range of specified MOD09GA data                | snowToday | scale_MOD09GA | 
%   cloudMaskForRefl                - cloudMaskForRefl creates a cloud mask by thresholding refl             | snowToday | STC_SCAGDRFS_snow.m | 
%   conditionalIDW                  - conditionalIDW - performs conditional inverse-distance weighted interpolation  | snowToday | STC_SCAGDRFS_snow.m |
%   configParPool                   -                                                                        | obsolete |  |
%   fNaNb                           - Freeze NaN color to black for plotting                                 | obsolete |  |
%   fNaNg                           - Freeze NaN color to grey for plotting                                  | obsolete |  |
%   freezeColors                    - freezeColors  Lock colors of plot ,  enabling multiple colormaps per figure. (v2.3)  | obsolete |  |
%   getMosaic                       -                                                                        | obsolete |  |
%   landsatInfo                     -                                                                        | obsolete |  |
%   landsatRGB                      -                                                                        | obsolete |  |
%   makeColorbarTicks               -                                                                        | obsolete |  |
%   makeGrsizeFscaConsistent        -                                                                       | obsolete | batchMakeGrsizeFscaConsistent.m |            
%   makePlotLim                     - Preps the limits for xplot , yplot inputs into imagesc.m
%   Mosaic                          - Generate and Save the daily Mosaic Files from the monthly STC cubes   | snowToday | runSnowTodayStep2.sh , runIndusTodayStep2.sh , runHMATodayStep2.sh , runUpdateMosaic.sh |
%   mosaicTilesDATpad               - mosaicTilesDATpad mosaics the requested variables from input tiles    | snowToday | mosaicSubsetSCAGDRFS.m |
%   makeSnowTodayPlotInContext      -                                                                       | obsolete | plotMostRecentVarInContext.m |
%   makeSnowTodayMap                -                                                                        | obsolete |  |
%   MedTest_Browse                  -                                                                        | obsolete |  |
%   MedTest_BrowseLandsat           -                                                                        | obsolete |  |
%   minSCPForLinePlots              -                                                                       | snowToday | runSnowTodayStep3.sh , runSnowTodayStep3Historical.sh |
%   minZForLinePlots                -                                                                       | snowToday | runSnowTodayStep3.sh , runSnowTodayStep3Historical.sh |
%   monthsFor                       -                                                                        | obsolete |  |
%   mosaicForestHeight              - mosaicForestHeigh mosaics tiled forest height files.                  | obsolete |  |
%   MosaicStatCalculator            -                                                                        | obsolete |  |
%   mosaicSubsetMOD09GA             - mosaicSubsetMOD09GA makes a year of MOD09GA space-time cubes          | snowToday | updateModisRawCubesFor.m |    
%   mosaicSubsetSCAGDRFS            - mosaicSubsetSCAGDRFS makes a year of SCAGDRFS space-time cubes        | snowToday | updateModisRawCubesFor.m |   
%   mosaicTiles234d                 - mosaicTiles234d - makes mosaicked composite from input filenames      | obsolete | updateMosaicFor.m |
%   mosaicTilesMOD09GApad           - mosaicTilesMOD09GApad mosaics the MOD09GA variable from input tiles   | snowToday | mosaicSubsetMOD09GA.m |
%   parloadDts                      -                                                                       | snowToday | MODISData.m |
%   parloadMatrices                 -                                                                       | snowToday | MODISData.m |
%   parprctile                      -                                                                       | snowToday | Filter_SCAGDRFS.m |
%   partitionColorMap               - partitionColorMap partitions cmap with gray/black/white               | obsolete | browseMODICE.m |
%   plotAnnualSCA_SCDInContext      - Plot 4 line graphs SCA and SCF for whole year and this month          | obsolete | runSnowTodayStep4.sh? |
%   plotMostRecentVarInContext      -                                                                       | obsolete | runSnowTodayStep4.sh? |
%   printPhoto                      -                                                                       | work |  |
%   PublicMosaic                    - Image of the Mosaic File, thresholded for unreliable data             | snowToday | Regions.m |
%   readBandsRGB                    -                                                                        | obsolete |  |
%   readMOD09day                    - readMOD09day reads requested variable data from the filename
%   readMosaic                      - reads the requested variable from the mosaic file                     | snowToday? | reprojectForestHeight.m , reprojectMosaic.m , runStatsForLinePlots.m |
%   readSCAGDRFSday                 - readSCAGDRFSday reads requested variable data from the filename       | snowToday | mosaicTilesDATpad.m |
%   read_MOD09GA                    - [grid1km grid500m] = read_MOD09GA(filename , datagroups , datasets)   | snowToday? | readSCAGDRFSday.m |
%   read_dat                        - read_dat reads single precision binary .dat file and returns transverse   | snowToday? | readSCAGDRFSday.m |
%   readTMbip                       -                                                                       | obsolete? |  |
%   readLandsatScag                 -                                                                       | snowToday | canopyAdjustFsca.m |
%   readTmscag                      -                                                                       | obsolete? |  |
%   Regions                         - Handle the upper-level regions and subregions                         | snowToday | *IMPORTANT * |
%   Regions_methods                 -                                                                       | obsolete |  |
%   reprojectMosaic                 - reprojectMosaic                                                       | snowToday? | batchReprojectMosaic.m |
%   Rs2RGB                          -                                                                       | snowToday? | batchReproject.m |
%   run_write_L8_bip                -                                                                       | obsolete? |  |
%   runStatsForLinePlots            -                                                                       | snowToday |  snowTodayStep3.sh , snowTodayStep3Historical3.sh |
%   saveFigureAtResolution          -                                                                       | obsolete |  |
%   scale_MOD09GA                   -                                                                       | snowToday | readMOD09day.m | 
%   scaleRawFractionImage           - scaleRawFractionImage scales raw image to uint8 
%   scale_QC_500m_1                 - Bit info:                                                             | snowToday | scale_MOD09GA.m |
%   scale_state_1km                 - scale_state_1km retreives bit flags from State_1km                    | snowToday | scale_MOD09GA.m |
%   scale_MOD09GA                   - Scale science dataset                                                  | snowToday | mosaicSubsetMOD09GA.m , readMOD09day.m | 
%   scaleRawFractionImage           -                                                                       | obsolete? |  |
%   setFigureTightBorders           -                                                                       | obsolete |  |
%   splitAlbedo                     -                                                                       | work | calculateAlbedo.m |
%   runSummarizeSCA_SCDForLinePlots - This script summarizes total snow cover fraction and median snow covered
%   showSCF_SCD                     -                                                                       | obsolete |  | 
%   showMostRecentVarMap            -                                                                       | obsolete |  |
%   SSN_Browse                      -                                                                       | obsolete |  |
%   SSN_BrowseLandsat               -                                                                       | obsolete |  |
%   subsetMonth                     - subsetMonth subsets (3- or 4-d hypercube) data and dates to a single month | snowToday | mosaicSubsetMOD09GA.m , mosaicSubsetSCAGDRFS.m |
%   subsetToMaskNV                  - subsetToMaskNV sets nodatavalue for masked regions in Big array           | snowToday | mosaicSubsetMOD09GA.m , mosaicSubsetSCAGDRFS.m |
%   summarizeSCA_SCDForLinePlots    - summarizeSCA_SCDForLinePlots summarizes total snow cover fraction and median snow covered
%   testBrowseTmscag                -                                                                       | obsolete |  |
%   testMJB                         -                                                                       | obsolete |  |
%   testTileLayout                  -                                                                       | obsolete |  |
%   TMrgb                           -                                                                       | obsolete |  |
%   Tools                           - reusable functions shared by several classes, e.g. parfor save        | snowToday | Mosaic.m , Variables.m |
%   untarLandsat                    -                                                                       | snowToday | readLandsatScag.m |
%   updateModisRawCubesFor          -                                                                       | snowToday | updateRegionsMonthCubes.m |
%   updateMosaicFor                 - updateMosaicFor creates daily mosaics with varNames variables         | obsolete | runSnowTodayStep2.sh |
%   updateRegionMonthCubes          -                                                                       | snowToday | runSnowTodayStep1.sh , runHMATodayStep1.sh |
%   updateWesternUSMonthCubes       - updateWesternUSMonthCubes - update WesternUS Modis tile/yr cubes
%   updateSTC_SCAGDRFSFor           - updateSTC_SCAGDRFSFor creates regionName STC month cubes for yr       | snowToday | runUpdateSTCMonthCubes.sh |
%   updateModisMonthCubesFor        - updateModisMonthCubesFor - creates tileID Modis month cubes for yr
%   Variables                       - handles calculations of variables (STC or Mosaic)                     | snowToday | updateSTC_SCAGDRFSFor.m, runHMATodayStep2.sh , runSnowTodayStep2.sh , runUpdateMosaic.sh |
%   WaterYearDate                   - handles dates with wateryear constraints                              | snowToday | *IMPORTANT* |
%   workESPEnv                      -                                                                       | snowToday | runUpdateMosaic.sh , runUpdateSTCMonthCubes.sh |
%   workMODISData                   -                                                                       | snowToday | runUpdateMosaic.sh , runUpdateSTCMonthCubes.sh |
%   write_L8_bip_txt                -                                                                       | obsolete |  |
%   readDataForAlbedoFrom           -                                                                       | obsolete |  |
