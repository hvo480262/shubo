function F=pmsm_angle_features(source,varargin)
% DNFD-inspired causal angle-domain candidates; not a DNFD threshold replica.
% Inputs: raw MAT path or struct with timeAbsolute, iabc, metadata.
% Prefer ElectricalAngle (UNWRAPPED electrical radians at each current sample).
% Otherwise integrate measured speed in diagnostics using past-only lookup.
% Nominal-rpm fallback requires explicit AllowNominalSpeed=true.
% No label or event time is read. Availability time is the bracketing RAW time.
% Outputs: Angle9=[Qabc,Dabc,RMSratios]; Angle21 adds four order bands/phase.
% q=abs(u)+u; d=abs(u)-u. Pointwise L2 denominator has no epsilon.
p=inputParser;
addParameter(p,'SamplesPerCycle',128,@(x) isscalar(x)&&x>=32&&fix(x)==x);
addParameter(p,'ElectricalAngle',[],@(x) isnumeric(x)&&isreal(x));
addParameter(p,'AllowNominalSpeed',false,@(x) islogical(x)&&isscalar(x));
addParameter(p,'AntiAliasCutoffHz',0,@(x) isscalar(x)&&isfinite(x)&&x>=0);
addParameter(p,'AntiAliasOrder',4,@(x) isscalar(x)&&x>=1&&fix(x)==x);
addParameter(p,'FilterTailTolerance',1e-4,@(x) isscalar(x)&&x>0&&x<1);
addParameter(p,'AngularOversample',1,@(x) isscalar(x)&&x>=1&&fix(x)==x);
parse(p,varargin{:}); o=p.Results;
if ischar(source)||isstring(source), D=load(source); else, D=source; end
t=double(D.timeAbsolute(:)); I=double(D.iabc); N=o.SamplesPerCycle;
assert(numel(t)>=3&&size(I,1)==numel(t)&&size(I,2)==3&& ...
    all(isfinite(t))&&all(diff(t)>0)&&all(isfinite(I(:))),'Invalid current/time data.');
if ~isempty(o.ElectricalAngle)
    theta=double(o.ElectricalAngle(:)); angleSource='measured electrical angle';
elseif isfield(D,'diagnostics')&&all(isfield(D.diagnostics,{'speedTime','speedRpm'}))
    st=double(D.diagnostics.speedTime(:)); sr=double(D.diagnostics.speedRpm(:));
    assert(numel(st)>=2&&numel(st)==numel(sr)&&all(diff(st)>0)&& ...
        all(isfinite(st))&&all(isfinite(sr)),'Invalid measured speed.');
    assert(t(1)>=st(1)-1e-10&&t(end)<=st(end)+1e-10,'Speed log must cover the current record.');
    rpm=interp1(st,sr,min(max(t,st(1)),st(end)),'previous');
    assert(all(rpm>0),'This version supports forward rotation only, without stops.');
    theta=cumtrapz(t,2*pi*D.metadata.polePairs*rpm/60);
    angleSource='integrated measured speed (relative electrical angle)';
elseif o.AllowNominalSpeed
    theta=2*pi*D.metadata.polePairs*D.metadata.speed_rpm/60*(t-t(1));
    angleSource='nominal constant speed; NOT variable-speed normalization';
    warning('PMSM:NominalAngle','Nominal rpm cannot represent within-record speed changes.');
else
    error('PMSM:NoAngle','Supply unwrapped electrical angle or measured speed; nominal fallback is disabled.');
end
assert(numel(theta)==numel(t)&&all(isfinite(theta))&&all(diff(theta)>0), ...
    'Electrical angle must be unwrapped and strictly increasing; reverse/stop unsupported.');
theta=theta-theta(1); step=2*pi/(N*o.AngularOversample);
assert(max(diff(theta))<=step,'Raw angle sampling is too sparse for requested resolution.');
den=hypot(hypot(I(:,1),I(:,2)),I(:,3)); valid=den>0;
U=zeros(size(I)); U(valid,:)=bsxfun(@rdivide,I(valid,:),den(valid));
% Calibrate one healthy electrical cycle at the beginning of the record.
% This reference is fixed thereafter; no fault label or fault time is read.
calRight=find(theta>=2*pi,1,'first');
assert(~isempty(calRight)&&calRight>3,'GeneralTCN:AmplitudeReference', ...
    '原始记录缺少完整的故障前参考电周期。');
imRef=sqrt((2/3)*mean(sum(I(1:calRight-1,:).^2,2)));
assert(isfinite(imRef)&&imRef>eps,'GeneralTCN:AmplitudeReference', ...
    '故障前电流幅值为零；无法做半波幅值归一化。');
Z=[U,abs(U)+U,abs(U)-U,I.^2,double(~valid),I];
guard=0;
if o.AntiAliasCutoffHz>0
    dt=median(diff(t)); fs=1/dt;
    assert(max(abs(diff(t)-dt))<max(1e-10,dt*1e-3),'Anti-alias stage requires uniform raw sampling.');
    assert(o.AntiAliasCutoffHz<fs/2,'Anti-alias cutoff exceeds raw Nyquist.');
    [z,poles,gain]=butter(o.AntiAliasOrder,o.AntiAliasCutoffHz/(fs/2),'low');
    radius=max(abs(poles)); assert(radius<1&&radius>0);
    guard=ceil(log(o.FilterTailTolerance)/log(radius))*dt;
    [sos,gain]=zp2sos(z,poles,gain);
    Z(:,1:12)=gain*sosfilt(sos,Z(:,1:12)); % causal, no delay subtraction
    Z(:,14:16)=gain*sosfilt(sos,Z(:,14:16));
