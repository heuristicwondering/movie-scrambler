function [phaseShiftedSound, shifts] = phaseShift(snd,varargin)
%PHASESHIFT Adds random phase shifts to every frequency component.
%   Takes a time domain signal and decomposes it to its frequency components
%   by FFT. Random phase shifts are chosen from a uniform distribution such 
%   that they are bounded between 0 and maxShift and added to each frequency
%   Before reconstructing the signal. If multiple channels are provided the
%   same set of shifts is applied to both channels.
%
%   INPUT:
%   sound - This is the original sound data. columns are treated as channels
%   and rows as time points.
%
%   maxShift - This is the most any phase can be shifted (in radians). 
%
%   shifts - a column vector of (L/2-1) data specifying the amount of phase 
%   to be added to each frequency component. The phaseShifts returned from 
%   this function can be passed along with the original sound signal to 
%   reproduce the original scramble. If this value is provided, maxShift is 
%   silently ignored.
%
%   OUTPUT:
%   phaseShiftedSound - This is the sound that has been produced by
%   applying phase shifts.
%   
%   phaseShifts - This is the vector of phases that has been added to the
%   frequency components of the data. This allows for complete
%   resonstruction of the scrambled signal given the original data.

boundsCheck(snd, varargin{:});

L = size(snd, 1);
numChannels = size(snd,2);

if mod(L,2) == 1 % formatting data
   pad = zeros(1, numChannels);
   snd = [snd;pad];
   L = L + 1;
end

if numel(varargin) == 1
    maxShift = varargin{1};
    shifts = rand(L/2-1,1)*maxShift;    
else
    shifts = varargin{2};
end

shifts = repmat(shifts,1,numChannels);
constants = ones( 1, numChannels); % to account for signal mean

% note that shifts are added to one half of the spectrum and subtracted 
% from the other to satisfy the conjugate symmetry condition of the Fourier 
% transform for a real-valued signal.
shiftsPolarForm = [ constants; exp(1i*shifts); constants; exp(-1i*shifts) ];

freqDomainDataOriginal = fft( snd );
freqDomainDataShifted = freqDomainDataOriginal .* shiftsPolarForm;

% reconstructing the signal in the time domain
phaseShiftedSound = real( ifft(freqDomainDataShifted) );

shifts = shifts(:,1);

end

function boundsCheck(snd, varargin)

    if nargin < 2
        error('phaseShift:TooFewArguments', 'Need to specify the sound and upper bound of phase shifts (in radians) to apply.')
    elseif nargin > 3
        error('phaseShift:TooManyArguments', 'Too many arguments provided.')
    end

    if nargin == 3
        shifts = varargin{2};
        L = ceil( size(snd,1) ); % will zero pad odd sample amounts
        
        if size(shifts) ~= [L/2-1,1]
            error('phaseShift:IllFormedInput', ['Due to how FFT works, ]',...
                'there are only %i frequencies I can shift given the number ',...
                'of samples (%i) you provided.'], L/2-1, L);
        end
        
    elseif nargin == 2
        maxPhaseShift = varargin{1};
        pass = isnumeric(maxPhaseShift) && isscalar(maxPhaseShift) && numel(maxPhaseShift)==1;
        if ~pass
            error('phaseShift:IllFormedInput', 'Expecting second argument to be a single number.')
        end
        
    end
    
    numchannels = size(snd,2);
    if numchannels > 2
       warning('Detected %i channels. The same phase shifts will be applied to both channels', numchannels); 
    end
    
end