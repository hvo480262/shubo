function report=RUN_FASTLOCK_BATCH(modelPath,rawDir,threshold)
% Replays a FROZEN model over all *_raw.mat beneath rawDir.
% With no rawDir, first tries the frozen test manifest, then asks for a file.
% Report includes every record: wrong/missing/pre-event lock fails.
root=fileparts(mfilename('fullpath')); addpath(fullfile(root,'code'));
if nargin<1||isempty(modelPath)
    [f,p]=uigetfile('*.mat','选择冻结的 trained_model.mat');
    if isequal(f,0), report=[]; return; end; modelPath=fullfile(p,f);
end
if nargin<3, threshold=[]; end
model=load(modelPath,'Model');
assert(isfield(model,'Model'),'FastLock:Model','第一个参数必须是 trained_model.mat。');
names=strings(0,1);
if nargin<2||isempty(rawDir), rawDir=""; else, rawDir=string(rawDir); end
if strlength(rawDir)==0
    M=model.Model;
    if isfield(M,'manifest')&&istable(M.manifest)&& ...
            all(ismember({'File','Role'},M.manifest.Properties.VariableNames))
        test=M.manifest(string(M.manifest.Role)=="test",:);
        paths=string(test.File);
        if ~isempty(paths)&&all(isfile(paths))
            names=paths(:);
            fprintf('直接使用冻结模型清单里的 %d 条 test 原始记录。\n',numel(names));
        end
    end
end
if isempty(names)
    if strlength(rawDir)==0
        [f,p]=uigetfile('*_raw.mat','选择任意一条原始 *_raw.mat，随后扫描其文件夹及子文件夹');
        if isequal(f,0), report=[]; return; end
        rawDir=string(p);
    end
    if isfile(rawDir)
        assert(endsWith(lower(rawDir),'_raw.mat'),'FastLock:NotRaw', ...
            '指定文件不是 *_raw.mat：%s',char(rawDir));
        names=rawDir;
    else
        assert(isfolder(rawDir),'FastLock:NoFolder','原始数据目录不存在：%s',char(rawDir));
        names=scanRaw(char(rawDir));
    end
end
assert(~isempty(names),'FastLock:NoRaw', ...
    ['指定目录及子目录找不到 *_raw.mat：%s\n', ...
     '请先解压原始数据，传入含有这些 MAT 的实际目录；', ...
     '也可只传 trained_model.mat 自动尝试冻结 test 清单。'],char(rawDir));
names=sort(names(:));
assert(numel(unique(names))==numel(names),'FastLock:Duplicate','原始文件列表有重复。');
rows=cell(numel(names),1);
for k=1:numel(names)
    rows{k}=RUN_FASTLOCK_REPLAY(modelPath,char(names(k)),threshold);
    fprintf('%d/%d %s -> %s %.3f T\n',k,numel(names), ...
        char(rows{k}.Label),char(rows{k}.Predicted),rows{k}.Lock_cycles);
end
T=struct2table(vertcat(rows{:}));
A=load(modelPath,'Model');
T.SplitRole=repmat("untracked",height(T),1);
if isfield(A.Model,'manifest')&&all(ismember({'RecordID','Role'},A.Model.manifest.Properties.VariableNames))
    [isKnown,at]=ismember(T.RecordID,string(A.Model.manifest.RecordID));
    roles=string(A.Model.manifest.Role); T.SplitRole(isKnown)=roles(at(isKnown));
end
folder=fullfile(fileparts(modelPath),['FASTLOCK_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
mkdir(folder); writetable(T,fullfile(folder,'LOCK_record_metrics.csv'));
save(fullfile(folder,'LOCK_replay.mat'),'T','modelPath','rawDir','threshold');
isFault=T.Label~="Normal"; isSingle=isFault&~contains(T.Label,"_");
isDouble=isFault&contains(T.Label,"_");
report=struct('outputFolder',folder,'Records',height(T), ...
    'SinglesMet',sum(T.MetDeadline(isSingle)),'SinglesTotal',sum(isSingle), ...
    'DoublesMet',sum(T.MetDeadline(isDouble)),'DoublesTotal',sum(isDouble), ...
    'WrongLocks',sum(~T.Correct&isFault&~isnan(T.LockTime_s)), ...
    'PreEventLocks',sum(T.PreEventFalseLock), ...
    'NormalFalseLocks',sum(T.Label=="Normal"&~isnan(T.LockTime_s)));
disp(report);
if any(T.SplitRole~="test")
    fprintf('包含非冻结 test 的记录；按 SplitRole 筛选后才能报告测试指标。\n');
end

function names=scanRaw(folder)
% MATLAB 的 dir('**') 在不同版本和目录层级下行为不一；显式递归。
names=strings(0,1); todo={folder};
while ~isempty(todo)
    here=todo{end}; todo(end)=[];
    files=dir(fullfile(here,'*_raw.mat'));
    for k=1:numel(files)
        if ~files(k).isdir, names(end+1,1)=string(fullfile(files(k).folder,files(k).name)); end %#ok<AGROW>
    end
    sub=dir(here); sub=sub([sub.isdir]);
    sub=sub(~ismember({sub.name},{'.','..'}));
    for k=1:numel(sub), todo{end+1}=fullfile(here,sub(k).name); end %#ok<AGROW>
end
end
end
