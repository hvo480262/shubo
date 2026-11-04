function [classes,label]=gt_classes(value)
% 拓扑标签固定为A/B/C相上下管，不猜测S1~S6与相/上下管的对应关系。
switches=["Sa1","Sa2","Sb1","Sb2","Sc1","Sc2"];
pairs=nchoosek(1:6,2); classes=["Normal",switches];
for k=1:size(pairs,1), classes(end+1)=strjoin(switches(pairs(k,:)),"_"); end %#ok<AGROW>
label=""; if nargin==0, return; end
assert((ischar(value)&&isrow(value))||(isstring(value)&&isscalar(value)), ...
    'GeneralTCN:Label','故障标签必须是一个字符串。');
s=lower(regexprep(strtrim(char(value)),'[\s,_+;]+',''));
if any(strcmp(s,{'normal','healthy','正常'})), label="Normal"; return; end
tokens=regexp(s,'s[abc][12]','match');
assert(~isempty(tokens)&&numel(tokens)<=2&&numel(unique(tokens))==numel(tokens)&& ...
    strcmp(strjoin(tokens,''),s),'GeneralTCN:Label', ...
    '标签应为Normal、Sa1、Sa1_Sb2等；只支持单管/同时双管，不猜测Sa6。');
[ok,ix]=ismember(string(tokens),lower(switches)); assert(all(ok));
label=strjoin(switches(sort(ix)),"_");
end
