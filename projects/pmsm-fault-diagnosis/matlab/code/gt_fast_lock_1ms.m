function L=gt_fast_lock_1ms(t,scores,threshold,confirm_s)
% Causal irreversible fault-class lock from raw top-1 probabilities.
% Normal does not latch: it must not block a later fault.
if nargin<4, confirm_s=0.001; end
t=double(t(:)); scores=double(scores);
assert(numel(t)==size(scores,1)&&numel(t)>=2&&all(isfinite(t))&& ...
    all(diff(t)>0)&&all(isfinite(scores(:)))&& ...
    isscalar(threshold)&&isfinite(threshold)&&threshold>=0&& ...
    isscalar(confirm_s)&&confirm_s>0,'FastLock:Input','时间、概率或阈值无效。');
[prob,candidate]=max(scores,[],2);
candidate(prob<threshold | candidate==1)=0;
locked=zeros(numel(t),1); lockIndex=NaN; lockClass=0;
startIndex=0; previous=0;
for k=1:numel(t)
    if lockClass~=0
        locked(k)=lockClass; continue;
    end
    if candidate(k)==0
        startIndex=0; previous=0; continue;
    end
    if candidate(k)~=previous
        previous=candidate(k); startIndex=k;
    end
    if t(k)-t(startIndex)+1e-12>=confirm_s
        lockClass=candidate(k); lockIndex=k; locked(k)=lockClass;
    end
end
L=struct('locked',locked,'candidate',candidate,'lockIndex',lockIndex, ...
    'lockClass',lockClass,'threshold',threshold,'confirm_s',confirm_s);
end
