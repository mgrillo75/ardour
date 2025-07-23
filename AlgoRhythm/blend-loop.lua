-- Lua script to blend regions intro.3 and intro.23 in track "intro 1"
local function blend_regions()
    -- Get the current session
    local session = ARDOUR.Session()

    -- Find the track named "intro 1"
    local track = nil
    for t in session:get_tracks():iter() do
        if t:name() == "intro 1" then
            track = t
            break
        end
    end

    if not track then
        print("Track 'intro 1' not found.")
        return
    end

    -- Find regions intro.3 and intro.23
    local region3, region23 = nil, nil
    for r in track:playlist():regions():iter() do
        if r:name() == "intro.3" then
            region3 = r
        elseif r:name() == "intro.23" then
            region23 = r
        end
    end

    if not region3 or not region23 then
        print("Regions 'intro.3' or 'intro.23' not found.")
        return
    end

    -- Determine the smaller region (intro.23)
    local smaller_region = region23
    local larger_region = region3

    -- Trim extra space in the front of the smaller region
    local extra_space = smaller_region:start() - larger_region:end()
    if extra_space > 0 then
        smaller_region:trim_front(extra_space)
    end

    -- Crossfade the regions
    local crossfade_length = 0.1 -- Adjust as needed (in seconds)
    larger_region:set_fade_out(crossfade_length, ARDOUR.FadeShape.Linear)
    smaller_region:set_fade_in(crossfade_length, ARDOUR.FadeShape.Linear)

    -- Position the smaller region right after the larger one
    smaller_region:set_position(larger_region:end())

    print("Regions blended successfully.")
end

-- Run the function
blend_regions()

