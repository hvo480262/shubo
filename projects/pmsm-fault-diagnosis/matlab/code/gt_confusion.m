function gt_confusion(cm,classes,stem,show)
% 行是真实类别，列是Pending及各预测类别；未判定也计入分母。
T=array2table(cm,'VariableNames',cellstr(["Pending",classes]));
T=addvars(T,classes(:),'Before',1,'NewVariableNames','TrueClass'); writetable(T,[stem '.csv']);
visible='off'; if show, visible='on'; end
n=numel(classes); f=figure('Visible',visible,'Color','w','Position',[80 80 max(750,45*n) max(550,30*n)]);
support=sum(cm,2); fraction=cm./max(support,1);
imagesc(fraction,[0 1]); colorbar; colormap(parula); axis tight;
xticks(1:n+1); xticklabels(["Pending",classes]); xtickangle(50);
yticks(1:n); yticklabels(classes); set(gca,'TickLabelInterpreter','none');
xlabel('Predicted class'); ylabel('True class'); title('Test windows: row fractions; absent rows have no support');
if n<=8
    for r=1:n
        for q=1:n+1, text(q,r,sprintf('%d',cm(r,q)),'HorizontalAlignment','center','Color','r'); end
    end
end
exportgraphics(f,[stem '.png'],'Resolution',160); if ~show, close(f); end
end
