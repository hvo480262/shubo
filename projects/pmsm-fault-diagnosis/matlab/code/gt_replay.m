function result=gt_replay(modelPath,rawPath)
% 对新记录用冻结模型回放；不重新拟合标准化、不调整阈值、不训练。
if nargin<1
    [a,b]=uigetfile('*.mat','选择trained_model.mat'); if isequal(a,0), result=[]; return; end
    modelPath=fullfile(b,a);
end
if nargin<2
    [a,b]=uigetfile('*.mat','选择带原始iabc的MAT'); if isequal(a,0), result=[]; return; end
    rawPath=fullfile(b,a);
end
A=load(modelPath,'Model'); assert(isfield(A,'Model')); M=A.Model; c=M.cfg;
D=gt_read(rawPath); m=D.metadata;
assert(ismember(string(m.faultType),M.classes),'GeneralTCN:NewClass', ...
    '模型还没学过%s。请加入该类训练数据后重新运行START_HERE。',m.faultType);
assert(isfield(c,'FeatureMode'),'GeneralTCN:OldModel','旧v4模型请用旧版gt_replay，新特征必须重新训练。');
r=gt_record_features(D,c);
r.id=D.id; r.label=string(m.faultType); r.eventKind=string(m.eventKind);
r.eventTime_s=m.eventTime_s; r.torque_Nm=m.torque_Nm; r.speed_rpm=m.speed_rpm;
assert(r.time_s(c.SeqLength)<r.eventTime_s,'GeneralTCN:Warmup','新记录事件前历史不足。');
assert(gt_relative_cycles(r,r.time_s(end))>=c.EvaluateAfterCycles, ...
    'GeneralTCN:Coverage','新记录的事件后覆盖不足评估时段。');
[X,~,t]=gt_sequences(r,M.columns,M.mu,M.sigma,c,false);
s=gt_predict_sequences(M.net,X,c); [metrics,P]=gt_score(r,t,s,M.calibration,c);
folder=fullfile(fileparts(modelPath),['replay_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]); mkdir(folder);
c.ModelNames=M.name; gt_prediction_plot(r,{P},c,fullfile(folder,'prediction.png'));
writetable(struct2table(metrics),fullfile(folder,'record_metrics.csv'));
save(fullfile(folder,'prediction.mat'),'P','metrics','modelPath','rawPath');
result=struct('outputFolder',folder,'metrics',metrics); disp(metrics); fprintf('回放已保存：%s\n',folder);
end
