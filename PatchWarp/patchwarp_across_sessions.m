function patchwarp_results = patchwarp_across_sessions(image1_all, image2_all, warp_blocksize, warp_overlap_pix_frac, warp_init_1st_affine)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% PatchWarp application to registration between different imaging sessions
% -------------------
% 
% Released by Ryoma Hattori
% Email: rhattori0204@gmail.com
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% General affine transformation parameters
transform = 'affine';
warp_pyramid_levels = 1;
warp_pyramid_iterations = 100;
warp_init_2nd_affine = [1 0 0; 0 1 0];

n_image_types = size(image1_all, 3);
for i = 1:n_image_types
    image1_all(:, :, i) = imnormalize(image1_all(:, :, i), 1, 32, 50);
    image2_all(:, :, i) = imnormalize(image2_all(:, :, i), 1, 32, 50);
end

%% Match the sizes of image1 and image2
x_list = zeros(2, 1);
y_list = zeros(2, 1);
[y_list(1), x_list(1)] = size(image1_all, [1, 2]);
[y_list(2), x_list(2)] = size(image2_all, [1, 2]);
[ymax, ymax_id] = max(y_list);
[xmax, xmax_id] = max(x_list);
temp_all = [];
if xmax_id == 1
    for i = 1:n_image_types
        temp = image2_all(:, :, i);
        temp = [temp, (prctile(temp(:), 30) - prctile(temp(:), 1)).*rand(size(temp, 1), abs(diff(x_list))) + prctile(temp(:), 1)];
        temp_all = cat(3, temp_all, temp);
    end
    image2_all = temp_all;
elseif xmax_id == 2
    for i = 1:n_image_types
        temp = image1_all(:, :, i);
        temp = [temp, (prctile(temp(:), 30) - prctile(temp(:), 1)).*rand(size(temp, 1), abs(diff(x_list))) + prctile(temp(:), 1)];
        temp_all = cat(3, temp_all, temp);
    end
    image1_all = temp_all;
end
temp_all = [];
if ymax_id == 1
    for i = 1:n_image_types
        temp = image2_all(:, :, i);
        temp = [temp; (prctile(temp(:), 30) - prctile(temp(:), 1)).*rand(abs(diff(y_list)), size(temp, 2)) + prctile(temp(:), 1)];
        temp_all = cat(3, temp_all, temp);
    end
    image2_all = temp_all;
elseif ymax_id == 2
    for i = 1:n_image_types
        temp = image1_all(:, :, i);
        temp = [temp; (prctile(temp(:), 30) - prctile(temp(:), 1)).*rand(abs(diff(y_list)), size(temp, 2)) + prctile(temp(:), 1)];
        temp_all = cat(3, temp_all, temp);
    end
    image1_all = temp_all;
end
    
% perhaps image1 needs to be larger than image2??

%% Get the 1st affine transformation matrix using the whole FOV
warp1_cell = cell(n_image_types, 1);
rho1 = zeros(n_image_types, 1);
for i = 1:n_image_types
    [~, warp1_cell{i}, ~, rho1(i)]= ecc_patchwarp(image2_all(:, :, i), image1_all(:, :, i), warp_pyramid_levels, warp_pyramid_iterations, transform, warp_init_1st_affine);
end

%% Apply the 1st affine transformation to the whole FOV
image2_affine1 = zeros(ymax, xmax, n_image_types);
for i = 1:n_image_types
    [~, rho1_max_id] = max(rho1);
    image2_affine1(:, :, i) = spatial_interp_patchwarp(image2_all(:, :, i), warp1_cell{rho1_max_id}, transform, 1:xmax, 1:ymax);
    zero_id = find(image2_affine1(:, :, i)==0);
    temp = image2_all(:, :, i);
    temp2 = image2_affine1(:, :, i);
    temp2(zero_id) = (prctile(temp(:), 30) - prctile(temp(:), 1)).*rand(size(zero_id, 1), 1) + prctile(temp(:), 1);
    image2_affine1(:, :, i) = temp2;
end

%% Get the x-y ranges of each patch for the 2nd piece-wise affine transformations
warp_overlap_pix = ceil(warp_overlap_pix_frac * (xmax/warp_blocksize));
qN_x = cell(warp_blocksize, warp_blocksize);
for i1 = 1:warp_blocksize
    qN_x{i1,1} = 1:ceil(xmax/warp_blocksize)+warp_overlap_pix;
    for i2 = 2:warp_blocksize-1
        qN_x{i1,i2} = (i2-1)*ceil(xmax/warp_blocksize)-warp_overlap_pix:i2*ceil(xmax/warp_blocksize)+warp_overlap_pix;
    end
    qN_x{i1,warp_blocksize} = (warp_blocksize-1)*ceil(xmax/warp_blocksize)-warp_overlap_pix:xmax;
