function r=gt_record_features(D,c)
m=D.metadata;
speedTrim=[0 0];
if ~isfield(D,'electricalAngle_rad') && isfield(D,'diagnostics') && ...
        all(isfield(D.diagnostics,{'speedTime','speedRpm'}))
    st=double(D.diagnostics.speedTime(:)); sr=double(D.diagnostics.speedRpm(:));
    assert(numel(st)>1&&numel(st)==numel(sr)&&all(isfinite(st))&& ...
        all(diff(st)>0),'GeneralTCN:SpeedLog','%s转速日志无效。',D.sourceFile);
    t=D.timeAbsolute;
    speedTrim=[max(0,st(1)-t(1)),max(0,t(end)-st(end))];
    speedTrim(speedTrim<=1e-10)=0;
    if any(speedTrim>1e-10)
        % Keep only raw current samples with an already available measured
        % speed. Never interpolate backwards from a future speed sample.
        Te=60/(m.speed_rpm*m.polePairs);
        limit=min(0.25*Te,max(4*median(diff(t)),2*median(diff(st))));
        if any(speedTrim>limit)
            detail=sprintf( ...
                '%s: 电流[%.9f, %.9f]s，转速[%.9f, %.9f]s；首/尾缺口%.6f/%.6fms，允许最多%.6fms。请检查转速日志，不能整条改用标称速度。', ...
                char(D.sourceFile),t(1),t(end),st(1),st(end), ...
                1000*speedTrim(1),1000*speedTrim(2),1000*limit);
            error('GeneralTCN:SpeedCoverage','%s',detail);
        end
        keep=t>=st(1)&t<=st(end);
        assert(sum(keep)>=3,'GeneralTCN:SpeedCoverage','%s没有足够的重叠电流和转速样本。',D.sourceFile);
        D.timeAbsolute=t(keep); D.iabc=D.iabc(keep,:);
    end
end
[theta,source]=gt_electrical_angle(D,c);
if c.FeatureMode=="nominal_time"
    r=gt_features(D.timeAbsolute,D.iabc,m.speed_rpm,m.polePairs,c);
    r.minimumHop_s=r.actualHop_s;
elseif c.FeatureMode=="angle"
    rpm=diff(theta)./diff(D.timeAbsolute)*60/(2*pi*m.polePairs);
    [lowest,imin]=min(rpm);
    if lowest<c.AngleMinimumRpm
        first=find(rpm<c.AngleMinimumRpm,1);
        event=NaN;
        if isfield(m,'eventTime_s'), event=m.eventTime_s;
        elseif isfield(m,'faultTime_s'), event=m.faultTime_s; end
        detail=sprintf(['%s\n角度来源=%s；最低转速=%.9g rpm（%.9fs），下界=%g rpm。\n', ...
            '首次低于下界的区间结束时刻=%.9fs，距故障参考时刻=%.6fms。请先运行AUDIT_SPEED核对转速。'], ...
            char(D.sourceFile),char(source),lowest,D.timeAbsolute(imin+1), ...
            c.AngleMinimumRpm,D.timeAbsolute(first+1),1000*(D.timeAbsolute(first+1)-event));
        error('GeneralTCN:Slow','%s',detail);
    end
    cutoff=0.35*c.AngleSamplesPerCycle*c.AngleOversample*c.AngleMinimumRpm*m.polePairs/60;
    F=pmsm_angle_features(D,'ElectricalAngle',theta, ...
        'SamplesPerCycle',c.AngleSamplesPerCycle,'AntiAliasCutoffHz',cutoff, ...
        'AntiAliasOrder',c.AngleAntiAliasOrder,'FilterTailTolerance',c.FilterTailTolerance, ...
        'AngularOversample',c.AngleOversample);
    if string(m.faultType)~="Normal"
        assert(F.amplitudeReferenceEnd_s<m.eventTime_s, ...
            'GeneralTCN:AmplitudeReferenceAfterFault', ...
            '%s的首个完整电周期已触及故障时刻；不能用它做故障前幅值参考。',D.sourceFile);
    end
    q=find(F.ready); assert(numel(q)>=c.SeqLength,'GeneralTCN:Short','角度域有效历史不足。');
    times=F.timeAvailable_s(q);
    % Existing Early12 was calculated but not exposed to model inputs.
    earlyNames=strings(1,12);
    base=string({'Q_A','Q_B','Q_C','D_A','D_B','D_C'});
    earlyNames(1:6)=base+"_quarter";
    earlyNames(7:12)=base+"_half";
    ampNames=[base+"_amp_quarter",base+"_amp_half"];
    r=struct('time_s',times,'features',single([F.Bands21(q,:),F.Early12(q,:),F.AmpHalf12(q,:)]), ...
        'featureNames',[string(F.featureNamesBands),earlyNames,ampNames], ...
        'amplitudeReference_A',F.amplitudeReference_A, ...
        'amplitudeReferenceEnd_s',F.amplitudeReferenceEnd_s, ...
        'electricalPeriod_s',60/(m.speed_rpm*m.polePairs), ...
        'actualHop_s',median(diff(times)),'minimumHop_s',min(diff(times)), ...
        'baseWindow_s',60/(m.speed_rpm*m.polePairs),'shortWindow_s',NaN, ...
        'filterGuard_s',F.filterGuard_s,'noCurrent',F.zeroVectorFraction(q)>0.5, ...
        'zeroVectorFraction',F.zeroVectorFraction(q),'angle_rad',F.angle_rad(q), ...
        'antiAliasCutoffHz',cutoff);
    assert(all(isfinite(r.features(:))));
else
    error('GeneralTCN:FeatureMode','FeatureMode必须为angle或nominal_time。');
end
r.angleSource=source; r.cycleTime_s=D.timeAbsolute; r.cycleCoordinate=theta/(2*pi);
r.speedTrimStart_s=speedTrim(1); r.speedTrimEnd_s=speedTrim(2);
end
