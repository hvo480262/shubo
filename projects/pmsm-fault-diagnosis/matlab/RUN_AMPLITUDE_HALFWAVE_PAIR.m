function result=RUN_AMPLITUDE_HALFWAVE_PAIR(modelPath,rawRoots)
% Version 20261026-frozen-group-fix. Frozen paired comparison: Angle9 L2 versus pre-fault amplitude-normalized
% 0.25/0.50-cycle half-wave means. Both use the SAME 1 ms irreversible lock.
% No arguments: choose the original Angle9 trained_model.mat; missing raw
% recordings can be found under one or more interactively selected folders.
here=fileparts(mfilename('fullpath')); addpath(fullfile(here,'code'));
result=[];
if nargin<1||isempty(modelPath)
    [name,folder]=uigetfile('*.mat','选择原始 Angle9 的 trained_model.mat');
    if isequal(name,0), return; end
    modelPath=fullfile(folder,name);
end
A=load(modelPath,'Model');
assert(isfield(A,'Model'),'AmpPair:Model','请选择含 Model 的原始 trained_model.mat。');
M=A.Model;
assert(string(M.name)=="Angle9",'AmpPair:Model','请选择原始 Angle9 模型。');
required={'File','Role','RecordID','CurrentSHA256','GroupID','Label'};
assert(isfield(M,'manifest')&&istable(M.manifest)&& ...
    all(ismember(required,M.manifest.Properties.VariableNames)), ...
    'AmpPair:Manifest','原模型缺冻结的完整划分和原始文件哈希清单。');
manifest=M.manifest; oldPaths=string(manifest.File);
assert(numel(unique(string(manifest.RecordID)))==height(manifest), ...
    'AmpPair:Duplicate','冻结清单有重复 RecordID。');
selected=oldPaths; selected(~isfile(selected))="";
if nargin<2||isempty(rawRoots)
    roots=strings(0,1);
else
    roots=string(rawRoots(:));
end
while true
    missing=find(strlength(selected)==0);
    if isempty(missing), break; end
    if isempty(roots)
        fprintf('还有 %d/%d 条冻结原始记录缺失。选择其所在目录；可连续选择多个目录。\n', ...
            numel(missing),height(manifest));
        root=uigetdir(pwd,'选择原始 *_raw.mat 的目录（可分批选多个）');
        if isequal(root,0)
            disp(table(oldPaths(missing), ...
                'VariableNames',{'MissingOriginalRawPath'}));
            error('AmpPair:MissingRaw','缺失 %d 条冻结原始记录；不删除记录或改变划分。第一条：%s', ...
                numel(missing),char(oldPaths(missing(1))));
        end
        roots=string(root);
    end
    current=roots(1); roots(1)=[];
    assert(isfolder(current),'AmpPair:DataRoot','原始数据目录不存在：%s',char(current));
    paths=gt_list_raw_paths(current,'*_raw.mat');
    filenames=strings(numel(paths),1);
    for j=1:numel(paths)
        [~,n,e]=fileparts(paths(j)); filenames(j)=lower(string(n)+string(e));
    end
    for j=reshape(missing,1,[])
        [~,n,e]=fileparts(oldPaths(j));
        hits=paths(filenames==lower(string(n)+string(e)));
        % Even a unique file name may refer to a different generation run.
        for h=reshape(hits,1,[])
            D=gt_read(h);
            if D.hash==string(manifest.CurrentSHA256(j))
                selected(j)=h; break;
            end
        end
    end
    fprintf('匹配后尚缺 %d 条。\n',sum(strlength(selected)==0));
end
assert(numel(unique(selected))==height(manifest),'AmpPair:DuplicatePaths', ...
    '两条清单记录映射到同一个原始文件，请检查数据目录。');
