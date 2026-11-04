function c=gt_select_data(c)
% Checkbox selection plus explicit roles. No raw MAT files are modified.
% Requires the v5 gt_read/pmsm_strict_split and patched gt_prepare.
assert(usejava('desktop'),'GeneralTCN:Desktop','勾选窗口需要MATLAB桌面。');
assert(contains(fileread(which('gt_prepare')),"isfield(c,'SelectedFiles')"), ...
    'GeneralTCN:SelectionPatch','请先将补丁gt_prepare.m复制到当前code目录，避免选中列表被忽略。');
files=dir(fullfile(c.DataFolder,'**',c.RawFilePattern));
assert(~isempty(files),'GeneralTCN:NoData', ...
    '未找到%s，请检查cfg.DataFolder和cfg.RawFilePattern。',c.RawFilePattern);
paths=sort(string(fullfile({files.folder},{files.name}))); paths=paths(:);
rows=cell(numel(paths),1); badFile=strings(0,1); badReason=strings(0,1);
for k=1:numel(paths)
    fprintf('读取元数据及分组 %d/%d: %s\n',k,numel(paths),paths(k));
    try
        D=gt_read(paths(k)); m=D.metadata;
        r=string(m.plannedRole);
        if ismissing(r)||strlength(r)==0, r="reserve"; end
        selected=~(string(m.eventKind)=="loadStep"&&~c.IncludeNormalLoadStep);
        rows{k}=struct('Use',selected,'RecordID',D.id,'File',paths(k), ...
            'Label',string(m.faultType),'Speed_rpm',m.speed_rpm,'Torque_Nm',m.torque_Nm, ...
            'EventTime_s',m.eventTime_s,'EventKind',string(m.eventKind), ...
            'GroupID',D.groupID,'SourceGroupID',D.groupID,'CurrentSHA256',D.hash, ...
            'ScenarioID',string(m.scenarioID),'ParentRecordID',string(m.parentRecordID), ...
            'PlannedRole',string(m.plannedRole),'Role',r);
    catch ME
        badFile(end+1,1)=paths(k); badReason(end+1,1)=string(ME.message); %#ok<AGROW>
    end
end
valid=~cellfun(@isempty,rows);
assert(any(valid),'GeneralTCN:NoValidData', ...
    '所有文件均读取失败，请核对原始数据格式。\n%s', ...
    strjoin(badFile+": "+badReason,newline));
T=struct2table(vertcat(rows{valid}));
bad=table(badFile,badReason,'VariableNames',{'File','Reason'});
condition=string(T.Speed_rpm)+" rpm / "+string(T.Torque_Nm)+" Nm";
conditions=unique(condition,'stable'); view=(1:height(T))';
committed=false; cancelled=false;
f=figure('Name','TCN 数据选择与用途分配','NumberTitle','off', ...
    'MenuBar','none','ToolBar','none','Position',[80 80 1240 720], ...
    'CloseRequestFcn',@cancel);
guard=onCleanup(@closeFigure); %#ok<NASGU>
uicontrol(f,'Style','text','Units','normalized','Position',[.02 .94 .96 .045], ...
    'HorizontalAlignment','left','String', ...
    '勾选=参加本次实验。只有用途为train的记录参与权重训练；其余用于独立评价。');
filter=uicontrol(f,'Style','popupmenu','Units','normalized','Position',[.02 .88 .28 .05], ...
    'String',[{'全部工况'};cellstr(conditions)],'Callback',@refresh);
mode=uicontrol(f,'Style','popupmenu','Units','normalized','Position',[.32 .88 .43 .05], ...
    'String',{'自动划分勾选数据（重新预定）','手动指定用途（严格按Role）'},'Callback',@refresh);
uicontrol(f,'Style','pushbutton','Units','normalized','Position',[.77 .88 .10 .05], ...
    'String','勾选当前工况','Callback',@(~,~)markVisible(true));
uicontrol(f,'Style','pushbutton','Units','normalized','Position',[.88 .88 .10 .05], ...
    'String','取消当前工况','Callback',@(~,~)markVisible(false));
roleList={'train','validation','calibration','test','reserve'};
bulk=uicontrol(f,'Style','popupmenu','Units','normalized','Position',[.02 .82 .19 .05], ...
    'String',roleList);
uicontrol(f,'Style','pushbutton','Units','normalized','Position',[.23 .82 .30 .05], ...
    'String','将当前工况内勾选记录设为此用途','Callback',@applyRole);
uicontrol(f,'Style','pushbutton','Units','normalized','Position',[.55 .82 .18 .05], ...
    'String','查看读取失败文件','Callback',@showFailures);
uicontrol(f,'Style','text','Units','normalized','Position',[.75 .81 .23 .06], ...
    'String',sprintf('calibration仅允许Normal。\n自动模式不采用Role列。'),'HorizontalAlignment','left');
tab=uitable(f,'Units','normalized','Position',[.02 .21 .96 .59], ...
    'ColumnName',{'使用','Role','故障类别','rpm','Nm','事件时刻(s)','事件类型','文件'}, ...
    'ColumnFormat',{'logical',roleList,'char','numeric','numeric','numeric','char','char'}, ...
    'ColumnEditable',[true false false false false false false false], ...
    'ColumnWidth',{45,105,85,65,55,95,85,560},'CellEditCallback',@editCell);
