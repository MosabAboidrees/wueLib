function [hdr] = read_brainvision_vhdr(filename)

% READ_BRAINVISION_VHDR reads the known items from the BrainVision EEG
% header file and returns them in a structure
%
% Use as
%   hdr = read_brainvision_vhdr(filename)
%
% See also READ_BRAINVISION_EEG, READ_BRAINVISION_VMRK

% Copyright (C) 2003, Robert Oostenveld
%
% This file is part of FieldTrip, see http://www.ru.nl/neuroimaging/fieldtrip
% for the documentation and details.
%
%    FieldTrip is free software: you can redistribute it and/or modify
%    it under the terms of the GNU General Public License as published by
%    the Free Software Foundation, either version 3 of the License, or
%    (at your option) any later version.
%
%    FieldTrip is distributed in the hope that it will be useful,
%    but WITHOUT ANY WARRANTY; without even the implied warranty of
%    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%    GNU General Public License for more details.
%
%    You should have received a copy of the GNU General Public License
%    along with FieldTrip. If not, see <http://www.gnu.org/licenses/>.
%
% $Id: read_brainvision_vhdr.m 7123 2012-12-06 21:21:38Z roboos $
  
[p, f, x] = fileparts(filename);
filename = fullfile(p,[f '.vhdr']);

hdr.DataFile         = read_asa(filename, 'DataFile=', '%s');
    
datafile = fullfile(p, hdr.DataFile);
info = dir(datafile);
if(isempty(info))
    datafile = fullfile(p, [f '.eeg']);
    info = dir(datafile);
    if isempty(info)
        error('cannot determine the location of the data file %s', hdr.DataFile);
    else
        hdr.DataFile = [f '.eeg'];
    end
end

hdr.MarkerFile       = read_asa(filename, 'MarkerFile=', '%s');
if(not(isempty(hdr.MarkerFile)))
markerfile = fullfile(p, hdr.MarkerFile);
info = dir(markerfile);
if(isempty(info))
    markerfile = fullfile(p, [f '.vmrk']);
    info = dir(markerfile);
    if isempty(info)
        error('cannot determine the location of the data file %s', hdr.MarkerFile);
    else
        hdr.MarkerFile = [f '.vmrk'];
    end
end
end
hdr.DataFormat       = read_asa(filename, 'DataFormat=', '%s');
hdr.DataOrientation  = read_asa(filename, 'DataOrientation=', '%s');
hdr.BinaryFormat     = read_asa(filename, 'BinaryFormat=', '%s');
hdr.NumberOfChannels = read_asa(filename, 'NumberOfChannels=', '%d');
hdr.SamplingInterval = read_asa(filename, 'SamplingInterval=', '%f');   % microseconds

if ~isempty(hdr.NumberOfChannels)
    for i=1:hdr.NumberOfChannels
        chan_str  = sprintf('Ch%d=', i);
        chan_info = read_asa(filename, chan_str, '%s');
        t = tokenize(chan_info, ',');
        hdr.label{i} = t{1};
        hdr.reference{i} = t{2};
        resolution = str2num(t{3});          % in microvolt
        if ~isempty(resolution)
            hdr.resolution(i) = resolution;
        else
            warning('Unknown resolution for channel %d in %s!', i, filename);
            hdr.resolution(i) = 1;
        end
        chanunit = str2num(t{4});          % in microvolt
        if ~isempty(chanunit)
            hdr.chanunit{i} = chanunit;
        else
%             warning('Unknown chanunit for channel %d in %s!', i, filename);
            hdr.chanunit{i} = 'uV';
        end
        if(numel(t)==5)
            hdr.chantype{i} = t{5};
        else
            hdr.chantype{i} = 'eeg';
        end
        hdr.layout.pos(i).type = hdr.chantype{i};
        hdr.layout.pos(i).labels = hdr.label{i};
        hdr.layout.pos(i).sph_theta_besa = [];
        hdr.layout.pos(i).sph_phi_besa = [];
    end
    if read_asa(filename, '[Coordinates]', '%s')
        for i=1:hdr.NumberOfChannels
            chan_str  = sprintf('Ch%d=1,', i);
            chan_info = read_asa(filename, chan_str, '%s');
            t = tokenize(chan_info, ',');
            hdr.layout.pos(i).sph_theta_besa = str2double(t{1});
            hdr.layout.pos(i).sph_phi_besa = str2double(t{2});
        end
    end
end

% compute the sampling rate in Hz
hdr.Fs = 1e6/(hdr.SamplingInterval);

% the number of samples is unkown to start with
hdr.nSamples = Inf;

% determine the number of samples by looking at the binary file
if strcmpi(hdr.DataFormat, 'binary')
    % the data file is supposed to be located in the same directory as the header file
    % but that might be on another location than the present working directory
    [p, f, x] = fileparts(filename);
    datafile = fullfile(p, hdr.DataFile);
    info = dir(datafile);
    if isempty(info)
        
        error('cannot determine the location of the data file %s', hdr.DataFile);
    end
    switch lower(hdr.BinaryFormat)
        case 'int_16';
            hdr.nSamples = info.bytes./(hdr.NumberOfChannels*2);
        case 'int_32';
            hdr.nSamples = info.bytes./(hdr.NumberOfChannels*4);
        case 'ieee_float_32';
            hdr.nSamples = info.bytes./(hdr.NumberOfChannels*4);
    end
elseif strcmpi(hdr.DataFormat, 'ascii') && strcmpi(hdr.DataOrientation, 'vectorized')
    % this is a very inefficient fileformat to read data from, it looks like this:
    % Fp1   -2.129 -2.404 -18.646 -15.319 -4.081 -14.702 -23.590 -8.650 -3.957
    % AF3   -24.023 -23.265 -30.677 -17.053 -24.889 -35.008 -21.444 -15.896 -12.050
    % F7    -10.553 -10.288 -19.467 -15.278 -21.123 -25.066 -14.363 -10.774 -15.396
    % F3    -28.696 -26.314 -35.005 -27.244 -31.401 -39.445 -30.411 -20.194 -16.488
    % FC1   -35.627 -29.906 -38.013 -33.426 -40.532 -49.079 -38.047 -26.693 -22.852
    % ...
    fid = fopen(hdr.DataFile, 'rt');
    tline = fgetl(fid);             % read the complete first line
    fclose(fid);
    t = tokenize(tline, ' ', true); % cut the line into pieces
    hdr.nSamples = length(t) - 1;   % the first element is the channel label
end

if isinf(hdr.nSamples)
    warning('cannot determine number of samples for this sub-fileformat');
end

% the number of trials is unkown, assume continuous data
hdr.nTrials     = 1;
hdr.nSamplesPre = 0;

% ensure that the labels are in a column
hdr.label      = hdr.label(:);
hdr.reference  = hdr.reference(:);
hdr.resolution = hdr.resolution(:);