function results = RUN_PORTFOLIO_DEMO()
% Recompute and visualize saved CSV results; no classifier training/simulation.
root = fileparts(mfilename('fullpath'));
addpath(fullfile(root,'matlab','code'));
T = readtable(fullfile(root,'evidence','open_circuit_records.csv'),'TextType','string');
T = T(T.Model=="Angle9" & T.Policy=="validation_selected",:);
single = T.FaultKind=="single"; doubleFault = T.FaultKind=="double"; normal = T.FaultKind=="normal";
assert(height(T)==66 && sum(single)==18 && sum(doubleFault)==45 && sum(normal)==3);
assert(all(T.Speed_rpm==1000 & T.Torque_Nm==10));
assert(all(abs(T.Threshold-.90)<1e-10));
assert(sum(T.MetDeadline(single))==2 && sum(T.MetDeadline(doubleFault))==42);
assert(sum(T.WrongLock)==0 && all(T.Correct(single|doubleFault)==1));
S=readtable(fullfile(root,'evidence','sensor_gain_records.csv'),'TextType','string');
assert(height(S)==108 && numel(unique(S.ParentRecordID))==3);
assert(all(S.CorrectLock==1 & S.FalseLock==0 & S.OpenFalseOnSensor==0));
results=struct('records',height(T),'singleTimely',sum(T.MetDeadline(single)), ...
    'doubleTimely',sum(T.MetDeadline(doubleFault)), ...
    'singleMedian_ms',median(T.Lock_ms(single)), ...
    'doubleMedian_ms',median(T.Lock_ms(doubleFault)), ...
    'gainMedian_ms',median(S.LockDelay_ms));
assert(abs(results.singleMedian_ms-12.803)<1e-6);
assert(abs(results.doubleMedian_ms-7.614)<1e-6);
assert(abs(results.gainMedian_ms-9.073)<1e-6);
% Focused checks of the archived lock routine: confidence reset, causality,
% irreversible decision, and normal predictions not latching.
t=(0:6)'*.0005;
p=[.99 .01 .00; .05 .94 .01; .05 .94 .01; .2 .7 .1; .05 .94 .01; .05 .94 .01; .05 .94 .01];
L=gt_fast_lock_1ms(t,p,.90,.001);
assert(L.lockIndex==7 && L.lockClass==2 && all(L.locked(1:6)==0));
p2=[p; .01 .01 .98; .01 .01 .98];
L2=gt_fast_lock_1ms((0:8)'*.0005,p2,.90,.001);
assert(isequal(L.locked,L2.locked(1:7)) && all(L2.locked(7:end)==2));
Pnormal=repmat([.99 .005 .005],7,1);
Ln=gt_fast_lock_1ms(t,Pnormal,.90,.001);
assert(Ln.lockClass==0 && all(Ln.locked==0));
assert(numel(gt_classes())==22);
out=fullfile(root,'assets');
if ~isfolder(out), mkdir(out); end
blue=[.12 .30 .47]; green=[.10 .53 .49]; muted=[.78 .82 .86];
f=figure('Visible','off','Color','w','Position',[100 100 1180 520]);
clean=onCleanup(@() close(f));
layout=tiledlayout(1,2,'Padding','compact','TileSpacing','compact');
ax=nexttile(layout); values=[100 100; 100*2/18 100*42/45];
b=bar(ax,values,'grouped'); b(1).FaceColor=blue; b(2).FaceColor=green;
set(ax,'XTick',1:2,'XTickLabel',{'Eventually correct','Correct within target'},'FontSize',12,'Box','off');
ylim(ax,[0 121]); ylabel(ax,'Fault records (%)'); grid(ax,'on'); ax.GridAlpha=.12;
legend(ax,{'Single-switch (n=18)','Double-switch (n=45)'},'Location','northoutside','Box','off');
for j=1:2
    text(ax,b(j).XEndPoints,b(j).YEndPoints+3,compose('%.1f%%',values(:,j)),'HorizontalAlignment','center','FontSize',11);
end
title(ax,'Correct final labels do not imply timely diagnosis');
ax=nexttile(layout);
axis(ax,[0 1 0 1]); axis(ax,'off');
lines={"SAVED SIMULATION STUDY", "1000 rpm | 10 N m | 3 injection angles", ...
    "66 records: 18 single, 45 double, 3 normal", "", ...
    "Single-switch target: <= 0.5 electrical cycle", ...
    "Double-switch target: <= 0.75 electrical cycle", ...
    "Selected confidence: 0.90 | Hold: 1 ms", "", ...
    "Wrong final fault locks: 0/63", "Normal false locks: 0/3", "", ...
    "Inherited source overlap limits independence.", ...
    "Simulation results; no hardware latency claim."};
text(ax,.02,.96,strjoin(string(lines),newline),'VerticalAlignment','top','FontSize',12,'Color',blue,'Interpreter','none');
title(layout,'PMSM open-circuit diagnosis | saved Angle9 run','FontSize',16,'FontWeight','bold');
exportgraphics(f,fullfile(out,'saved-run-results.png'),'Resolution',160);
clear clean;
f=figure('Visible','off','Color','w','Position',[100 100 1150 510]);
clean=onCleanup(@() close(f));
layout=tiledlayout(1,2,'Padding','compact','TileSpacing','compact');
kinds={single,doubleFault}; names={'Single-switch','Double-switch'}; limits=[.5 .75]; colors={blue,green};
for j=1:2
    ax=nexttile(layout); v=sort(T.Lock_cycles(kinds{j}));
    scatter(ax,(1:numel(v))',v,45,colors{j},'filled'); hold(ax,'on');
    yline(ax,limits(j),'--','Target','Color',[.65 .22 .17],'LineWidth',1.4,'FontSize',11);
    xlabel(ax,'Records sorted by final-lock delay'); ylabel(ax,'Final-lock delay (electrical cycles)');
    title(ax,sprintf('%s: %d/%d within target',names{j},sum(T.MetDeadline(kinds{j})),numel(v)));
    set(ax,'FontSize',11,'Box','off'); grid(ax,'on'); ax.GridAlpha=.12; xlim(ax,[0 numel(v)+1]);
end
title(layout,'Timing remains the main single-switch limitation','FontSize',16,'FontWeight','bold');
exportgraphics(f,fullfile(out,'lock-delay-distribution.png'),'Resolution',160);
clear clean;
fprintf('CSV checks and MATLAB lock-logic checks passed.\n');
disp(results);
end