status=uicontrol(f,'Style','text','Units','normalized','Position',[.02 .09 .96 .10], ...
    'HorizontalAlignment','left');
uicontrol(f,'Style','pushbutton','Units','normalized','Position',[.54 .025 .20 .055], ...
    'String','检查划分并预览','Callback',@preview);
uicontrol(f,'Style','pushbutton','Units','normalized','Position',[.76 .025 .22 .055], ...
    'String','保存选择并继续','Callback',@commit);
refresh(); uiwait(f);
if cancelled||~committed, error('GeneralTCN:Cancelled','已取消选择，没有开始训练。'); end

    function refresh(varargin)
        v=get(filter,'Value');
        if v==1, view=(1:height(T))'; else, view=find(condition==conditions(v-1)); end
        data=[num2cell(T.Use(view)),cellstr(T.Role(view)),cellstr(T.Label(view)), ...
            num2cell(T.Speed_rpm(view)),num2cell(T.Torque_Nm(view)), ...
            num2cell(T.EventTime_s(view)),cellstr(T.EventKind(view)),cellstr(T.File(view))];
        set(tab,'Data',data,'ColumnEditable',[true get(mode,'Value')==2 false(1,6)]);
        q=T.Use;
        set(status,'String',sprintf(['有效%d条；读取失败%d条；勾选%d条（%d个类别）。\n' ...
            '配额：每类训练≥%d组，验证≥%d组，测试≥%d组；Normal额外校准≥%d组。\n' ...
            '每次保存建立新划分目录。不会重写旧结果；不会将一条记录的窗口拆到不同集合。'], ...
            height(T),height(bad),sum(q),numel(unique(T.Label(q))), ...
            c.MinTrainGroups,c.MinValidationGroups,c.MinTestGroups,c.MinCalibrationGroups));
    end
    function editCell(~,ev)
        i=view(ev.Indices(1));
        if ev.Indices(2)==1, T.Use(i)=logical(ev.NewData);
        elseif ev.Indices(2)==2, T.Role(i)=string(ev.NewData); end
        refresh();
    end
    function markVisible(value)
        T.Use(view)=value; refresh();
    end
    function applyRole(~,~)
        set(mode,'Value',2); ix=view(T.Use(view));
        T.Role(ix)=string(roleList{get(bulk,'Value')}); refresh();
    end
    function showFailures(~,~)
        if isempty(bad), msgbox('没有读取失败文件。'); return; end
        text=strjoin(bad.File+newline+bad.Reason,newline+newline);
        helpdlg(char(text),'读取失败明细（保存时也会导出CSV）');
    end
    function preview(~,~)
        try
            [A,C]=gt_selection_plan(T,c,get(mode,'Value')==2);
            disp(C); disp(conditionSummary(A));
            g=figure('Name','划分预览：记录数，不是滑窗数','NumberTitle','off');
            S=conditionSummary(A);
            uitable(g,'Data',table2cell(S),'ColumnName',S.Properties.VariableNames, ...
                'Units','normalized','Position',[0 0 1 1]);
        catch ME, errordlg(ME.message,'划分未通过'); end
    end
    function commit(~,~)
        try
            [A,C]=gt_selection_plan(T,c,get(mode,'Value')==2);
            % Unique folder; failure leaves an audit trail, never overwrites.
            base=fullfile(c.Root,'splits','manual_selection');
            if ~isfolder(base), mkdir(base); end
            folder=tempname(base); mkdir(folder);
            newc=c; newc.SelectedFiles=A.File; newc.Plan="manual";
            newc.UsePlannedRoles=true; newc.SplitFolder=folder;
            splitFile=fullfile(folder,sprintf('manual_seed%d.csv',c.SplitSeed));
            writetable(A,splitFile); writetable(T,fullfile(folder,'selection_inventory.csv'));
            writetable(C,fullfile(folder,'selection_coverage.csv'));
            writetable(conditionSummary(A),fullfile(folder,'selection_by_condition.csv'));
            writetable(bad,fullfile(folder,'selection_read_failures.csv'));
            cfg=newc; save(fullfile(folder,'selected_config.mat'),'cfg');
            c=newc; committed=true;
            fprintf('选择已保存：%s\n只有train记录用于拟合；两个模型共享同一划分。\n',folder);
            uiresume(f);
        catch ME, errordlg(ME.message,'未保存：请调整选择'); end
    end
    function cancel(~,~)
        cancelled=true; uiresume(f);
    end
    function closeFigure()
        if isgraphics(f), delete(f); end
    end
end

function S=conditionSummary(A)
roles=["train","validation","calibration","test","reserve"];
points=unique([A.Speed_rpm A.Torque_Nm],'rows');
S=table(points(:,1),points(:,2),'VariableNames',{'Speed_rpm','Torque_Nm'});
for role=roles
    n=zeros(height(S),1);
    for k=1:height(S)
        n(k)=sum(A.Speed_rpm==S.Speed_rpm(k)&A.Torque_Nm==S.Torque_Nm(k)&A.Role==role);
    end
    S.(char(role))=n;
end
end
