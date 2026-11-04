function paths=gt_list_raw_paths(root,pattern)
% Explicit recursive walk, also works when dir('**') is unsupported.
if nargin<2||isempty(pattern), pattern='*_raw.mat'; end
assert(isfolder(root),'GeneralTCN:DataFolder','原始数据目录不存在：%s',char(root));
paths=strings(0,1); todo={char(root)};
while ~isempty(todo)
    here=todo{end}; todo(end)=[];
    f=dir(fullfile(here,pattern));
    for k=1:numel(f)
        if ~f(k).isdir
            paths(end+1,1)=string(fullfile(f(k).folder,f(k).name)); %#ok<AGROW>
        end
    end
    sub=dir(here); sub=sub([sub.isdir]);
    sub=sub(~ismember({sub.name},{'.','..'}));
    for k=1:numel(sub), todo{end+1}=fullfile(here,sub(k).name); end %#ok<AGROW>
end
paths=sort(paths);
end
