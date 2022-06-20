%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%                                %%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%      DECLIPPING MAIN FILE      %%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%    Analysis Social Sparsity    %%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%           (all sounds)         %%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%                                %%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%
% The implementation of the Analysis version of Social Sparsity Declipper.
% Pavel Z�vi�ka, Brno University of Technology, 2022
%
% using toolbox LTFAT
ltfatstart;

addpath('Tools')
addpath('Sounds')
addpath(genpath('Evaluation_algorithms'))

% Database
sounds = {'a08_violin', 'a16_clarinet', 'a18_bassoon', 'a25_harp', 'a35_glockenspiel', 'a41_celesta', ...
    'a42_accordion', 'a58_guitar_sarasate', 'a60_piano_schubert', 'a66_wind_ensemble_stravinsky'};
fs = 44100;

shrinkage = 'PEW'; % 'L', 'WGL', 'EW', 'PEW';
input_SDRs = [1, 3, 5, 7, 10, 15, 20];

% load audio samples
load('Sounds\Sound_database.mat')

% set weighting
weighting = false; % enable parabola-based weights

% set verbose mode
verbose = false;

% initialization of matrices for SDR and dSDR values, and computational time
SDR = NaN(length(sounds), length(input_SDRs));
dSDR = NaN(length(sounds), length(input_SDRs));
TIME = NaN(length(sounds), length(input_SDRs));

% initialization of counter
cnt = 0;


for sound = 1:length(sounds)
    for clip_idx = 1:length(input_SDRs)
        
        cnt = cnt + 1;
        % load audio-file
        data = eval(sounds{sound});
        
        % signal length
        Ls = length(data);
        
        
        %% settings
        % input SDR of the clipped signal
        inputSDR = input_SDRs(clip_idx);    % set (symetric) clipping threshold
        
        % DGT parameters
        wtype = 'hann';   % window type
        w = 8192;         % window length
        a = w / 4;  % window shift
        M = 2*8192;       % number of frequency channels
        
        % clipping
        [data_clipped, masks, theta, ~, ~] = clip_sdr(data, inputSDR); % clipping of original signal
        
        data_r = zeros(Ls,1);
        data_r(masks.Mr) = data_clipped(masks.Mr);
        
        data_c = zeros(Ls,1);
        data_c(masks.Mh) = theta;
        data_c(masks.Ml) = -theta;
        
        % construction of the frame
        g = gabwin({'tight', {'hann', w}}, a, M);
        
        G_clip = dgtreal(data_clipped, g, a, M);
        [nf,nt] = size(G_clip);
        
        gab.analysis = @(x) dgtreal(x,g,a,M);
        gab.synthesis = @(x) idgtreal(x,g,a,M,Ls);
        
        % Setting of the Shrinkage operator
        shrinkL   = struct('type', 'l', 'lambda', 1e-4, 'mu', 1, 'glabel', 'time','neigh', 1, 'center', [1 1], 'expo', 1,'orth',0);
        shrinkWGL = struct('type', 'l', 'lambda', 1e-4, 'mu', 1, 'glabel', 'time','neigh', ones(3,7), 'center', [2,4], 'expo', 1,'orth',0);
        shrinkEW  = struct('type', 'l', 'lambda', 1e-4, 'mu', 1, 'glabel', 'time','neigh', 1, 'center', [1 1], 'expo', 2,'orth',0);
        shrinkPEW = struct('type', 'l', 'lambda', 1e-4, 'mu', 1, 'glabel', 'time','neigh', ones(3,7), 'center', [2,4], 'expo', 2,'orth',0);
        
        switch shrinkage
            case 'L'
                shrink = shrinkL;
            case 'WGL'
                shrink = shrinkWGL;
            case 'EW'
                shrink = shrinkEW;
            case 'PEW'
                shrink = shrinkPEW;
            otherwise
                error('Invalid shrinkage operator!')
        end

        % construction of weights
        if weighting == true
            shrink.weights = comp_weights(0, fs/2, floor(M/2)+1, fs/2, 2);
        end
        

        %% Loris-Verhoeven algorithm
        tic
        
        number_lambdas = 20;
        inner_iterations = 500;
        delta = 1e-4;
        iter_cnt = 0;
        
        dSDR_process = NaN(number_lambdas*inner_iterations, 1);
        data_rec = data_clipped;
        
        x = data_rec;
        u = gab.analysis(data_rec);
        l = data_rec;

        tau = 1.5;
        sigma = 1/tau;
        rho = 1;
        
        for lambda=logspace(-1,-4,number_lambdas)
            shrink.lambda_orig = lambda;
            for k=1:inner_iterations
                
                data_rec_old = data_rec;
                iter_cnt = iter_cnt + 1;
                
                % compute b (gradient of h)
                r1 = zeros(Ls, 1);
                r1(masks.Mr) = x(masks.Mr) - data_r(masks.Mr); %ok

                r2 = zeros(Ls, 1);
                r2(masks.Mh) = data_c(masks.Mh) - x(masks.Mh);
                r2(masks.Ml) = data_c(masks.Ml) - x(masks.Ml);

                r2(abs(x)>theta) = 0;
                r2 = -r2;

                b = r1 + r2;

                % u update
                uu = u + sigma*gab.analysis(x - tau*(b+l));
                shrink.lambda = shrink.lambda_orig ./ sigma;
                u_half = uu - sigma*gen_thresh(uu./sigma, shrink); % Moreau identity

                % l update
                l_half = gab.synthesis(u_half);

                % x,u,l updates
                x = x - rho * tau * (b + l_half);
                u = u + rho * (u_half - u);
                l = l + rho * (l_half - l);

                data_rec = x;
                if norm(data_rec_old - data_rec) < delta
                    break
                end
                
                                
                if verbose == true
                    sdr_rec = sdr(data, data_rec);
                    fprintf('  lambda = %f -- it = %d -- SDR = %f -- dSDR = %f \n',lambda,k,sdr_rec,sdr_rec-input_SDRs(clip_idx));
                end
                
            end
        end
        
        time = toc;
        
        %% Evaluation of the results
        % Time
        TIME(sound, clip_idx) = time;
        
        % Save restored file
        eval([sounds{sound} '_rec_ASS_' shrinkage '_' num2str(input_SDRs(clip_idx), '%02d') ' = data_rec;']);
        
        % SDR
        sdr_clip = sdr(data, data_clipped);
        sdr_rec = sdr(data, data_rec);
        
        SDR(sound, clip_idx) = sdr_rec;
        dSDR(sound, clip_idx) = sdr_rec - sdr_clip;
        
        
        disp(['Done: ' num2str(cnt), '/70'  ]);
        
        %save(['Results/ASS_' shrinkage '_Sounds_ALL.mat']);
        
    end
end
