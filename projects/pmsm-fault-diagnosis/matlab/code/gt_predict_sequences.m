function scores = gt_predict_sequences(net,X,cfg)
scores=minibatchpredict(net,X,'InputDataFormats','CTB','OutputDataFormats','BC', ...
    'MiniBatchSize',cfg.MiniBatchSize,'ExecutionEnvironment',cfg.ExecutionEnvironment);
if isa(scores,'dlarray'), scores=extractdata(scores); end
if isa(scores,'gpuArray'), scores=gather(scores); end
scores=double(scores);
assert(size(scores,1)==numel(X),'GeneralTCN:OutputShape','预测输出应为样本数×类别数。');
assert(all(isfinite(scores(:)))&&max(abs(sum(scores,2)-1))<1e-4, ...
    'GeneralTCN:Probabilities','预测概率维度或数值不正确。');
end
