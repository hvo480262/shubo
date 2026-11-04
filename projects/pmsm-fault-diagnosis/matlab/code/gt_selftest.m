function gt_selftest(testNetwork)
% MATLAB端接口及因果性自检。合成数据仅用于软件检查，不计入训练或测试结果。
if nargin<1, testNetwork=false; end
c=gt_config(); registry=gt_classes(); assert(numel(registry)==22&&numel(unique(registry))==22);
[~,label]=gt_classes('Sc2,Sa1'); assert(label=="Sa1_Sc2");
rejected=false; try, gt_classes('Sa6'); catch, rejected=true; end; assert(rejected);
rejected=false; try, gt_classes('Sa1 Sa1'); catch, rejected=true; end; assert(rejected);
t=(0:2e-5:.15).'; I=[sin(2*pi*80*t),sin(2*pi*80*t-2*pi/3),sin(2*pi*80*t+2*pi/3)];
F=gt_features(t,I,1200,4,c); assert(size(F.features,2)==21);
assert(max(abs(sum(double(F.features(:,4:6)).^2,2)-1))<1e-6);
J=I; J(t>=.08,1)=0; G=gt_features(t,J,1200,4,c); before=F.time_s<.08;
assert(max(abs(F.features(before,:)-G.features(before,:)),[],'all')<1e-5,'GeneralTCN:Future','未来影响了过去特征。');
Q=gt_features(t,2*I,1200,4,c); assert(max(abs(F.features-Q.features),[],'all')<1e-4);
Z=gt_features(t,zeros(size(I)),1200,4,c); assert(all(isfinite(Z.features(:)))&&all(Z.features(:)==0));
S=[.9 .04 .03 .03;.9 .04 .03 .03;.05 .8 .1 .05;.05 .8 .1 .05;.9 .04 .03 .03];
assert(isequal(gt_gate(S,.7,2),[0;1;0;2;0]));
r=struct('id',"synthetic",'label',"Normal",'eventKind',"steady",'eventTime_s',0, ...
    'torque_Nm',10,'speed_rpm',1200,'electricalPeriod_s',.0125,'actualHop_s',.001);
c.CalibrationStartOffsetCycles=0; C=gt_calibrate({(1:5)'*.001},{S},{r},c); assert(C.threshold>.8);
c.Classes=["Normal","Sa1","Sa2","Sa1_Sa2"];
S=[repmat([.9 .04 .03 .03],3,1);repmat([.05 .1 .8 .05],4,1);repmat([.05 .8 .1 .05],3,1)];
r.label="Sa1"; r.eventKind="fault"; r.eventTime_s=.003; tt=(0:9)'*.001;
[m,~]=gt_score(r,tt,S,struct('threshold',.7),c);
assert(abs(m.FirstDetection_ms-1)<1e-10&&abs(m.FirstCorrect_ms-5)<1e-10&&~m.Missed);
[m,~]=gt_score(r,tt,repmat([.9 .04 .03 .03],10,1),struct('threshold',.7),c);
assert(m.Missed&&isnan(m.FirstCorrect_ms));
% 22类不应沿用四分类的0.25概率下界。
r.label="Normal"; r.eventKind="steady"; r.eventTime_s=0;
S=repmat([.3,repmat(.7/21,1,21)],5,1); C=gt_calibrate({(1:5)'*.001},{S},{r},c);
assert(abs(C.threshold-1/22)<1e-10);
if testNetwork
    rng(1); X=cell(22,1); for k=1:22, X{k}=single(randn(9,c.SeqLength)); end
    Y=categorical(registry(:),cellstr(registry),cellstr(registry)); Y=reordercats(Y,cellstr(registry));
    net=gt_build_tcn(9,22,c);
    opts=trainingOptions('adam','MaxEpochs',1,'MiniBatchSize',11,'InputDataFormats','CTB', ...
        'ExecutionEnvironment','cpu','Verbose',false);
    net=trainnet(X,Y,net,'crossentropy',opts); p=gt_predict_sequences(net,X,c);
    assert(isequal(size(p),[22 22])&&max(abs(sum(p,2)-1))<1e-4);
end
fprintf('gt_selftest通过；22类网络接口检查=%d。\n',testNetwork);
end
