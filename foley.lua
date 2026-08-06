-- foley.lua
-- Standalone Love2D sound library for UI foley cues.
-- No Clay or UI dependencies.

local Foley = {}

Foley.masterVolume = 2.5
Foley.space = 0.22

-- ── Constants ─────────────────────────────────────────────────────────────────
Foley.WAVES   = { "sine", "triangle", "square", "sawtooth" }
Foley.FILTERS = { "bandpass", "lowpass", "highpass" }

Foley.FAMILIES = {
    { label = "Pointer",  cues = { "tick","hover","glide","pop" } },
    { label = "Press",    cues = { "press","release","tap","thock" } },
    { label = "Toggle",   cues = { "on","off","switch","latch" } },
    { label = "Feedback", cues = { "success","error","warning","denied" } },
    { label = "Notify",   cues = { "chime","ping","bell","bubble" } },
    { label = "Motion",   cues = { "swoosh","whoosh","drop","rise" } },
    { label = "State",    cues = { "loading","ready","complete","sparkle" } },
}

-- ── Parameter definitions (public, used by UI) ───────────────────────────────
Foley.AT_PARAM = { key="at", label="Offset", step=0.01, min=0,   max=1.5,  fmt="%.2f s" }

Foley.TONE_PARAMS = {
    { key="f",     label="Freq",   step=10,    min=40,   max=8000, fmt="%d Hz"   },
    { key="f2",    label="Freq2",  step=10,    min=40,   max=8000, fmt="%d Hz",  nullable=true },
    { key="glide", label="Glide",  step=0.01,  min=0.005,max=1,    fmt="%.2f s", nullable=true, default=0.06 },
    { key="a",     label="Attack", step=0.001, min=0,    max=0.5,  fmt="%.3f s"  },
    { key="d",     label="Decay",  step=0.01,  min=0.005,max=2.5,  fmt="%.2f s"  },
    { key="peak",  label="Peak",   step=0.01,  min=0,    max=0.4,  fmt="%.2f"    },
}

Foley.NOISE_PARAMS = {
    { key="f",     label="Freq",   step=50,    min=40,   max=8000, fmt="%d Hz"   },
    { key="f2",    label="Freq2",  step=50,    min=40,   max=8000, fmt="%d Hz",  nullable=true },
    { key="glide", label="Glide",  step=0.01,  min=0.005,max=1,    fmt="%.2f s", nullable=true, default=0.1 },
    { key="q",     label="Q",      step=0.1,   min=0.3,  max=12,   fmt="%.1f"    },
    { key="a",     label="Attack", step=0.001, min=0,    max=0.5,  fmt="%.3f s"  },
    { key="d",     label="Decay",  step=0.01,  min=0.005,max=2.5,  fmt="%.2f s"  },
    { key="peak",  label="Peak",   step=0.01,  min=0,    max=0.4,  fmt="%.2f"    },
}

Foley.CLUSTER_PARAMS = {
    { key="n",    label="Grains", step=1,    min=1,    max=12,   fmt="%d"      },
    { key="step", label="Step",   step=0.005,min=0,    max=0.2,  fmt="%.3f s"  },
    { key="fMin", label="f Min",  step=50,   min=40,   max=8000, fmt="%d Hz"   },
    { key="fMax", label="f Max",  step=50,   min=40,   max=8000, fmt="%d Hz"   },
    { key="d",    label="Decay",  step=0.01, min=0.005,max=2.5,  fmt="%.2f s"  },
    { key="peak", label="Peak",   step=0.01, min=0,    max=0.4,  fmt="%.2f"    },
    { key="seed", label="Seed",   step=1,    min=1,    max=999,  fmt="%d"      },
}

