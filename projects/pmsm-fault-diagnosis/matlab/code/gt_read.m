function D=gt_read(path)
% 支持顶层原始字段、D结构、P结构。必须保留未经处理的iabc与绝对时间。
A=load(path); candidates={A};
if isfield(A,'D')&&isstruct(A.D), candidates{end+1}=A.D; end
if isfield(A,'P')&&isstruct(A.P), candidates{end+1}=A.P; end
found=false;
for k=1:numel(candidates)
    if isscalar(candidates{k})&&all(isfield(candidates{k},{'iabc','timeAbsolute','metadata'}))
        A=candidates{k}; found=true; break;
    end
end
assert(found,'GeneralTCN:Schema','%s缺原始iabc/timeAbsolute/metadata。不能只提供归一化图或特征。',path);
m=A.metadata;
need={'faultType','speed_rpm','torque_Nm','polePairs','faultTime_s'};
assert(all(isfield(m,need)),'GeneralTCN:Metadata','%s的metadata至少需要%s。',path,strjoin(need,', '));
[~,label]=gt_classes(m.faultType); m.faultType=char(label);
for key={'speed_rpm','torque_Nm','polePairs','faultTime_s'}
    validateattributes(m.(key{1}),{'numeric'},{'scalar','real','finite'}); m.(key{1})=double(m.(key{1}));
end
assert(m.speed_rpm>0&&m.polePairs>=1&&m.polePairs==round(m.polePairs));
if isfield(m,'skipCycles'), assert(m.skipCycles==0,'GeneralTCN:Skipped','%s已跳过故障初期，不能用于早诊断。',path); end
if isfield(m,'hasInjectedFault')
    assert(logical(m.hasInjectedFault)==(label~="Normal"),'GeneralTCN:Label','hasInjectedFault与标签冲突。');
end
if ~isfield(m,'eventTime_s'), m.eventTime_s=m.faultTime_s; end
m.eventTime_s=double(m.eventTime_s); assert(isscalar(m.eventTime_s)&&isfinite(m.eventTime_s));
if label~="Normal", assert(abs(m.eventTime_s-m.faultTime_s)<1e-9,'GeneralTCN:Time','两个故障时刻字段冲突。'); end
if ~isfield(m,'eventKind'), m.eventKind='fault'; if label=="Normal", m.eventKind='steady'; end; end
kind=string(m.eventKind);
assert(isscalar(kind)&&ismember(kind,["fault","steady","loadStep"]));
assert((kind=="fault")==(label~="Normal"),'GeneralTCN:Kind','事件类型与故障标签冲突。');
t=double(A.timeAbsolute(:)); I=double(A.iabc);
assert(numel(t)>30&&isequal(size(I),[numel(t),3])&&isreal(I)&&isreal(t));
assert(all(isfinite(t))&&all(isfinite(I(:)))&&all(diff(t)>0));
dt=median(diff(t)); assert(max(abs(diff(t)-dt))<max(1e-10,1e-3*dt), ...
    'GeneralTCN:Sampling','需要等间隔原始采样；代码不会静默插值。');
Te=60/(m.speed_rpm*m.polePairs);
assert(t(1)<m.eventTime_s&&t(end)>=m.eventTime_s+Te,'GeneralTCN:Coverage','缺事件前数据或不足一个事件后电周期。');
md=java.security.MessageDigest.getInstance('SHA-256'); md.update(typecast(I(:),'int8'));
h=lower(reshape(dec2hex(typecast(md.digest(),'uint8'),2).',1,[]));
g="raw_"+string(h);
if isfield(m,'groupID')&&strlength(string(m.groupID))>0, g=string(m.groupID); end
assert(isscalar(g)); m.groupID=char(g);
D=struct('timeAbsolute',t,'iabc',I,'metadata',m,'hash',string(h), ...
    'id',"r_"+extractBefore(string(h),17),'groupID',g,'sourceFile',string(path));
if isfield(A,'diagnostics'), D.diagnostics=A.diagnostics; end
if isfield(A,'electricalAngle_rad'), D.electricalAngle_rad=A.electricalAngle_rad; end
for key={'scenarioID','parentRecordID','plannedRole'}
    if ~isfield(D.metadata,key{1}), D.metadata.(key{1})=''; end
    assert(isscalar(string(D.metadata.(key{1}))),'GeneralTCN:Metadata','分组元数据必须为标量。');
end
end
