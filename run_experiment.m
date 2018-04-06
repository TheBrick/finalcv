function run_experiment (training_image_count_per_category, k, verbose)
    %% 2.1 feature extraction
    categories = {'airplanes', 'cars', 'faces', 'motorbikes'};

    % collect descriptors from n images from each category
    all_descriptors = extract_all_descriptors(categories, training_image_count_per_category);
    fprintf("extracted %i features\n", size(all_descriptors,2));

    %% 2.2 construct visual vocabulary (kmeans)
    [C, idx] = vl_ikmeans(all_descriptors, k);
    disp("constructed visual vocabulary");

    if verbose
        % display some centroids
        figure(1);
        for i = 1:9
            subplot(3,3,i);
            descriptor = C(:,i);
            vl_plotsiftdescriptor(descriptor);
        end
    end


    %% collect all training and test data
    testing_image_count_per_category = 50; % 50 = all test images
    [training_labels, training_histograms] = get_labeled_histograms_from_set(categories, 'train', training_image_count_per_category, training_image_count_per_category, C);
    [testing_labels, testing_histograms, testing_paths] = get_labeled_histograms_from_set(categories, 'test', testing_image_count_per_category, 0, C);
    disp("collected training and test data");

    %% construct training and test labels for 4 one-vs-all classifiers
    classifier_labels = cell(length(categories), 2);
    for i = 1:length(categories)
        classifier_labels{i, 1} = training_labels == i;
        classifier_labels{i, 2} = testing_labels == i;
    end

    %% train 4-class SVM just to test accuracy
%     fprintf("4-class classifier:  ");
%     model = train(training_labels, sparse(training_histograms), '-s 0 -q');
%     predictions = predict(testing_labels, sparse(testing_histograms), model);

    %% for each category, train and run one-vs-all classifier
    sorted_paths_per_category = cell(1, length(categories));
    APs = zeros(length(categories), 1);
    for i = 1:length(categories)
        category = categories{i}

        % train and run SVM model
        model = train(double(classifier_labels{i,1}), sparse(training_histograms), '-s 0 -q');
        [predictions, accuracy, decision_values] = predict(double(classifier_labels{i,2}), sparse(testing_histograms), model, '-q');
        predictions(1:10)
        decision_values(1:10)
        
        % sort predictions by confidence. The sign of the decision values is
        % determined by the first prediction: https://stackoverflow.com/questions/11030253/decision-values-in-libsvm
        % WELL NOT ALWAYS
        if sign(predictions(1)-0.5) == sign(decision_values(1))
            [sorted, idx] = sort(decision_values, 'descend');
        else
            [sorted, idx] = sort(decision_values, 'ascend');
        end
        sorted_labels = classifier_labels{i,2}(idx); % apply sorting to testing labels
        sorted_paths_per_category{i} = testing_paths(idx); % apply sorting to file paths (for HTML)

        % calculate MAP score
        n = length(sorted_labels);
        mc = testing_image_count_per_category;
        x = double(squeeze(sorted_labels'));
        x(x==1) = (1:mc); % convert [1 0 1 1 0 1] to [1 0 2 3 0 4]
        APs(i) = (1/mc) * sum(x ./ (1:n));

        % print results
        fprintf("one-vs-all classifier for %s:  %.1f%% accuracy, %.2f AP\n", category, accuracy(1), APs(i));
    end
    MAP = mean(APs);
    fprintf("MAP: %.3f\n", MAP);

    %% generate HTML file
    % load template
    template = fileread('Template_Result.html');

    % remove example body
    idx1 = strfind(template, '<tr><td><img src="Caltech4/ImageData/airplanes_test/img003.jpg"');
    idx2 = strfind(template, '</tbody>') -1;
    template = eraseBetween(template, idx1, idx2);

    % insert names and settings
    template = strrep(template, 'stu1_name, stu2_name', 'Daan Smedinga 10560963, Jens Dudink 11421479');
    template = strrep(template, 'SIFT step size</th><td>XXX px', sprintf('SIFT step size</th><td>%i px', 20));
    template = strrep(template, 'SIFT block sizes</th><td>XXX pixels', sprintf('SIFT block sizes</th><td>%i pixels', 1111111111));
    template = strrep(template, 'SIFT method</th><td>XXX-SIFT', sprintf('SIFT method</th><td>%s-SIFT', 'gray'));
    template = strrep(template, 'Vocabulary size</th><td>XXX words', sprintf('Vocabulary size</th><td>%i words', k));
    template = strrep(template, 'Vocabulary fraction</th><td>XXX', sprintf('Vocabulary fraction</th><td>%.2f', 0.5));
    template = strrep(template, 'SVM training data</th><td>XXX positive, XXX negative per class', sprintf('SVM training data</th><td>%i positive, %i negative per class', training_image_count_per_category, 3*training_image_count_per_category));
    template = strrep(template, 'SVM kernel type</th><td>XXX', sprintf('SVM kernel type</th><td>%s', 'default in LIBLINEAR (L2-regularized logistic regression (primal) solver)'));

    % insert MAP values
    template = strrep(template, 'Prediction lists (MAP: 0.XXX)', sprintf('Prediction lists (MAP: %.3f)', MAP));
    template = strrep(template, 'Airplanes (AP: 0.XXX)', sprintf('Airplanes (AP: %.3f)', APs(1)));
    template = strrep(template, 'Cars (AP: 0.XXX)', sprintf('Cars (AP: %.3f)', APs(2)));
    template = strrep(template, 'Faces (AP: 0.XXX)', sprintf('Faces (AP: %.3f)', APs(3)));
    template = strrep(template, 'Motorbikes (AP: 0.XXX)', sprintf('Motorbikes (AP: %.3f)', APs(4)));

    % insert lists of images
    htmlbody = '';
    for i = 1:length(testing_paths)
        htmlbody = strcat(htmlbody, '<tr>');
        for j = 1:length(categories)
            file_path = strrep(sorted_paths_per_category{j}{i}, '\', '\\');
            htmlbody = strcat(htmlbody, sprintf('<td><img src="%s" /></td>', file_path));
        end
        htmlbody = strcat(htmlbody, '</tr>');
    end
    template = strrep(template, '<tbody>', sprintf('<tbody> %s', htmlbody));

    filename = sprintf('MAP%.3f_%s-SIFT_%s_k%i_n%i.html', MAP, 'gray', 'dense', k, training_image_count_per_category);
    fid = fopen(filename, 'wt');
    fprintf(fid, template);
    fclose(fid);
end