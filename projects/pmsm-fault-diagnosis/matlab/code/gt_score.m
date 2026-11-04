function [M,P]=gt_score(R,t,scores,C,c)
% All delays use causal availability timestamps; durations use actual time.
t=t(:); assert(numel(t)>1&&all(diff(t)>0));
pred=gt_gate(scores,C.threshold,c.ConfirmSteps);
isFault=R.label~="Normal"; target=find(c.Classes==R.label); assert(isscalar(target));
truth=ones(size(t)); if isFault, truth(t>=R.eventTime_s)=target; end
rel=t-R.eventTime_s; cycles=gt_relative_cycles(R,t);
finish=gt_cycle_time(R,c.EvaluateAfterCycles);
if isFault
    start=gt_cycle_time(R,-1);
    evalMask=t>=start&t<=finish;
    nw=weights(t,start,R.eventTime_s);
else
    start=t(1); evalMask=true(size(t)); nw=weights(t,t(1),t(end));
end
post=evalMask&rel>=0; pw=weights(t,R.eventTime_s,finish); pw(~post)=0;
normal=evalMask&truth==1; nw(~normal)=0; fa=normal&pred>1;
M=struct('RecordID',R.id,'Label',R.label,'EventKind',R.eventKind, ...
    'EventTime_s',R.eventTime_s,'Torque_Nm',R.torque_Nm,'Speed_rpm',R.speed_rpm,'IsFault',isFault, ...
    'Threshold',C.threshold,'NormalObservation_s',sum(nw), ...
    'NormalFalseAlarmEvents',sum(diff([false;fa])==1),'NormalFalseDecisions',sum(fa), ...
    'NormalDecisions',sum(normal),'NormalFalseDecisionFraction',sum(fa)/max(1,sum(normal)), ...
    'NormalFalseDuration_s',sum(nw(pred>1)), ...
    'FirstDetection_ms',NaN,'FirstCorrect_ms',NaN,'FirstStableCorrect_ms',NaN,'Missed',false, ...
    'CorrectByOneCycle',false,'StableCorrectByOneCycle',false, ...
    'WrongLocationFraction',NaN,'CorrectLocationFraction',NaN, ...
    'PostFaultWrongTimeFraction',NaN,'PostFaultCorrectTimeFraction',NaN, ...
    'PendingFraction',mean(pred(evalMask)==0),'WrongAfterFirstCorrect',false, ...
    'FirstCorrectUntilLastEvaluated_ms',NaN, ...
    'AlarmAlreadyActiveBeforeEvent',false,'EvaluationHorizon_ms',1000*(finish-R.eventTime_s), ...
    'EvaluationHorizon_cycles',c.EvaluateAfterCycles, ...
    'FirstDetection_cycles',NaN,'FirstCorrect_cycles',NaN,'FirstStableCorrect_cycles',NaN);
if isFault
    a=find(post&pred>1,1); b=find(post&pred==target,1);
    if ~isempty(a), M.FirstDetection_ms=1000*rel(a); M.FirstDetection_cycles=cycles(a); end
    if ~isempty(b)
        M.FirstCorrect_ms=1000*rel(b); M.FirstCorrect_cycles=cycles(b);
        M.WrongAfterFirstCorrect=any(post&((1:numel(t))'>b)&pred>1&pred~=target);
    end
    M.Missed=isempty(b); M.CorrectByOneCycle=any(post&cycles<=1&pred==target);
    M.WrongLocationFraction=sum(post&pred>1&pred~=target)/max(1,sum(post));
    M.CorrectLocationFraction=sum(post&pred==target)/max(1,sum(post));
    if sum(pw)>0
        M.PostFaultWrongTimeFraction=sum(pw(pred>1&pred~=target))/sum(pw);
        M.PostFaultCorrectTimeFraction=sum(pw(pred==target))/sum(pw);
    end
    runStart=NaN;
    for k=1:numel(t)
        if post(k)&&pred(k)==target
            if isnan(runStart), runStart=t(k); end
            if t(k)-runStart+1e-12>=c.StableCorrect_ms/1000
                M.FirstStableCorrect_ms=1000*rel(k); M.FirstStableCorrect_cycles=cycles(k);
                M.StableCorrectByOneCycle=cycles(k)<=1; break;
            end
        else, runStart=NaN;
        end
    end
    idx=find(post);
    if ~isempty(idx)&&pred(idx(end))==target
        bad=find(pred(idx)~=target,1,'last');
        if isempty(bad), q=idx(1); else, q=idx(bad+1); end
        M.FirstCorrectUntilLastEvaluated_ms=1000*rel(q);
    end
    q=find(t<R.eventTime_s,1,'last');
    if ~isempty(q), M.AlarmAlreadyActiveBeforeEvent=pred(q)>1; end
end
P=struct('time_s',t,'relative_ms',1000*rel,'relative_cycles',cycles, ...
    'scores',scores,'confirmed',pred,'truth',truth,'evaluationMask',evalMask, ...
    'threshold',C.threshold,'classes',c.Classes);
end
function w=weights(t,lo,hi)
% Hold each available decision until the next; never extrapolate beyond last.
next=[t(2:end);t(end)]; w=max(0,min(next,hi)-max(t,lo));
end