-- ── Default cue specs ─────────────────────────────────────────────────────────
local defaults = {
    -- Pointer
    tick   = { { kind="tone",   wave="sine",     f=1800, a=0.001, d=0.03,  peak=0.3  } },
    hover  = { { kind="tone",   wave="sine",     f=800,  f2=1200, glide=0.1, a=0.005, d=0.15, peak=0.15 } },
    glide  = { { kind="tone",   wave="sine",     f=300,  f2=1200, glide=0.2, a=0.01,  d=0.4,  peak=0.2  } },
    pop    = { { kind="tone",   wave="sine",     f=600,  a=0.002, d=0.08, peak=0.35 } },
    -- Press
    press  = { { kind="tone",   wave="sine",     f=400,  a=0.001, d=0.05, peak=0.25 } },
    release= { { kind="tone",   wave="sine",     f=600,  a=0.001, d=0.1,  peak=0.2  } },
    tap    = { { kind="noise",  filter="bandpass", f=2000, q=5,   a=0.001, d=0.04, peak=0.3  } },
    thock  = { { kind="noise",  filter="bandpass", f=200,  q=2,   a=0.001, d=0.1,  peak=0.25 } },
    -- Toggle
    on     = { { kind="tone",   wave="square",   f=1000, a=0.005, d=0.1,  peak=0.2  } },
    off    = { { kind="tone",   wave="square",   f=800,  a=0.005, d=0.1,  peak=0.15 } },
    switch = { { kind="noise",  filter="bandpass", f=800,  q=3,   a=0.002, d=0.05, peak=0.25 } },
    latch  = { { kind="noise",  filter="bandpass", f=600,  q=1.5, a=0.002, d=0.08, peak=0.2  } },
    -- Feedback
    success = { { kind="tone", wave="triangle", f=800,  f2=1200, glide=0.05, a=0.005, d=0.2, peak=0.25 } },
    error   = { { kind="tone", wave="sawtooth", f=200,  f2=100,  glide=0.1,  a=0.005, d=0.3, peak=0.25 } },
    warning = { { kind="tone", wave="triangle", f=500,  f2=400,  glide=0.08, a=0.005, d=0.25,peak=0.25 } },
    denied  = { { kind="noise",filter="lowpass",  f=300,  q=1,    a=0.005, d=0.3, peak=0.3  } },
    -- Notify
    chime   = { { kind="tone", wave="sine",     f=1200, f2=1600, glide=0.1,  a=0.005, d=0.4, peak=0.2  } },
    ping    = { { kind="tone", wave="sine",     f=2000, a=0.001, d=0.1,  peak=0.25 } },
    bell    = { { kind="tone", wave="triangle", f=1500, a=0.001, d=0.6,  peak=0.15 } },
    bubble  = { { kind="tone", wave="sine",     f=800,  a=0.005, d=0.15, peak=0.15 } },
    -- Motion
    swoosh  = { { kind="noise",filter="bandpass", f=2000, f2=500, glide=0.2, q=3, a=0.01, d=0.3, peak=0.2 } },
    whoosh  = { { kind="noise",filter="bandpass", f=3000, f2=800, glide=0.3, q=2, a=0.01, d=0.4, peak=0.2 } },
    drop    = { { kind="tone", wave="sine",     f=600,  f2=200, glide=0.15, a=0.005, d=0.3, peak=0.25 } },
    rise    = { { kind="tone", wave="sine",     f=200,  f2=800, glide=0.2,  a=0.005, d=0.3, peak=0.25 } },
    -- State
    loading  = { { kind="cluster", n=6, step=0.1, fMin=200, fMax=600, d=0.15, peak=0.1, seed=42 } },
    ready    = { { kind="tone",   wave="sine",     f=1000, a=0.005, d=0.15, peak=0.2 } },
    complete = { { kind="tone",   wave="triangle", f=1200, a=0.005, d=0.3,  peak=0.2 } },
    sparkle  = { { kind="cluster", n=8, step=0.04, fMin=3000, fMax=6000, d=0.05, peak=0.1, seed=7 } },
}

-- ── Internal state (user overrides) ─────────────────────────────────────────
local overrides = {}

-- ── Utility functions ───────────────────────────────────────────────────────
local function deep_copy_spec(spec)
    local out = {}
    for i, layer in ipairs(spec) do
        local l = {}
        for k, v in pairs(layer) do l[k] = v end
        out[i] = l
    end
    return out
