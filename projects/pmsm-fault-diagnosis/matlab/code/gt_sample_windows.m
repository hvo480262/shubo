function [chosen,counts]=gt_sample_windows(labels,owners,c,seed)
% Class-balanced, record-round-robin sampling, without replacement by default.
s=RandStream('mt19937ar','Seed',seed); counts=zeros(numel(c.Classes),1);
for k=1:numel(c.Classes), counts(k)=sum(labels==c.Classes(k)); end
assert(all(counts>0),'GeneralTCN:TrainingClass','训练窗口缺类。');
n=c.WindowsPerClass;
if ~c.SampleWithReplacement, n=min(n,min(counts)); end
chosen=[];
for k=1:numel(c.Classes)
    ids=find(labels==c.Classes(k)); records=unique(owners(ids));
    queues=cell(numel(records),1);
    for j=1:numel(records)
        q=ids(owners(ids)==records(j)); queues{j}=q(randperm(s,numel(q)));
    end
    picked=zeros(n,1); count=0;
    while count<min(n,numel(ids))
        for j=randperm(s,numel(records))
            if isempty(queues{j}), continue; end
            count=count+1; picked(count)=queues{j}(end); queues{j}(end)=[];
            if count>=min(n,numel(ids)), break; end
        end
    end
    if count<n, picked(count+1:n)=ids(randi(s,numel(ids),n-count,1)); end
    chosen=[chosen;picked]; %#ok<AGROW>
end
chosen=chosen(randperm(s,numel(chosen)));
if ~c.SampleWithReplacement, assert(numel(unique(chosen))==numel(chosen)); end
end
