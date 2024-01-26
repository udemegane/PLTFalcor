#pragma once

import PathHelper;
import Utils.HWSS;
struct Reservoir
{
    uint M = 0u;
    float w_sum = 0.0f;
    hwss_t p_hat = 0.0f;
    hwss_t W = 0.0f;
    PathReconstructionData s;

    __init() {
        M = 0u;
        w_sum = 0.0f;
        p_hat = 0.0f;
        s = {};
    }

    [mutating]
    bool update(const float  wi, PathReconstructionData si, const hwss_t p_hat_i, const float rnd)
    {
        w_sum += wi;
        M++;
        if (rnd < wi / w_sum)
        {
            p_hat = p_hat_i;
            s = si;
            W = w_sum / p_hat;
            return true;
        }
        return false;
    }

    hwss_t evalUCW() {
         return w_sum / p_hat;
    }
};


