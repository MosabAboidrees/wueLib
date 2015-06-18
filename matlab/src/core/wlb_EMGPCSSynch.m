function status = wlb_EMGPCSSynch(varargin)
%WLB_TENSSYNCH synchronize multiple files in the same vhdr/eeg file
%	FLAG = WLB_TENSSYNCH(VARARGIN) I'll edit it when it will be ready

% Edited 2015-06-15 by Gabriele Arnulfo <gabriele.arnulfo@gmail.com>

		p = inputParser;
		p.addRequired('path_emg',@ischar);
		p.addRequired('path_pcs',@ischar);
		p.addRequired('outdir',@ischar);

		p.addOptional('path_events',[],@ischar)
		p.addOptional('fnameFilters',{[]},@iscell);

		p.addOptional('pcsRefChannel',1,@isnumeric);
		p.addOptional('pcsCuttingTime',0,@isnumeric);
		p.addOptional('emgCuttingTime',0,@isnumeric);

		p.parse(varargin{:});

		path_pcs = p.Results.path_pcs;
		path_emg = p.Results.path_emg;
		path_events = p.Results.path_events;
		fnameFilters = p.Results.fnameFilters;

		% get filenames within each path
		pcsFileNames = dir(fullfile(path_pcs,'*PCS.xml'));
		emgFileNames = dir(fullfile(path_emg,'*EMG.txt'));

		% check whether we have the same number of files 
		assert(checkDataConsistency(pcsFileNames,emgFileNames));


