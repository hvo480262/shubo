function [theta,source]=gt_electrical_angle(D,c)
% Only measurements available at the current raw timestamp are used.
t=D.timeAbsolute; m=D.metadata;
if isfield(D,'electricalAngle_rad')
    theta=double(D.electricalAngle_rad(:)); source="measured_electrical_angle";
elseif isfield(D,'diagnostics')&&all(isfield(D.diagnostics,{'speedTime','speedRpm'}))
    st=double(D.diagnostics.speedTime(:)); rpm=double(D.diagnostics.speedRpm(:));
    assert(numel(st)==numel(rpm)&&numel(st)>1&&all(isfinite(st))&&all(isfinite(rpm))&&all(diff(st)>0));
    assert(st(1)<=t(1)+1e-10&&st(end)>=t(end)-1e-10, ...
        'GeneralTCN:SpeedCoverage', ...
        '%s: 电流[%.9f, %.9f]s，转速[%.9f, %.9f]s，日志与电流未对齐。', ...
        D.sourceFile,t(1),t(end),st(1),st(end));
    v=interp1(st,rpm,min(max(t,st(1)),st(end)),'previous');
    assert(all(v>0),'GeneralTCN:Direction','角度分支暂不支持停转和反转。');
    theta=cumtrapz(t,2*pi*m.polePairs*v/60); source="integrated_measured_speed";
elseif c.AllowNominalSpeed || c.FeatureMode=="nominal_time"
    theta=2*pi*m.speed_rpm*m.polePairs/60*(t-t(1)); source="nominal_constant_speed";
else
    error('GeneralTCN:NoAngle', ...
        '%s缺实测角度/转速。请补采，或仅对恒速旧数据显式设置cfg.AllowNominalSpeed=true。',D.sourceFile);
end
assert(numel(theta)==numel(t)&&isreal(theta)&&all(isfinite(theta))&&all(diff(theta)>0), ...
    'GeneralTCN:Angle','电角度必须展开、严格递增且与电流同步。');
theta=theta-theta(1);
end
