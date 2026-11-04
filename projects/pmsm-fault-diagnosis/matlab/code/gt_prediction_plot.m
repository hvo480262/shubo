function gt_prediction_plot(R,PP,c,path)
visible='off'; if c.ShowFigures, visible='on'; end
f=figure('Visible',visible,'Color','w','Position',[60 60 1350 max(450,340*numel(PP))]);
tl=tiledlayout(f,numel(PP),2,'TileSpacing','compact');
title(tl,sprintf('%s | %.0f rpm | %.3g Nm | event %.6f s', ...
    R.label,R.speed_rpm,R.torque_Nm,R.eventTime_s),'Interpreter','none');
target=find(c.Classes==R.label); xmax=1000*(gt_cycle_time(R,c.EvaluateAfterCycles)-R.eventTime_s);
xmin=1000*(gt_cycle_time(R,-1)-R.eventTime_s);
for j=1:numel(PP)
    P=PP{j}; x=P.relative_ms; mask=x>=xmin&x<=xmax;
    nexttile(tl); plot(x(mask),P.scores(mask,1),'Color',[.2 .5 .2],'LineWidth',1.2); hold on;
    names="P(Normal)";
    others=2:numel(c.Classes);
    if target>1
        plot(x(mask),P.scores(mask,target),'b','LineWidth',1.2); names(end+1)="P("+R.label+")";
        others(others==target)=[];
    end
    if ~isempty(others)
        plot(x(mask),max(P.scores(mask,others),[],2),'Color',[.85 .3 .15],'LineWidth',1);
        names(end+1)="max P(other fault)";
    end
    yline(P.threshold,'k--','Threshold','HandleVisibility','off'); xline(0,'k:','HandleVisibility','off');
    ylim([0 max(1.02,P.threshold+.02)]); xlim([xmin xmax]); grid on;
    xlabel('Time relative to event (ms)'); ylabel('Probability');
    title(c.ModelNames(j),'Interpreter','none'); legend(names,'Location','best','Interpreter','none');
    nexttile(tl); stairs(x(mask),P.truth(mask),'k--','LineWidth',1.6); hold on;
    stairs(x(mask),P.confirmed(mask),'b','LineWidth',1); xline(0,'k:','HandleVisibility','off');
    used=unique([0;1;P.truth(mask);P.confirmed(mask)]); labels=["Pending",c.Classes];
    yticks(used); yticklabels(labels(used+1)); ylim([-.3 max(used)+.6]);
    xlim([xmin xmax]); grid on; xlabel('Time relative to event (ms)');
    title('Confirmed output (includes confidence + consecutive decisions)');
    legend('Ground truth','Prediction','Location','best');
end
exportgraphics(f,path,'Resolution',160);
if ~c.ShowFigures, close(f); end
end
