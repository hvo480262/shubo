function report=gt_run(c)
% 可扩展的整记录分组训练。两种输入共用划分、采样规则、网络结构和确认规则。
assert(exist('butter','file')~=0,'GeneralTCN:Toolbox','需要Signal Processing Toolbox。');
c.ModelNames=string(c.ModelNames);
if c.FeatureMode=="angle", supported=["Angle9","Angle21","Angle9Half","AngleAmpHalf"];
else, supported=["Base9","Bands21"]; end
assert(~isempty(c.ModelNames)&&all(ismember(c.ModelNames,supported))&&numel(unique(c.ModelNames))==numel(c.ModelNames));
c.ModelNames=supported(ismember(supported,c.ModelNames));
validateattributes(c.Seeds,{'numeric'},{'vector','integer','nonnegative','nonempty'});
assert(c.ConfirmSteps>=1&&c.ConfirmSteps==round(c.ConfirmSteps));
assert(c.EvaluateAfterCycles>0&&c.StableCorrect_ms>=0);
folder=fullfile(c.OutputRoot,char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
if ~isfolder(folder), mkdir(folder); end
diary(fullfile(folder,'run_log.txt')); cleanup=onCleanup(@()diary('off')); %#ok<NASGU>
fprintf('Universal TCN v5：严格场景分组、多记录验证测试、可选因果角度域特征。\n');
[R,T,c,splitFile,labelMap]=gt_prepare(c);
writetable(T,fullfile(folder,'locked_manifest.csv')); writetable(labelMap,fullfile(folder,'label_map.csv'));
save(fullfile(folder,'prepared_features.mat'),'R','T','c','-v7.3');
report=struct('outputFolder',folder,'splitFile',splitFile,'trained',false,'classes',c.Classes);
if ~c.Train, save(fullfile(folder,'report.mat'),'report'); fprintf('数据检查完成；尚未训练。\n'); return; end
for name=["trainnet","minibatchpredict","indexing1dLayer"]
    assert(exist(char(name),'file')~=0,'GeneralTCN:MATLAB', ...
        '需要MATLAB R2024a或更新版本、Deep Learning Toolbox；缺少%s。',name);
end
train=find(T.Role=="train"); val=find(T.Role=="validation"); cal=find(T.Role=="calibration"); test=find(T.Role=="test");
assert(~c.UseValidationEarlyStopping||~isempty(val),'GeneralTCN:Validation', ...
    '开启早停需独立validation记录，不能使用test记录选择训练轮次。');
gt_selftest(c.RunNetworkSelfTest);
allMetrics={}; summaries={}; pairedRows={}; deadlines={}; cycleDeadlines={};
for seed=reshape(c.Seeds,1,[])
    savedPred=cell(numel(c.ModelNames),numel(test)); seedMetrics=cell(numel(c.ModelNames),1);
    for mode=1:numel(c.ModelNames)
        name=c.ModelNames(mode); cols=1:9;
        if endsWith(name,"21"), cols=1:21; end
        if name=="Angle9Half", cols=[1:9,22:33]; end
        if name=="AngleAmpHalf", cols=34:45; end
        out=fullfile(folder,sprintf('%s_seed%d',name,seed)); mkdir(out);
        a=cellfun(@(r)double(r.features(:,cols)),R(train),'UniformOutput',false); a=vertcat(a{:});
        mu=mean(a,1); sigma=std(a,0,1); sigma(sigma<1e-8)=1;
        [X,Y,owners,times]=collect(R,train,cols,mu,sigma,c,true);
        [chosen,counts]=gt_sample_windows(string(Y),owners,c,seed);
        X=X(chosen); Y=Y(chosen);
        countTable=table(c.Classes(:),counts,'VariableNames',{'Class','AvailableTrainingWindows'});
        writetable(countTable,fullfile(out,'training_window_counts.csv'));
        sampleTable=table(chosen,owners(chosen),times(chosen),string(Y), ...
            'VariableNames',{'WindowIndex','RecordID','EndTime_s','Label'});
        writetable(sampleTable,fullfile(out,'sampled_training_windows.csv'));
        opts={'InitialLearnRate',c.LearnRate,'MaxEpochs',c.MaxEpochs,'MiniBatchSize',c.MiniBatchSize, ...
            'Shuffle','every-epoch','GradientThreshold',1,'OutputNetwork','last-iteration', ...
            'InputDataFormats','CTB','ExecutionEnvironment',c.ExecutionEnvironment, ...
            'Plots',c.TrainingPlots,'Verbose',true,'VerboseFrequency',ceil(numel(X)/c.MiniBatchSize)};
        if ~isempty(val)
            [VX,VY]=collect(R,val,cols,mu,sigma,c,false);
            opts=[opts,{'ValidationData',{VX,VY},'ValidationFrequency',ceil(numel(X)/c.MiniBatchSize)}]; %#ok<AGROW>
            if c.UseValidationEarlyStopping
                assert(all(ismember(c.Classes,unique(string(VY)))),'GeneralTCN:ValidationClasses', ...
                    '早停验证集需覆盖当前所有类别。');
                q=find(cellfun(@(x)ischar(x)&&strcmp(x,'OutputNetwork'),opts),1); opts{q+1}='best-validation';
                opts=[opts,{'ValidationPatience',c.ValidationPatience}]; %#ok<AGROW>
            end
        end
        rng(seed,'twister'); net=gt_build_tcn(numel(cols),numel(c.Classes),c);
        options=trainingOptions('adam',opts{:});
        fprintf('\n训练%s seed%d：%d类，%d通道，最多%d轮。\n',name,seed,numel(c.Classes),numel(cols),c.MaxEpochs);
        tic; [net,info]=trainnet(X,Y,net,'crossentropy',options); trainingSeconds=toc;
        save(fullfile(out,'network_checkpoint.mat'),'net','info','mu','sigma','c','cols','-v7.3');
        ct=cell(numel(cal),1); cs=ct;
        for j=1:numel(cal)
            [XC,~,ct{j}]=gt_sequences(R{cal(j)},cols,mu,sigma,c,false);
            cs{j}=gt_predict_sequences(net,XC,c);
        end
        calibration=gt_calibrate(ct,cs,R(cal),c);
        fprintf('独立健康校准：阈值%.8f，观察%.5fs，校准区间0次误报。\n',calibration.threshold,calibration.normalExposure_s);
        if calibration.degenerateRejectAll
            warning('GeneralTCN:RejectAll','本次阈值大于1，会拒绝所有类别；这是模型失败信号，不能解释为有效零误报。');
        end
        timingCfg=c; timingCfg.HopSeconds=min(cellfun(@(r)r.minimumHop_s,R));
        timing=cpuTiming(net,XC,timingCfg);
        Model=struct('schema','universal_tcn_v5_dnfd','net',net,'classes',c.Classes,'columns',cols, ...
            'featureNames',R{1}.featureNames(cols),'mu',mu,'sigma',sigma,'cfg',c, ...
            'calibration',calibration,'name',name,'seed',seed,'trainIDs',T.RecordID(train), ...
            'validationIDs',T.RecordID(val),'calibrationIDs',T.RecordID(cal),'testIDs',T.RecordID(test), ...
            'trainingSeconds',trainingSeconds,'cpuInference_ms',timing, ...
            'parameters',sum(cellfun(@numel,net.Learnables.Value)),'manifest',T,'labelMap',labelMap);
        save(fullfile(out,'trained_model.mat'),'Model','info','chosen','countTable','-v7.3');
        save(fullfile(out,'calibration_predictions.mat'),'ct','cs','calibration');
        mm=cell(numel(test),1); cm=zeros(numel(c.Classes),numel(c.Classes)+1);
        for j=1:numel(test)
            r=R{test(j)}; [XT,~,tt]=gt_sequences(r,cols,mu,sigma,c,false);
            scores=gt_predict_sequences(net,XT,c); [m,P]=gt_score(r,tt,scores,calibration,c);
            m.Model=name; m.Seed=seed; mm{j}=m; savedPred{mode,j}=P;
            save(fullfile(out,char(r.id+"_predictions.mat")),'P','m');
            used=P.evaluationMask;
            cm=cm+accumarray([P.truth(used),P.confirmed(used)+1],1,size(cm));
        end
        M=table; if ~isempty(mm), M=struct2table(vertcat(mm{:})); end
        seedMetrics{mode}=M; allMetrics=[allMetrics;mm]; %#ok<AGROW>
        if ~isempty(mm)
            writetable(M,fullfile(out,'test_record_metrics.csv'));
            writetable(gt_class_summary(M,c.Classes),fullfile(out,'CLASS_record_summary.csv'));
            gt_confusion(cm,c.Classes,fullfile(out,'test_confusion'),c.ShowFigures);
        end
        s=summarize(M,Model,calibration,cm); summaries{end+1,1}=s; %#ok<AGROW>
        if ~isempty(mm)
            for d=c.EarlyDeadlines_ms
                faults=M.IsFault; eligible=faults&M.EvaluationHorizon_ms>=d;
                deadlines{end+1,1}=struct('Seed',seed,'Model',name,'Deadline_ms',d, ...
                    'EligibleFaultRecords',sum(eligible),'RecordsCorrectByDeadline',sum(eligible&M.FirstCorrect_ms<=d), ...
                    'RecordsStablyCorrectByDeadline',sum(eligible&M.FirstStableCorrect_ms<=d)); %#ok<AGROW>
            end
        end
        if ~isempty(mm)
            for d=[0.25 0.5 0.75 1 2]
                eligible=M.IsFault&M.EvaluationHorizon_cycles>=d;
                cycleDeadlines{end+1,1}=struct('Seed',seed,'Model',name,'Deadline_cycles',d, ...
                    'EligibleFaultRecords',sum(eligible), ...
                    'RecordsCorrectByDeadline',sum(eligible&M.FirstCorrect_cycles<=d), ...
                    'RecordsStablyCorrectByDeadline',sum(eligible&M.FirstStableCorrect_cycles<=d)); %#ok<AGROW>
            end
        end
        fprintf('%s：测试故障%d条，评估时段内未正确定位%d条，正常区间误报%d次。\n', ...
            name,s.FaultRecords,s.MissedRecords,s.NormalFalseAlarmEvents);
        if isempty(test), fprintf('当前没有独立测试记录：已保存模型，不报告测试准确率。\n'); end
        writeRows(summaries,fullfile(folder,'MODEL_comparison.csv'));
        writeRows(allMetrics,fullfile(folder,'ALL_record_metrics.csv'));
        writeRows(deadlines,fullfile(folder,'EARLY_deadlines.csv'));
        writeRows(cycleDeadlines,fullfile(folder,'EARLY_cycles.csv'));
    end
    for j=1:numel(test)
        gt_prediction_plot(R{test(j)},savedPred(:,j),c, ...
            fullfile(folder,sprintf('seed%d_%s_%s_comparison.png',seed,R{test(j)}.label,R{test(j)}.id)));
    end
    if numel(c.ModelNames)==2&&~isempty(test)
        b=seedMetrics{1}; e=seedMetrics{2}; assert(isequal(b.RecordID,e.RecordID));
        both=b.IsFault&~b.Missed&~e.Missed; gain=b.FirstCorrect_ms-e.FirstCorrect_ms;
        sameEvents=sum(b.NormalFalseAlarmEvents)==sum(e.NormalFalseAlarmEvents);
        sameFrames=sum(b.NormalFalseDecisions)==sum(e.NormalFalseDecisions);
        statement="EXPLORATORY_SMALL_SAMPLE";
        if ~sameEvents||~sameFrames, statement="TEST_FALSE_ALARMS_DIFFER_NO_EQUAL_FAR_CLAIM"; end
        pairedRows{end+1,1}=struct('Seed',seed,'Base',c.ModelNames(1),'Enhanced',c.ModelNames(2), ...
            'SameTestFalseAlarmEvents',sameEvents,'SameTestFalseDecisionCount',sameFrames, ...
            'BaseFalseEvents',sum(b.NormalFalseAlarmEvents),'EnhancedFalseEvents',sum(e.NormalFalseAlarmEvents), ...
            'PairedCorrectRecords',sum(both),'MedianPairedGain_ms',median(gain(both),'omitnan'), ...
            'BaseMisses',sum(b.Missed),'EnhancedMisses',sum(e.Missed), ...
            'EnhancedFasterRecords',sum(both&gain>0),'Conclusion',statement); %#ok<AGROW>
        writeRows(pairedRows,fullfile(folder,'PAIRED_comparison.csv'));
    end
end
report.trained=true; report.summary=struct2table(vertcat(summaries{:}));
report.paired=table; if ~isempty(pairedRows), report.paired=struct2table(vertcat(pairedRows{:})); end
save(fullfile(folder,'report.mat'),'report','c','-v7.3'); disp(report.summary);
fprintf('\n完成：%s\n预测图就在此目录，*_comparison.png。\n',folder);
fprintf('延迟按信号时间计算；未包括实时采集、计算与通信。健康校准仅%.4fs，不能保证真实总体误报率。\n',calibration.normalExposure_s);
end

function [X,Y,owners,times]=collect(R,ids,cols,mu,sigma,c,training)
xx=cell(numel(ids),1); yy=xx; oo=xx; tt=xx;
for k=1:numel(ids)
    r=R{ids(k)}; [xx{k},yy{k},tt{k}]=gt_sequences(r,cols,mu,sigma,c,training);
    oo{k}=repmat(r.id,numel(tt{k}),1);
end
X=vertcat(xx{:}); Y=vertcat(yy{:}); owners=vertcat(oo{:}); times=vertcat(tt{:});
assert(~any(isundefined(Y)),'GeneralTCN:Category','出现未在训练类别表中的标签。');
end

function writeRows(rows,path)
if ~isempty(rows), writetable(struct2table(vertcat(rows{:})),path); end
end

function s=summarize(M,Model,C,cm)
s=struct('Seed',Model.seed,'Model',Model.name,'Classes',numel(Model.classes), ...
    'Parameters',Model.parameters,'Threshold',C.threshold,'CalibrationExposure_s',C.normalExposure_s, ...
    'CalibrationFalseEvents',C.falseAlarmEvents,'RejectAllThreshold',C.degenerateRejectAll, ...
    'TestRecords',height(M),'FaultRecords',0,'MissedRecords',0,'MedianCorrectDelay_ms',NaN, ...
    'MedianStableCorrectDelay_ms',NaN,'CorrectByOneCycle',0,'StableCorrectByOneCycle',0, ...
    'MeanPostFaultCorrectFraction',NaN,'MeanPostFaultCorrectTimeFraction',NaN, ...
    'MeanWrongLocationFraction',NaN,'WrongAfterFirstCorrectRecords',0,'NormalFalseAlarmEvents',0, ...
    'NormalFalseDecisionFraction',NaN,'NormalFalseTimeFraction',NaN, ...
    'NormalExposure_s',0,'NormalFalseEventsPerSecond',NaN, ...
    'TestWindowAccuracyIncludingPending',NaN,'MacroRecallObservedClasses',NaN, ...
    'CPUInferenceMedian_ms',Model.cpuInference_ms,'TrainingSeconds',Model.trainingSeconds);
if height(M)==0, return; end
fault=M.IsFault; good=fault&~M.Missed;
s.FaultRecords=sum(fault); s.MissedRecords=sum(M.Missed);
s.MedianCorrectDelay_ms=median(M.FirstCorrect_ms(good),'omitnan');
s.MedianStableCorrectDelay_ms=median(M.FirstStableCorrect_ms(fault),'omitnan');
s.CorrectByOneCycle=sum(M.CorrectByOneCycle);
s.StableCorrectByOneCycle=sum(M.StableCorrectByOneCycle);
s.MeanPostFaultCorrectTimeFraction=mean(M.PostFaultCorrectTimeFraction(fault),'omitnan');
s.MeanPostFaultCorrectFraction=mean(M.CorrectLocationFraction(fault),'omitnan');
s.MeanWrongLocationFraction=mean(M.WrongLocationFraction(fault),'omitnan');
s.WrongAfterFirstCorrectRecords=sum(M.WrongAfterFirstCorrect);
s.NormalFalseAlarmEvents=sum(M.NormalFalseAlarmEvents); s.NormalExposure_s=sum(M.NormalObservation_s);
s.NormalFalseEventsPerSecond=s.NormalFalseAlarmEvents/max(s.NormalExposure_s,eps);
s.NormalFalseTimeFraction=sum(M.NormalFalseDuration_s)/max(s.NormalExposure_s,eps);
s.NormalFalseDecisionFraction=sum(M.NormalFalseDecisions)/max(sum(M.NormalDecisions),1);
support=sum(cm,2); correct=diag(cm(:,2:end));
s.TestWindowAccuracyIncludingPending=sum(correct)/max(sum(support),1);
s.MacroRecallObservedClasses=mean(correct(support>0)./support(support>0));
end

function ms=cpuTiming(net,X,c)
if c.TimingRepeats<=0, ms=NaN; return; end
minibatchpredict(net,X(1),'InputDataFormats','CTB','OutputDataFormats','BC','MiniBatchSize',1,'ExecutionEnvironment','cpu');
a=zeros(c.TimingRepeats,1);
for k=1:numel(a)
    tic; minibatchpredict(net,X(1),'InputDataFormats','CTB','OutputDataFormats','BC','MiniBatchSize',1,'ExecutionEnvironment','cpu');
    a(k)=toc*1000;
end
ms=median(a);
if ms>c.HopSeconds*1000
    warning('GeneralTCN:Timing','单窗CPU调用%.3fms超过请求步长%.3fms；尚不能宣称实时运行。',ms,c.HopSeconds*1000);
end
end
