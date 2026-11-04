function result=RUN_HALFWAVE_COMPARE(modelPath,rawRoot)
% Frozen-split Angle9 versus Angle9Half, then identical 1 ms lock replay.
% Run with no arguments: choose the original Angle9 trained_model.mat.
here=fileparts(mfilename('fullpath')); addpath(fullfile(here,'code'));
if nargin<1||isempty(modelPath)
    [f,p]=uigetfile('*.mat','选择原始 Angle9 的 trained_model.mat');
    if isequal(f,0), result=[]; return; end
    modelPath=fullfile(p,f);
end
A=load(modelPath,'Model');
assert(isfield(A,'Model'),'Halfwave:Model','请选择含 Model 的 trained_model.mat。');
M=A.Model;
assert(string(M.name)=="Angle9",'Halfwave:Model','请选原始 Angle9 模型，不能选 Angle21。');
assert(isfield(M,'manifest')&&istable(M.manifest)&& ...
    all(ismember({'File','Role','RecordID','CurrentSHA256','GroupID'}, ...
    M.manifest.Properties.VariableNames)),'Halfwave:Manifest', ...
    '模型没有可冻结的完整原始数据划分清单。');
manifest=M.manifest;
assert(numel(unique(string(manifest.RecordID)))==height(manifest), ...
    'Halfwave:Duplicate','冻结清单中存在重复记录。');
oldFiles=string(manifest.File);
if nargin<2||isempty(rawRoot)
    if all(isfile(oldFiles))&&isfolder(M.cfg.DataFolder)
        rawRoot=string(M.cfg.DataFolder);
        fprintf('沿用冻结模型的原始数据目录：%s\n',char(rawRoot));
    else
        rawRoot=uigetdir(pwd,'选择覆盖冻结清单全部工况和角度的原始 MAT 总目录');
        if isequal(rawRoot,0), result=[]; return; end
    end
end
rawRoot=string(rawRoot);
assert(isfolder(rawRoot),'Halfwave:DataRoot','数据总目录不存在：%s',char(rawRoot));
paths=gt_list_raw_paths(rawRoot,'*_raw.mat');
fileNames=strings(numel(paths),1);
for k=1:numel(paths)
    [~,n,e]=fileparts(paths(k)); fileNames(k)=string(n)+string(e);
end
assert(~isempty(paths),'Halfwave:NoRaw','目录及子目录找不到 *_raw.mat：%s',char(rawRoot));
selected=strings(height(manifest),1); missing=strings(0,1);
for k=1:height(manifest)
    [~,name,ext]=fileparts(oldFiles(k));
    hit=paths(lower(fileNames)==lower(string(name)+string(ext)));
    if numel(hit)~=1, missing(end+1,1)=oldFiles(k); %#ok<AGROW>
    else, selected(k)=hit; end
end
if ~isempty(missing)
    error('Halfwave:MissingRaw', ...
        '无法唯一匹配冻结清单中的 %d 条记录；须选择覆盖全部原始工况的总目录。第一条：%s', ...
        numel(missing),char(missing(1)));
end
manifest.File=selected;
c=M.cfg;
c.Root=here; c.DataFolder=char(rawRoot);
c.OutputRoot=fullfile(here,'results');
c.SplitFolder=fullfile(here,'splits',['halfwave_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'))]);
c.SelectedFiles=selected; c.ModelNames=["Angle9","Angle9Half"];
c.Seeds=double(M.seed); c.Train=true;
if ~isfolder(c.SplitFolder), mkdir(c.SplitFolder); end
splitFile=fullfile(c.SplitFolder,sprintf('%s_seed%d.csv',c.Plan,c.SplitSeed));
writetable(manifest,splitFile); % gt_prepare checks every raw SHA and retains frozen Role/GroupID
fprintf('冻结清单 %d 条已映射；接下来重训两个模型并做同口径 1 ms 锁定。\n',height(manifest));
training=gt_run(c);
newManifest=readtable(fullfile(training.outputFolder,'locked_manifest.csv'),'TextType','string');
[ok,ix]=ismember(string(manifest.RecordID),string(newManifest.RecordID));
assert(all(ok)&&height(newManifest)==height(manifest),'Halfwave:SplitChanged', ...
    '重训数据与冻结清单记录不一致，不能用于成对比较。');
assert( ...
    all(string(manifest.Role)==string(newManifest.Role(ix))), ...
    'Halfwave:SplitChanged','训练前后记录角色变化，不能用于成对比较。');
baseModel=fullfile(training.outputFolder,sprintf('Angle9_seed%d',M.seed),'trained_model.mat');
halfModel=fullfile(training.outputFolder,sprintf('Angle9Half_seed%d',M.seed),'trained_model.mat');
b=RUN_FASTLOCK_BATCH(baseModel);
h=RUN_FASTLOCK_BATCH(halfModel);
B=readtable(fullfile(b.outputFolder,'LOCK_record_metrics.csv'),'TextType','string');
H=readtable(fullfile(h.outputFolder,'LOCK_record_metrics.csv'),'TextType','string');
[same,j]=ismember(B.RecordID,H.RecordID);
assert(all(same)&&height(B)==height(H),'Halfwave:Pair','测试记录无法一一配对。');
H=H(j,:);
paired=table(B.RecordID,B.Label,B.SplitRole,B.Lock_cycles,H.Lock_cycles, ...
    B.Correct,H.Correct,B.MetDeadline,H.MetDeadline, ...
    'VariableNames',{'RecordID','Label','SplitRole','Angle9Lock_cycles', ...
    'HalfwaveLock_cycles','Angle9Correct','HalfwaveCorrect', ...
    'Angle9MetDeadline','HalfwaveMetDeadline'});
file=fullfile(training.outputFolder,'PAIRED_FASTLOCK.csv');
writetable(paired,file);
test=paired.SplitRole=="test";
single=test&paired.Label~="Normal"&~contains(paired.Label,"_");
double=test&contains(paired.Label,"_");
result=struct('outputFolder',training.outputFolder,'pairedFile',file, ...
    'SingleTotal',sum(single),'Angle9SingleMet',sum(paired.Angle9MetDeadline(single)), ...
    'HalfwaveSingleMet',sum(paired.HalfwaveMetDeadline(single)), ...
    'DoubleTotal',sum(double),'Angle9DoubleMet',sum(paired.Angle9MetDeadline(double)), ...
    'HalfwaveDoubleMet',sum(paired.HalfwaveMetDeadline(double)), ...
    'Angle9Wrong',sum(~paired.Angle9Correct(single|double)), ...
    'HalfwaveWrong',sum(~paired.HalfwaveCorrect(single|double)));
disp(result);
end
