function x=gt_relative_cycles(r,t)
if isfield(r,'cycleTime_s')
    event=interp1(r.cycleTime_s,r.cycleCoordinate,r.eventTime_s,'linear');
    x=interp1(r.cycleTime_s,r.cycleCoordinate,t,'linear')-event;
else
    x=(t-r.eventTime_s)/r.electricalPeriod_s;
end
assert(all(isfinite(x)),'GeneralTCN:CycleCoverage','周期坐标超出记录范围。');
end
