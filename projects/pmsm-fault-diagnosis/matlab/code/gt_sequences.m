function [X,Y,t,ends]=gt_sequences(R,cols,mu,sigma,c,training)
ends=(c.SeqLength:size(R.features,1)).';
if training
    keep=mod(ends-c.SeqLength,c.TrainStride)==0;
    if R.label~="Normal"
        cycles=gt_relative_cycles(R,R.time_s(ends));
        keep=keep|(cycles>=0 & cycles<=1);
    end
    ends=ends(keep);
end
A=(single(R.features(:,cols))-single(mu))./single(sigma);
X=cell(numel(ends),1);
for k=1:numel(ends), X{k}=A(ends(k)-c.SeqLength+1:ends(k),:).'; end
t=R.time_s(ends); labels=repmat("Normal",numel(t),1);
if R.label~="Normal", labels(t>=R.eventTime_s)=R.label; end
Y=categorical(labels,cellstr(c.Classes),cellstr(c.Classes));
Y=reordercats(Y,cellstr(c.Classes));
end
