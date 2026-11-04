function C=gt_calibrate(times,scores,records,c)
% 独立健康记录校准统一置信度阈值；目标只是本段健康数据零误报。
assert(iscell(times)&&iscell(scores)&&numel(times)==numel(scores)&&~isempty(times));
boundary=0; total=0; count=0; starts=zeros(numel(times),1);
for j=1:numel(times)
    r=records{j}; assert(r.label=="Normal");
    starts(j)=gt_cycle_time(r,c.CalibrationStartOffsetCycles);
    t=times{j}; S=scores{j}; mask=t>=starts(j);
    assert(sum(mask)>c.ConfirmSteps,'GeneralTCN:CalShort','%s健康校准时段太短，请延长录波。',r.id);
    [p,cls]=max(S,[],2);
    for k=c.ConfirmSteps:numel(t)
        if ~mask(k), continue; end
        q=k-c.ConfirmSteps+1:k;
        if cls(k)>1&&all(cls(q)==cls(k)), boundary=max(boundary,min(p(q))); end
    end
    total=total+max(0,t(end)-max(t(1),starts(j))); count=count+sum(mask);
end
threshold=max(1/size(scores{1},2),boundary+eps(1));
for j=1:numel(times)
    y=gt_gate(scores{j},threshold,c.ConfirmSteps);
    assert(~any(y(times{j}>=starts(j))>1),'GeneralTCN:CalCheck','校准内部检查失败。');
end
C=struct('threshold',threshold,'boundary',boundary,'falseAlarmEvents',0, ...
    'normalExposure_s',total,'normalDecisionCount',count,'startTimes_s',starts, ...
    'degenerateRejectAll',threshold>1,'meaning', ...
    'zero empirical alarms on independent healthy calibration intervals; not a population FAR guarantee');
end
