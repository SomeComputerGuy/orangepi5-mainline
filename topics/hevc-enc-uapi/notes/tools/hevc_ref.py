#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
"""
Independent reference for the v4l2-hevc-enc-rbsp KUnit vectors.

No HEVC encoder (x265, ffmpeg, gstreamer) is installed on the build host,
so the expected bitstreams of the KUnit test are produced here instead,
from a second implementation that shares no code with the kernel writer:

  * the writer builds a list of bits per syntax element straight from the
    ITU-T H.265 syntax tables, then runs a separate byte-level emulation
    prevention pass over the finished RBSP (the textbook two-step method;
    the kernel does it on the fly);
  * the parser reads the bytes back (removing emulation prevention bytes)
    and decodes VPS/SPS/PPS/AUD/slice segment headers into a trace, which
    is compared field by field with the configuration.

Usage:
  hevc_ref.py check   - write every vector, parse it back, compare, print
  hevc_ref.py carrays - print the expected byte arrays for the KUnit test
  hevc_ref.py trace   - print a syntax trace of every vector
"""

import sys

# --------------------------------------------------------------------------
# Writer


class Bits:
    def __init__(self):
        self.b = []

    def u(self, n, v):
        assert 0 <= v < (1 << n) or n == 0, (n, v)
        self.b += [(v >> (n - 1 - i)) & 1 for i in range(n)]

    def f(self, v):
        self.u(1, 1 if v else 0)

    def ue(self, v):
        assert v >= 0
        code = v + 1
        n = code.bit_length()
        self.u(n - 1, 0)
        self.u(n, code)

    def se(self, v):
        self.ue(2 * v - 1 if v > 0 else -2 * v)

    def trailing(self):
        self.b.append(1)
        while len(self.b) % 8:
            self.b.append(0)

    def bytes(self):
        assert len(self.b) % 8 == 0
        return bytes(int(''.join(map(str, self.b[i:i + 8])), 2)
                     for i in range(0, len(self.b), 8))


def epb(payload):
    out = bytearray()
    zeros = 0
    for byte in payload:
        if zeros >= 2 and byte <= 3:
            out.append(3)
            zeros = 0
        out.append(byte)
        zeros = zeros + 1 if byte == 0 else 0
    return bytes(out)


def nal(nut, tid1, payload, start_code=True):
    hdr = bytes([nut << 1, tid1])
    return (b'\x00\x00\x00\x01' if start_code else b'') + hdr + epb(payload)


def w_ptl(w, ptl, max_sub_layers_minus1):
    w.u(2, ptl['profile_space'])
    w.f(ptl['tier'])
    w.u(5, ptl['profile_idc'])
    w.u(32, ptl['compat'])
    w.f(ptl['progressive'])
    w.f(ptl['interlaced'])
    w.f(ptl['non_packed'])
    w.f(ptl['frame_only'])
    w.u(43, 0)
    w.u(1, 0)
    w.u(8, ptl['level_idc'])
    for _ in range(max_sub_layers_minus1):
        w.u(1, 0)
        w.u(1, 0)
    if max_sub_layers_minus1 > 0:
        for _ in range(max_sub_layers_minus1, 8):
            w.u(2, 0)


def w_ordering(w, sps):
    present = 1 if sps['max_sub_layers_minus1'] == 0 else 0
    w.f(present)
    # One entry: for i = (present ? 0 : max_sub_layers_minus1) .. max
    w.ue(sps['dpb_minus1'])
    w.ue(sps['reorder'])
    w.ue(sps['latency_plus1'])


def w_timing(w, vid):
    w.u(32, vid['num_units_in_tick'])
    w.u(32, vid['time_scale'])
    w.f(vid.get('poc_proportional', 0))
    if vid.get('poc_proportional', 0):
        w.ue(vid['num_ticks_poc_diff_one_minus1'])


def write_vps(sps, vid):
    w = Bits()
    w.u(4, sps['vps_id'])
    w.f(1)
    w.f(1)
    w.u(6, 0)
    w.u(3, sps['max_sub_layers_minus1'])
    w.f(vid['temporal_id_nesting'])
    w.u(16, 0xffff)
    w_ptl(w, vid['ptl'], sps['max_sub_layers_minus1'])
    w_ordering(w, sps)
    w.u(6, 0)
    w.ue(0)
    w.f(vid.get('vps_timing', 0))
    if vid.get('vps_timing', 0):
        w_timing(w, vid)
        w.ue(0)
    w.f(0)
    w.trailing()
    return nal(32, 1, w.bytes())


