function path=gt_save_raw(timeAbsolute,iabc,label,rpm,torque,eventTime,poles,folder,groupID)
% 可选：将一次新仿真的原始连续三相电流保存为训练程序支持的格式。
% 输入iabc为N×3安培值，timeAbsolute为对应绝对秒；不要传归一化电流。
% 同一次仿真的不同裁剪段必须传相同groupID。此函数不修改Simulink故障或工况。
if nargin<8||isempty(folder), folder=fullfile(fileparts(fileparts(mfilename('fullpath'))),'data'); end
stamp=char(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
if nargin<9||isempty(groupID), groupID=['run_' stamp]; end
[~,label]=gt_classes(label); timeAbsolute=double(timeAbsolute(:)); iabc=double(iabc);
assert(isequal(size(iabc),[numel(timeAbsolute),3])&&all(isfinite(iabc(:)))&&all(diff(timeAbsolute)>0));
validateattributes(rpm,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(torque,{'numeric'},{'scalar','real','finite'});
validateattributes(poles,{'numeric'},{'scalar','integer','positive'});
validateattributes(eventTime,{'numeric'},{'scalar','real','finite'});
assert(timeAbsolute(1)<eventTime&&timeAbsolute(end)>eventTime,'GeneralTCN:Save','需包含事件前后的连续录波。');
kind='fault'; if label=="Normal", kind='steady'; end
metadata=struct('schema','fault_transient_raw_v1','faultType',char(label), ...
    'hasInjectedFault',label~="Normal",'speed_rpm',double(rpm),'torque_Nm',double(torque), ...
    'polePairs',double(poles),'faultTime_s',double(eventTime),'eventTime_s',double(eventTime), ...
    'eventKind',kind,'skipCycles',0,'groupID',char(groupID),'createdAt',stamp, ...
    'preprocessing','none: raw continuous three-phase current', ...
    'columnsOfIabc',{{'ia','ib','ic'}},'units','time: s; current: A; speed: rpm; torque: N*m');
D=struct('timeAbsolute',timeAbsolute,'iabc',iabc,'metadata',metadata);
if ~isfolder(folder), mkdir(folder); end
name=sprintf('%s_%grpm_%gNm_t%.6f_%s_raw.mat',label,rpm,torque,eventTime,stamp);
path=fullfile(folder,name); assert(~isfile(path),'GeneralTCN:Save','同名文件已存在，未覆盖。');
save(path,'D','-v7'); fprintf('已保存原始记录：%s\n',path);
end
