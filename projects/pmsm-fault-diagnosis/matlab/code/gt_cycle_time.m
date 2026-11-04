function t=gt_cycle_time(r,x)
if isfield(r,'cycleTime_s')
    event=interp1(r.cycleTime_s,r.cycleCoordinate,r.eventTime_s,'linear');
    t=interp1(r.cycleCoordinate,r.cycleTime_s,event+x,'linear');
else
    t=r.eventTime_s+x*r.electricalPeriod_s;
end
assert(all(isfinite(t)),'GeneralTCN:CycleCoverage','记录未覆盖所需的电角度周期。');
end