end

local function params_for(layer)
    if layer.kind == "tone"    then return Foley.TONE_PARAMS    end
    if layer.kind == "noise"   then return Foley.NOISE_PARAMS   end
    if layer.kind == "cluster" then return Foley.CLUSTER_PARAMS end
    return {}
end

-- ── Audio synthesis ─────────────────────────────────────────────────────────
local SAMPLE_RATE = 44100
local TWO_PI = 2 * math.pi

-- Biquad filter (Direct Form I) based on RBJ cookbook
local function compute_biquad_coeffs(freq, q, filter_type)
    local w0 = TWO_PI * freq / SAMPLE_RATE
    local cos_w0 = math.cos(w0)
    local sin_w0 = math.sin(w0)
    local alpha = sin_w0 / (2 * q)

    local b0, b1, b2, a0, a1, a2
    if filter_type == "lowpass" then
        b0 = (1 - cos_w0) / 2
        b1 = 1 - cos_w0
        b2 = (1 - cos_w0) / 2
        a0 = 1 + alpha
        a1 = -2 * cos_w0
        a2 = 1 - alpha
    elseif filter_type == "highpass" then
        b0 = (1 + cos_w0) / 2
        b1 = -(1 + cos_w0)
        b2 = (1 + cos_w0) / 2
        a0 = 1 + alpha
        a1 = -2 * cos_w0
        a2 = 1 - alpha
    else -- bandpass (0 dB peak gain)
        b0 = alpha
        b1 = 0
        b2 = -alpha
        a0 = 1 + alpha
        a1 = -2 * cos_w0
        a2 = 1 - alpha
    end

    -- Normalize
    b0, b1, b2 = b0 / a0, b1 / a0, b2 / a0
    a1, a2 = a1 / a0, a2 / a0
    return b0, b1, b2, a1, a2
end

local function envelope(t, attack, decay, peak)
    if t < attack then
        return (t / attack) * peak
    elseif t < attack + decay then
        local decay_t = (t - attack) / decay
        -- Web Audio exponentialRampToValueAtTime typically decays exponentially
        return peak * math.pow(0.001, decay_t)
    end
    return 0
end