def w_vui(w, v):
    ar = 'aspect_ratio_idc' in v
    w.f(ar)
    if ar:
        w.u(8, v['aspect_ratio_idc'])
        if v['aspect_ratio_idc'] == 255:
            w.u(16, v['sar_width'])
            w.u(16, v['sar_height'])
    ov = 'overscan_appropriate' in v
    w.f(ov)
    if ov:
        w.f(v['overscan_appropriate'])
    vs = 'video_format' in v
    w.f(vs)
    if vs:
        w.u(3, v['video_format'])
        w.f(v['full_range'])
        cd = 'colour_primaries' in v
        w.f(cd)
        if cd:
            w.u(8, v['colour_primaries'])
            w.u(8, v['transfer'])
            w.u(8, v['matrix'])
    cl = 'chroma_loc_top' in v
    w.f(cl)
    if cl:
        w.ue(v['chroma_loc_top'])
        w.ue(v['chroma_loc_bottom'])
    w.f(0)
    w.f(0)
    w.f(0)
    w.f(0)
    t = v.get('vui_timing', 0)
    w.f(t)
    if t:
        w_timing(w, v)
        w.f(0)
    br = 'bitstream_restriction' in v
    w.f(br)
    if br:
        r = v['bitstream_restriction']
        w.f(r['tiles_fixed'])
        w.f(r['mv_over_pic'])
        w.f(r['restricted_ref'])
        w.ue(r['min_spatial_seg'])
        w.ue(r['max_bytes_per_pic'])
        w.ue(r['max_bits_per_min_cu'])
        w.ue(r['log2_mv_h'])
        w.ue(r['log2_mv_v'])


def write_sps(s, vid):
    w = Bits()
    w.u(4, s['vps_id'])
    w.u(3, s['max_sub_layers_minus1'])
    w.f(vid['temporal_id_nesting'])
    w_ptl(w, vid['ptl'], s['max_sub_layers_minus1'])
    w.ue(s['sps_id'])
    w.ue(s['chroma_format_idc'])
    w.ue(s['width'])
    w.ue(s['height'])
    cw = vid.get('conf_win')
    w.f(cw is not None)
    if cw:
        for x in cw:
            w.ue(x)
    w.ue(s['bit_depth_luma_minus8'])
    w.ue(s['bit_depth_chroma_minus8'])
    w.ue(s['log2_max_poc_lsb_minus4'])
    w_ordering(w, s)
    w.ue(s['log2_min_cb_minus3'])
    w.ue(s['log2_diff_cb'])
    w.ue(s['log2_min_tb_minus2'])
    w.ue(s['log2_diff_tb'])
    w.ue(s['max_th_inter'])
    w.ue(s['max_th_intra'])
    w.f(s['scaling_list'])
    if s['scaling_list']:
        w.f(0)
    w.f(s['amp'])
    w.f(s['sao'])
    pcm = s.get('pcm')
    w.f(pcm is not None)
    if pcm:
        w.u(4, pcm['luma_minus1'])
        w.u(4, pcm['chroma_minus1'])
        w.ue(pcm['log2_min_minus3'])
        w.ue(pcm['log2_diff'])
        w.f(pcm['loop_filter_disabled'])
    w.ue(0)
    w.f(s['lt_present'])
    if s['lt_present']:
        w.ue(0)
    w.f(s['tmvp'])
    w.f(s['strong_intra'])
    w.f(vid.get('vui') is not None)
    if vid.get('vui') is not None:
        w_vui(w, vid['vui'])
    w.f(0)
    w.trailing()
    return nal(33, 1, w.bytes())


def write_pps(s, p):
    w = Bits()
    w.ue(p['pps_id'])
    w.ue(s['sps_id'])
    w.f(p['dependent_slices'])
    w.f(p['output_flag_present'])
    w.u(3, p['extra_bits'])
    w.f(p['sign_data_hiding'])
    w.f(p['cabac_init_present'])
    w.ue(p['l0_default_minus1'])
    w.ue(p['l1_default_minus1'])
    w.se(p['init_qp_minus26'])
    w.f(p['constrained_intra'])
    w.f(p['transform_skip'])
    w.f(p['cu_qp_delta_depth'] is not None)
    if p['cu_qp_delta_depth'] is not None:
        w.ue(p['cu_qp_delta_depth'])
    w.se(p['cb_qp_offset'])
    w.se(p['cr_qp_offset'])
    w.f(p['slice_chroma_qp_offsets'])
    w.f(0)  # weighted_pred
    w.f(0)  # weighted_bipred
    w.f(0)  # transquant_bypass
    tiles = p.get('tiles')
    w.f(tiles is not None)
    w.f(p['wpp'])
    if tiles:
        w.ue(tiles['cols_minus1'])
        w.ue(tiles['rows_minus1'])
        w.f(tiles['uniform'])
        if not tiles['uniform']:
            for c in tiles['col_widths_minus1']:
                w.ue(c)
            for r in tiles['row_heights_minus1']:
                w.ue(r)
        w.f(tiles['lf_across'])
    w.f(p['lf_across_slices'])
    dbk = p.get('deblocking')
    w.f(dbk is not None)
    if dbk:
        w.f(dbk['override_enabled'])
        w.f(dbk['disabled'])
        if not dbk['disabled']:
            w.se(dbk['beta'])
            w.se(dbk['tc'])
    w.f(0)
    w.f(p['lists_mod'])
    w.ue(p['log2_pml_minus2'])
    w.f(p['sh_ext'])
    w.f(0)
    w.trailing()
    return nal(34, 1, w.bytes())


def write_aud(pic_type, tid1):
    w = Bits()
    w.u(3, pic_type)
    w.trailing()
    return nal(35, tid1, w.bytes())


