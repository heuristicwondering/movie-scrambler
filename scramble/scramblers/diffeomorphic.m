function warpedData = diffeomorphic( imgData, varargin )
%===========================================================================
% Create diffewarped images.
%   warpedData = diffeomorphic( imgData, warpParams );
%
% INPUT:
% imgData - data to be distorted. Distortion calculated along rows and and
%   columns with the same warp applied to each page if present (ex. data in
%   true color format). If multiple images provided (ex. disortorting an
%   entire movie), image frames must be concatenated along the 4th
%   dimensions. The same warp is applied to every image frame.
% 
% warpParams - optional set of warping parameters. This is provided as a 2
%   element numeric array in which the first element is the maximum amount  
%   of distortion applied to the image(s). The second element determines 
%   how many times a warp is applied to an image.
%
% OUTPUT:
% warpedData -- resampled data after applying warps.
%
% USAGE EXAMPLE:
%   imgData = repmat( checkerboard(40), [1,1,1,300] );
%   warpParameters = [10; 40];
%   
%   % add some movement to our checkerboard movie for illustration
%   step = 20;
%   for frame = 1:size(imgData,4)
%       splitIndx = rem( step*frame, size(imgData,2) ) + 1;
%       imgData(:,:,:,frame) = [ imgData(:,splitIndx:end,:,frame),imgData(:,1:splitIndx-1,:,frame) ];
%   end
% 
%   warpedImg = diffeomorphic( imgData, warpParameters );
%   
%   v = VideoWriter('originalmovie.avi'); open(v)
%   writeVideo(v,imgData); close(v)
%   v = VideoWriter('scrambledmovie.avi'); open(v)
%   writeVideo(v,warpedImg); close(v)
%
% Please reference: Stojanoski, B., & Cusack, R. (2014). Time to wave good-bye to phase scrambling: Creating controlled scrambled images using
% diffeomorphic transformations. Journal of Vision, 14(12), 6. doi:10.1167/14.12.6

% Rhodri Cusack and Bobby Stojanoski July 2013
% modified by Megan Finnegan July 2019

%===========================================================================

boundscheck( imgData, varargin{:} );

% this flag allows me to start a parallel pool externally


% setting warp paramters
maxdistortion=60; % changes max amount of distortion
nsteps=40; % number of steps
if numel(varargin) >= 1
    warpParams = varargin{1};
    maxdistortion = warpParams(1);
    nsteps = warpParams(2);
end

imszX= 2 * size(imgData, 1);
imszY = 2 * size(imgData, 2);
imszZ = size(imgData, 3);

[YI, XI]=meshgrid(1:imszY,1:imszX);

% creating a single warp to apply to all images
[cxA, cyA]=getdiffeo(imszX, imszY, maxdistortion,nsteps);
[cxB, cyB]=getdiffeo(imszX, imszY, maxdistortion,nsteps);
[cxF, cyF]=getdiffeo(imszX, imszY, maxdistortion,nsteps);

warpedData = zeros( size( imgData ) ); 
totalFrames = size(imgData, 4); % This is the number of frames/images to warp

spmd
   warning('off', 'MATLAB:mir_warning_maybe_uninitialized_temporary'); 
end

% applying warp
parfor i=1:totalFrames
    
    fprintf('\nApplying warp for image %i of %i.\n', i, totalFrames );
    
    P = imgData(:,:,:,i);
    Psz = [ size(P,1), size(P,2), size(P,3) ]; % including 3rd dim even if size is 1.
    
    % average value of image for background
    Im=ones(imszX,imszY,imszZ);
    for page = 1:imszZ
        Im(:,:,page) = Im(:,:,page) * mean( P(:,:,page), 'all' );
    end
    
    % Upsample by factor of 2 in two dimensions
    P2=zeros([2*Psz(1:2),Psz(3)]);
    P2(1:2:end,1:2:end,:)=P;
    P2(2:2:end,1:2:end,:)=P;
    P2(2:2:end,2:2:end,:)=P;
    P2(1:2:end,2:2:end,:)=P;
    P=P2;
    Psz=size(P);
    
    % Pad image if necessary
    x1=round((imszX-Psz(1))/2);
    y1=round((imszY-Psz(2))/2);
    
    Im((x1+1):(x1+Psz(1)),(y1+1):(y1+Psz(2)),:)=P;
        
    interpIm=Im;

    for quadrant=1:4
        switch (quadrant)
            case 1
                cx=cxA;
                cy=cyA;
            case 2
                cx=cxF-cxA;
                cy=cyF-cyA;
            case 3
                cx=cxB;
                cy=cyB;
            case 4
                cx=cxF-cxB;
                cy=cyF-cyB;
        end
        
        % prevent sampling out of bounds of the image
        cy=YI+cy;
        cx=XI+cx;
        mask=(cx<1) | (cx>imszX) | (cy<1) | (cy>imszY) ;
        cx(mask)=1;
        cy(mask)=1;
        

        for j=1:nsteps % this is the number of steps - Total number of warps is nsteps * quadrant
            for page = 1:imszZ
                interpIm(:,:,page)=interp2(double(interpIm(:,:,page)),cy,cx);
            end
        end
                
    end
    
    % down sampling to original dimensions
    warpedData(:,:,:,i) = interpIm(1:2:end, 1:2:end, :);
end

% cleaning up
% spmd
%    warning('on', 'MATLAB:mir_warning_maybe_uninitialized_temporary'); 
% end

end

function boundscheck(imgData, varargin)

imgDims = size(imgData);
if numel(imgDims) > 4
    error('diffeomorphic:TooManyDimensions', 'Expecting image(s) in no more than 4 dimensions.');
elseif numel(varargin) > 2
    error('diffeomorphic:TooManyInputs', 'Expecting only 1 or 2 inputs.');
elseif numel(varargin) >= 1
    option = varargin{1};
    err = 'Expecting 1 by 2 non-negative numeric array for warp parameters';
    if ~all( size(option) == [1, 2] | size(option) == [2, 1])
        error('diffeomorphic:IncorrectSize', err);
    elseif any( option < 0 )
        error('diffeomorphic:NegativeNumbersDisallowed', err);
    elseif any( option ~= round(option) )
        error('diffeomorphic:NonIntegersDisallowed', err);
    end
end

end

function [XIn, YIn]=getdiffeo(imszX, imszY, maxdistortion,nsteps)

ncomp=6;

[YI, XI]=meshgrid(1:imszY,1:imszX);

% make diffeomorphic warp field by adding random DCTs
ph=rand(ncomp,ncomp,4)*2*pi;
a=rand(ncomp,ncomp,2)*2*pi;
Xn=zeros(imszX,imszY);
Yn=zeros(imszX,imszY);

for xc=1:ncomp
    for yc=1:ncomp
        Xn=Xn+a(xc,yc,1)*cos(xc*XI/imszX*2*pi+ph(xc,yc,1)).*cos(yc*YI/imszY*2*pi+ph(xc,yc,2));
        Yn=Yn+a(xc,yc,2)*cos(xc*XI/imszX*2*pi+ph(xc,yc,3)).*cos(yc*YI/imszY*2*pi+ph(xc,yc,4));
    end
end

% Normalise to RMS of warps in each direction
Xn=Xn/sqrt(mean(Xn(:).*Xn(:)));
Yn=Yn/sqrt(mean(Yn(:).*Yn(:)));

YIn=maxdistortion*Yn/nsteps;
XIn=maxdistortion*Xn/nsteps;

end
