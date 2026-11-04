function F=gt_features(t,I,rpm,poles,c)
% 标签、转矩、故障时刻不进入特征或网络。所有窗为[t-W,t)，无未来样本。
t=double(t(:)); I=double(I); dt=median(diff(t)); Te=60/(double(rpm)*double(poles)); fs=1/dt;
assert(isequal(size(I),[numel(t),3])&&all(isfinite(I(:)))&&all(diff(t)>0));
assert(max(abs(diff(t)-dt))<max(1e-10,dt*1e-3));
nb=max(1,round(c.BaseWindowCycles*Te/dt)); ns=max(1,round(c.ShortWindowCycles*Te/dt));
if isfield(c,'HopCycles') && ~isempty(c.HopCycles)
    validateattributes(c.HopCycles,{'numeric'},{'scalar','positive','finite'});
    hop=max(1,round(c.HopCycles*Te/dt));
else
    hop=max(1,round(c.HopSeconds/dt));
end
edges=c.BandOrders/Te; K=size(edges,1);
assert(K==4&&size(edges,2)==2&&all(edges(:,1)>0)&&all(edges(:,2)>edges(:,1))&&max(edges(:))<.45*fs);
filters=cell(K,1); guard=0;
for k=1:K
    [b,a]=butter(1,edges(k,:)/(fs/2),'bandpass'); rad=max(abs(roots(a)));
    assert(rad>0&&rad<1); g=ceil(log(c.FilterTailTolerance)/log(rad)); guard=max(guard,g);
    filters{k}=struct('b',b,'a',a,'guardSamples',g);
end
idx=(guard+max(nb,ns)+1:hop:numel(t)).';
assert(numel(idx)>=c.SeqLength,'GeneralTCN:Short','连续录波不足以形成特征历史。');
E=energy(I,idx,nb); Ep=energy(max(I,0),idx,nb); Em=energy(min(I,0),idx,nb);
H=zeros(size(E)); nz=E>0; H(nz)=(Ep(nz)-Em(nz))./E(nz);
Es=energy(I,idx,ns); total=sum(Es,2)/ns; valid=total>0;
B=zeros(numel(idx),3*K);
for k=1:K
    y=filter(filters{k}.b,filters{k}.a,I,[],1); P=energy(y,idx,ns)/ns;
    q=zeros(size(P)); q(valid,:)=10*log10(max(P(valid,:)./total(valid),c.LogPowerFloor));
    B(:,(k-1)*3+(1:3))=q;
end
names=["H_A","H_B","H_C","RMS_A","RMS_B","RMS_C","ShortRMS_A","ShortRMS_B","ShortRMS_C"];
for k=1:K, names=[names,"B"+k+"_"+["A","B","C"]+"_dB"]; end %#ok<AGROW>
F=struct('time_s',t(idx),'features',single([H,ratio(E),ratio(Es),B]), ...
    'featureNames',names,'electricalPeriod_s',Te,'actualHop_s',hop*dt, ...
    'baseWindow_s',nb*dt,'shortWindow_s',ns*dt,'filterGuard_s',guard*dt, ...
    'noCurrent',~valid,'bandEdges_Hz',edges,'filters',{filters});
assert(all(isfinite(F.features(:))));
end
function E=energy(X,idx,n)
cs=[zeros(1,size(X,2));cumsum(X.^2,1)]; E=max(0,cs(idx,:)-cs(idx-n,:));
end
function R=ratio(E)
z=sum(E,2); R=zeros(size(E)); nz=z>0; R(nz,:)=sqrt(E(nz,:)./z(nz));
end
