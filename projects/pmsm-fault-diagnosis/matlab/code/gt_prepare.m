function [R,T,c,splitFile,labelMap]=gt_prepare(c)
% Inspect provenance and quotas BEFORE feature extraction/training.
if isfield(c,'AllowExternalSelectedFiles')&&c.AllowExternalSelectedFiles
    assert(isfield(c,'SelectedFiles')&&~isempty(c.SelectedFiles), ...
        'GeneralTCN:Selection','外部原始数据列表不能为空。');
    paths=string(c.SelectedFiles(:));
    assert(all(isfile(paths)),'GeneralTCN:SelectionMissing', ...
        '冻结清单中的部分原始文件不存在。');
else
    paths=gt_list_raw_paths(c.DataFolder,c.RawFilePattern);
end
assert(~isempty(paths),'GeneralTCN:NoData', ...
    '没有找到原始MAT：%s。旧文件名不以_raw.mat结尾时，请在纯原始数据目录使用cfg.RawFilePattern=''*.mat''。',c.DataFolder);
% Explicit selection is an allow-list; an empty selection never means all.
if isfield(c,'SelectedFiles')
    selected=string(c.SelectedFiles(:));
    assert(~isempty(selected),'GeneralTCN:EmptySelection','未选择任何记录。');
    assert(~any(ismissing(selected)|strlength(selected)==0)&& ...
        numel(unique(selected))==numel(selected),'GeneralTCN:Selection','选择清单无效或重复。');
    missing=selected(~ismember(selected,paths));
    assert(isempty(missing),'GeneralTCN:SelectionMissing', ...
        '选择的文件不在当前数据目录/匹配规则下，请重新选择：%s',strjoin(missing,newline));
    paths=paths(ismember(paths,selected));
end
rows=cell(numel(paths),1);
for k=1:numel(paths)
    D=gt_read(paths(k)); m=D.metadata;
    speedGaps=[NaN NaN]; speedStep_ms=NaN;
    if isfield(D,'diagnostics')&&all(isfield(D.diagnostics,{'speedTime','speedRpm'}))
        st=double(D.diagnostics.speedTime(:));
        if numel(st)>1
            speedGaps=1000*[max(0,st(1)-D.timeAbsolute(1)), ...
                max(0,D.timeAbsolute(end)-st(end))];
            speedStep_ms=1000*median(diff(st));
        end
    end
    rows{k}=struct('RecordID',D.id,'File',paths(k),'Label',string(m.faultType), ...
        'Speed_rpm',m.speed_rpm,'Torque_Nm',m.torque_Nm,'EventTime_s',m.eventTime_s, ...
        'EventKind',string(m.eventKind),'GroupID',D.groupID,'SourceGroupID',D.groupID, ...
        'CurrentSHA256',D.hash,'ScenarioID',string(m.scenarioID), ...
        'ParentRecordID',string(m.parentRecordID),'PlannedRole',string(m.plannedRole), ...
        'Samples',numel(D.timeAbsolute),'Start_s',D.timeAbsolute(1),'End_s',D.timeAbsolute(end), ...
        'SpeedStartGap_ms',speedGaps(1),'SpeedEndGap_ms',speedGaps(2), ...
        'SpeedMedianInterval_ms',speedStep_ms,'Role',"reserve");
end
T=struct2table(vertcat(rows{:}));
if ~isfolder(c.SplitFolder), mkdir(c.SplitFolder); end
writetable(T,fullfile(c.SplitFolder,'data_inventory.csv'));
[hashes,~,j]=unique(T.CurrentSHA256); counts=accumarray(j,1);
if any(counts>1)
    h=hashes(find(counts>1,1));
    error('GeneralTCN:Duplicate','完全相同电流不可重复计为独立记录，请只保留一份：\n%s',strjoin(T.File(T.CurrentSHA256==h),newline));
end
assert(numel(unique(T.RecordID))==height(T),'GeneralTCN:ID','记录ID冲突。');
assert(ismember(c.Plan,["random_group","manual"]),'GeneralTCN:Plan', ...
    'v5支持random_group/manual；跨负载或跨转速请用manual预定角色，并满足所有类验证/测试配额。');
splitFile=fullfile(c.SplitFolder,sprintf('%s_seed%d.csv',c.Plan,c.SplitSeed));
try
    missing=c.RequiredClasses(~ismember(c.RequiredClasses,T.Label));
    assert(isempty(missing),'GeneralTCN:MissingClasses','缺少类别：%s',strjoin(missing,', '));
    T=gt_random_roles(T,c,splitFile);
