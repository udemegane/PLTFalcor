#pragma once

import PathHelper;
import Utils.HWSS;
struct Reservoir
{
    float M = 0.0f;
    float w_sum = 0.0f;
    hwss_t p_hat = 0.0f;
    bool debugFlag = false;
    bool needMis = false;
    PathReconstructionData s;

    __init() {
        M = 0.0f;
        w_sum = 0.0f;
        p_hat = 0.0f;
        s = {};
    }

    [mutating]
    bool update(const float wi, PathReconstructionData si, const hwss_t p_hat_i, const float rnd)
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

    hwss_t evalUCW() {
        return w_sum / p_hat;
    }
};


