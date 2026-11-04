function net = gt_build_tcn(numFeatures,numClasses,cfg)
% 因果TCN：每块两层膨胀卷积；最后时刻输出。无跨时间归一化。
rf=1+2*(cfg.KernelSize-1)*sum(cfg.Dilations);
assert(cfg.SeqLength==rf,'GeneralTCN:RF','SeqLength应等于当前感受野%d。',rf);
net=dlnetwork;
net=addLayers(net,sequenceInputLayer(numFeatures,'Normalization','none','Name','input'));
previous='input';
for j=1:numel(cfg.Dilations)
    stem=sprintf('block%d_',j); d=cfg.Dilations(j);
    layers=[
        convolution1dLayer(cfg.KernelSize,cfg.NumFilters,'DilationFactor',d,'Padding','causal','Name',[stem 'conv1'])
        reluLayer('Name',[stem 'relu1'])
        dropoutLayer(cfg.Dropout,'Name',[stem 'drop1'])
        convolution1dLayer(cfg.KernelSize,cfg.NumFilters,'DilationFactor',d,'Padding','causal','Name',[stem 'conv2'])
        reluLayer('Name',[stem 'relu2'])
        dropoutLayer(cfg.Dropout,'Name',[stem 'drop2'])
        additionLayer(2,'Name',[stem 'add'])
        reluLayer('Name',[stem 'out'])];
    net=addLayers(net,layers);
    net=connectLayers(net,previous,[stem 'conv1']);
    if j==1
        net=addLayers(net,convolution1dLayer(1,cfg.NumFilters,'Name','input_projection'));
        net=connectLayers(net,previous,'input_projection');
        net=connectLayers(net,'input_projection',[stem 'add/in2']);
    else
        net=connectLayers(net,previous,[stem 'add/in2']);
    end
    previous=[stem 'out'];
end
head=[indexing1dLayer('last','Name','last_time')
    fullyConnectedLayer(numClasses,'Name','class_logits')
    softmaxLayer('Name','probabilities')];
net=addLayers(net,head); net=connectLayers(net,previous,'last_time');
end
