% This script scrambles both the video and audio of selected movies.
%
% REQUIRES the Computer Vision System Toolbox.
% RECOMMENDED to also have the ffmpeg libaries installed and accessible via
% the command line.
%
% NOTES:
% -- this is not designed to handle very large movies.
%
% -- In cases were audio and video start at different times, scrambled 
% video and audio are centered so that there is equal silence/black-screen 
% on either side of the longer stream. This relies on the assumption that
% for most cases, this will be close enough to the true start time and was
% done because this metadata is not included in video objects in MATLAB.
% This is marked for fix on next release.
%
% -- Again, due to limitations in MATLAB, scrambled videos are
% uncompressed. An attempt to compress them is made by making a call to the
% ffmpeg libraries. If these are not installed and also (at least for 
% Windows) enabled on the the command line, then movies will need to be 
% compressed afterwards with a 3rd party software.
%
% An example of compressing generated video if you are using ffmpeg.
% This is the approach used in the current experiment.
%    ffmpeg -i ./scrambled-other_pos.avi -vcodec h264 -acodec mp2 ./scrabled-other_pos.mp4


ok = setup();
if ~ok; return; end

[files2scramble, folder2write2, warpParams, maxPhaseShift, ok] = getUserInput();
if ~ok; return; end

for path2movie = files2scramble
    
    clc
    [~, file, ext] = fileparts(path2movie{:});
    
    fprintf('####~~~~~~~~~~  Loading file %s  ~~~~~~~~~~####\n\n', [file, ext]);
    movie = LoadVid( path2movie );
    
    fprintf('\n####~~~~~~~~~~  Scrambling file %s  ~~~~~~~~~~####\n\n', [file, ext]);
    scrambledMovie = ScrambleVid( movie, warpParams, maxPhaseShift );
    
    fprintf('\n####~~~~~~~~~~  Writing file %s  ~~~~~~~~~~####\n\n', [file, ext]);
    moviefilename = WriteVid( scrambledMovie, folder2write2 );
    
    fprintf('\n####~~~~~~~~~~  Compressing file %s  ~~~~~~~~~~####\n\n', [file, ext]);
    CompressVid(moviefilename);
        
end

fprintf('\n\n\nThat''s it! All your files should now be scrambled.');
fprintf('\n\nIf you found this program useful, please consider sharing it.');


function ok = setup()
    % Check that user has the Computer Vision Toolbox installed.
    ok = true;
    hasIPT = license('test', 'Video_and_Image_Blockset');
    if ~hasIPT
      % User does not have the toolbox installed.
      message = sprintf('Sorry, but you do not seem to have the Computer Vision Toolbox.\nDo you want to try to continue anyway?');
      reply = questdlg(message, 'Toolbox missing', 'Yes', 'No', 'Yes');
      if strcmpi(reply, 'No')
        % User said No, so exit.
        ok = false;
        return
      end
    end
    
    % Add needed folders to path.
    [mpath, ~] = fileparts( mfilename('fullpath') );
    addpath( genpath( fullfile( mpath, 'scramblers') ) );
end

function [files2scramble, folder2write2, warpParams, maxPhaseShift, ok] = getUserInput()
    clc
    
    files2scramble = NaN; folder2write2 = NaN; %#ok<NASGU>
    warpParams = NaN; maxPhaseShift = NaN;
    
    fprintf('\n\nWelcome to the video scrambler.\n\n');
    fprintf('Please select the videos you''d like to scramble.\n');
    [files2scramble, folder] = uigetfile(['..', filesep, '*.*'], 'Multiselect', 'on');
        
    % formatting to a cell array of full file paths
    if ischar( files2scramble ) 
        files2scramble = {files2scramble};
    elseif isnumeric(files2scramble)
        if files2scramble == 0; ok = false; return; end % user pressed cancel
    end
    files2scramble = cellfun( @(file) fullfile(folder, file), files2scramble, 'un', false );

    clc

    fprintf('\n\nNow select the directory you''d like to write the files to.\n\n');
    folder2write2 = uigetdir( ['..', filesep] );
    if folder2write2 == 0; ok = false; return; end

    clc

    fprintf(['\n\nPlease specify the amount of distortion you''d like to apply ',...
        'to the video.\nHigher values mean more extreme warping. Values must be ',...
        'non-negative integers.\n']);
    fprintf(['\nNote that the total number of warps applied ',...
        'will be the number of steps times 4. \nSimilarily the max distortion is ',...
        '(roughly) the max number of pixels a pixel can move times 4.\n\n']);
    prompt = {'Enter maximum amount of distortion:','Enter number of warp steps:'};
    dlgtitle = 'Warp Paramaters';
    dims = [1 35];
    definput = {'20','10'};
    warpParams = inputdlg(prompt,dlgtitle,dims,definput);
    warpParams = cellfun(@str2num, warpParams);
    if isempty(warpParams); ok = false; return; end

    % bounds checking warp parameters
    isNegative = any( warpParams < 0 );
    isInteger = all( warpParams == round(warpParams) );
    if ~isInteger || isNegative
       fprintf('\nSetting ill-formed values to 0...\n');
       warpParams( warpParams < 0 ) = 0;
       warpParams( warpParams ~= round(warpParams) ) = 0;  
    end

    clc

    fprintf(['\n\nNow specify the maximum amount of phase shift you''d like to ',...
        'apply to the sound.\nThis is specified as radians. Symbolic expressions ',...
        'like those using ''pi'' are allowed.\n\nNote that 2*pi represents the largest ',...
        'amount of scrambling possible and is equivalent \nto noise produced at the '...
        'frequencies-amplitudes present in the original signal.\n\n']);
    prompt = {'Enter maximum amount of phase shifting:'};
    dlgtitle = 'Phase Shift Limit';
    dims = [1 35];
    definput = {'2*pi'};
    maxPhaseShift = inputdlg(prompt,dlgtitle,dims,definput);
    if isempty(maxPhaseShift); ok = false; return; end
    
    % evaluating and bounds checking
    try
        maxPhaseShift = eval(maxPhaseShift{:});
        if ~isscalar(maxPhaseShift) && ~isnumeric(maxPhaseShift)
            throwError
        end
    catch
       error('scramble:IllformedInput', 'Expression could not be evaluated.'); 
    end
    
    ok = true;
  
