function warpedData = diffeomorphic( imgData, varargin )
%===========================================================================
% Create diffewarped images.
%   warpedData = diffeomorphic( imgData, warpParams,  );
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
%   how many times a warp is applied to an image. Default if no argument is
%   provided is 60 and 40.
%
% usePool - optional flag to enable parallelization of applying warps
%   across movie frames. Default is false.
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

% setting warp paramters
maxdistortion=60; % changes max amount of distortion
nsteps=40; % number of steps
if numel(varargin) >= 1
    warpParams = varargin{1};
    maxdistortion = warpParams(1);
    nsteps = warpParams(2);
end

% this flag allows parrallel application of warps
usePool = false;
if numel(varargin) == 2
    usePool = varargin{2};
end

imsz.X= 2 * size(imgData, 1);
imsz.Y = 2 * size(imgData, 2);
imsz.Z = size(imgData, 3);

% average value of image for background
imgBackground=ones(imsz.X,imsz.Y,imsz.Z);
for page = 1:imsz.Z
    imgBackground(:,:,page) = imgBackground(:,:,page) * mean( imgData(:,:,page), 'all' );
end

[YI, XI]=meshgrid(1:imsz.Y,1:imsz.X);

% creating a single warp to apply to all images
[c.xA, c.yA]=getdiffeo(imsz.X, imsz.Y, maxdistortion,nsteps);
[c.xB, c.yB]=getdiffeo(imsz.X, imsz.Y, maxdistortion,nsteps);
[c.xF, c.yF]=getdiffeo(imsz.X, imsz.Y, maxdistortion,nsteps);

warpedData = zeros( size( imgData ) ); 
totalFrames = size(imgData, 4); % This is the number of frames/images to warp

% applying warp
if usePool
    parfor i=1:totalFrames   
        fprintf('\nApplying warp for image %i of %i.\n', i, totalFrames );

        warpedP = applydiffeo( imgData(:,:,:,i), imgBackground, imsz, YI, XI, c, nsteps);
        warpedData(:,:,:,i) = warpedP;
    end
else
    for i=1:totalFrames   
        fprintf('\nApplying warp for image %i of %i.\n', i, totalFrames );

        warpedP = applydiffeo( imgData(:,:,:,i), imgBackground, imsz, YI, XI, c, nsteps);
        warpedData(:,:,:,i) = warpedP;
    end
end


end

function boundscheck(imgData, varargin)

imgDims = size(imgData);
if numel(imgDims) > 4
    error('diffeomorphic:TooManyDimensions', 'Expecting image(s) in no more than 4 dimensions.');
elseif numel(varargin) > 2
    error('diffeomorphic:TooManyInputs', 'Expecting only 1 to 3 inputs.');
elseif numel(varargin) >= 1
    option = varargin{1};
    err = 'Expecting 1 by 2 non-negative numeric array for warp parameters';
    if ~all( size(option) == [1, 2] ) && ~all(size(option) == [2, 1])
        error('diffeomorphic:IncorrectSize', err);
    elseif any( option < 0 )
        error('diffeomorphic:NegativeNumbersDisallowed', err);
    elseif any( option ~= round(option) )
        error('diffeomorphic:NonIntegersDisallowed', err);
    end
end

end

function [XIn, YIn] = getdiffeo(imszX, imszY, maxdistortion, nsteps)

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

function [warpedP] = applydiffeo( P, imgBackground, imsz, YI, XI, c, nsteps)
    Psz = [ size(P,1), size(P,2), size(P,3) ]; % including 3rd dim even if size is 1.
            
    % Upsample by factor of 2 in two dimensions
    P2=zeros([2*Psz(1:2),Psz(3)]);
    P2(1:2:end,1:2:end,:)=P;
    P2(2:2:end,1:2:end,:)=P;
    P2(2:2:end,2:2:end,:)=P;
    P2(1:2:end,2:2:end,:)=P;
    P=P2;
    Psz=[ size(P,1), size(P,2), size(P,3) ];
    
    % Pad image if necessary 
    x1=round((imsz.X-Psz(1))/2);
    y1=round((imsz.Y-Psz(2))/2);
    
    imgBackground((x1+1):(x1+Psz(1)),(y1+1):(y1+Psz(2)),:)=P;
        
    interpIm=imgBackground;

    for quadrant=1:4
        switch (quadrant)
            case 1
                cx=c.xA;
                cy=c.yA;
            case 2
                cx=c.xF-c.xA;
                cy=c.yF-c.yA;
            case 3
                cx=c.xB;
                cy=c.yB;
            case 4
                cx=c.xF-c.xB;
                cy=c.yF-c.yB;
        end
        
        % prevent sampling out of bounds of the image
        cy=YI+cy;
        cx=XI+cx;
        mask=(cx<1) | (cx>imsz.X) | (cy<1) | (cy>imsz.Y) ;
        cx(mask)=1;
        cy(mask)=1;
        

        for j=1:nsteps % this is the number of steps - Total number of warps is nsteps * quadrant
            for page = 1:imsz.Z
                interpIm(:,:,page)=interp2(double(interpIm(:,:,page)),cy,cx);
            end
        end
                
    end
    
    % down sampling to original dimensions
    warpedP = interpIm(1:2:end, 1:2:end, :);
end