-- Generate one layer's samples and add to buffer
local function render_layer(buffer, reverb_buffer, layer, start_sample)
    local at  = layer.at or 0
    local a   = layer.a  or 0
    local d   = layer.d  or 0
    local peak= layer.peak or 0.2
    local duration = a + d
    local offset = math.floor(at * SAMPLE_RATE)
    local start = start_sample + offset
    local length = math.floor(duration * SAMPLE_RATE)
    if length == 0 then return end

    if layer.kind == "tone" then
        local wave = layer.wave or "sine"
        local f_start = layer.f
        local f_end = layer.f2 or layer.f
        local glide_time = (layer.f2 and layer.glide) and layer.glide or 0

        -- Phase accumulator
        local phase = 0
        local freq
        for i = 1, length do
            local t = (i-1) / SAMPLE_RATE
            -- envelope
            local env = envelope(t, a, d, peak)

            -- frequency interpolation
            if t < glide_time and layer.f2 then
                local frac = t / glide_time
                freq = f_start * math.pow(f_end / f_start, frac)
            else
                freq = f_end
            end

            -- phase increment
            phase = phase + freq / SAMPLE_RATE
            phase = phase % 1

            -- waveform sample
            local s = 0
            if wave == "sine" then
                s = math.sin(phase * TWO_PI)
            elseif wave == "triangle" then
                s = 2 * math.abs(2 * (phase - 0.5)) - 1
            elseif wave == "square" then
                s = phase < 0.5 and 1 or -1
            elseif wave == "sawtooth" then
                s = 2 * phase - 1
            end

            local idx = start + i
            if idx <= #buffer then
                local val_env = s * env
                buffer[idx] = buffer[idx] + val_env
                if layer.send and layer.send > 0 then
                    reverb_buffer[idx] = reverb_buffer[idx] + val_env * layer.send * Foley.space
                end
            end
        end

    elseif layer.kind == "noise" then
        local f_start = layer.f
        local f_end = layer.f2 or layer.f
        local glide_time = (layer.f2 and layer.glide) and layer.glide or 0
        local q = layer.q or 1
        local filter_type = layer.filter or "bandpass"

        -- Filter state
        local x1, x2, y1, y2 = 0, 0, 0, 0
        local b0, b1, b2, a1, a2 = 0, 0, 0, 0, 0
        local last_freq = nil

        for i = 1, length do
            local t = (i-1) / SAMPLE_RATE
            local env = envelope(t, a, d, peak)

            -- update filter coefficients if frequency changed
            local freq
            if t < glide_time and layer.f2 then
                freq = f_start * math.pow(f_end / f_start, t / glide_time)
            else
                freq = f_end
            end
            if freq ~= last_freq then
                b0, b1, b2, a1, a2 = compute_biquad_coeffs(freq, q, filter_type)
                last_freq = freq
            end

            -- white noise
            local input = (math.random() * 2 - 1) * env

            -- biquad
            local output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2, x1 = x1, input
            y2, y1 = y1, output

            local idx = start + i
            if idx <= #buffer then
                local val_env = output
                buffer[idx] = buffer[idx] + val_env
                if layer.send and layer.send > 0 then
                    reverb_buffer[idx] = reverb_buffer[idx] + val_env * layer.send * Foley.space
                end
            end
        end

    elseif layer.kind == "cluster" then
        local n = layer.n or 3
        local step = layer.step or 0.02
        local fMin = layer.fMin or 400
        local fMax = layer.fMax or 2000
        local d_grain = layer.d or 0.1
        local peak_grain = layer.peak or 0.1
        
        -- Local deterministic PRNG for cluster so we don't mess up the global math.random state
        local seed = layer.seed or 1
        local function lcg()
            seed = (seed * 1103515245 + 12345) % 2147483648
            return seed / 2147483648
        end

        for g = 0, n-1 do
            local grain_start = g * step
            local freq = fMin + lcg() * (fMax - fMin)
            local grain_length = math.floor(d_grain * SAMPLE_RATE)
            local offset_g = math.floor(grain_start * SAMPLE_RATE)
            local phase = 0

            for i = 1, grain_length do
                local t = (i-1) / SAMPLE_RATE
                local env = envelope(t, 0, d_grain, peak_grain)  -- attack=0

                phase = phase + freq / SAMPLE_RATE
                phase = phase % 1
                local s = math.sin(phase * TWO_PI)

                local idx = start + offset_g + i
                if idx <= #buffer then
                    local s_env = s * env
                    buffer[idx] = buffer[idx] + s_env
                    if layer.send and layer.send > 0 then
                        reverb_buffer[idx] = reverb_buffer[idx] + s_env * layer.send * Foley.space
                    end
                end
            end
        end
    end
end

local function schroeder_reverb(buffer)
    local out = {}
    for i = 1, #buffer do out[i] = 0 end
    
    local comb_delays = { 1557, 1617, 1491, 1422 }
    local allpass_delays = { 225, 341 }
    local feedback = 0.8
    local damp = 0.2
    
    for _, d in ipairs(comb_delays) do
        local comb_buf = {}
        for i = 1, d do comb_buf[i] = 0 end
        local idx = 1
        local filter_store = 0
        for i = 1, #buffer do
            local x = buffer[i]
            local y = comb_buf[idx]
            filter_store = (y * (1 - damp)) + (filter_store * damp)
            comb_buf[idx] = x + filter_store * feedback
            out[i] = out[i] + y
            idx = idx + 1
            if idx > d then idx = 1 end
        end
    end
    
    for _, d in ipairs(allpass_delays) do
        local ap_buf = {}
        for i = 1, d do ap_buf[i] = 0 end
        local idx = 1
        for i = 1, #buffer do
            local x = out[i]
            local y = ap_buf[idx]
            local v = x + 0.5 * y
            ap_buf[idx] = v
            out[i] = -0.5 * v + y
            idx = idx + 1
            if idx > d then idx = 1 end
        end
    end
    return out
