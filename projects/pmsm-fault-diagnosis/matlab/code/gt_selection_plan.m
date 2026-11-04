function [A,coverage]=gt_selection_plan(T,c,manual)
% Validate before committing a selection. Uses the existing v5 group rules.
assert(istable(T)&&ismember('Use',T.Properties.VariableNames));
A=T(T.Use,:);
assert(height(A)>0,'GeneralTCN:EmptySelection','至少选择一条记录。');
assert(numel(unique(A.CurrentSHA256))==height(A), ...
    'GeneralTCN:Duplicate','选中数据含完全相同电流，请取消重复副本。');
assert(numel(unique(A.RecordID))==height(A),'GeneralTCN:ID','记录ID冲突。');
assert(c.IncludeNormalLoadStep||~any(A.EventKind=="loadStep"), ...
    'GeneralTCN:LoadStep','选中了负载突变记录；请显式开启cfg.IncludeNormalLoadStep。');
missing=c.RequiredClasses(~ismember(c.RequiredClasses,A.Label));
assert(isempty(missing),'GeneralTCN:MissingClasses', ...
    '所选数据缺少类别：%s',strjoin(missing,', '));
if manual
    A.PlannedRole=lower(strtrim(string(A.Role)));
else
    A.PlannedRole=repmat("",height(A),1);
end
[A,coverage]=pmsm_strict_split(A,'Seed',c.SplitSeed, ...
    'MinTrain',c.MinTrainGroups,'MinValidation',c.MinValidationGroups, ...
    'MinTest',c.MinTestGroups,'MinCalibration',c.MinCalibrationGroups, ...
    'TestFraction',c.TestFraction,'ValidationFraction',c.ValidationFraction, ...
    'UsePlannedRoles',logical(manual));
% Keep the original provenance columns; freeze the effective union too.
A.LockedGroupID=A.EffectiveGroupID;
end