end

function movie = LoadVid( path2movie )
    
    % formatting to string array
    if iscell( path2movie ), path2movie = path2movie{:}; end
    
    
    % reading audio samples
    [movie.audio.data, movie.audio.Fs] = audioread( path2movie );
    
    % reading video frames
    movie.video = VideoReader( path2movie );
    movie.imgData = read(movie.video, [1, Inf]);
    
    
    % checking for possible variable frame rate since this will fail
    estNumFrames = movie.video.Duration * movie.video.FrameRate;
    numFrames = size( movie.imgData, 4 );
    
    if( round( estNumFrames ) ~= numFrames )
       warning('LoadVid:inconsistentFrameRate', ['The calculated number ',...
           'of frames does not match the actual number of frames.\n',...
           'This could be numerical errors or due to variable frame rate video ',...
           'which I am not \ndesigned to handle. This can cause audio/video ',...
           'sync problems. If you find this try \nconverting your samples to ',...
           'a constant frame rate first.\n']); 
    end
        
end

function scrambledMovie = ScrambleVid( movie, warpParams, maxPhaseShift )

    scrambledMovie = movie;
    
    % scramble audio -- only phase is distorted       
    [scrambledMovie.audio.data, scrambledMovie.audio.shifts4audio] = phaseShift(movie.audio.data, maxPhaseShift);
    
    % scramble video
    startPool = false; % preventing diffeomorphic from attempting to start it's own pool
    scrambledMovie.imgData = diffeomorphic(movie.imgData, warpParams, startPool);    
        
end

function filename = WriteVid( movie, path2movie )
    % create filenames to write to
    extIndx = regexp(movie.video.Name, '\.\w*$');
    filename = movie.video.Name( 1:extIndx-1 );
    filename = strcat( 'scrambled-', filename, '.avi' );
    phasesFilename = strcat( 'scrambled-', filename, '.mat' );
    filename = fullfile( path2movie, filename );
    phasesFilename = fullfile( path2movie, phasesFilename );
        
    movieWriter = vision.VideoFileWriter(filename,...
        'FileFormat', 'AVI',...
        'AudioInputPort', true,...
        'FrameRate', movie.video.FrameRate);
    
    % calculating how much audio to include per video frame
    audioSmplPerFrame = movie.audio.Fs / movie.video.FrameRate;
    
    % calculating how much padding is needed
    numAudioSmpls = size(movie.audio.data, 1);
    numAudioFrames = numAudioSmpls/audioSmplPerFrame;
    numVidFrames = size(movie.imgData, 4);
    
    % add padding
    w = ['Dectected mismatch between number of video and audio samples. \n',...
        'This may be because difference in start times however I am currently\n',...
        'centering shorter streams against the longer for simplicity. In most ',...
        'cases this should be ok but if this is causing problems for you, please ',...
        'send a feature request.\n\n'];
    
    if numAudioFrames < numVidFrames
        warning('Scramble:TooFewAudioSamples', w);
        totAudioSmplNeeded = numVidFrames * audioSmplPerFrame;
        AudioSmplMissing = totAudioSmplNeeded - numAudioSmpls;
        channels = size(movie.audio.data, 2);
        
        frontpad = zeros( ceil(AudioSmplMissing/2), channels );
        backpad = zeros( floor(AudioSmplMissing/2), channels );
        
        movie.audio.data = [frontpad; movie.audio.data; backpad];
    
    elseif numVidFrames < numAudioFrames
       error('Scramble:VideoPadding', ['Detected that there are fewer ',...
           'video frames than audio frames.\nStill need to write code to ',...
           'handle this. Please send a feature request if you need it.']); 
    end
        
    for frameIndx = 1:numVidFrames
        frame = rescale( movie.imgData(:,:,:,frameIndx) );
        
        audioStart = ( (frameIndx-1) * audioSmplPerFrame ) + 1;
        audioStop = frameIndx * audioSmplPerFrame;
        audio = movie.audio.data( audioStart:audioStop, : );
        
        step( movieWriter, frame, audio );
    end
    
    release(movieWriter);
    
    % Writing the audio phase shifts to file for record keeping purposes.
    info = 'These variables provide all the needed information to recreate the scrambled audio from the source data.';
    shifts4audio = movie.audio.shifts4audio;
    save(phasesFilename, 'shifts4audio', 'filename', 'info');
    
end

function ok = CompressVid(filename)
    % try to compress the video that was just written
    [p, f, ~] = fileparts(filename);
    newfilename = fullfile(p, [f, '.mp4']);
    call = sprintf('ffmpeg -i %s -vcodec h264 -acodec mp2 %s', filename, newfilename);
    status = system(call);
    if status == 0
        delete(filename) % cleaning up
    else
        warning('scramble:CompressionFailed', ['Failed to compress new data using the ',...
            'ffmpeg libraries. These may need to be installed on your system.']);
    end
end