catch ME
    labels=unique([T.Label(:);c.RequiredClasses(:)]); n=zeros(numel(labels),1);
    for k=1:numel(labels)
        mask=T.Label==labels(k); ids=T.SourceGroupID(mask);
        scenario=T.ScenarioID(mask); q=~ismissing(scenario)&strlength(scenario)>0; ids(q)=scenario(q);
        n(k)=numel(unique(ids));
    end
    need=repmat(c.MinTrainGroups+c.MinValidationGroups+c.MinTestGroups,numel(labels),1);
    need(labels=="Normal")=need(labels=="Normal")+c.MinCalibrationGroups;
    gap=max(0,need-n);
    Q=table(labels,n,need,gap,'VariableNames',{'Label','ApproximateAvailableGroups','MinimumRequired','ApproximateShortfall'});
    writetable(Q,fullfile(c.SplitFolder,'collection_shortfall.csv'));
    if any(gap>0)
        disp(Q(Q.ApproximateShortfall>0,:));
    else
        fprintf('各类数量已达最低要求；本次错误需检查分组关系、预定角色或其他约束。\n');
    end
    rethrow(ME);
end
writetable(T,splitFile); gt_split_coverage(T,splitFile);
R=cell(height(T),1); T.AngleSource=strings(height(T),1);
T.SpeedTrimStart_ms=zeros(height(T),1); T.SpeedTrimEnd_ms=zeros(height(T),1);
for k=1:height(T)
    D=gt_read(T.File(k)); m=D.metadata;
    tic; r=gt_record_features(D,c); elapsed=toc;
    r.id=D.id; r.label=string(m.faultType); r.eventKind=string(m.eventKind);
    r.eventTime_s=m.eventTime_s; r.torque_Nm=m.torque_Nm; r.speed_rpm=m.speed_rpm;
    r.hash=D.hash; r.groupID=T.GroupID(k); r.sourceFile=D.sourceFile;
    assert(numel(r.time_s)>=c.SeqLength,'GeneralTCN:Warmup','特征历史过短。');
    ready=r.time_s(c.SeqLength);
    assert(ready<r.eventTime_s,'GeneralTCN:Warmup','%s事件前历史不足；请增加故障前录波。',T.File(k));
    assert(gt_relative_cycles(r,r.time_s(end))>=c.EvaluateAfterCycles, ...
        'GeneralTCN:PostCoverage','%s没有覆盖实际电角度的评估周期。',T.File(k));
    if T.Role(k)=="calibration"
        start=gt_cycle_time(r,c.CalibrationStartOffsetCycles);
        assert(sum(r.time_s(c.SeqLength:end)>=start)>c.ConfirmSteps,'GeneralTCN:CalShort','健康校准记录太短，请增加校准记录时长。');
    end
    R{k}=r;
    T.FirstPredictionAvailable_s(k)=ready; T.FeatureFrames(k)=numel(r.time_s);
    T.Hop_ms(k)=1000*r.actualHop_s; T.MinimumHop_ms(k)=1000*r.minimumHop_s;
    T.FeatureComputation_s(k)=elapsed; T.AngleSource(k)=r.angleSource;
    T.SpeedTrimStart_ms(k)=1000*r.speedTrimStart_s;
    T.SpeedTrimEnd_ms(k)=1000*r.speedTrimEnd_s;
end
registry=gt_classes(); present=unique(T.Label(T.Role=="train"));
c.Classes=registry(ismember(registry,["Normal";present]));
assert(numel(c.Classes)>=2&&all(ismember(T.Label(T.Role~="reserve"),c.Classes)));
labelMap=table(registry(:),zeros(numel(registry),1),false(numel(registry),1), ...
    'VariableNames',{'Label','NetworkIndex','Trained'});
for k=1:numel(c.Classes)
    q=labelMap.Label==c.Classes(k); labelMap.NetworkIndex(q)=k; labelMap.Trained(q)=true;
end
for role=["train","validation","calibration","test","reserve"]
    v=zeros(height(labelMap),1); g=v;
    for k=1:height(labelMap)
        q=T.Role==role&T.Label==labelMap.Label(k); v(k)=sum(q); g(k)=numel(unique(T.GroupID(q)));
    end
    labelMap.(char(role+"Records"))=v; labelMap.(char(role+"Groups"))=g;
end
writetable(T,splitFile);
fprintf('读取%d条记录；train=%d，validation=%d，calibration=%d，test=%d，reserve=%d。\n', ...
    height(T),sum(T.Role=="train"),sum(T.Role=="validation"),sum(T.Role=="calibration"),sum(T.Role=="test"),sum(T.Role=="reserve"));
fprintf('%d类；特征=%s；划分=%s\n',numel(c.Classes),c.FeatureMode,splitFile);
if any(T.AngleSource=="nominal_constant_speed")
    warning('GeneralTCN:NominalAngle','部分记录使用标称恒速角度，不能用于证明动态变速归一化。详见AngleSource。');
end
if any(T.SpeedTrimStart_ms>0|T.SpeedTrimEnd_ms>0)
    warning('GeneralTCN:SpeedTrim', ...
        '有%d条记录的转速日志首尾略短，已仅在重叠区间提取特征。首/尾最大裁剪%.4f/%.4fms；详情见划分表。', ...
        sum(T.SpeedTrimStart_ms>0|T.SpeedTrimEnd_ms>0), ...
        max(T.SpeedTrimStart_ms),max(T.SpeedTrimEnd_ms));
end
end
