function result=RUN_VALIDATE_LOCK_THRESHOLD_PAIR(runFolder)
% No retraining. Choose each model's lock threshold ONLY on frozen validation.
% Test uses saved *_predictions.mat probabilities after selection is frozen.
here=fileparts(mfilename('fullpath')); addpath(fullfile(here,'code'));
result=[];
if nargin<1||isempty(runFolder)
    runFolder=uigetdir(pwd,'选择含 Angle9_seed 和 AngleAmpHalf_seed 子目录的成对训练结果目录');
    if isequal(runFolder,0), return; end
end
runFolder=char(runFolder);
base=dir(fullfile(runFolder,'Angle9_seed*','trained_model.mat'));
amp=dir(fullfile(runFolder,'AngleAmpHalf_seed*','trained_model.mat'));
assert(numel(base)==1&&numel(amp)==1,'ValLock:Models', ...
    '请选择那次成对训练的结果目录；其中须各有一个 Angle9 与 AngleAmpHalf 的 trained_model.mat。');
paths={fullfile(base.folder,base.name),fullfile(amp.folder,amp.name)};
models=cell(2,1);
for i=1:2
    a=load(paths{i},'Model'); assert(isfield(a,'Model'),'ValLock:Model','模型文件缺 Model。');
    models{i}=a.Model;
end
B=models{1}; H=models{2};
assert(string(B.name)=="Angle9"&&string(H.name)=="AngleAmpHalf"&& ...
    B.seed==H.seed&&isequal(string(B.classes),string(H.classes))&& ...
    string(B.classes(1))=="Normal",'ValLock:Pair','两模型的类别或种子不一致。');
required={'RecordID','CurrentSHA256','Role','Label','File','GroupID','EventTime_s'};
assert(all(ismember(required,B.manifest.Properties.VariableNames))&& ...
    all(ismember(required,H.manifest.Properties.VariableNames)), ...
    'ValLock:Manifest','模型缺少冻结清单必要字段。');
mb=B.manifest; mh=H.manifest;
[ok,ix]=ismember(string(mb.CurrentSHA256),string(mh.CurrentSHA256));
assert(all(ok)&&height(mb)==height(mh)&& ...
    all(string(mb.RecordID)==string(mh.RecordID(ix)))&& ...
    all(string(mb.Role)==string(mh.Role(ix)))&& ...
    all(string(mb.GroupID)==string(mh.GroupID(ix)))&& ...
    all(string(mb.Label)==string(mh.Label(ix))), ...
    'ValLock:Split','两模型冻结记录、标签、分组或角色不一致。');
val=mb(string(mb.Role)=="validation",:);
test=mb(string(mb.Role)=="test",:);
assert(~isempty(val)&&~isempty(test)&&any(string(val.Label)=="Normal")&& ...
    any(string(test.Label)=="Normal"),'ValLock:Roles', ...
    'validation 与 test 都须有记录及正常对照。');
