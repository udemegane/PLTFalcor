#pragma once
#include "Utils/Math/MathConstants.slangh"
import PathHelper;
import Utils.HWSS;
import Utils.Color.SpectrumUtils;
import StaticVars;
import Utils.Color.ColorHelpers;
import Rendering.Utils.LightsSamplingUtils;

struct DIReservoir
{
    uint M = 0u;
    float w_sum = 0.0f;
    float p_hat = 0.0f;
    LightSample ls;
    __init()
    {
        M = 0u;
        w_sum = 0.0f;
        p_hat = 0.0f;
        ls = {};
    }

    [mutating]
    bool update(const float wi, LightSample si, const float p_hat_i, const float rnd)
    {
        w_sum += wi;
        M++;
        if (rnd < wi / w_sum)
        {
            p_hat = max(0.0f, p_hat_i);
            ls = si;
            // W = w_sum / p_hat;
            return true;
        }
        return false;
    }
    float evalUCW() { return w_sum / (p_hat + FLT_EPSILON); }
}

struct Reservoir
{
    uint M = 0u;
    float w_sum = 0.0f;
    float p_hat = 0.0f;
    // hwss_t W = 0.0f;
    PathReconstructionData s;

    __init() {
        M = 0u;
        w_sum = 0.0f;
        p_hat = 0.0f;
        s = {};
    }

    [mutating]
    bool update(const float  wi, PathReconstructionData si, const float p_hat_i, const float rnd)
    {
        w_sum += wi;
        M++;
        if (rnd < wi / w_sum)
        {
            p_hat = max(0.0f,p_hat_i);
            s = si;
            // W = w_sum / p_hat;
            return true;
        }
        M = min(M, 32);
        return false;
    }

    float evalUCW(){ return w_sum / (p_hat + FLT_EPSILON); }

    // hwss_t evalUCW() { return w_sum / p_hat; }
    static Reservoir MergeReservoirsForTemporal(const Reservoir prev, const Reservoir curr, float rng1) {
        Reservoir newRes = Reservoir();
        const float weightedPrevL = prev.M * prev.p_hat;
        const float weightedCurrL =  curr.M * curr.p_hat;
        const float misPrev = weightedPrevL / (weightedPrevL + weightedCurrL + FLT_EPSILON);
        const float misCurr = weightedCurrL / (weightedPrevL + weightedCurrL + FLT_EPSILON);
        const float w_prev = misPrev * prev.w_sum; // prev.p_hat * prev.evalUCW();
        const float w_curr = misCurr * curr.w_sum; //curr.p_hat * curr.evalUCW();
        const bool usePrev = rng1 < w_prev / (w_prev + w_curr);
        const float w_sum = w_prev + w_curr;
        newRes.w_sum = w_sum;
        newRes.M = min(prev.M + curr.M ,255);
        newRes.p_hat = usePrev ? prev.p_hat : curr.p_hat;
        // newRes.W = w_sum / newRes.p_hat;
        if(usePrev)
            newRes.s = prev.s;
        else
            newRes.s = curr.s;
        return newRes;
    }
};
