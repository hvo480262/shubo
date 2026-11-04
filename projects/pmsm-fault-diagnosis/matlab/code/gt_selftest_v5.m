function gt_selftest_v5
% Synthetic data here checks software/math, never physical fault performance.
c=gt_config(); c.Classes=["Normal","Sa1","Sa2"];
t=(0:2e-5:0.15)'; theta=2*pi*(60*t+100*t.^2);
I=[sin(theta),sin(theta-2*pi/3),sin(theta+2*pi/3)];
D=struct('timeAbsolute',t,'iabc',I,'electricalAngle_rad',theta, ...
    'sourceFile',"synthetic",'metadata',struct('polePairs',4,'speed_rpm',1200));
F=gt_record_features(D,c); J=D; J.iabc=7*I; G=gt_record_features(J,c);
assert(isequal(F.time_s,G.time_s));
assert(max(abs(F.features-G.features),[],'all')<1e-5,'Amplitude invariance failed.');
assert(all(isfinite(F.features(:)))&&size(F.features,2)==21);
assert(max(abs(sum(double(F.features(:,7:9)).^2,2)-1))<1e-5);
assert(max(abs(double(F.features(:,1:6))-(2/pi)*sqrt(2/3)),[],'all')<0.02);
J=D; J.iabc(t>.08,1)=100*I(t>.08,2); G=gt_record_features(J,c);
past=F.time_s<=.08; assert(isequal(F.features(past,:),G.features(past,:)),'Future affected past.');
% A truncated input prefix must also produce the same available outputs.
K=D; q=t<=.08; K.timeAbsolute=t(q); K.iabc=I(q,:); K.electricalAngle_rad=theta(q);
H=gt_record_features(K,c);
assert(isequal(F.time_s(past),H.time_s)&&isequal(F.features(past,:),H.features));
% Speed logging may miss a few edge samples: trim both raw and feature
% time axes to the measured overlap, without borrowing future speed.
A=rmfield(D,'electricalAngle_rad');
A.diagnostics=struct('speedTime',t(3:end-3), ...
    'speedRpm',1200*ones(numel(t)-5,1));
E=gt_record_features(A,c);
assert(E.cycleTime_s(1)==t(3)&&E.cycleTime_s(end)==t(end-3)&& ...
    E.angleSource=="integrated_measured_speed"&& ...
    E.speedTrimStart_s>0&&E.speedTrimEnd_s>0, ...
    'Small speed-log edge mismatch was not trimmed safely.');
A.diagnostics.speedTime=t(t>=.025);
A.diagnostics.speedRpm=1200*ones(numel(A.diagnostics.speedTime),1);
rejected=false;
try, gt_record_features(A,c); catch err
    if ~strcmp(err.identifier,'GeneralTCN:SpeedCoverage')
        rethrow(err); % Preserve the real cause instead of masking it.
    end
    assert(contains(err.message,char(A.sourceFile)), ...
        'Speed coverage error must identify its source file.');
    rejected=true;
end
assert(rejected,'Large speed-log gap must fail with the source file.');
% Non-uniform prediction time: 3 decisions do not imply 1ms of evidence.
r=struct('id',"synthetic",'label',"Sa1",'eventKind',"fault",'eventTime_s',.003, ...
    'torque_Nm',10,'speed_rpm',1200,'electricalPeriod_s',.0125,'actualHop_s',.001);
