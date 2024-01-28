#pragma once
#include "Utils/Math/MathConstants.slangh"
import PathHelper;
import Utils.HWSS;
import Utils.Color.SpectrumUtils;
import StaticVars;
import Utils.Color.ColorHelpers;

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
        // return curr;
        const float prev_p_hat = SpectrumUtils.luminance(prev.p_hat, prev.s.wavelength);
        const float curr_p_hat = SpectrumUtils.luminance(curr.p_hat, curr.s.wavelength);
        const float weightedPrevL = prev.M * prev_p_hat;
        const float weightedCurrL =  curr.M * curr_p_hat;
        const float misPrev = weightedPrevL / (weightedPrevL + weightedCurrL + FLT_EPSILON);
        const float misCurr = weightedCurrL / (weightedPrevL + weightedCurrL + FLT_EPSILON);
        // TODO
        const float w_prev = misPrev * prev_p_hat; // prev.p_hat[0] * prev.evalUCW()[0];
        const float w_curr = misCurr * curr_p_hat; //curr.p_hat[0] * curr.evalUCW()[0];
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