end

-- Synthesize a whole SoundData from a spec
local function synthesize_spec(spec)
    if #spec == 0 then return love.sound.newSoundData(1, SAMPLE_RATE, 16, 1) end

    -- determine total length
    local total_dur = 0
    local has_reverb = false
    for _, layer in ipairs(spec) do
        local at = layer.at or 0
        local a  = layer.a or 0
        local d  = layer.d or 0
        local layer_end = at + a + d
        if layer.kind == "cluster" then
            local n = layer.n or 1
            local step = layer.step or 0
            local d_grain = layer.d or 0.1
            local cluster_end = at + (n-1)*step + d_grain
            if cluster_end > layer_end then layer_end = cluster_end end
        end
        if layer_end > total_dur then total_dur = layer_end end
        if layer.send and layer.send > 0 and Foley.space > 0 then has_reverb = true end
    end
    if has_reverb then total_dur = total_dur + 0.6 end
    total_dur = math.max(total_dur, 0.5)
    local sample_count = math.ceil(total_dur * SAMPLE_RATE)
    local buffer = {}
    local reverb_buffer = {}
    for i = 1, sample_count do 
        buffer[i] = 0 
        reverb_buffer[i] = 0 
    end

    -- render layers
    for _, layer in ipairs(spec) do
        render_layer(buffer, reverb_buffer, layer, 1)
    end

    if has_reverb then
        local rev_out = schroeder_reverb(reverb_buffer)
        for i = 1, sample_count do
            buffer[i] = buffer[i] + rev_out[i]
        end
    end

    -- clamp and create SoundData
    local sd = love.sound.newSoundData(sample_count, SAMPLE_RATE, 16, 1)
    for i = 1, sample_count do
        local val = math.max(-1, math.min(1, buffer[i] * Foley.masterVolume))
        sd:setSample(i-1, val)
    end
    return sd
end

-- ── Public API ───────────────────────────────────────────────────────────────

--- Return a deep copy of the current spec for a cue (default or override).
function Foley.getSpec(cue)
    local spec = overrides[cue] or defaults[cue] or {}
    return deep_copy_spec(spec)
end

--- Permanently set an override spec for a cue.
function Foley.setSpec(cue, spec)
    overrides[cue] = deep_copy_spec(spec)
end

--- Remove any override and revert to the built-in default.
function Foley.resetSpec(cue)
    overrides[cue] = nil
end

--- Check whether the cue has a user override.
function Foley.isOverridden(cue)
    return overrides[cue] ~= nil
end

--- Play the current sound for a cue (respects overrides).
function Foley.play(cue)
    Foley.playSpec(Foley.getSpec(cue))
end

--- Play a sound directly from a spec table.
function Foley.playSpec(spec)
    local sd = synthesize_spec(spec)
    local source = love.audio.newSource(sd)
    love.audio.play(source)
end

--- Generate waveform points for visualisation.
--- Returns a table of `numPoints` values in [-1, 1].
function Foley.getWaveformPoints(cue, numPoints)
    return Foley.buildSpecWaveformPoints(Foley.getSpec(cue), numPoints)
end

function Foley.buildSpecWaveformPoints(spec, numPoints)
    local sd = synthesize_spec(spec)
    local totalSamples = sd:getSampleCount()
    if totalSamples == 0 then return {} end
    local chunkSize = math.max(1, math.floor(totalSamples / numPoints))
    local points = {}
    for i = 1, numPoints do
        local startSample = (i-1) * chunkSize
        local endSample = math.min(startSample + chunkSize - 1, totalSamples - 1)
        local peak = 0
        for s = startSample, endSample do
            local val = math.abs(sd:getSample(s))
            if val > peak then peak = val end
        end
        points[i] = peak
    end
    return points
end

return Foley