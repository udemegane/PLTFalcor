#pragma once

import PathHelper;
import Utils.HWSS;
import StaticVars;

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
        M = max(M, kReSTIRPTReservoirSize);
        return false;
    }

    // hwss_t evalUCW() { return w_sum / p_hat; }
    static Reservoir MergeReservoirsForTemporal(const Reservoir prev, const Reservoir curr, float rng1, float rng2) {
        Reservoir newRes = Reservoir();
        const float weightedPrevL =  prev.p_hat[0];
        const float weightedCurrL =  curr.p_hat[0];
        const float misPrev = weightedPrevL / (weightedPrevL + weightedCurrL);
        const float misCurr = weightedCurrL / (weightedPrevL + weightedCurrL);
        const float w_prev = misPrev * prev.p_hat[0] * prev.W[0];
        const float w_curr = misCurr * curr.p_hat[0] * curr.W[0];
        const bool usePrev = rng1 < w_prev / (w_prev + w_curr);
        const float w_sum = w_prev + w_curr;
        newRes.w_sum = w_sum;
        newRes.M = max(usePrev?prev.M+1:curr.M+1 ,128);
        newRes.p_hat = usePrev ? prev.p_hat : curr.p_hat;
        newRes.W = w_sum / newRes.p_hat;
        if(usePrev)
            newRes.s = prev.s;
        else
            newRes.s = curr.s;
        return newRes;
    }
};
