function confirmed=gt_gate(scores,threshold,steps)
% 0=证据不足，1=正常，2及以上按Model.classes映射；不锁存、不在事件点重置。
[p,candidate]=max(scores,[],2); candidate(p<threshold)=0;
confirmed=zeros(size(candidate)); last=0; count=0;
for k=1:numel(candidate)
    if candidate(k)==0
        last=0; count=0;
    elseif candidate(k)==last
        count=count+1;
    else
        last=candidate(k); count=1;
    end
    if count>=steps, confirmed(k)=last; end
end
end