tt=[0;.001;.002;.003;.0031;.0032;.005;.008];
S=[repmat([.9 .05 .05],3,1);repmat([.05 .9 .05],5,1)];
cc=c; cc.ConfirmSteps=1; cc.StableCorrect_ms=1;
[m,~]=gt_score(r,tt,S,struct('threshold',.7),cc);
assert(abs(m.FirstStableCorrect_ms-2)<1e-10);
% Balanced sampling without replacement and reproducible record ownership.
labels=[repmat("Normal",11,1);repmat("Sa1",9,1);repmat("Sa2",7,1)];
owners="r"+string(mod((1:27)',3)); c.WindowsPerClass=10;
[a,counts]=gt_sample_windows(labels,owners,c,11);
[b,~]=gt_sample_windows(labels,owners,c,11);
assert(isequal(a,b)&&numel(a)==21&&numel(unique(a))==21&&isequal(counts,[11;9;7]));
% Five complete 3-class scenarios, plus independent normal calibration.
rid=strings(16,1); lab=rid; gid=rid;
for g=1:5
 for j=1:3
    k=(g-1)*3+j; rid(k)="s"+g+"_"+j; lab(k)=c.Classes(j); gid(k)="scenario"+g;
 end
end
rid(16)="cal"; lab(16)="Normal"; gid(16)="cal";
M=table(rid,lab,gid,rid,'VariableNames',{'RecordID','Label','GroupID','CurrentSHA256'});
[Z,C]=pmsm_strict_split(M); assert(all(C.testGroups>=2)&&all(C.validationGroups>=1));
for g=unique(Z.EffectiveGroupID)'
    assert(numel(unique(Z.Role(Z.EffectiveGroupID==g)))==1);
end
% Four full scenarios plus class-only records: global quotas can be met,
% although the full-scenario signature has only four of the required five.
extraLabels=["Normal";"Normal";"Sa1";"Sa1";"Sa2";"Sa2"];
extraIDs="mixed_extra_"+string((1:6)');
extra=table(extraIDs,extraLabels,extraIDs,extraIDs, ...
    'VariableNames',{'RecordID','Label','GroupID','CurrentSHA256'});
mixed=[M(1:12,:);extra];
[mixedAssigned,mixedCoverage]=pmsm_strict_split(mixed);
assert(all(mixedCoverage.trainGroups>=2)&&all(mixedCoverage.validationGroups>=1)&& ...
    all(mixedCoverage.testGroups>=2)&&mixedCoverage.calibrationGroups(mixedCoverage.Label=="Normal")>=1, ...
    'Overlapping scenario and singleton quotas were not met.');
for h=unique(mixedAssigned.EffectiveGroupID)'
    assert(numel(unique(mixedAssigned.Role(mixedAssigned.EffectiveGroupID==h)))==1);
end
bad=M; bad.CurrentSHA256(15)=bad.CurrentSHA256(12); failed=false;
try, pmsm_strict_split(bad); catch e, failed=strcmp(e.identifier,'PMSM:InsufficientGroups'); end
assert(failed,'Duplicate scenario cannot increase independent sample count.');
% Three-class synthetic scenarios: validate gt_prepare integration.
tmp=tempname; mkdir(tmp); cleanup=onCleanup(@()rmdir(tmp,'s')); %#ok<NASGU>
c=gt_config(tmp); c.DataFolder=fullfile(tmp,'data'); mkdir(c.DataFolder);
c.RequiredClasses=["Normal","Sa1","Sa2"]; c.AllowNominalSpeed=true;
timeAbsolute=(.45:2e-5:.65)'; th=2*pi*80*timeAbsolute;
base=[sin(th),sin(th-2*pi/3),sin(th+2*pi/3)]; roles=["train","train","validation","test","test"];
for scenario=1:5
 for j=1:3
    iabc=base*(1+scenario/10+j/1000);
    metadata=struct('faultType',char(c.RequiredClasses(j)),'speed_rpm',1200,'torque_Nm',10, ...
        'polePairs',4,'faultTime_s',.5,'hasInjectedFault',j>1, ...
        'scenarioID',sprintf('scenario%d',scenario),'plannedRole',char(roles(scenario)));
    save(fullfile(c.DataFolder,sprintf('r%d_%d_raw.mat',scenario,j)),'iabc','timeAbsolute','metadata');
 end
end
iabc=base*3; metadata.faultType='Normal'; metadata.hasInjectedFault=false;
metadata.scenarioID='cal'; metadata.plannedRole='calibration';
save(fullfile(c.DataFolder,'normal_cal_raw.mat'),'iabc','timeAbsolute','metadata');
reportOnly=struct('status','not_raw'); %#ok<NASGU>
save(fullfile(c.DataFolder,'batch_report.mat'),'reportOnly');
[R,T,cc,splitFile,map]=gt_prepare(c); %#ok<ASGLU>
assert(sum(T.Role=="test")==6&&sum(T.Role=="validation")==3&&numel(cc.Classes)==3);
[~,T2]=gt_prepare(c); assert(isequal(T.Role,T2.Role),'Frozen split changed.');
disp('v5 checks passed: angle causality, amplitude scaling, real-time durations, sampling, grouped splits, prepare/freeze integration.');
end
