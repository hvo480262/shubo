function [M,coverage] = pmsm_strict_split(M,varargin)
% Standalone manifest splitter; NOT a drop-in replacement for gt_prepare.
% Required columns: RecordID, Label, GroupID, CurrentSHA256.
% Optional ScenarioID / ParentRecordID merge related records into one group.
% Optional PlannedRole (all rows) preserves the acquisition plan.
% Never splits windows, duplicates or scenarios across subsets.
p=inputParser;
addParameter(p,'Seed',2026,@(x) isscalar(x)&&isfinite(x)&&x>=0&&fix(x)==x);
addParameter(p,'MinTrain',2,@positiveInt);
addParameter(p,'MinValidation',1,@positiveInt);
addParameter(p,'MinTest',2,@positiveInt);
addParameter(p,'MinCalibration',1,@positiveInt);
addParameter(p,'TestFraction',0.2,@(x) isscalar(x)&&x>=0&&x<1);
addParameter(p,'ValidationFraction',0.2,@(x) isscalar(x)&&x>=0&&x<1);
addParameter(p,'UsePlannedRoles',true,@(x) islogical(x)&&isscalar(x));
parse(p,varargin{:}); o=p.Results;
assert(o.TestFraction+o.ValidationFraction<1,'Fractions must leave training data.');
if ischar(M)||isstring(M), M=readtable(M,'TextType','string'); end
req={'RecordID','Label','GroupID','CurrentSHA256'};
assert(istable(M)&&all(ismember(req,M.Properties.VariableNames)), ...
    'Manifest must contain RecordID, Label, GroupID, CurrentSHA256.');
assert(height(M)>0,'Empty manifest.');
for c=req
    v=string(M.(c{1}));
    assert(~any(ismissing(v)|strlength(v)==0),'Required manifest fields cannot be empty.');
    M.(c{1})=v;
end
% Detect conflicting exact-current labels before grouping.
hashes=unique(M.CurrentSHA256);
for j=1:numel(hashes)
    assert(numel(unique(M.Label(M.CurrentSHA256==hashes(j))))==1, ...
        'Identical current hash has conflicting labels. Audit data first.');
end
n=height(M); root=(1:n)';
keys={'RecordID','GroupID','CurrentSHA256','ScenarioID','ParentRecordID','LockedGroupID'};
for c=keys
 if ~ismember(c{1},M.Properties.VariableNames), continue; end
 v=string(M.(c{1})); u=unique(v(~ismissing(v)&strlength(v)>0));
 for j=1:numel(u)
    idx=find(v==u(j)); ids=unique(root(idx));
    root(ismember(root,ids))=min(ids);
 end
end
[~,~,g]=unique(root); G=max(g); classes=unique(M.Label,'stable'); C=numel(classes);
present=false(G,C);
for j=1:G
    present(j,:)=ismember(classes,unique(M.Label(g==j)))';
end
normal=find(classes=="Normal"); assert(~isempty(normal),'Normal class required.');
minimum=o.MinTrain+o.MinValidation+o.MinTest;
required=repmat(minimum,C,1); required(normal)=required(normal)+o.MinCalibration;
counts=sum(present,1)';
bad=counts<required;
if any(bad)
    detail=join(classes(bad)+": "+string(counts(bad))+" groups; need "+string(required(bad)),newline);
    error('PMSM:InsufficientGroups','Independent groups insufficient:\n%s',char(detail));
end
role=strings(G,1);
if o.UsePlannedRoles && ismember('PlannedRole',M.Properties.VariableNames)
    planned=string(M.PlannedRole);
    assert(~any(ismissing(planned)|strlength(planned)==0),'PlannedRole is incomplete.');
    for j=1:G
        r=unique(planned(g==j));
        assert(numel(r)==1,'Related or duplicate records have conflicting planned roles.');
        role(j)=r;
    end
else
    s=RandStream('mt19937ar','Seed',o.Seed);
    healthyOnly=find(present(:,normal)&sum(present,2)==1);
    assert(numel(healthyOnly)>=o.MinCalibration,'Need independent normal-only calibration groups.');
    % A multi-label scenario may have fewer than five copies while
    % single-label groups supply the remaining class quotas. Assign whole
    % groups globally; never demand that each label signature is sufficient
    % on its own. Keep a necessary future-capacity bound after each choice.
    target=[o.MinTrain;o.MinValidation;o.MinTest]*ones(1,C);
    names=["train","validation","test"];
    solved=false;
    for attempt=1:128
        role(:)="";
        ix=healthyOnly(randperm(s,numel(healthyOnly),o.MinCalibration));
        role(ix)="calibration";
        pending=find(role=="");
        [~,ord]=sortrows([-sum(present(pending,:),2),rand(s,numel(pending),1)]);
        pending=pending(ord); assigned=zeros(3,C); possible=true;
        for k=1:numel(pending)
            group=pending(k); remaining=sum(present(pending(k:end),:),1);
            future=remaining-double(present(group,:));
            scores=-inf(1,3);
            for z=1:3
                next=assigned; next(z,:)=next(z,:)+double(present(group,:));
                deficit=max(0,target-next);
                if any(sum(deficit,1)>future), continue; end
                need=max(0,target(z,:)-assigned(z,:));
                scores(z)=sum(double(present(group,:)).*need./max(1,remaining));
                % Extra groups follow the configured fractions after quotas.
                bonus=[1-o.ValidationFraction-o.TestFraction, ...
                    o.ValidationFraction,o.TestFraction];
                scores(z)=scores(z)+1e-7*bonus(z);
            end
            if all(isinf(scores)), possible=false; break; end
            [~,pick]=max(scores);
            role(group)=names(pick);
            assigned(pick,:)=assigned(pick,:)+double(present(group,:));
        end
        if possible&&all(all(assigned>=target)), solved=true; break; end
    end
    if ~solved
        error('PMSM:GroupTopology', ...
            'No whole-group allocation met every class quota in 128 attempts. Inspect group topology or preassign complete roles.');
    end
end
assert(all(ismember(role,["train","validation","calibration","test","reserve"])), ...
    'Unknown or unassigned role.');
assert(~any(any(present(role=="calibration",classes~="Normal"))), ...
    'Calibration groups must contain only Normal records.');
M.Role=role(g); M.EffectiveGroupID="group_"+string(g);
coverage=table(classes,'VariableNames',{'Label'});
for r=["train","validation","calibration","test","reserve"]
    coverage.(char(r+"Groups"))=sum(present(role==r,:),1)';
end
assert(all(coverage.trainGroups>=o.MinTrain),'Training coverage incomplete.');
assert(all(coverage.validationGroups>=o.MinValidation),'Validation coverage incomplete.');
assert(all(coverage.testGroups>=o.MinTest),'Test coverage incomplete.');
assert(coverage.calibrationGroups(normal)>=o.MinCalibration,'Calibration coverage incomplete.');
end
function tf=positiveInt(x)
tf=isnumeric(x)&&isscalar(x)&&isfinite(x)&&x>=1&&fix(x)==x;
end