def ctb_info(s):
    log2 = s['log2_min_cb_minus3'] + 3 + s['log2_diff_cb']
    size = 1 << log2
    wc = -(-s['width'] // size)
    hc = -(-s['height'] // size)
    return wc * hc


def write_slice(s, p, h):
    w = Bits()
    nut = h['nut']
    irap = 16 <= nut <= 23
    idr = nut in (19, 20)
    first = h['address'] == 0
    w.f(first)
    if irap:
        w.f(h.get('no_output_of_prior_pics', 0))
    w.ue(p['pps_id'])
    dep = h.get('dependent', 0)
    if not first:
        if p['dependent_slices']:
            w.f(dep)
        n = ctb_info(s)
        w.u((n - 1).bit_length(), h['address'])
    tmvp = sao_l = sao_c = 0
    dbk = p.get('deblocking')
    dis = dbk['disabled'] if dbk else 0
    if not dep:
        w.u(p['extra_bits'], 0)
        st = h['slice_type']
        w.ue(st)
        if p['output_flag_present']:
            w.f(h.get('pic_output', 1))
        if not idr:
            w.u(s['log2_max_poc_lsb_minus4'] + 4, h['poc_lsb'])
            w.f(0)
            neg = h.get('neg', [])
            pos = h.get('pos', [])
            # stRpsIdx = num_short_term_ref_pic_sets = 0 -> no inter flag
            w.ue(len(neg))
            w.ue(len(pos))
            prev = 0
            for d, used in neg:   # d: negative POC deltas, closest first
                w.ue(prev - d - 1)
                prev = d
                w.f(used)
            prev = 0
            for d, used in pos:
                w.ue(d - prev - 1)
                prev = d
                w.f(used)
            lts = h.get('lt', [])
            if s['lt_present']:
                w.ue(len(lts))
                for lt in lts:
                    w.u(s['log2_max_poc_lsb_minus4'] + 4, lt['lsb'])
                    w.f(lt['used'])
                    w.f(lt['msb_present'])
                    if lt['msb_present']:
                        w.ue(lt['msb_cycle'])
            if s['tmvp']:
                tmvp = h.get('tmvp', 0)
                w.f(tmvp)
        if s['sao']:
            sao_l = h.get('sao_luma', 0)
            w.f(sao_l)
            if s['chroma_format_idc']:
                sao_c = h.get('sao_chroma', 0)
                w.f(sao_c)
        if st != 2:
            ov = 'l0_minus1' in h
            l0 = p['l0_default_minus1']
            l1 = p['l1_default_minus1']
            w.f(ov)
            if ov:
                l0 = h['l0_minus1']
                w.ue(l0)
                if st == 0:
                    l1 = h['l1_minus1']
                    w.ue(l1)
            used_total = sum(u for _, u in h.get('neg', [])) + \
                sum(u for _, u in h.get('pos', [])) + \
                sum(lt['used'] for lt in h.get('lt', []))
            if p['lists_mod'] and used_total > 1:
                w.f(0)
                if st == 0:
                    w.f(0)
            if st == 0:
                w.f(h.get('mvd_l1_zero', 0))
            if p['cabac_init_present']:
                w.f(h.get('cabac_init', 0))
            if tmvp:
                from_l0 = 1
                if st == 0:
                    from_l0 = h.get('col_from_l0', 1)
                    w.f(from_l0)
                if (from_l0 and l0 > 0) or (not from_l0 and l1 > 0):
                    w.ue(h['col_ref_idx'])
            w.ue(h['five_minus_merge'])
        w.se(h['qp_delta'])
        if p['slice_chroma_qp_offsets']:
            w.se(h.get('cb', 0))
            w.se(h.get('cr', 0))
        if dbk and dbk['override_enabled']:
            ovr = 'dbk_disabled' in h
            w.f(ovr)
            if ovr:
                dis = h['dbk_disabled']
                w.f(dis)
                if not dis:
                    w.se(h['beta'])
                    w.se(h['tc'])
        if p['lf_across_slices'] and (sao_l or sao_c or not dis):
            w.f(h.get('lf_across_slices', 0))
    if p.get('tiles') or p['wpp']:
        eps = h.get('entry_points', [])
        w.ue(len(eps))
        if eps:
            ln = max(max(eps).bit_length(), 1)
            w.ue(ln - 1)
            for e in eps:
                w.u(ln, e)
    if p['sh_ext']:
        w.ue(0)
    w.trailing()
    return nal(nut, h['tid1'], w.bytes())


# --------------------------------------------------------------------------
# Parser (reads the bitstream back; used to check the writer output)


class Reader:
    def __init__(self, data):
        # Remove emulation prevention bytes after the 2-byte NAL header.
        rbsp = bytearray(data[:2])
        zeros = 0
        for byte in data[2:]:
            if zeros >= 2 and byte == 3:
                zeros = 0
                continue
            rbsp.append(byte)
            zeros = zeros + 1 if byte == 0 else 0
        self.bits = ''.join(format(x, '08b') for x in rbsp)
        self.pos = 0
        self.trace = []

    def u(self, n, name=None):
        v = int(self.bits[self.pos:self.pos + n], 2) if n else 0
        self.pos += n
        if name:
            self.trace.append((name, v))
        return v

    def ue(self, name=None):
        z = 0
        while self.bits[self.pos] == '0':
            z += 1
            self.pos += 1
        v = int(self.bits[self.pos:self.pos + z + 1], 2) - 1
        self.pos += z + 1
        if name:
            self.trace.append((name, v))
        return v

    def se(self, name=None):
        k = self.ue()
        v = (k + 1) // 2 if k & 1 else -(k // 2)
        if name:
            self.trace.append((name, v))
        return v

    def trailing(self, name):
        assert self.u(1) == 1, name + ': stop bit'
        while self.pos % 8:
            assert self.u(1) == 0, name + ': alignment'
        assert self.pos == len(self.bits), \
            '%s: %d trailing bits' % (name, len(self.bits) - self.pos)


def split_nals(stream):
    out = []
    i = 0
    starts = []
    while i < len(stream) - 3:
        if stream[i:i + 4] == b'\x00\x00\x00\x01':
            starts.append(i + 4)
            i += 4
        else:
            i += 1
    for k, s in enumerate(starts):
        e = starts[k + 1] - 4 if k + 1 < len(starts) else len(stream)
        out.append(stream[s:e])
    return out


def p_ptl(r, maxsl):
    r.u(2, 'general_profile_space')
    r.u(1, 'general_tier_flag')
    r.u(5, 'general_profile_idc')
    r.u(32, 'general_profile_compatibility_flags')
    r.u(1, 'general_progressive_source_flag')
    r.u(1, 'general_interlaced_source_flag')
    r.u(1, 'general_non_packed_constraint_flag')
    r.u(1, 'general_frame_only_constraint_flag')
    assert r.u(43) == 0 and r.u(1) == 0
    r.u(8, 'general_level_idc')
    for _ in range(maxsl):
        assert r.u(2) == 0
    if maxsl:
        for _ in range(maxsl, 8):
            assert r.u(2) == 0


def p_ordering(r, maxsl):
    present = r.u(1, 'sub_layer_ordering_info_present_flag')
    for _ in range(0 if present else maxsl, maxsl + 1):
        r.ue('max_dec_pic_buffering_minus1')
        r.ue('max_num_reorder_pics')
        r.ue('max_latency_increase_plus1')


def p_timing(r):
    r.u(32, 'num_units_in_tick')
    r.u(32, 'time_scale')
    if r.u(1, 'poc_proportional_to_timing_flag'):
        r.ue('num_ticks_poc_diff_one_minus1')


def parse(data, ctx):
    r = Reader(data)
    assert r.u(1) == 0
    nut = r.u(6, 'nal_unit_type')
    assert r.u(6) == 0
    r.u(3, 'nuh_temporal_id_plus1')
    if nut == 32:
        r.u(4, 'vps_video_parameter_set_id')
        assert r.u(1) == 1 and r.u(1) == 1 and r.u(6) == 0
        msl = r.u(3, 'vps_max_sub_layers_minus1')
        r.u(1, 'vps_temporal_id_nesting_flag')
        assert r.u(16) == 0xffff
        p_ptl(r, msl)
        p_ordering(r, msl)
        assert r.u(6) == 0 and r.ue() == 0
        if r.u(1, 'vps_timing_info_present_flag'):
            p_timing(r)
            assert r.ue('vps_num_hrd_parameters') == 0
        assert r.u(1) == 0
        r.trailing('vps')
    elif nut == 33:
        r.u(4, 'sps_video_parameter_set_id')
        msl = r.u(3, 'sps_max_sub_layers_minus1')
        r.u(1, 'sps_temporal_id_nesting_flag')
        p_ptl(r, msl)
        r.ue('sps_seq_parameter_set_id')
        cf = r.ue('chroma_format_idc')
        if cf == 3:
            r.u(1, 'separate_colour_plane_flag')
        w = r.ue('pic_width_in_luma_samples')
        h = r.ue('pic_height_in_luma_samples')
        if r.u(1, 'conformance_window_flag'):
            for n in ('left', 'right', 'top', 'bottom'):
                r.ue('conf_win_%s_offset' % n)
        r.ue('bit_depth_luma_minus8')
        r.ue('bit_depth_chroma_minus8')
        poc = r.ue('log2_max_pic_order_cnt_lsb_minus4')
        p_ordering(r, msl)
        mincb = r.ue('log2_min_luma_coding_block_size_minus3')
        diff = r.ue('log2_diff_max_min_luma_coding_block_size')
        r.ue('log2_min_luma_transform_block_size_minus2')
        r.ue('log2_diff_max_min_luma_transform_block_size')
        r.ue('max_transform_hierarchy_depth_inter')
        r.ue('max_transform_hierarchy_depth_intra')
        if r.u(1, 'scaling_list_enabled_flag'):
            assert r.u(1, 'sps_scaling_list_data_present_flag') == 0
        r.u(1, 'amp_enabled_flag')
        sao = r.u(1, 'sample_adaptive_offset_enabled_flag')
        if r.u(1, 'pcm_enabled_flag'):
            r.u(4, 'pcm_sample_bit_depth_luma_minus1')
            r.u(4, 'pcm_sample_bit_depth_chroma_minus1')
            r.ue('log2_min_pcm_luma_coding_block_size_minus3')
            r.ue('log2_diff_max_min_pcm_luma_coding_block_size')
            r.u(1, 'pcm_loop_filter_disabled_flag')
        assert r.ue('num_short_term_ref_pic_sets') == 0
        lt = r.u(1, 'long_term_ref_pics_present_flag')
        if lt:
            assert r.ue('num_long_term_ref_pics_sps') == 0
        tmvp = r.u(1, 'sps_temporal_mvp_enabled_flag')
        r.u(1, 'strong_intra_smoothing_enabled_flag')
        if r.u(1, 'vui_parameters_present_flag'):
            if r.u(1, 'aspect_ratio_info_present_flag'):
                if r.u(8, 'aspect_ratio_idc') == 255:
                    r.u(16, 'sar_width')
                    r.u(16, 'sar_height')
            if r.u(1, 'overscan_info_present_flag'):
                r.u(1, 'overscan_appropriate_flag')
            if r.u(1, 'video_signal_type_present_flag'):
                r.u(3, 'video_format')
                r.u(1, 'video_full_range_flag')
                if r.u(1, 'colour_description_present_flag'):
                    r.u(8, 'colour_primaries')
                    r.u(8, 'transfer_characteristics')
                    r.u(8, 'matrix_coeffs')
            if r.u(1, 'chroma_loc_info_present_flag'):
                r.ue('chroma_sample_loc_type_top_field')
                r.ue('chroma_sample_loc_type_bottom_field')
            for n in ('neutral_chroma_indication_flag', 'field_seq_flag',
                      'frame_field_info_present_flag',
                      'default_display_window_flag'):
                assert r.u(1, n) == 0
            if r.u(1, 'vui_timing_info_present_flag'):
                p_timing(r)
                assert r.u(1, 'vui_hrd_parameters_present_flag') == 0
            if r.u(1, 'bitstream_restriction_flag'):
                r.u(1, 'tiles_fixed_structure_flag')
                r.u(1, 'motion_vectors_over_pic_boundaries_flag')
                r.u(1, 'restricted_ref_pic_lists_flag')
                r.ue('min_spatial_segmentation_idc')
                r.ue('max_bytes_per_pic_denom')
                r.ue('max_bits_per_min_cu_denom')
                r.ue('log2_max_mv_length_horizontal')
                r.ue('log2_max_mv_length_vertical')
        assert r.u(1, 'sps_extension_present_flag') == 0
        r.trailing('sps')
        log2 = mincb + 3 + diff
        ctx['sps'] = dict(cf=cf, poc=poc + 4, sao=sao, lt=lt, tmvp=tmvp,
                          ctbs=(-(-w >> log2)) * (-(-h >> log2)))
    elif nut == 34:
        r.ue('pps_pic_parameter_set_id')
        r.ue('pps_seq_parameter_set_id')
        p = {}
        p['dep'] = r.u(1, 'dependent_slice_segments_enabled_flag')
        p['out'] = r.u(1, 'output_flag_present_flag')
        p['extra'] = r.u(3, 'num_extra_slice_header_bits')
        r.u(1, 'sign_data_hiding_enabled_flag')
        p['cabac'] = r.u(1, 'cabac_init_present_flag')
        p['l0'] = r.ue('num_ref_idx_l0_default_active_minus1')
        p['l1'] = r.ue('num_ref_idx_l1_default_active_minus1')
        r.se('init_qp_minus26')
        r.u(1, 'constrained_intra_pred_flag')
        r.u(1, 'transform_skip_enabled_flag')
        if r.u(1, 'cu_qp_delta_enabled_flag'):
            r.ue('diff_cu_qp_delta_depth')
        r.se('pps_cb_qp_offset')
        r.se('pps_cr_qp_offset')
        p['cqo'] = r.u(1, 'pps_slice_chroma_qp_offsets_present_flag')
        assert r.u(1, 'weighted_pred_flag') == 0
        assert r.u(1, 'weighted_bipred_flag') == 0
        r.u(1, 'transquant_bypass_enabled_flag')
        p['tiles'] = r.u(1, 'tiles_enabled_flag')
        p['wpp'] = r.u(1, 'entropy_coding_sync_enabled_flag')
        if p['tiles']:
            c = r.ue('num_tile_columns_minus1')
            rr = r.ue('num_tile_rows_minus1')
            if not r.u(1, 'uniform_spacing_flag'):
                for _ in range(c):
                    r.ue('column_width_minus1')
                for _ in range(rr):
                    r.ue('row_height_minus1')
            r.u(1, 'loop_filter_across_tiles_enabled_flag')
        p['lfs'] = r.u(1, 'pps_loop_filter_across_slices_enabled_flag')
        p['dbk_ovr'] = 0
        p['dbk_dis'] = 0
        if r.u(1, 'deblocking_filter_control_present_flag'):
            p['dbk_ovr'] = r.u(1, 'deblocking_filter_override_enabled_flag')
            p['dbk_dis'] = r.u(1, 'pps_deblocking_filter_disabled_flag')
            if not p['dbk_dis']:
                r.se('pps_beta_offset_div2')
                r.se('pps_tc_offset_div2')
        assert r.u(1, 'pps_scaling_list_data_present_flag') == 0
        p['lmod'] = r.u(1, 'lists_modification_present_flag')
        r.ue('log2_parallel_merge_level_minus2')
        p['ext'] = r.u(1, 'slice_segment_header_extension_present_flag')
        assert r.u(1, 'pps_extension_present_flag') == 0
        r.trailing('pps')
        ctx['pps'] = p
    elif nut == 35:
        r.u(3, 'pic_type')
        r.trailing('aud')
    else:
        s, p = ctx['sps'], ctx['pps']
        first = r.u(1, 'first_slice_segment_in_pic_flag')
        if 16 <= nut <= 23:
            r.u(1, 'no_output_of_prior_pics_flag')
        r.ue('slice_pic_parameter_set_id')
        dep = 0
        if not first:
            if p['dep']:
                dep = r.u(1, 'dependent_slice_segment_flag')
            r.u((s['ctbs'] - 1).bit_length(), 'slice_segment_address')
        if not dep:
            r.u(p['extra'])
            st = r.ue('slice_type')
            if p['out']:
                r.u(1, 'pic_output_flag')
            tmvp = sao_l = sao_c = 0
            used = 0
            if nut not in (19, 20):
                r.u(s['poc'], 'slice_pic_order_cnt_lsb')
                assert r.u(1, 'short_term_ref_pic_set_sps_flag') == 0
                nn = r.ue('num_negative_pics')
                np_ = r.ue('num_positive_pics')
                for _ in range(nn):
                    r.ue('delta_poc_s0_minus1')
                    used += r.u(1, 'used_by_curr_pic_s0_flag')
                for _ in range(np_):
                    r.ue('delta_poc_s1_minus1')
                    used += r.u(1, 'used_by_curr_pic_s1_flag')
                if s['lt']:
                    for _ in range(r.ue('num_long_term_pics')):
                        r.u(s['poc'], 'poc_lsb_lt')
                        used += r.u(1, 'used_by_curr_pic_lt_flag')
                        if r.u(1, 'delta_poc_msb_present_flag'):
                            r.ue('delta_poc_msb_cycle_lt')
                if s['tmvp']:
                    tmvp = r.u(1, 'slice_temporal_mvp_enabled_flag')
            if s['sao']:
                sao_l = r.u(1, 'slice_sao_luma_flag')
                if s['cf']:
                    sao_c = r.u(1, 'slice_sao_chroma_flag')
            if st != 2:
                l0, l1 = p['l0'], p['l1']
                if r.u(1, 'num_ref_idx_active_override_flag'):
                    l0 = r.ue('num_ref_idx_l0_active_minus1')
                    if st == 0:
                        l1 = r.ue('num_ref_idx_l1_active_minus1')
                if p['lmod'] and used > 1:
                    assert r.u(1, 'ref_pic_list_modification_flag_l0') == 0
                    if st == 0:
                        assert r.u(1, 'ref_pic_list_modification_flag_l1') == 0
                if st == 0:
                    r.u(1, 'mvd_l1_zero_flag')
                if p['cabac']:
                    r.u(1, 'cabac_init_flag')
                if tmvp:
                    fl0 = 1
                    if st == 0:
                        fl0 = r.u(1, 'collocated_from_l0_flag')
                    if (fl0 and l0) or (not fl0 and l1):
                        r.ue('collocated_ref_idx')
                r.ue('five_minus_max_num_merge_cand')
            r.se('slice_qp_delta')
            if p['cqo']:
                r.se('slice_cb_qp_offset')
                r.se('slice_cr_qp_offset')
            dis = p['dbk_dis']
            if p['dbk_ovr'] and r.u(1, 'deblocking_filter_override_flag'):
                dis = r.u(1, 'slice_deblocking_filter_disabled_flag')
                if not dis:
                    r.se('slice_beta_offset_div2')
                    r.se('slice_tc_offset_div2')
            if p['lfs'] and (sao_l or sao_c or not dis):
                r.u(1, 'slice_loop_filter_across_slices_enabled_flag')
        if p['tiles'] or p['wpp']:
            n = r.ue('num_entry_point_offsets')
            if n:
                ln = r.ue('offset_len_minus1') + 1
                for _ in range(n):
                    r.u(ln, 'entry_point_offset_minus1')
        if p['ext']:
            r.ue('slice_segment_header_extension_length')
        r.trailing('slice')
    return r.trace


# --------------------------------------------------------------------------
# Vectors (keep in sync with v4l2-hevc-enc-rbsp-test.c)

MAIN = dict(profile_space=0, tier=0, profile_idc=1, compat=0x60000000,
            progressive=1, interlaced=0, non_packed=0, frame_only=1,
            level_idc=93)

SPS_A = dict(vps_id=0, sps_id=0, max_sub_layers_minus1=0, chroma_format_idc=1,
             width=1280, height=720, bit_depth_luma_minus8=0,
             bit_depth_chroma_minus8=0, log2_max_poc_lsb_minus4=4,
             dpb_minus1=4, reorder=2, latency_plus1=5, log2_min_cb_minus3=0,
             log2_diff_cb=3, log2_min_tb_minus2=0, log2_diff_tb=3,
             max_th_inter=0, max_th_intra=0, scaling_list=0, amp=1, sao=1,
             lt_present=0, tmvp=1, strong_intra=1)
VID_A = dict(ptl=MAIN, temporal_id_nesting=1,
             vui=dict(video_format=5, full_range=0, colour_primaries=1,
                      transfer=1, matrix=1, vui_timing=1,
                      num_units_in_tick=1, time_scale=25))
PPS_A = dict(pps_id=0, dependent_slices=0, output_flag_present=0,
             extra_bits=0, sign_data_hiding=1, cabac_init_present=0,
             l0_default_minus1=0, l1_default_minus1=0, init_qp_minus26=0,
             constrained_intra=0, transform_skip=0, cu_qp_delta_depth=None,
             cb_qp_offset=0, cr_qp_offset=0, slice_chroma_qp_offsets=0,
             wpp=0, lf_across_slices=1, deblocking=None, lists_mod=0,
             log2_pml_minus2=0, sh_ext=0)

SPS_B = dict(vps_id=1, sps_id=1, max_sub_layers_minus1=0, chroma_format_idc=1,
             width=640, height=368, bit_depth_luma_minus8=0,
             bit_depth_chroma_minus8=0, log2_max_poc_lsb_minus4=0,
             dpb_minus1=2, reorder=0, latency_plus1=0, log2_min_cb_minus3=0,
             log2_diff_cb=2, log2_min_tb_minus2=0, log2_diff_tb=3,
             max_th_inter=1, max_th_intra=1, scaling_list=0, amp=0, sao=0,
             pcm=dict(luma_minus1=7, chroma_minus1=7, log2_min_minus3=0,
                      log2_diff=1, loop_filter_disabled=1),
             lt_present=1, tmvp=1, strong_intra=0)
VID_B = dict(ptl=dict(MAIN, level_idc=90), temporal_id_nesting=1,
             conf_win=(0, 0, 0, 4))
PPS_B = dict(pps_id=1, dependent_slices=1, output_flag_present=1,
             extra_bits=2, sign_data_hiding=1, cabac_init_present=1,
             l0_default_minus1=1, l1_default_minus1=0, init_qp_minus26=-4,
             constrained_intra=1, transform_skip=1, cu_qp_delta_depth=1,
             cb_qp_offset=-2, cr_qp_offset=3, slice_chroma_qp_offsets=1,
             tiles=dict(cols_minus1=1, rows_minus1=1, uniform=1,
                        lf_across=1),
             wpp=0, lf_across_slices=1,
             deblocking=dict(override_enabled=1, disabled=0, beta=-2, tc=1),
             lists_mod=1, log2_pml_minus2=2, sh_ext=1)

SPS_C = dict(vps_id=2, sps_id=2, max_sub_layers_minus1=2, chroma_format_idc=1,
             width=3840, height=2160, bit_depth_luma_minus8=2,
             bit_depth_chroma_minus8=2, log2_max_poc_lsb_minus4=12,
             dpb_minus1=5, reorder=0, latency_plus1=0, log2_min_cb_minus3=0,
             log2_diff_cb=3, log2_min_tb_minus2=0, log2_diff_tb=3,
             max_th_inter=2, max_th_intra=2, scaling_list=1, amp=1, sao=0,
             lt_present=0, tmvp=1, strong_intra=1)
VID_C = dict(ptl=dict(MAIN, tier=1, profile_idc=2, compat=0x20000000,
                      level_idc=153),
             temporal_id_nesting=1, vps_timing=1, poc_proportional=1,
             num_ticks_poc_diff_one_minus1=0, num_units_in_tick=1001,
             time_scale=60000,
             vui=dict(aspect_ratio_idc=255, sar_width=4, sar_height=3,
                      overscan_appropriate=0, video_format=5, full_range=1,
                      colour_primaries=9, transfer=16, matrix=9,
                      chroma_loc_top=2, chroma_loc_bottom=2, vui_timing=1,
                      num_units_in_tick=1001, time_scale=60000,
                      poc_proportional=1, num_ticks_poc_diff_one_minus1=0,
                      bitstream_restriction=dict(
                          tiles_fixed=1, mv_over_pic=1, restricted_ref=1,
                          min_spatial_seg=0, max_bytes_per_pic=2,
                          max_bits_per_min_cu=1, log2_mv_h=15,
                          log2_mv_v=15)))
PPS_C = dict(pps_id=2, dependent_slices=0, output_flag_present=0,
             extra_bits=0, sign_data_hiding=0, cabac_init_present=0,
             l0_default_minus1=0, l1_default_minus1=0, init_qp_minus26=8,
             constrained_intra=0, transform_skip=0, cu_qp_delta_depth=2,
             cb_qp_offset=0, cr_qp_offset=0, slice_chroma_qp_offsets=0,
             tiles=dict(cols_minus1=2, rows_minus1=1, uniform=0,
                        col_widths_minus1=[19, 19], row_heights_minus1=[16],
                        lf_across=0),
             wpp=1, lf_across_slices=0,
             deblocking=dict(override_enabled=0, disabled=1),
             lists_mod=0, log2_pml_minus2=0, sh_ext=0)

SLICES = {
    'a_idr': ('A', dict(nut=19, tid1=1, slice_type=2, address=0,
                        qp_delta=2, sao_luma=1, sao_chroma=1)),
    'a_p': ('A', dict(nut=1, tid1=1, slice_type=1, address=0, poc_lsb=8,
                      neg=[(-1, 1), (-3, 0)], tmvp=1, sao_luma=1,
                      five_minus_merge=2, qp_delta=-3, lf_across_slices=1)),
    'b_b': ('B', dict(nut=1, tid1=1, slice_type=0, address=5, pic_output=0,
                      poc_lsb=3, neg=[(-1, 1)], pos=[(2, 1)],
                      lt=[dict(lsb=0, used=0, msb_present=1, msb_cycle=1)],
                      tmvp=1, l0_minus1=1, l1_minus1=1, mvd_l1_zero=1,
                      cabac_init=1, col_from_l0=0, col_ref_idx=1,
                      five_minus_merge=0, qp_delta=0, cb=1, cr=-1,
                      dbk_disabled=0, beta=2, tc=-2, lf_across_slices=1,
                      entry_points=[99, 1999, 6])),
    'b_dep': ('B', dict(nut=1, tid1=1, slice_type=0, address=10,
                        dependent=1)),
    'b_cra': ('B', dict(nut=21, tid1=1, slice_type=2, address=0,
                        no_output_of_prior_pics=1, pic_output=1, poc_lsb=0,
                        qp_delta=-1, cb=0, cr=0, dbk_disabled=1,
                        lf_across_slices=0)),
    'c_tsa': ('C', dict(nut=2, tid1=3, slice_type=1, address=0,
                        poc_lsb=4095, neg=[(-2, 1)], tmvp=0,
                        five_minus_merge=1, qp_delta=5,
                        entry_points=[49, 59])),
}

CFG = {'A': (SPS_A, VID_A, PPS_A), 'B': (SPS_B, VID_B, PPS_B),
       'C': (SPS_C, VID_C, PPS_C)}

# A commonly seen x265 VPS (Main, level 3.1, one sub-layer, dpb 5, 2
# reorder pictures, latency +5). Recalled, not regenerated on this host:
# no x265 is installed. It must equal what VPS A writes.
X265_VPS = bytes.fromhex(
    '000000014001 0c01ffff0160000003009000000300000300 5d959809'
    .replace(' ', ''))


def vectors():
    v = []
    for name, (s, vid, p) in CFG.items():
        v.append(('vps_' + name.lower(), write_vps(s, vid)))
        v.append(('sps_' + name.lower(), write_sps(s, vid)))
        v.append(('pps_' + name.lower(), write_pps(s, p)))
    for name, (c, h) in SLICES.items():
        s, _, p = CFG[c]
        v.append(('slice_' + name, write_slice(s, p, h)))
    v.append(('aud', write_aud(1, 2)))
    return v


def check():
    vec = dict(vectors())
    assert vec['vps_a'] == X265_VPS, vec['vps_a'].hex()
    for name, (s, vid, p) in CFG.items():
        ctx = {}
        for k in ('vps', 'sps', 'pps'):
            data = vec['%s_%s' % (k, name.lower())]
            assert data[:4] == b'\x00\x00\x00\x01'
            body = data[4:]
            tr = dict(parse(body, ctx))
            assert b'\x00\x00\x00' not in body and \
                b'\x00\x00\x01' not in body and b'\x00\x00\x02' not in body
            if k == 'sps':
                assert tr['pic_width_in_luma_samples'] == s['width']
                assert tr['pic_height_in_luma_samples'] == s['height']
                assert tr['general_level_idc'] == vid['ptl']['level_idc']
        CFG[name] = (s, vid, p)
        for sname, (c, h) in SLICES.items():
            if c != name:
                continue
            body = vec['slice_' + sname][4:]
            tr = parse(body, ctx)
            d = dict(tr)
            assert d['nal_unit_type'] == h['nut']
            if 'slice_qp_delta' in d:
                assert d['slice_qp_delta'] == h['qp_delta']
            if 'entry_point_offset_minus1' in d:
                eps = [v for k, v in tr if k == 'entry_point_offset_minus1']
                assert eps == h['entry_points'], eps
    parse(vec['aud'][4:], {})
    print('ok: %d vectors written, parsed back and checked' % len(vec))


def carrays():
    for name, data in vectors():
        print('static const u8 %s[] = {' % name)
        for i in range(0, len(data), 12):
            print('\t' + ', '.join('0x%02x' % x for x in data[i:i + 12]) +
                  ',')
        print('};\n')


def trace():
    vec = dict(vectors())
    for name in CFG:
        ctx = {}
        names = ['%s_%s' % (k, name.lower()) for k in ('vps', 'sps', 'pps')]
        names += ['slice_' + s for s, (c, _) in SLICES.items() if c == name]
        for n in names:
            data = vec[n]
            print('== %s (%d bytes): %s' % (n, len(data), data.hex()))
            for k, v in parse(data[4:], ctx):
                print('  %-48s %d' % (k, v))
    print('== aud: %s' % vec['aud'].hex())


if __name__ == '__main__':
    {'check': check, 'carrays': carrays, 'trace': trace}[
        sys.argv[1] if len(sys.argv) > 1 else 'check']()
