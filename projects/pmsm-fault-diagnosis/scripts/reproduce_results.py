"""Recompute saved record-level results using only the Python standard library."""
from pathlib import Path
import csv
import json
import statistics

ROOT = Path(__file__).resolve().parents[1]
def read(name):
    with (ROOT / 'evidence' / name).open(encoding='utf-8-sig', newline='') as handle:
        return list(csv.DictReader(handle))

def calculate():
    all_rows = read('open_circuit_records.csv')
    summary = read('open_circuit_summary.csv')
    assert len(all_rows) == 264
    records = [r for r in all_rows if r['Model'] == 'Angle9' and r['Policy'] == 'validation_selected']
    assert len(records) == 66 and len({r['RecordID'] for r in records}) == 66
    assert all(r['Role'] == 'test' and float(r['Speed_rpm']) == 1000 and float(r['Torque_Nm']) == 10 for r in records)
    assert all(abs(float(r['Threshold']) - .90) < 1e-10 for r in records)
    angles = {int(r['ScenarioID'].rsplit('_', 1)[1]) for r in records}
    assert angles == {90, 210, 330}
    groups = {k: [r for r in records if r['FaultKind'] == k] for k in ['single', 'double', 'normal']}
    assert [len(groups[k]) for k in ['single', 'double', 'normal']] == [18, 45, 3]
    assert len({r['Label'] for r in groups['single']}) == 6
    assert len({r['Label'] for r in groups['double']}) == 15
    def met(kind):
        return sum(int(r['MetDeadline']) for r in groups[kind])
    def wrong(rows):
        return sum(int(r['WrongLock']) for r in rows)
    selected = next(r for r in summary if r['Model'] == 'Angle9' and r['Policy'] == 'validation_selected')
    assert met('single') == int(selected['SingleMet']) == 2
    assert met('double') == int(selected['DoubleMet']) == 42
    assert wrong(groups['single'] + groups['double']) == int(selected['FaultWrong']) == 0
    assert wrong(groups['normal']) == int(selected['NormalWrong']) == 0
    assert all(int(r['Correct']) == 1 and r['Predicted'] == r['Label'] for r in groups['single'] + groups['double'])
    gain = read('sensor_gain_records.csv')
    parents = read('sensor_gain_parents.csv')
    assert len(gain) == 108 and len(parents) == 3
    for parent in parents:
        children = [r for r in gain if r['ParentRecordID'] == parent['ParentRecordID']]
        assert len(children) == int(parent['CorrelatedCases']) == 36
        assert sum(int(r['CorrectLock']) for r in children) == int(parent['CorrectLocks']) == 36
    assert all(int(r['Sensor']) == 1 and int(r['CorrectLock']) == 1 and int(r['FalseLock']) == 0 and int(r['OpenFalseOnSensor']) == 0 for r in gain)
    result = {
        'open_circuit': {
            'records': len(records), 'operating_condition': {'speed_rpm': 1000, 'torque_Nm': 10, 'angles_deg': sorted(angles)},
            'single_timely': [met('single'), len(groups['single'])],
            'double_timely': [met('double'), len(groups['double'])],
            'single_median_lock_ms': statistics.median(float(r['Lock_ms']) for r in groups['single']),
            'double_median_lock_ms': statistics.median(float(r['Lock_ms']) for r in groups['double']),
            'wrong_final_fault_locks': wrong(groups['single'] + groups['double']),
            'normal_false_locks': wrong(groups['normal']),
            'threshold': .90, 'confirmation_ms': 1,
            'source_overlap_reported': bool(read('cross_role_source_groups.csv')),
        },
        'separate_sensor_prototype': {
            'correlated_cases': len(gain), 'parent_records': len(parents),
            'correct_locks': sum(int(r['CorrectLock']) for r in gain),
            'median_lock_delay_ms': statistics.median(float(r['LockDelay_ms']) for r in gain),
        },
        'interpretation': 'Saved simulation/replay evidence only; not independent multi-condition accuracy or hardware execution latency.',
    }
    assert abs(result['open_circuit']['single_median_lock_ms'] - 12.803) < 1e-6
    assert abs(result['open_circuit']['double_median_lock_ms'] - 7.614) < 1e-6
    assert abs(result['separate_sensor_prototype']['median_lock_delay_ms'] - 9.073) < 1e-6
    return result

if __name__ == '__main__':
    print(json.dumps(calculate(), indent=2))