end
% Piecewise-constant angle integration: each sample holds until next sample.
% Angular bin averaging attenuates high orders but is NOT an ideal anti-alias filter.
integral=[zeros(1,size(Z,2));cumsum(bsxfun(@times,diff(theta),Z(1:end-1,:)),1)];
edges=(0:floor(theta(end)/step))'*step;
assert(numel(edges)>N*o.AngularOversample,'Record must contain at least one electrical cycle.');
S=interp1(theta,integral,edges,'linear'); bins=diff(S,1,1)/step;
right=interp1(theta,(1:numel(t))',edges(2:end),'next'); right=round(right);
validAfterTime=t(1)+guard;
if o.AngularOversample>1
    [z,ap,ag]=butter(o.AntiAliasOrder,0.8/o.AngularOversample,'low');
    [sos,ag]=zp2sos(z,ap,ag);
    bins(:,1:12)=ag*sosfilt(sos,bins(:,1:12));
    bins(:,14:16)=ag*sosfilt(sos,bins(:,14:16));
    agGuard=ceil(log(o.FilterTailTolerance)/log(max(abs(ap))));
    start=find(t(right)>=validAfterTime,1);
    assert(~isempty(start)&&start+agGuard<=numel(right),'Insufficient anti-alias filter warm-up.');
    validAfterTime=t(right(start+agGuard));
    sel=(o.AngularOversample:o.AngularOversample:numel(right))';
    % Preserve exact zero-current occupancy by averaging the fine bins.
    occupancy=mean(reshape(bins(1:numel(sel)*o.AngularOversample,13),o.AngularOversample,[]),1)';
    bins=bins(sel,:); bins(:,13)=occupancy; right=right(sel); edges=[0;edges(sel+1)];
end
F=struct; F.angleSource=angleSource; F.samplesPerCycle=N;
F.angle_rad=edges(2:end); F.timeAvailable_s=t(right);
F.equivalentTime_s=interp1(theta,t,edges(2:end),'linear');
F.rawRightIndex=right; F.Uabc=bins(:,1:3);
F.filterGuard_s=validAfterTime-t(1);
F.Base9=nan(size(bins,1),9); F.Bands21=nan(size(bins,1),21);
F.Early12=nan(size(bins,1),12); F.zeroVectorFraction=nan(size(bins,1),1);
F.AmpHalf12=nan(size(bins,1),12);
F.amplitudeReference_A=imRef;
F.amplitudeReferenceEnd_s=t(calRight-1);
F.featureNamesBase={'Q_A','Q_B','Q_C','D_A','D_B','D_C','R_A','R_B','R_C'};
F.featureNamesBands=F.featureNamesBase;
orders={1,[3 5],[2 4 6],7:12}; bandNames={'ord1','ord3_5','ord2_4_6','ord7_12'};
for j=1:4
 for ph={'A','B','C'}
    F.featureNamesBands{end+1}=[bandNames{j} '_' ph{1}];
 end
end
for k=1:size(bins,1)
    for z=1:2
        w=round(N*[0.25 0.5]); width=w(z);
        if k>=width, F.Early12(k,(z-1)*6+(1:6))=mean(bins(k-width+1:k,4:9),1); end
        if k>=width
            raw=bins(k-width+1:k,14:16)/imRef;
            F.AmpHalf12(k,(z-1)*6+(1:6))= ...
                [mean(max(raw,0),1),mean(max(-raw,0),1)];
        end
    end
    if k<N, continue; end
    win=bins(k-N+1:k,:); e=max(0,mean(win(:,10:12),1));
    rr=zeros(1,3); if sum(e)>0, rr=sqrt(e/sum(e)); end
    F.Base9(k,:)=[mean(win(:,4:9),1),rr];
    F.zeroVectorFraction(k)=mean(win(:,13));
    X=win(:,1:3); X=bsxfun(@minus,X,mean(X,1));
    % Periodic Hann within a trailing window: no access to future samples.
    h=0.5-0.5*cos(2*pi*(0:N-1)'/N);
    P=abs(fft(bsxfun(@times,X,h),N,1)).^2;
    total=sum(P(2:floor(N/2)+1,:),1); B=zeros(1,12);
    for b=1:4
        energy=sum(P(orders{b}+1,:),1); ratio=zeros(1,3);
        ok=total>0; ratio(ok)=energy(ok)./total(ok);
        B((b-1)*3+(1:3))=ratio;
    end
    F.Bands21(k,:)=[F.Base9(k,:),B];
end
startTimes=interp1(theta,t,edges(1:end-1),'linear');
warm=false(size(F.timeAvailable_s));
warm(N:end)=startTimes(1:end-N+1)>=validAfterTime;
F.ready=all(isfinite(F.Base9),2)&warm;
F.notes=['New Angle9/Angle21 features, NOT old Base9/Bands21 definitions. ', ...
    'Requires retraining and train-only scaling. No fault-aligned crop. ', ...
    'Use timeAvailable_s for latency, not equivalentTime_s. ', ...
    'Zero-vector fraction is a quality flag, not a Normal decision. ', ...
    'Causal anti-alias stages are optional here and enabled by gt_record_features. ', ...
    'Validate residual switching-ripple aliasing on acquired data.'];
end
