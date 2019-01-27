% ESPToolbox
% Version 1.4 (R2017b) 14-Aug-2018
%
% Functions
%
%   getJPLmodis                - getJPLmodis retrieves files from JPL MODSCAG website to a local folder


%   writeRectangleToCsv        - writeRectangleToCsv writes Rectangle shape coords to .csv file

%   saveStudyExtentGeolocation - saveStudyExtentGeolocation saves geotiffs of lat/lon and x,y


%   studyExtent                - studyExtent - information about a named study extent

%   ESPEnv                     - 
%   batchBrowse                - batchBrowse do batch of LandSat/MODIS browse images
%   batchReproject             - batchReproject reprojects a batch of typeOfData files to extentName
%   batch_getJPLmodis          - whichSet - string. Either 'historic' or 'NRT'
%   browseLandsat              - browseLandsat makes browse image of Landsat RGB, snow & masks
%   browseLandsatMODIS         - browseLandsatMODIS makes browse image of Landsat & MODIS files
%   canopyAdjLandsat           - canopyAdjLandsat returns canopy-adjusted fsca from mat file
%   contFSCALandsat            - contFSCALandsat returns continuous FSCA from mat file
%   getSaturationFromQcal      - getSaturationFromQcal finds pixels with bands 123 all saturated
%   landsatRGB                 - landsatRGB returns scaled bands 642 RGB from mat file
%   reprojectRaster            - [ B, RB, RRB] = reprojectRaster(A,RA,InStruct,OutStruct,... )
%   reprojectToStudyExtent     - reprojectToStudyExtent returns sensor data reprojected to StudyExtent
%   run_getJPLmodis            - tiles={'h23v05';'h24v05';'h25v06';'h22v04';'h22v05';'h23v04';'h23v06';'h24v04';...
%   scale2uint8                - scale2uint8 scales data to uint8 with NaNs set to 255
%   utmMstructFromTmInfo       - utmMstruct creates mstruct from the tmInfo struct

