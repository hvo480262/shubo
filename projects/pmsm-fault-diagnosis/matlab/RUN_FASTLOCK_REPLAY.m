function result=RUN_FASTLOCK_REPLAY(modelPath,rawPath,threshold)
% RUN_FASTLOCK_REPLAY(trained_model.mat, one_raw.mat)
% Optional threshold is exploratory; default is the FROZEN model calibration.
root=fileparts(mfilename('fullpath')); addpath(fullfile(root,'code'));
if nargin<1||isempty(modelPath)
    [f,p]=uigetfile('*.mat','选择冻结的 trained_model.mat');
    if isequal(f,0), result=[]; return; end; modelPath=fullfile(p,f);
end
if nargin<2||isempty(rawPath)
    [f,p]=uigetfile('*_raw.mat','选择含原始三相电流的记录');
    if isequal(f,0), result=[]; return; end; rawPath=fullfile(p,f);
end
A=load(modelPath,'Model'); assert(isfield(A,'Model'),'FastLock:Model','文件缺少 Model。');
M=A.Model; c=M.cfg;
assert(string(M.classes(1))=="Normal",'FastLock:Classes','模型第一类必须是 Normal。');
if nargin<3||isempty(threshold), threshold=M.calibration.threshold; end
D=gt_read(rawPath); m=D.metadata;
assert(ismember(string(m.faultType),string(M.classes)),'FastLock:Class','模型未学习该类别。');
r=gt_record_features(D,c);
r.id=D.id; r.label=string(m.faultType); r.eventKind=string(m.eventKind);
r.eventTime_s=m.eventTime_s; r.torque_Nm=m.torque_Nm; r.speed_rpm=m.speed_rpm;
[X,~,t]=gt_sequences(r,M.columns,M.mu,M.sigma,c,false);
scores=gt_predict_sequences(M.net,X,c);
L=gt_fast_lock_1ms(t,scores,threshold,0.001);
trueIndex=find(string(M.classes)==r.label,1);
if isnan(L.lockIndex)
    predicted="Pending"; lock_s=NaN; lock_ms=NaN; lock_cycles=NaN; preEvent=false;
else
    predicted=string(M.classes(L.lockClass)); lock_s=t(L.lockIndex);
    lock_ms=1000*(lock_s-r.eventTime_s);
    lock_cycles=gt_relative_cycles(r,lock_s);
    preEvent=lock_s<r.eventTime_s;
end
isSingle=r.label~="Normal"&&~contains(r.label,"_");
isDouble=r.label~="Normal"&&contains(r.label,"_");
deadline=NaN; if isSingle, deadline=0.5; end
if isDouble, deadline=0.75; end
if r.label=="Normal"
    correct=isnan(L.lockIndex); met=correct;
else
    correct=~isnan(L.lockIndex)&&L.lockClass==trueIndex&&~preEvent;
    met=correct&&lock_cycles<=deadline;
end
result=struct('RecordID',string(r.id),'Label',r.label, ...
    'Predicted',predicted,'LockTime_s',lock_s,'LockDelay_ms',lock_ms, ...
    'Lock_cycles',lock_cycles,'Deadline_cycles',deadline,'Correct',logical(correct), ...
    'MetDeadline',logical(met),'PreEventFalseLock',logical(preEvent), ...
    'Threshold',threshold,'Confirm_ms',1,'Model',string(M.name), ...
    'RawFile',string(rawPath));
if nargout==0, disp(struct2table(result)); end
end