end
qN_y = cell(warp_blocksize,warp_blocksize);
for i2 = 1:warp_blocksize
    qN_y{1,i2} = 1:ceil(ymax/warp_blocksize)+warp_overlap_pix;
    for i1 = 2:warp_blocksize-1
        qN_y{i1,i2} = (i1-1)*ceil(ymax/warp_blocksize)-warp_overlap_pix:i1*ceil(ymax/warp_blocksize)+warp_overlap_pix;
    end
    qN_y{warp_blocksize,i2} = (warp_blocksize-1)*ceil(ymax/warp_blocksize)-warp_overlap_pix:ymax;
end

%% Get the 2nd affine transformation matries using each of the subfield
warp2_cell = cell(warp_blocksize, warp_blocksize, n_image_types);
rho2 = NaN(warp_blocksize, warp_blocksize, n_image_types);
for i = 1:n_image_types
    for i1 = 1:warp_blocksize
        for i2 = 1:warp_blocksize
            [~, warp2_cell{i1, i2, i}, ~, rho2(i1, i2, i)]= ...
                ecc_patchwarp(image2_affine1(qN_y{i1, i2}, qN_x{i1, i2}, i),...
                image1_all(qN_y{i1, i2}, qN_x{i1, i2}, i),...
                warp_pyramid_levels, warp_pyramid_iterations, transform, warp_init_2nd_affine);
        end
    end
end

%% Apply the 2nd affine transformations to the subfields
image2_affine2 = zeros(ymax, xmax, n_image_types);
for i = 1:n_image_types
    image2_affine2_temp = cell(warp_blocksize, warp_blocksize);
    for i1 = 1:warp_blocksize
        for i2 = 1:warp_blocksize
            [~, rho2_max_id] = max(rho2(i1, i2, :));
            image2_affine2_temp{i1, i2} = spatial_interp_patchwarp(double(image2_affine1(qN_y{i1, i2}, qN_x{i1, i2}, i)), warp2_cell{i1, i2, rho2_max_id}, transform, 1:length(qN_x{i1, i2}), 1:length(qN_y{i1, i2}));
            image2_affine2_temp{i1, i2}(image2_affine2_temp{i1, i2}==0) = NaN;
        end
    end
    image2_affine2_temp = cell2mat(image2_affine2_temp);
    for i1 = 2:warp_blocksize
        image2_affine2_temp(qN_y{i1-1, 1}(end)-(2*warp_overlap_pix+1)+1:qN_y{i1-1, 1}(end), :) = ...
            nanmean(cat(3,image2_affine2_temp(qN_y{i1-1, 1}(end)-(2*warp_overlap_pix+1)+1:qN_y{i1-1, 1}(end), :)...
            , image2_affine2_temp(qN_y{i1-1, 1}(end)+1:qN_y{i1-1, 1}(end)+(2*warp_overlap_pix+1), :)),3);
        image2_affine2_temp(qN_y{i1-1, 1}(end)+1:qN_y{i1-1, 1}(end)+(2*warp_overlap_pix+1), :) = [];
    end
    for i2 = 2:warp_blocksize
        image2_affine2_temp(:, qN_x{1, i2-1}(end)-(2*warp_overlap_pix+1)+1:qN_x{1, i2-1}(end)) = ...
            nanmean(cat(3, image2_affine2_temp(:, qN_x{1, i2-1}(end)-(2*warp_overlap_pix+1)+1:qN_x{1, i2-1}(end))...
            , image2_affine2_temp(:, qN_x{1, i2-1}(end)+1:qN_x{1, i2-1}(end)+(2*warp_overlap_pix+1))), 3);
        image2_affine2_temp(:, qN_x{1, i2-1}(end)+1:qN_x{1, i2-1}(end)+(2*warp_overlap_pix+1)) = [];
    end
    nan_elements = find(isnan(image2_affine2_temp));
    image2_affine2_temp(nan_elements) = (prctile(image2_affine2_temp(~isnan(image2_affine2_temp)), 30) - prctile(image2_affine2_temp(~isnan(image2_affine2_temp)), 1)).*rand(length(nan_elements), 1) + prctile(image2_affine2_temp(~isnan(image2_affine2_temp)), 1);
    image2_affine2(:, :, i) = image2_affine2_temp;
end

patchwarp_results.image1_all = image1_all;
patchwarp_results.image2_all = image2_all;
patchwarp_results.x_list = x_list;
patchwarp_results.y_list = y_list;
patchwarp_results.warp_blocksize = warp_blocksize;
patchwarp_results.warp_overlap_pix_frac = warp_overlap_pix_frac;
patchwarp_results.n_image_types= n_image_types;
patchwarp_results.warp_overlap_pix = warp_overlap_pix;
patchwarp_results.xmax = xmax;
patchwarp_results.ymax = ymax;
patchwarp_results.qN_x = qN_x;
patchwarp_results.qN_y = qN_y;
patchwarp_results.transform = transform;
patchwarp_results.warp_pyramid_levels = warp_pyramid_levels;
patchwarp_results.warp1_cell = warp1_cell;
patchwarp_results.warp2_cell = warp2_cell;
patchwarp_results.rho1 = rho1;
patchwarp_results.rho2 = rho2;
patchwarp_results.image2_affine1 = image2_affine1;
patchwarp_results.image2_affine2 = image2_affine2;

end