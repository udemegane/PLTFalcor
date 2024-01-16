#pragma once


import PathHelper;

struct Reservoir
{
    float M = 0.0f;
    float w_sum = 0.0f;
    float p_hat = 0.0f;
    PathReconstructionData s;

    __init() {
        M = 0.0f;
        w_sum = 0.0f;
        p_hat = 0.0f;
        s = {};
    }

    [mutating]
    bool update(const float wi, PathReconstructionData si, const float p_hat_i, const float rnd)
    {
        w_sum += wi;
        M+=1.0f;
        if (rnd < wi / w_sum)
        {
            p_hat = p_hat_i;
            s = si;
            return true;
        }
        return false;
    }

    float evalUCW() {
        return w_sum / p_hat;
    }
};

// https://developer.nvidia.com/content/understanding-structured-buffer-performance
// For efficiency, it is recommended that the size of a structured buffer be a multiple of 16 bytes.
struct PackedReservoir
{
    // Size: 80B
    float M; // 4B
    float w_sum; // 4B
    float p_hat; // 4B
    float _padding; // 4B
    PackedPathReconstructionData s; // 64B
    __init(Reservoir r) {
        M = r.M;
        w_sum = r.w_sum;
        p_hat = r.p_hat;
        s = PackedPathReconstructionData(r.s);
    }
    Reservoir unpack() {
        Reservoir r;
        r.M = M;
        r.w_sum = w_sum;
        r.p_hat = p_hat;
        r.s = s.unpack();
        return r;
    }
};
