#pragma once

import PathHelper;
import Utils.HWSS;
// import StaticVars;

struct Reservoir
{
    float M = 0.0f;
    float w_sum = 0.0f;
    hwss_t p_hat = 0.0f;
    float W = 0.0f; // Unbiased Contribution Weight
    PathReconstructionData s;

    __init() {
        M = 0.0f;
        w_sum = 0.0f;
        p_hat = 0.0f;
        s = {};
    }

    [mutating]
    bool update(const float  wi, PathReconstructionData si, const hwss_t p_hat_i, const float rnd)
    {
        w_sum += wi;
        M+=1.0f;
        if (rnd < wi / w_sum)
        {
            p_hat = p_hat_i;
            s = si;
            W = w_sum / p_hat[0];
            return true;
        }
        M = max(M, 30);
        return false;
    }

    // hwss_t evalUCW() { return w_sum / p_hat; }
    static Reservoir MergeReservoirsForTemporal(const Reservoir prev, const Reservoir curr, float rng1, float rng2) {
        Reservoir newRes = Reservoir();
        const float weightedPrevL = prev.M * prev.p_hat[0];
        const float weightedCurrL = curr.M * curr.p_hat[0];
        const float misPrev = weightedPrevL / (weightedPrevL + weightedCurrL);
        const float misCurr = weightedCurrL / (weightedPrevL + weightedCurrL);
        const float w_prev = misPrev * prev.p_hat[0] * prev.W;
        const float w_curr = misCurr * curr.p_hat[0] * curr.W;
        newRes.update(w_curr, curr.s, curr.p_hat, rng1);
        newRes.update(w_prev, prev.s, prev.p_hat, rng2);
        return newRes;
    }
};


