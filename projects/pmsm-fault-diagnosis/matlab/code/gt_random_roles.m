function T=gt_random_roles(T,c,splitFile)
% Frozen entire-record/scenario roles; strict quotas on every active class.
active=T.EventKind~="loadStep"|c.IncludeNormalLoadStep;
T.Role(:)="reserve"; A=T(active,:);
args={'Seed',c.SplitSeed,'MinTrain',c.MinTrainGroups, ...
    'MinValidation',c.MinValidationGroups,'MinTest',c.MinTestGroups, ...
    'MinCalibration',c.MinCalibrationGroups, ...
    'TestFraction',c.TestFraction,'ValidationFraction',c.ValidationFraction};
if isfile(splitFile)
    old=readtable(splitFile,'TextType','string');
    assert(all(ismember({'CurrentSHA256','Role'},old.Properties.VariableNames)));
    assert(height(old)==height(T)&&numel(unique(old.CurrentSHA256))==height(old)&& ...
        all(ismember(T.CurrentSHA256,old.CurrentSHA256)), ...
        'GeneralTCN:DatasetChanged','数据已变化。请设置新的SplitFolder版本，保留旧划分和结果。');
    [~,ix]=ismember(A.CurrentSHA256,old.CurrentSHA256);
    A.PlannedRole=lower(strtrim(old.Role(ix)));
    if ismember('GroupID',old.Properties.VariableNames)
        A.LockedGroupID=string(old.GroupID(ix));
        if isfield(c,'UseFrozenManifestRoles')&&c.UseFrozenManifestRoles
            % Legacy raw SourceGroupID may span multiple frozen roles.
            % Replaying an existing split must use its saved group key.
            A.GroupID=A.LockedGroupID;
        end
    end
    [A,~]=pmsm_strict_split(A,args{:},'UsePlannedRoles',true);
    if isfield(c,'UseFrozenManifestRoles')&&c.UseFrozenManifestRoles
        assert(ismember('GroupID',old.Properties.VariableNames)&& ...
            all(string(A.Role)==lower(strtrim(string(old.Role(ix))))), ...
            'GeneralTCN:FrozenSplit','冻结角色没有完整保留。');
        A.EffectiveGroupID=string(old.GroupID(ix));
    end
else
    hasPlan=~ismissing(string(A.PlannedRole))&strlength(string(A.PlannedRole))>0;
    if any(hasPlan)&&c.UsePlannedRoles
        assert(all(hasPlan),'GeneralTCN:PartialPlan', ...
            '存在不完整PlannedRole。请单独使用完整新采集会话，或显式设UsePlannedRoles=false后重新预定划分。');
        use=true;
    else
        A.PlannedRole=[]; use=false;
    end
    if c.Plan=="manual"
        writetable(T,splitFile);
        error('GeneralTCN:Manual','已生成手工表%s，请填写Role后重跑。',splitFile);
    end
    [A,~]=pmsm_strict_split(A,args{:},'UsePlannedRoles',use);
end
T.Role(active)=string(A.Role); T.GroupID(active)=string(A.EffectiveGroupID);
end
