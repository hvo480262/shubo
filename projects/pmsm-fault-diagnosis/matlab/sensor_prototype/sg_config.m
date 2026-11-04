function o=sg_config()
% Predeclared experiment settings. Do not change them after inspecting test.
o.RawDataRoots=strings(0,1); % optional complete raw-data roots; empty opens picker
o.Seed=11; o.MaxEpochs=50; o.WindowsPerClass=1600;
o.MinimumTrainingAge_cycles=0.05; % exclude intrinsically ambiguous onset from loss only
% All frames, including age <0.05, remain in causal replay and false-lock scoring.
o.EarlyThresholds=[.8 .9 .95 .98 .995];
o.EarlyMargins=[.1 .2 .3]; o.EarlyHolds_cycles=[.02 .04 .07 .1];
o.SensorTopology="unknown"; % three_independent / reconstructed / unknown
% Only three_independent enables the KCL gain detector.
o.SensorFastWindow_cycles=.05; o.SensorFitWindow_cycles=.5;
o.SensorHold_cycles=.03; o.SensorHealthyRecovery_cycles=.05;
o.MinimumGainDeviation=.03; o.GainRange=[.5 1.5];
o.MaxUnexplainedFraction=.15; o.MinFitSeparation=.15;
o.MaxOffsetRatio=.01; o.MinPhaseVarianceRatio=.01;
o.SensorNoiseFloor=.002; o.SensorCalibrationSafetyFactor=1.25;
o.ValidationGains=[.9 1.1]; o.TestGains=[.7 .8 .925 1.075 1.2 1.3];
o.RampDurations_cycles=[0 1];
o.SaveAllTraces=true;
end
