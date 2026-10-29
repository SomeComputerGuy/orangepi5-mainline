import sys, re
recs = []; cur = None; pkt = -1
for line in open(sys.argv[1]):
    line = line.rstrip()
    if line.startswith('Packet:'):
        pkt += 1; continue
    if line == 'Frame':
        cur = {'pkt': pkt}; recs.append(cur); continue
    m = re.match(r'\d+\s+(\S+)\s+\S+\s+=\s+(-?\d+)', line)
    if m and cur is not None:
        k, v = m.group(1), int(m.group(2))
        cur.setdefault(k, v) if not k.startswith(('feature', 'loop_filter_ref', 'loop_filter_mode', 'update_')) else None
        if k.startswith(('feature_value', 'feature_sign', 'feature_enabled', 'loop_filter_ref_deltas', 'loop_filter_mode_deltas')):
            cur.setdefault('x', []).append(f"{k}={v}")
disp = 0
for i, r in enumerate(recs):
    sh = r.get('show_frame', 0) or r.get('show_existing_frame', 0)
    s = (f"#{i:3d} pkt{r['pkt']:3d} disp={'%3d' % disp if sh else '  -'} "
         f"{'K' if r.get('frame_type', 1) == 0 else ('I' if r.get('intra_only') else 'P')}"
         f"{' SE' if r.get('show_existing_frame') else ''} show={r.get('show_frame', '-')} er={r.get('error_resilient_mode', '-')} "
         f"ref={r.get('refresh_frame_flags', '-')} ridx={[r.get(f'ref_frame_idx[{j}]') for j in range(3)]} "
         f"sz={r.get('frame_width_minus_1', '')} fctx={r.get('frame_context_idx', '-')} rfc={r.get('refresh_frame_context', '-')} par={r.get('frame_parallel_decoding_mode', '-')} rst={r.get('reset_frame_context', '-')} "
         f"lf={r.get('loop_filter_level', '-')} lfde={r.get('loop_filter_delta_enabled', '-')}/{r.get('loop_filter_delta_update', '-')} q={r.get('base_q_idx', '-')} "
         f"seg={r.get('segmentation_enabled', '-')} um={r.get('segmentation_update_map', '-')} tu={r.get('segmentation_temporal_update', '-')} ud={r.get('segmentation_update_data', '-')} abs={r.get('segmentation_abs_or_delta_update', '-')}")
    if '-v' in sys.argv:
        s += ' ' + ' '.join(x for x in r.get('x', []) if not x.endswith('=0') or 'enabled' not in x)
    print(s)
    if sh: disp += 1