%		pcsFileNames = filterFnames(pcsFileNames,fnameFilters);
%		emgFileNames = filterFnames(emgFileNames,fnameFilters);


		eventsInfo = [];
		if ~isempty(p.Results.path_events)
			eventsInfo					= wlb_readExternalEventFile( path_events );
		end

		for fileIdx = 1 : numel(pcsFileNames)

				pcsFname = pcsFileNames(fileIdx).name;
				emgFname = emgFileNames(fileIdx).name;

				% read pcs header file
				[pcs_hdr, pcs_data] = wlb_readActivaPC( pcsFname );
				[emg_hdr, emg_data] = wlb_readEMG_wue( emgFname );
			 
				% cut data if needed
				pcs_data = pcs_data(:,(p.Results.pcsCuttingTime*...
						pcs_hdr.SenseChannelConfig.TDSampleRate)+1:end);
				emg_data = emg_data(:,(p.Results.emgCuttingTime*emg_hdr.freq)+1:end);

				% pick the first channel
				pcs_ch_idx = p.Results.pcsRefChannel;
				emg_ch_idx = find(ismember(emg_hdr.labels,'artefakt')==1);

				pcs_ch = pcs_data(pcs_ch_idx,:);
				emg_ch = emg_data(emg_ch_idx,:);
			
				% search for the TENS artefact 
				pcs_locs = findTENSArtefact(pcs_data(pcs_ch_idx,:),pcs_hdr.SenseChannelConfig.TDSampleRate);
				emg_locs = findTENSArtefact(emg_data(emg_ch_idx,:),emg_hdr.freq);

				method = min([length(pcs_locs)/2,length(emg_locs)/2]);
				pcs_locs = pcs_locs(1:method*2);
				emg_locs = emg_locs(1:method*2);
				
				% actually compute t0 for all channels
				data_cell = [{pcs_ch},{emg_ch}];
				
				t0 = cellfun(@find_t_init,data_cell,{pcs_locs,emg_locs},...
							{method, method},'uni',false);

				t0 = reshape([t0{:}],2,2)';
					 
				if( method == 2 )
						% estimate the correct fs for PCS
						pcs_fs = (t0(2,2)-t0(2,1))* emg_hdr.Fs /(t0(1,2)-t0(1,1));
				else
						% use default
						t0(:,2) = [length(pcs_ch) length(emg_ch)];
						if pcs_hdr.SenseChannelConfig.TDSampleRate > 422
							pcs_fs = 793.65;
						else
							pcs_fs = 422;
						end
				end
					 
				% downsample pcs data to integer sampling frequency and eeg accordingly
				fs 							= 400;
				[pcs_data,~,~] 	= ResampleCascade(pcs_data,fs,pcs_fs);
				emg_data 				= resample(emg_data',fs,emg_hdr.freq)';
				
				% each t0 row represent eeg,pcs,emg data before
				% we have to recompute the exact point in time after
				% resampling
				t0(2,:) = (round(t0(2,:)/emg_hdr.freq*pcs_fs));
				t0 			= round(t0/pcs_fs*fs);
							 
				% also compute the sample indices fo each events with new sampling freq
				for evIdx = 1:numel(eventsInfo)
						eventsInfo(evIdx).samples = round(eventsInfo(evIdx).times * fs)...
								+ min(t0(:,1));

						eventsInfo(evIdx).times	 = eventsInfo(evIdx).times + min(t0(:,1))/fs;
				end


				% t0 has start and end samples foreach channel
				% cut data to have the same number of samples
				onset  			= min(t0(:,1));
				off 		 		= [1 -1;1 -1] * onset ;
				data_wnd		= t0 - off;

				pcs_data_out 	= pcs_data(:,1+data_wnd(1,1):...
						min([data_wnd(1,2),length(pcs_data)]));

				emg_data_out 	= emg_data(:,1+data_wnd(2,1):...
						min([data_wnd(2,2),length(emg_data)]));
				
				final_size   	= min([size(pcs_data_out,2),....
														size(emg_data_out,2)]);
				data_out 	 		= [pcs_data_out(:,1:final_size);...
												emg_data_out(:,1:final_size)];
				
				pcs_channels	= size(pcs_data,1);
				emg_channels  = size(emg_data,1);
				
				if(pcs_channels == 1)
						data_out  = [data_out; zeros(1,size(data_out,2))];
						pcs_channels = 2;
				end
				
				pcs_hdr.labels(end+1) 	= {'none'};
				pcs_hdr.chanUnits(pcs_channels) = {'mV'};
				out_hdr.chanunit = [pcs_hdr.chanUnits, emg_hdr.units];
				
				wnd_plot = -100:100;
				figure(1), clf
				subplot(211)
				hold on, plot(pcs_data(pcs_ch_idx,wnd_plot + t0(1)).*1e5,'r');
				plot(emg_data(emg_ch_idx,wnd_plot + t0(2)),'k');

				if(method == 2)
						subplot(312)
						hold on, plot(pcs_data(pcs_ch_idx,wnd_plot + t0(3)).*10,'r');
						plot(emg_data(emg_ch_idx,wnd_plot+ t0(4)),'k');
				end
				drawnow
				
				% update header info
				out_hdr.label 	= [pcs_hdr.labels';emg_hdr.labels'];
				out_hdr.nChans 	= pcs_channels + emg_channels;
				out_hdr.NumberOfChannels = out_hdr.nChans;
				out_hdr.Fs			= fs;
				out_hdr.chanunit(out_hdr.nChans) = {'mV'};
				
				for ii = 1:2

						stn_pos_struct(ii)  = struct('type','stn',...
								'labels',pcs_hdr.labels(ii),...
								'sph_theta_besa',-134,...
								'sph_phi_besa',-45);
				end

				for ii = 1:emg_channels

						emg_pos_struct(ii)  = struct('type','emg',...
								'labels',emg_hdr.labels(ii),...
								'sph_theta_besa',-134,...
								'sph_phi_besa',-45);

				end
				
				out_hdr.layout.pos = [stn_pos_struct, emg_pos_struct];
				out_hdr.chantype(out_hdr.nChans) = {'other'};
				
				% this is the only supported data format
				out_hdr.DataFormat      = 'BINARY';
				out_hdr.DataOrientation = 'MULTIPLEXED';
				out_hdr.BinaryFormat    = 'IEEE_FLOAT_32';

				% no additional calibration needed, since float32
				out_hdr.resolution      = ones(size(out_hdr.label));      

				% write data
				[~, fname_pcs, ~] = fileparts(pcsFname);
				filename = strcat(fname_pcs,'_EMG');
				
				out_hdr.DataFile = strcat(filename,'.eeg');
				out_hdr.MarkerFile = strcat(filename,'.vmrk');
				
				write_brainvision_eeg(p.Results.outdir, out_hdr, data_out);
				write_brainvision_vmrk(p.Results.outdir, out_hdr, eventsInfo);
				write_brainvision_vhdr(p.Results.outdir, out_hdr);

				status = 0;
		end % for files
end % function

function tau = find_t_init(D,locs,chunks)
%FIND_T_INIT Description
%	TAU = FIND_T_INIT(D,LOCS,CHUNKS) Long description
%

% number of levels used for WICA and wavelet family
num_lvl   = 8;
vfilter   = 'db1';

% below we separate the portions containing the TENS artefacts

tau = [0 0];

for chunk = 0:chunks-1
    
    artefact_duration = locs(2+2*chunk)-locs(1+2*chunk);
    if((locs(2+2*chunk)+artefact_duration)<=length(D))
        data0 				= D(locs(1+2*chunk):(locs(2+2*chunk)+artefact_duration));
    else
        data0 				= D(locs(1+2*chunk):end);
    end
    data 				= data0;

    nsamples    = length(data);
    offset      = ceil(nsamples/(2^num_lvl)) * (2^num_lvl);
    
    data(nsamples+1:offset) = zeros(1,offset-nsamples);
    
    [thr, ~, ~] = ddencmp('den','wv',data);
    
    [swa, swd] = swt(data,num_lvl, vfilter);

    swd(abs(swd) < thr) = 0;
    swd(3:num_lvl,:) = zeros(size(swd(3:num_lvl,:)));
    swa = zeros(size(swa));
    
    out = iswt(swa,swd,vfilter)';
    out = out(1:nsamples);
    thresh = 2*std(abs(out((artefact_duration+1):end)));
    
    out( abs(out) <  std(out) ) = 0;
    
    [~, max_locs] = findpeaks((out),'MINPEAKHEIGHT',thresh);
    [~, min_locs] = findpeaks(-(out),'MINPEAKHEIGHT',thresh);  

    data_locs = max(max(max_locs),max(min_locs));
    
%     figure,
%     subplot(2,1,1), plot(t,out,t(data_locs),out(data_locs),'rx');
%     subplot(2,1,2), plot(t,data0,t(data_locs),data0(data_locs),'rx');
    
    tau(chunk+1) = data_locs + locs(1+2*chunk)-1;
end

end

function [x,Pfac,Qfac] = ResampleCascade(x,NewRate,OldRate,Method)
    % Default method: 'resample'
    if (nargin < 4)
        Method = 'resample';
    end
    % Common factors
    [P,Q] = rat(NewRate/OldRate);
    % We want to upsample by P and downsample by Q to achieve the new rate
    % But big numbers cause problems.
    Pfac = factor(P);
    Qfac = factor(Q);
    % Longest number of factors
    iFacs = max(length(Pfac),length(Qfac));
    % Pad the shorter one to have unity factors
    Pfac((length(Pfac)+1):iFacs) = 1;
    Qfac((length(Qfac)+1):iFacs) = 1;

    % So now we have two factorization lists of the same length, and
    % prod(Pfac) / prod(Qfac) = P/Q.
    Pfac = sort(Pfac,'descend'); % upsample largest first
    Qfac = sort(Qfac,'ascend'); % downsample smallest rates first
    Rates = Pfac./Qfac;  % rates per step
    CRate = cumprod(Rates); % cumulative resampling rates

    % We can't go below min(1,P/Q) without losing information. Because of low-pass filtering, 
		% don't be too precise
    Problem = CRate < (0.9 * P/Q);
    if any(Problem)
        fprintf(1, 'RESAMPLE> Warning: Desired rate is %.f\n', P/Q);
    end
    if any(Pfac > 10)
        disp(['RESAMPLE> Warning: Upsampling by more than 10 in the cascades, P = ' sprintf('%d ', Pfac)]);
    end
    if any(Qfac > 10)
        disp(['RESAMPLE> Warning: Downsampling by more than 10 in the cascades, Q = ' sprintf('%d ', Qfac)]);
    end

    % ===== RESAMPLING =====
    switch Method
        % Decimate/interp inputs cannot be vectorized
        case 'decimate'
            % Initialize output parameters
            len_resmp = ceil(size(x,2) * prod(Pfac) / prod(Qfac));
            nRow = size(x,1);
            x_resmp = zeros(nRow, len_resmp);
            % Loop on factors and rows
            for iRow = 1:size(x,1)
                x_tmp = x(iRow,:);
                for i = 1:iFacs
                    x_tmp = decimate(interp(x_tmp, Pfac(i)), Qfac(i));
                end
                x_resmp(iRow,:) = x_tmp;
            end
            x = x_resmp;
        % Resample takes vectorized inputs
        case 'resample'
            for i = 1:iFacs
                x = resample(x', Pfac(i), Qfac(i))';
            end
    end
end

function fnames = filterFnames(fnames,pattern)
%FILTERFNAMES Description
%	FNAME = FILTERFNAMES(FNAMES,PATTERN) Long description
%
		
		tmp = [{fnames.name}];
		mask = ~cellfun(@isempty,regexp(tmp,pattern));
		fnames = fnames(mask);
end

function bool = checkDataConsistency(fname_mod1, fname_mod2)
%CHECKDATACONSISTENCY Description
%	BOOL = CHECKDATACONSISTENCY(FNAME_MOD1, FNAME_MOD2) Long description
%

		fname_mod1 = [{fname_mod1.name}];
		fname_mod2 = [{fname_mod2.name}];

		[~,mod1,~] = cellfun(@fileparts,fname_mod1,'uni',false);
		[~,mod2,~] 	= cellfun(@fileparts,fname_mod2,'uni',false);

		nMod1Files = numel(mod1);
		nMod2Files = numel(mod2);

		nMatchingFiles = sum(ismember(mod1,mod2));

		if nMod1Files == nMod2Files || nMatchingFiles == Mod1Files
				bool = true;
		else
				bool = false;
		end
end


function locs = findTENSArtefact(data,fs)
%FINDTENSARTEFACT data [1xN] time samples
%	LOCS = FINDTENSARTEFACT(DATA) Long description

		data = abs(data);

		data_bp = wlb_bandpass_fft(data, fs, 90, 110,1,1,[]);
		data_bp(:,:,2) = wlb_bandpass_fft(data, fs, 190, 210, 1,1,[]);
		data_bp(:,:,3) = wlb_bandpass_fft(data, fs, 290, 310, 1,1,[]);
		data_bp = wlb_bandpass_fft(mean(abs(data_bp(:,:,:)),3), fs, .001, 1, 1,1,[]);

		thr = 3*std(data_bp);
		[pks,locs] = findpeaks(data_bp,'MINPEAKHEIGHT',thr,'MINPEAKDISTANCE',10*fs);
		if(length(locs)>2)
				[val,~] = sort(pks,'descend');
				thr = val(3)+2*eps;
		end

		[locs] = find(abs(diff((data_bp>thr))));
		if(length(locs)==3)
				start_end = find(diff(locs)>5*fs);
				if (start_end == 1)
						locs = [1 locs];
				else
						locs = locs(1:2);
				end
		end



end