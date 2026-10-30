/* Minimal environment for the extracted MPP table code */
#ifndef MPP_SHIM_H
#define MPP_SHIM_H
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include "rk_type.h"
#include "mpp_err.h"
#define mpp_calloc(type, n) ((type *)calloc((n), sizeof(type)))
#define MPP_FREE(p) do { free(p); (p) = NULL; } while (0)
#include "mpp_bitput.h"
#include "vp9d_syntax.h"
typedef RK_U8 vp9_prob;
#define PARTITION_CONTEXTS 16
#define PARTITION_TYPES 4
#define MAX_SEGMENTS 8
#define SEG_TREE_PROBS (MAX_SEGMENTS-1)
#define PREDICTION_PROBS 3
#define SKIP_CONTEXTS 3
#define TX_SIZE_CONTEXTS 2
#define TX_SIZES 4
#define INTRA_INTER_CONTEXTS 4
#define PLANE_TYPES 2
#define COEF_BANDS 6
#define COEFF_CONTEXTS 6
#define UNCONSTRAINED_NODES 3
#define INTRA_MODES 10
#define BLOCK_SIZE_GROUPS 4
#define COMP_INTER_CONTEXTS 5
#define REF_CONTEXTS 5
#define INTER_MODE_CONTEXTS 7
#define SWITCHABLE_FILTERS 3
#define SWITCHABLE_FILTER_CONTEXTS (SWITCHABLE_FILTERS + 1)
#define INTER_MODES 4
#define MV_JOINTS 4
#define MV_CLASSES 11
#define CLASS0_BITS 1
#define CLASS0_SIZE (1 << CLASS0_BITS)
#define MV_OFFSET_BITS (MV_CLASSES + CLASS0_BITS - 2)
#define MV_FP_SIZE 4
#define PROB_SIZE 4864
#define VP9_DUMP 0
#endif
