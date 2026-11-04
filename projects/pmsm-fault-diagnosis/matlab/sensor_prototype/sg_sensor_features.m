function S=sg_sensor_features(t,I,theta,at,o)
% Past-only raw-current sufficient statistics. No event/label/nominal gain input.
% For a sole multiplicative error y_j=g*i_j, r=sum(y)=beta*y_j,
% beta=1-1/g. Intercept fitted separately to reject additive offsets.
t=double(t(:)); I=double(I); theta=double(theta(:)); at=double(at(:));
assert(size(I,1)==numel(t)&&size(I,2)==3&&numel(theta)==numel(t));
assert(all(diff(t)>0)&&all(diff(theta)>0)&&all(isfinite(I(:))));
assert(all(at>=t(1)&at<=t(end)));
r=sum(I,2); A=[I,I.^2,r,r.^2,I.*r]; C=[zeros(1,11);cumsum(A,1)];
right=round(interp1(t,(1:numel(t))',at,'previous'));
coord=theta/(2*pi); z=coord(right);
S=struct('rhoFast',nan(numel(at),1),'rhoFit',nan(numel(at),1), ...
    'amplitude',nan(numel(at),1),'gain',nan(numel(at),3), ...
    'unexplained',nan(numel(at),3),'offsetRatio',nan(numel(at),3), ...
    'varianceRatio',nan(numel(at),3),'ready',false(numel(at),1));
for w=1:2
    width=o.SensorFastWindow_cycles; if w==2, width=o.SensorFitWindow_cycles; end
    left=interp1(coord,(1:numel(t))',z-width,'next',NaN);
    good=isfinite(left)&left<=right; a=round(left(good)); b=right(good);
    n=b-a+1; V=(C(b+1,:)-C(a,:))./n;
    ex=V(:,1:3); ex2=V(:,4:6); er=V(:,7); er2=V(:,8); exr=V(:,9:11);
    energy=sum(ex2,2); rho=sqrt(max(0,er2)./max(energy,realmin));
    if w==1, S.rhoFast(good)=rho; continue; end
    S.ready(good)=true; S.rhoFit(good)=rho; S.amplitude(good)=sqrt(energy);
    vx=max(0,ex2-ex.^2); vr=max(0,er2-er.^2); cov=exr-ex.*er;
    beta=cov./max(vx,realmin); intercept=er-beta.*ex;
    unexplained=max(0,vr-cov.^2./max(vx,realmin))./max(vr,realmin);
    S.gain(good,:)=1./(1-beta);
    S.unexplained(good,:)=unexplained;
    S.offsetRatio(good,:)=abs(intercept)./max(sqrt(energy),realmin);
    S.varianceRatio(good,:)=vx./max(energy,realmin);
end
S.ready=S.ready&isfinite(S.rhoFast);
end
