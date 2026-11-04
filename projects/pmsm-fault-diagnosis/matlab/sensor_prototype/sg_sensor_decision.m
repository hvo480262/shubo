function [blocked,candidate,estimate]=sg_sensor_decision(S,coord,sc)
n=numel(coord); blocked=false(n,1); candidate=zeros(n,1); estimate=nan(n,1);
if ~sc.enabled, return; end
o=sc.options;
% Any large unexplained residual inhibits open-circuit locking; localization
% is deliberately allowed to remain pending instead of fabricating a phase.
bad=~S.ready | S.rhoFast>sc.fastThreshold | S.rhoFit>sc.fitThreshold | S.amplitude<sc.minAmplitude;
lastBad=-Inf;
for k=1:n
    if bad(k), lastBad=coord(k); end
    blocked(k)=bad(k)||coord(k)-lastBad<o.SensorHealthyRecovery_cycles;
end
[err,phase]=min(S.unexplained,[],2); sorted=sort(S.unexplained,2);
idx=sub2ind([n,3],(1:n)',phase); gain=S.gain(idx);
ok=S.ready & S.amplitude>=sc.minAmplitude & S.rhoFit>sc.fitThreshold & ...
    err<=o.MaxUnexplainedFraction & sorted(:,2)-err>=o.MinFitSeparation & ...
    S.offsetRatio(idx)<=o.MaxOffsetRatio & S.varianceRatio(idx)>=o.MinPhaseVarianceRatio & ...
    isfinite(gain) & gain>=o.GainRange(1)&gain<=o.GainRange(2)& ...
    abs(gain-1)>=o.MinimumGainDeviation;
candidate(ok)=phase(ok); estimate(ok)=gain(ok);
end
