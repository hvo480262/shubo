# Methods and interpretation

## Open-circuit task

The classifier labels are Normal; Sa1, Sa2, Sb1, Sb2, Sc1, Sc2; and all 15 unordered pairs of those switches. The phase/upper-lower naming convention is explicit in `matlab/code/gt_classes.m`; the mapping to each physical model gate must be checked before injecting faults.

For a measured current vector i = [ia, ib, ic], the pointwise denominator is sqrt(ia² + ib² + ic²). The implementation computes normalized currents only where the denominator is positive and tracks zero-vector occupancy. It does not silently add an arbitrary epsilon to every vector.

The Angle9 features comprise the three Q means, three D means, and three phase RMS ratios over an electrical cycle, where Q = |u| + u and D = |u| - u. These are twice the positive and negative magnitudes; they should not be confused with unscaled half-wave definitions. Electrical-angle resampling, causal filtering/warm-up, and feature availability times are implemented in `pmsm_angle_features.m`.

The retained network is a temporal convolutional classifier. Feature settings in generic configuration files are source defaults and may differ from the frozen model used for the saved evidence; the CSV outputs and provenance define the reported run. The public package does not contain the frozen network weights.

## First irreversible decision

The original `gt_fast_lock_1ms` uses only predicted class probabilities and timestamps. Normal predictions, predictions below threshold, or a class change reset the candidate interval. A non-normal class locks when the same eligible class persists for at least 1 ms; once locked, later changes do not revise the decision. It does not receive the true fault class or injection time. Evaluation uses known injection times only to measure performance.

Single-switch timely success means a correct first final lock within 0.5 electrical cycle; double-switch timely success uses 0.75 cycle. The median delays reported in the main README concern the selected Angle9 policy in the saved 66-record set. The 1 ms hold is not inference latency.

## Threshold selection and comparison

The original script freezes models and record roles, then evaluates candidate thresholds on validation data. It favors no normal false locks where available, maximizes timely successes minus wrong fault locks minus five times normal false locks, and uses predefined tie-breakers. Test results are replayed after selection. The saved selection is 0.90 for Angle9 and 0.925 for AngleAmpHalf.

The amplitude-normalized comparison fixes a healthy reference from the beginning of each record and forms 0.25/0.5-cycle half-wave features. A deployment implementation would need to maintain and freeze a healthy reference causally. The saved comparison changed both the denominator and window lengths, preventing a clean causal attribution to either change alone.

## Gain drift and the shared denominator

If one measured phase is multiplied by a gain, both that phase and the common L2 denominator change. Consequently, normalized features of all three phases can move. Normalization alone does not distinguish this measurement fault from an inverter fault.

The separately saved gain prototype uses the raw-current residual r = ya + yb + yc. Under ideal three-wire current balance and a sole multiplicative error yj = g*ij, r = (1 - 1/g)*yj. Past-window regression can therefore estimate gain from beta = 1 - 1/g. Its applicability depends on independently measured phase currents and the physical validity of the current-balance relation. The selected routines included here are not a full calibrated joint diagnostic package.

## Evidence boundaries

- Only one nominal operating condition is represented in the reported open-circuit test subset.
- A normal-current source group crosses train, validation, and test in the inherited split; the roles are frozen but not fully source-disjoint. Test results have also informed continuing method development.
- Three normal records do not establish a low long-duration false-alarm rate.
- The 108 gain cases share only three parent records and belong to a separate prototype.
- The archived source model and methods have not been established as a hardware-validated, real-time deployment system.
- This repository does not report the separate EAST reconstruction timing study as a result of this PMSM classifier.