out=fullfile(runFolder,['VALIDATION_1MS_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
mkdir(out);
fprintf('冻结网络，validation %d 条，test %d 条。先只使用 validation 选择阈值。\n',height(val),height(test));
valScores=cell(2,1); gridRows=cell(2,1); chosen=zeros(2,1);
for i=1:2
    M=models{i}; valScores{i}=inferValidation(M,val);
    floorThreshold=double(M.calibration.threshold);
    assert(isscalar(floorThreshold)&&isfinite(floorThreshold)&&floorThreshold>=0&& ...
        floorThreshold<=1,'ValLock:Threshold','冻结校准阈值无效。');
    candidates=unique([floorThreshold,(0.05:0.025:0.975),0.99]);
    candidates=candidates(candidates>=floorThreshold-1e-12);
    G=cell(numel(candidates),1);
    for j=1:numel(candidates)
        rows=evaluateSet(valScores{i},M,candidates(j),"validation","grid");
        G{j}=summarize(rows,M,candidates(j),"validation","grid");
    end
    G=vertcat(G{:}); G.IsDefault=abs(G.Threshold-floorThreshold)<1e-12;
    G.Utility=G.SingleMet+G.DoubleMet-G.FaultWrong-5*G.NormalWrong;
    eligible=G(G.SingleMet+G.DoubleMet>0,:);
    if any(eligible.NormalWrong==0), eligible=eligible(eligible.NormalWrong==0,:); end
    eligible=sortrows(eligible,{'Utility','FaultWrong','SingleMet','DoubleMet','Threshold'}, ...
        {'descend','ascend','descend','descend','ascend'});
    if isempty(eligible)
        chosen(i)=floorThreshold; % No useful validation threshold exists.
        warning('ValLock:NoViableThreshold','%s 在validation上没有及时正确锁定，沿用原阈值。',char(M.name));
    else
        chosen(i)=eligible.Threshold(1);
    end
    G.Chosen=abs(G.Threshold-chosen(i))<1e-12;
    gridRows{i}=G;
    fprintf('%s validation: 原阈值 %.6f -> 选定 %.6f，目标=及时正确数-错锁数-5×正常误锁数。\n', ...
        char(M.name),floorThreshold,chosen(i));
end
save(fullfile(out,'VALIDATION_scores.mat'),'valScores','chosen','paths','-v7.3');
grid=vertcat(gridRows{:}); writetable(grid,fullfile(out,'VALIDATION_THRESHOLD_GRID.csv'));
validationRows=cell(4,1); testRows=cell(4,1); summaries=cell(4,1); index=0;
% Thresholds have already been chosen. Test probabilities are loaded only now.
for i=1:2
    M=models{i}; testScores=loadTestCache(M,test,paths{i});
    tBase=double(M.calibration.threshold);
    for policy=["frozen_default","validation_selected"]
        index=index+1;
        threshold=tBase; if policy=="validation_selected", threshold=chosen(i); end
        validationRows{index}=evaluateSet(valScores{i},M,threshold,"validation",policy);
        testRows{index}=evaluateSet(testScores,M,threshold,"test",policy);
        summaries{index}=summarize(testRows{index},M,threshold,"test",policy);
    end
end
V=vertcat(validationRows{:}); Q=vertcat(testRows{:}); S=vertcat(summaries{:});
original=fullfile(runFolder,'PAIRED_AMPLITUDE_HALFWAVE.csv');
assert(isfile(original),'ValLock:PairedMissing', ...
    '运行目录缺原始 PAIRED_AMPLITUDE_HALFWAVE.csv，无法复核基线 test 回放。');
prior=readtable(original,'TextType','string');
assert(height(prior)==height(test)&& ...
    all(ismember({'RecordID','L2Predicted','AmpPredicted', ...
    'L2Lock_cycles','AmpLock_cycles','L2Met','AmpMet'},prior.Properties.VariableNames)), ...
    'ValLock:PairedMismatch','原始成对测试表不完整。');
for i=1:2
    modelName=string(models{i}.name);
    q=Q(Q.Model==modelName&Q.Policy=="frozen_default",:);
    [found,j]=ismember(q.RecordID,prior.RecordID);
    assert(all(found)&&height(q)==height(prior),'ValLock:PairedMismatch', ...
        '默认阈值回放的测试记录与原始成对表不一致。');
    prefix="L2"; if i==2, prefix="Amp"; end
    previousPred=string(prior.(char(prefix+"Predicted"))); previousPred=previousPred(j);
    previousCycles=double(prior.(char(prefix+"Lock_cycles"))); previousCycles=previousCycles(j);
    previousMet=logical(prior.(char(prefix+"Met"))); previousMet=previousMet(j);
    sameCycles=(abs(q.Lock_cycles-previousCycles)<1e-6)| ...
        (isnan(q.Lock_cycles)&isnan(previousCycles));
    assert(all(q.Predicted==previousPred)&&all(sameCycles)&& ...
        all(q.MetDeadline==previousMet),'ValLock:PairedMismatch', ...
        '%s 的默认阈值缓存回放未逐条重现原始 test 结果，已停止。',char(modelName));
end
writetable(V,fullfile(out,'VALIDATION_SELECTED_RECORDS.csv'));
writetable(Q,fullfile(out,'TEST_RECORDS_DEFAULT_VS_SELECTED.csv'));
writetable(S,fullfile(out,'TEST_SUMMARY.csv'));
save(fullfile(out,'SELECTION.mat'),'chosen','paths','grid','S','-v7.3');
result=struct('outputFolder',out,'thresholds',chosen,'testSummary',S);
disp(S);
fprintf('选阈值只用了 validation；test 概率来自已保存的 *_predictions.mat，未重训。\n');
end

function records=inferValidation(M,T)
items=cell(height(T),1);
for j=1:height(T)
    path=char(string(T.File(j)));
    assert(isfile(path),'ValLock:MissingValidationRaw', ...
        'validation 原始文件不存在：%s。请恢复冻结路径后再回放；不要替换记录。',path);
    D=gt_read(path); assert(D.hash==string(T.CurrentSHA256(j)), ...
        'ValLock:Hash','validation 原始电流 SHA 不符：%s',path);
    r=gt_record_features(D,M.cfg);
    r.id=D.id; r.label=string(D.metadata.faultType);
    r.eventTime_s=D.metadata.eventTime_s;
    [X,~,t]=gt_sequences(r,M.columns,M.mu,M.sigma,M.cfg,false);
    scores=gt_predict_sequences(M.net,X,M.cfg);
    items{j}=makeItem(T(j,:),t,scores,gt_relative_cycles(r,t), ...
        1000*(t-r.eventTime_s));
    if mod(j,10)==0||j==height(T)
        fprintf('%s validation 概率：%d/%d\n',char(M.name),j,height(T));
    end
end
records=vertcat(items{:});
end

function records=loadTestCache(M,T,modelFile)
items=cell(height(T),1); folder=fileparts(modelFile);
for j=1:height(T)
    file=fullfile(folder,char(string(T.RecordID(j))+"_predictions.mat"));
    assert(isfile(file),'ValLock:MissingTestScores', ...
        '缺少 %s 的 test 概率缓存：%s。请找回原训练输出，不能用test重新选阈值。', ...
        char(M.name),file);
    A=load(file,'P','m'); assert(isfield(A,'P')&&isfield(A,'m'), ...
        'ValLock:Cache','预测缓存缺 P 或 m：%s',file);
    P=A.P;
    assert(string(A.m.RecordID)==string(T.RecordID(j))&& ...
        string(A.m.Label)==string(T.Label(j))&& ...
        isequal(string(P.classes(:)),string(M.classes(:))), ...
        'ValLock:CacheMismatch','缓存 RecordID/Label/类别与冻结模型不一致：%s',file);
    t=double(P.time_s(:)); scores=double(P.scores);
    assert(size(scores,2)==numel(M.classes)&&size(scores,1)==numel(t)&& ...
        numel(t)>1&&all(diff(t)>0)&&all(isfinite(scores(:)))&& ...
        max(abs(sum(scores,2)-1))<1e-4,'ValLock:Scores', ...
        '缓存概率或时间无效：%s',file);
    items{j}=makeItem(T(j,:),t,scores,double(P.relative_cycles(:)), ...
        double(P.relative_ms(:)));
    assert(numel(items{j}.cycles)==numel(t)&&numel(items{j}.relative_ms)==numel(t), ...
        'ValLock:Time','缓存周期/毫秒坐标不齐：%s',file);
end
records=vertcat(items{:});
end

function r=makeItem(meta,t,scores,cycles,relativeMs)
scenario="";
if ismember('ScenarioID',meta.Properties.VariableNames)
    scenario=string(meta.ScenarioID);
end
r=struct('id',string(meta.RecordID),'label',string(meta.Label), ...
    'scenario',scenario, ...
    'speed',double(meta.Speed_rpm),'torque',double(meta.Torque_Nm), ...
    'event',double(meta.EventTime_s),'time',double(t(:)), ...
    'scores',double(scores),'cycles',double(cycles(:)), ...
    'relative_ms',double(relativeMs(:)));
end

function rows=evaluateSet(records,M,threshold,role,policy)
items=cell(numel(records),1);
for k=1:numel(records)
    r=records(k); L=gt_fast_lock_1ms(r.time,r.scores,threshold,0.001);
    idx=L.lockIndex; predicted="Pending"; lockCycles=NaN; lockMs=NaN;
    preEvent=false; correct=false; met=false;
    isNormal=r.label=="Normal"; isSingle=~isNormal&&~contains(r.label,"_");
    if ~isnan(idx)
        predicted=string(M.classes(L.lockClass));
        lockCycles=r.cycles(idx); lockMs=r.relative_ms(idx);
        preEvent=r.time(idx)<r.event;
        correct=~isNormal&&~preEvent&&predicted==r.label;
    elseif isNormal
        correct=true;
    end
    if isNormal
        met=correct; kind="normal";
    elseif isSingle
        met=correct&&lockCycles<=0.5; kind="single";
    else
        met=correct&&lockCycles<=0.75; kind="double";
    end
    items{k}=table(r.id,r.label,r.scenario,kind,string(M.name),role,policy,threshold, ...
        r.speed,r.torque,predicted,lockCycles,lockMs,logical(correct),logical(met), ...
        logical(~isnan(idx)&&~correct),logical(preEvent), ...
        'VariableNames',{'RecordID','Label','ScenarioID','FaultKind','Model','Role','Policy', ...
        'Threshold','Speed_rpm','Torque_Nm','Predicted','Lock_cycles','Lock_ms', ...
        'Correct','MetDeadline','WrongLock','PreEventWrong'});
end
rows=vertcat(items{:});
end

function row=summarize(rows,M,threshold,role,policy)
single=rows.FaultKind=="single"; double=rows.FaultKind=="double";
fault=single|double; normal=rows.FaultKind=="normal";
row=table(string(M.name),role,policy,threshold,sum(single), ...
    sum(rows.MetDeadline(single)),sum(double),sum(rows.MetDeadline(double)), ...
    sum(rows.WrongLock(fault)),sum(rows.WrongLock(normal)), ...
    sum(rows.WrongLock & rows.Lock_cycles<0.25), ...
    sum(~rows.Correct & ~rows.WrongLock & fault), ...
    'VariableNames',{'Model','Role','Policy','Threshold', ...
    'SingleTotal','SingleMet','DoubleTotal','DoubleMet', ...
    'FaultWrong','NormalWrong','EarlyWrongBeforeQuarter','FaultPending'});
end
