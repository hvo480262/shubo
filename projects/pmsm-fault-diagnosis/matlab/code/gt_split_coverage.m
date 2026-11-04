function gt_split_coverage(T,splitFile)
labels=unique(T.Label); rows=cell(numel(labels),1);
for k=1:numel(labels)
    ix=T.Label==labels(k); r=struct('Label',labels(k));
    for role=["train","validation","calibration","test","reserve"]
        r.(char(role+"Groups"))=numel(unique(T.GroupID(ix&T.Role==role)));
    end
    r.HasIndependentTest=r.testGroups>0;
    rows{k}=r;
end
C=struct2table(vertcat(rows{:}));
[parent,name]=fileparts(splitFile); writetable(C,fullfile(parent,[name '_coverage.csv']));
disp(C);
missing=C.Label(~C.HasIndependentTest);
if ~isempty(missing)
    warning('GeneralTCN:Coverage','这些类别没有独立测试记录：%s。不得报告完整22类测试性能。',strjoin(missing,', '));
end
end