manifest.File=selected;
c=M.cfg; c.Root=here; c.DataFolder=fileparts(char(selected(1)));
c.OutputRoot=fullfile(here,'results');
c.SplitFolder=fullfile(here,'splits',['amp_pair_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
c.SelectedFiles=selected; c.AllowExternalSelectedFiles=true;
c.UseFrozenManifestRoles=true;
c.ModelNames=["Angle9","AngleAmpHalf"]; c.Seeds=double(M.seed); c.Train=true;
% Historical models may store a Plan name that v5 no longer accepts. The
% already-written SHA/Role/GroupID split below is authoritative; this is
% only the v5-compatible name of the split-file slot, not a fresh split.
c.Plan="random_group";
if ~isfolder(c.SplitFolder), mkdir(c.SplitFolder); end
if ismember('SourceGroupID',manifest.Properties.VariableNames)
    sourceID=string(manifest.SourceGroupID);
    available=~ismissing(sourceID)&strlength(sourceID)>0;
    sources=unique(sourceID(available));
    crossSource=strings(0,1); crossRoles=strings(0,1); crossRecords=zeros(0,1);
    for k=1:numel(sources)
        mask=available&sourceID==sources(k);
        roles=unique(string(manifest.Role(mask)));
        if numel(roles)>1
            crossSource(end+1,1)=sources(k); %#ok<AGROW>
            crossRoles(end+1,1)=strjoin(roles,','); %#ok<AGROW>
            crossRecords(end+1,1)=sum(mask); %#ok<AGROW>
        end
    end
    if ~isempty(crossSource)
        sourceAudit=table(crossSource,crossRoles,crossRecords, ...
            'VariableNames',{'SourceGroupID','Roles','Records'});
        writetable(sourceAudit,fullfile(c.SplitFolder,'CROSS_ROLE_SOURCE_GROUPS.csv'));
        warning('AmpPair:CrossRoleSource', ...
            '%d 个原始来源组跨冻结角色；本对照复用原角色，但这些来源不能称为相互独立。详情：CROSS_ROLE_SOURCE_GROUPS.csv', ...
            height(sourceAudit));
    end
end
splitFile=fullfile(c.SplitFolder,sprintf('%s_seed%d.csv',c.Plan,c.SplitSeed));
writetable(manifest,splitFile);
fprintf('完整冻结清单 %d 条，开始重训两个模型；原始哈希、角色和组信息会再次验证。\n',height(manifest));
training=gt_run(c);
actual=readtable(fullfile(training.outputFolder,'locked_manifest.csv'),'TextType','string');
[present,idx]=ismember(string(manifest.CurrentSHA256),string(actual.CurrentSHA256));
assert(all(present)&&height(actual)==height(manifest)&& ...
    all(string(manifest.Role)==string(actual.Role(idx)))&& ...
    all(string(manifest.GroupID)==string(actual.GroupID(idx))), ...
    'AmpPair:SplitChanged','成对训练中的记录、角色或分组与冻结清单不符。');
baseModel=fullfile(training.outputFolder,sprintf('Angle9_seed%d',M.seed),'trained_model.mat');
ampModel=fullfile(training.outputFolder,sprintf('AngleAmpHalf_seed%d',M.seed),'trained_model.mat');
baseline=RUN_FASTLOCK_BATCH(baseModel);
amplitude=RUN_FASTLOCK_BATCH(ampModel);
B=readtable(fullfile(baseline.outputFolder,'LOCK_record_metrics.csv'),'TextType','string');
H=readtable(fullfile(amplitude.outputFolder,'LOCK_record_metrics.csv'),'TextType','string');
[found,order]=ismember(B.RecordID,H.RecordID);
assert(all(found)&&height(B)==height(H),'AmpPair:Pair','两组测试记录无法逐一配对。');
H=H(order,:);
assert(all(B.Label==H.Label)&all(B.SplitRole=="test")&all(H.SplitRole=="test"), ...
    'AmpPair:TestOnly','测试角色或真值不一致。');
[found,order]=ismember(B.RecordID,string(actual.RecordID));
assert(all(found),'AmpPair:Pair','冻结记录 ID 匹配失败。');
meta=actual(order,:);
paired=table(B.RecordID,B.Label,meta.Speed_rpm,meta.Torque_Nm,meta.ScenarioID, ...
    B.Predicted,H.Predicted,B.Lock_cycles,H.Lock_cycles, ...
    B.LockDelay_ms,H.LockDelay_ms,B.Correct,H.Correct, ...
    B.MetDeadline,H.MetDeadline,B.PreEventFalseLock,H.PreEventFalseLock, ...
    'VariableNames',{'RecordID','Label','Speed_rpm','Torque_Nm','ScenarioID', ...
    'L2Predicted','AmpPredicted','L2Lock_cycles','AmpLock_cycles', ...
    'L2Lock_ms','AmpLock_ms','L2Correct','AmpCorrect', ...
    'L2Met','AmpMet','L2PreEventWrong','AmpPreEventWrong'});
paired.L2Wrong=paired.L2Predicted~="Pending"&~paired.L2Correct;
paired.AmpWrong=paired.AmpPredicted~="Pending"&~paired.AmpCorrect;
paired.L2SingleToDouble=paired.Label~="Normal"& ...
    ~contains(paired.Label,"_")&contains(paired.L2Predicted,"_");
paired.AmpSingleToDouble=paired.Label~="Normal"& ...
    ~contains(paired.Label,"_")&contains(paired.AmpPredicted,"_");
paired.FaultKind=repmat("normal",height(paired),1);
paired.FaultKind(paired.Label~="Normal"&~contains(paired.Label,"_"))="single";
paired.FaultKind(contains(paired.Label,"_"))="double";
writetable(paired,fullfile(training.outputFolder,'PAIRED_AMPLITUDE_HALFWAVE.csv'));
groups=findgroups(paired.Speed_rpm,paired.Torque_Nm,paired.FaultKind);
byCondition=table;
byCondition.Speed_rpm=splitapply(@(x)x(1),paired.Speed_rpm,groups);
byCondition.Torque_Nm=splitapply(@(x)x(1),paired.Torque_Nm,groups);
byCondition.FaultKind=splitapply(@(x)x(1),paired.FaultKind,groups);
byCondition.Records=splitapply(@numel,paired.L2Met,groups);
byCondition.L2Met=splitapply(@sum,double(paired.L2Met),groups);
byCondition.AmpMet=splitapply(@sum,double(paired.AmpMet),groups);
byCondition.L2Wrong=splitapply(@sum,double(paired.L2Wrong),groups);
byCondition.AmpWrong=splitapply(@sum,double(paired.AmpWrong),groups);
byCondition.L2SingleToDouble=splitapply(@sum,double(paired.L2SingleToDouble),groups);
byCondition.AmpSingleToDouble=splitapply(@sum,double(paired.AmpSingleToDouble),groups);
writetable(byCondition,fullfile(training.outputFolder,'BY_CONDITION.csv'));
result=struct('outputFolder',training.outputFolder, ...
    'pairedFile',fullfile(training.outputFolder,'PAIRED_AMPLITUDE_HALFWAVE.csv'), ...
    'singleTotal',sum(paired.FaultKind=="single"), ...
    'L2SingleMet',sum(paired.L2Met(paired.FaultKind=="single")), ...
    'AmpSingleMet',sum(paired.AmpMet(paired.FaultKind=="single")), ...
    'doubleTotal',sum(paired.FaultKind=="double"), ...
    'L2DoubleMet',sum(paired.L2Met(paired.FaultKind=="double")), ...
    'AmpDoubleMet',sum(paired.AmpMet(paired.FaultKind=="double")), ...
    'L2Wrong',sum(paired.L2Wrong),'AmpWrong',sum(paired.AmpWrong), ...
    'L2SingleToDouble',sum(paired.L2SingleToDouble), ...
    'AmpSingleToDouble',sum(paired.AmpSingleToDouble));
disp(result);
disp(byCondition);
