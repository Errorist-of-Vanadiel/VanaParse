--[[
VanaCore 0.3.3.0
Copyright (c) 2026 Errorist of Vana'diel
MIT License

Shared, non-running library for the Vana suite.  VanaCore intentionally owns no
HUD and registers no Windower events.  Each consumer owns and cleans up its own
runtime state.
]]

local Core = {}
Core.VERSION = '0.3.3.0'
Core.SCHEMA = 1

local function now_clock()
    return os.clock()
end

function Core.now()
    return now_clock()
end

function Core.clamp(value, low, high)
    value = tonumber(value) or 0
    if low ~= nil and value < low then value = low end
    if high ~= nil and value > high then value = high end
    return value
end

function Core.merge(target, source)
    target = type(target) == 'table' and target or {}
    for key, value in pairs(source or {}) do
        if type(value) == 'table' then
            target[key] = Core.merge(type(target[key]) == 'table' and target[key] or {}, value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
    return target
end

function Core.copy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for k, v in pairs(value) do out[Core.copy(k, seen)] = Core.copy(v, seen) end
    return out
end

function Core.trim(value)
    return tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', '')
end

function Core.lower(value)
    return Core.trim(value):lower()
end

function Core.join(values, separator)
    local out = {}
    for _, value in ipairs(values or {}) do
        if value ~= nil and tostring(value) ~= '' then out[#out + 1] = tostring(value) end
    end
    return table.concat(out, separator or ' ')
end

function Core.comma(value)
    value = math.floor(tonumber(value) or 0)
    local sign = value < 0 and '-' or ''
    local digits = tostring(math.abs(value))
    return sign .. digits:reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')
end

function Core.compact(value)
    value = tonumber(value) or 0
    local absolute = math.abs(value)
    if absolute >= 1000000000000000 then return ('%.2fQ'):format(value / 1000000000000000) end
    if absolute >= 1000000000000 then return ('%.2fT'):format(value / 1000000000000) end
    if absolute >= 1000000000 then return ('%.2fB'):format(value / 1000000000) end
    if absolute >= 1000000 then return ('%.2fM'):format(value / 1000000) end
    if absolute >= 1000 then return ('%.1fk'):format(value / 1000) end
    return tostring(math.floor(value + (value >= 0 and 0.5 or -0.5)))
end

function Core.duration(seconds)
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(seconds / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    local secs = seconds % 60
    if hours > 0 then return ('%d:%02d:%02d'):format(hours, minutes, secs) end
    return ('%02d:%02d'):format(minutes, secs)
end

function Core.percent(numerator, denominator, decimals)
    numerator, denominator = tonumber(numerator) or 0, tonumber(denominator) or 0
    if denominator <= 0 then return nil end
    return (numerator / denominator) * 100, decimals or 1
end

function Core.percent_text(numerator, denominator, decimals)
    local value = Core.percent(numerator, denominator, decimals)
    if value == nil then return '-' end
    return (('%.' .. tostring(decimals or 1) .. 'f%%'):format(value))
end

function Core.rate_text(value)
    if value == nil then return '--' end
    value = tonumber(value) or 0
    return Core.compact(value)
end

function Core.safe_div(numerator, denominator)
    numerator, denominator = tonumber(numerator) or 0, tonumber(denominator) or 0
    if denominator == 0 then return nil end
    return numerator / denominator
end

function Core.pad(value, width, align)
    -- Backward-compatible wrapper.  Once the module is fully loaded, route all
    -- legacy callers through the color/control-code-aware formatter so no HUD
    -- table can drift simply because a cell contains Windower escape sequences.
    if Core.visible_pad then return Core.visible_pad(value, width, align) end
    value = tostring(value == nil and '' or value)
    local visible = value:gsub('\\cs%b()', ''):gsub('\\cr', '')
    width = math.max(1, tonumber(width) or #visible)
    local missing = math.max(0, width - #visible)
    if align == 'right' then return string.rep(' ', missing) .. value end
    return value .. string.rep(' ', missing)
end



-- Visible text helpers for HUD tables. Windower text color escape sequences do
-- not occupy screen columns, so table sizing must ignore them.
function Core.visible_text(value)
    return tostring(value == nil and '' or value):gsub('\\cs%b()', ''):gsub('\\cr', '')
end

function Core.visible_len(value)
    return #Core.visible_text(value)
end

function Core.color_text(value, red, green, blue)
    if not red then return tostring(value == nil and '' or value) end
    return ('\\cs(%d,%d,%d)%s\\cr'):format(red, green or red, blue or red, tostring(value == nil and '' or value))
end

-- Compute the minimum width needed for each table column. A caller may pass a
-- state table to retain high-water widths while the view remains active; this
-- prevents a HUD from jittering narrower when a transient large value leaves.
function Core.table_widths(headers, rows, options, state)
    options = options or {}
    local widths = {}
    local count = #(headers or {})
    for _, row in ipairs(rows or {}) do if #row > count then count = #row end end
    for i = 1, count do
        local width = Core.visible_len(headers and headers[i] or '')
        local min_width = options.min_widths and tonumber(options.min_widths[i]) or 1
        local max_width = options.max_widths and tonumber(options.max_widths[i]) or nil
        width = math.max(width, min_width or 1)
        for _, row in ipairs(rows or {}) do width = math.max(width, Core.visible_len(row[i])) end
        if max_width then width = math.min(width, max_width) end
        if state then
            state[i] = math.max(tonumber(state[i]) or 0, width)
            width = state[i]
        end
        widths[i] = width
    end
    return widths
end

-- Truncate a Windower-colored string by visible characters while preserving
-- color escape sequences.  This is deliberately byte-oriented because the
-- in-game HUD labels are resource-derived ASCII/Latin text; Japanese user-facing
-- documentation remains outside this formatter.
function Core.visible_truncate(value, width, suffix)
    value = tostring(value == nil and '' or value)
    width = math.max(1, tonumber(width) or Core.visible_len(value))
    if Core.visible_len(value) <= width then return value end
    suffix = suffix == nil and '...' or tostring(suffix)
    local suffix_len = Core.visible_len(suffix)
    local keep = math.max(0, width - suffix_len)
    if width <= suffix_len then suffix=''; keep=width end
    local out, visible, i, colored = {}, 0, 1, false
    while i <= #value and visible < keep do
        local rest=value:sub(i)
        local cs=rest:match('^(\\cs%b())')
        if cs then out[#out+1]=cs; i=i+#cs; colored=true
        elseif rest:sub(1,3)=='\\cr' then out[#out+1]='\\cr'; i=i+3; colored=false
        else out[#out+1]=value:sub(i,i); i=i+1; visible=visible+1 end
    end
    if colored then out[#out+1]='\\cr' end
    out[#out+1]=suffix
    return table.concat(out)
end

function Core.visible_pad(value, width, align)
    value = tostring(value == nil and '' or value)
    local visible = Core.visible_len(value)
    width = math.max(1, tonumber(width) or visible)
    if visible > width then value=Core.visible_truncate(value,width); visible=Core.visible_len(value) end
    if visible >= width then return value end
    local spaces = string.rep(' ', width - visible)
    if align == 'right' then return spaces .. value end
    return value .. spaces
end

-- Wrap a delimiter-separated list without allowing one long status stack to
-- force an entire HUD off screen.  Existing color escapes are preserved.
function Core.wrap_joined(prefix, values, separator, max_width, continuation_prefix)
    prefix=tostring(prefix or '')
    values=values or {}
    separator=tostring(separator or ' | ')
    max_width=math.max(Core.visible_len(prefix)+4,tonumber(max_width) or 64)
    continuation_prefix=continuation_prefix or string.rep(' ',Core.visible_len(prefix))
    local lines={}; local current=prefix
    for _,raw in ipairs(values) do
        local value=tostring(raw or '')
        if Core.visible_len(value)>math.max(4,max_width-Core.visible_len(continuation_prefix)) then
            value=Core.visible_truncate(value,math.max(4,max_width-Core.visible_len(continuation_prefix)))
        end
        local addition=(current==prefix and '' or separator)..value
        if Core.visible_len(current)+Core.visible_len(addition)<=max_width then
            current=current..addition
        else
            if current~=prefix then lines[#lines+1]=current end
            current=continuation_prefix..value
        end
    end
    if current~=prefix or #values==0 then lines[#lines+1]=current end
    return lines
end

function Core.format_dynamic_table(headers, rows, aligns, options, state)
    -- Alignment contract used by every Vana HUD: descriptive text columns are
    -- left aligned; quantitative/stat/time/value columns are right aligned.
    -- Callers provide the semantic alignment map while this formatter guarantees
    -- that visible screen columns, not raw Lua byte length, determine padding.
    options = options or {}
    local gap = string.rep(' ', math.max(1, tonumber(options.gap) or 3))
    local widths = Core.table_widths(headers, rows, options, state)
    local lines = {}
    local function render(row)
        local out = {}
        for i = 1, #widths do
            out[#out + 1] = Core.visible_pad(row and row[i] or '', widths[i], aligns and aligns[i] or 'left')
        end
        return table.concat(out, gap)
    end
    lines[#lines + 1] = render(headers or {})
    for _, row in ipairs(rows or {}) do lines[#lines + 1] = render(row) end
    return lines, widths
end
function Core.format_row(columns, widths, aligns, separator)
    -- Descriptive text is left aligned and numeric/time/stat values are right
    -- aligned by the caller's semantic map. All HUD table rows are aligned by
    -- *visible* characters. Windower
    -- color/control escapes occupy bytes in the Lua string but no screen
    -- columns. Using Core.pad here caused intermittent one-character shifts in
    -- VanaParse/VanaWatch whenever a colored value appeared in a numeric cell.
    local out = {}
    for i, value in ipairs(columns or {}) do
        out[#out + 1] = Core.visible_pad(value, widths[i] or 8, aligns and aligns[i] or 'left')
    end
    return table.concat(out, separator or ' ')
end

-- Compact repeated enemy-family/content prefixes without throwing away the
-- identifying species. This is intentionally conservative and only abbreviates
-- known verbose prefixes unless a caller explicitly requests a hard max width.
function Core.abbreviate_enemy_name(value, max_width)
    local name = tostring(value == nil and '' or value)
    local prefixes = {
        Temenos=true, Apollyon=true, Apex=true, Locus=true, Bezzetto=true,
    }
    local first, rest = name:match('^(%S+)%s+(.+)$')
    if first and rest and prefixes[first] then
        name = first:sub(1,1) .. '. ' .. rest
    end
    if max_width and Core.visible_len(name) > tonumber(max_width) then
        name = Core.visible_truncate(name, tonumber(max_width))
    end
    return name
end

function Core.display_word(value)
    local s = tostring(value == nil and '' or value)
    if s == '' then return s end
    return s:sub(1,1):upper() .. s:sub(2)
end

-- -------------------------------------------------------------------------
-- Shared command vocabulary
-- -------------------------------------------------------------------------
-- VanaCore defines the common verbs and presentation rules. Individual
-- addons register only the verbs that make sense for their own subjects; the
-- Core does not force meaningless combinations on every addon.
Core.COMMAND_VERBS = {
    'on','off','start','stop','continue','pause','enable','disable','log','report',
    'add','remove','include','exclude','pin','unpin','save','reset','load','reload','unload',
}

local COMMAND_VERB_SET = {}
for _, word in ipairs(Core.COMMAND_VERBS) do COMMAND_VERB_SET[word] = true end
local COMMAND_VERB_ALIASES = {resume='continue',begin='start'}

function Core.command_verb(value)
    local word = Core.lower(value)
    word = COMMAND_VERB_ALIASES[word] or word
    return COMMAND_VERB_SET[word] and word or nil
end

function Core.command_options(values)
    local out = {}
    for _, value in ipairs(values or {}) do
        local text = Core.trim(value)
        if text ~= '' then out[#out + 1] = text end
    end
    return table.concat(out, ' | ')
end

-- Human-facing command/help text always uses a single space on both sides of
-- the option separator. This intentionally does not alter ordinary HUD data.
function Core.humanize_command_text(value)
    local text = tostring(value or '')
    return (text:gsub('%s*|%s*', ' | '))
end

local function command_subject_accepts(spec, verb)
    if spec == true then return true end
    if type(spec) ~= 'table' then return false end
    if spec[verb] == true then return true end
    for _, value in ipairs(spec) do
        if Core.command_verb(value) == verb then return true end
    end
    return false
end

-- Recognizes both subject-first and verb-first forms. For example, an addon
-- may register WS for report/include/exclude and then accept both
--   //vp ws report
-- and
--   //vp report ws
-- without duplicating vocabulary/parsing rules.
function Core.command_subject_verb(args, supported)
    if type(args) ~= 'table' or type(supported) ~= 'table' then return nil end
    local first, second = Core.lower(args[1]), Core.lower(args[2])
    local second_verb = Core.command_verb(second)
    if supported[first] and second_verb and command_subject_accepts(supported[first], second_verb) then
        return first, second_verb, 3
    end
    local first_verb = Core.command_verb(first)
    if first_verb and supported[second] and command_subject_accepts(supported[second], first_verb) then
        return second, first_verb, 3
    end
    return nil
end

-- Fixed-second rolling accumulator.  It stores at most max_seconds + 2 buckets,
-- so event volume cannot cause the table to grow without bound.
local Window = {}
Window.__index = Window

function Window.new(max_seconds)
    return setmetatable({
        max_seconds = math.max(1, math.floor(tonumber(max_seconds) or 600)),
        buckets = {},
        first_at = nil,
        last_at = nil,
    }, Window)
end

function Window:add(value, timestamp)
    value = tonumber(value) or 0
    timestamp = tonumber(timestamp) or now_clock()
    local second = math.floor(timestamp)
    self.buckets[second] = (self.buckets[second] or 0) + value
    self.first_at = self.first_at or timestamp
    self.last_at = timestamp
    self:prune(timestamp)
end

function Window:prune(timestamp)
    timestamp = tonumber(timestamp) or now_clock()
    local floor = math.floor(timestamp - self.max_seconds - 2)
    for second in pairs(self.buckets) do
        if second < floor then self.buckets[second] = nil end
    end
end

function Window:sum(seconds, timestamp)
    seconds = math.max(1, math.floor(tonumber(seconds) or self.max_seconds))
    timestamp = tonumber(timestamp) or now_clock()
    local first = math.floor(timestamp - seconds + 1)
    local last = math.floor(timestamp)
    local total = 0
    for second = first, last do total = total + (self.buckets[second] or 0) end
    return total
end

function Window:ready(seconds, timestamp)
    seconds = math.max(1, tonumber(seconds) or self.max_seconds)
    timestamp = tonumber(timestamp) or now_clock()
    return self.first_at ~= nil and (timestamp - self.first_at) >= seconds
end

function Window:rate(seconds, timestamp)
    seconds = math.max(1, tonumber(seconds) or self.max_seconds)
    timestamp = tonumber(timestamp) or now_clock()
    if not self:ready(seconds, timestamp) then return nil end
    return (self:sum(seconds, timestamp) / seconds) * 3600
end

function Window:per_second(seconds, timestamp)
    seconds = math.max(1, tonumber(seconds) or self.max_seconds)
    timestamp = tonumber(timestamp) or now_clock()
    if not self:ready(seconds, timestamp) then return nil end
    return self:sum(seconds, timestamp) / seconds
end

function Window:reset()
    self.buckets, self.first_at, self.last_at = {}, nil, nil
end

Core.Window = Window

-- Activity clock with explicit active/inactive state.  mark() starts/resumes it;
-- tick() pauses it after the configured quiet period.  Session time starts at
-- the first mark and is kept separate from active time.
local Activity = {}
Activity.__index = Activity

function Activity.new(timeout_seconds)
    return setmetatable({
        timeout = math.max(1, tonumber(timeout_seconds) or 15),
        started_at = nil,
        active_started_at = nil,
        active_accumulated = 0,
        last_activity = nil,
        running = false,
    }, Activity)
end

function Activity:mark(timestamp)
    timestamp = tonumber(timestamp) or now_clock()
    self.started_at = self.started_at or timestamp
    if not self.running then
        self.running = true
        self.active_started_at = timestamp
    end
    self.last_activity = timestamp
end

function Activity:tick(timestamp)
    timestamp = tonumber(timestamp) or now_clock()
    if not self.running or not self.last_activity or not self.active_started_at then return false end
    if timestamp - self.last_activity >= self.timeout then
        local stop_at = self.last_activity + self.timeout
        self.active_accumulated = self.active_accumulated + math.max(0, stop_at - self.active_started_at)
        self.active_started_at = nil
        self.running = false
        return true
    end
    return false
end

function Activity:active_seconds(timestamp)
    timestamp = tonumber(timestamp) or now_clock()
    local total = self.active_accumulated
    if self.running and self.active_started_at then total = total + math.max(0, timestamp - self.active_started_at) end
    return total
end

function Activity:session_seconds(timestamp)
    timestamp = tonumber(timestamp) or now_clock()
    if not self.started_at then return 0 end
    return math.max(0, timestamp - self.started_at)
end

function Activity:quiet_seconds(timestamp)
    timestamp = tonumber(timestamp) or now_clock()
    if not self.last_activity then return math.huge end
    return math.max(0, timestamp - self.last_activity)
end

function Activity:reset()
    self.started_at = nil
    self.active_started_at = nil
    self.active_accumulated = 0
    self.last_activity = nil
    self.running = false
end

Core.Activity = Activity

-- Conservative action-message helper.  It only classifies outcomes when the
-- installed Windower resources actually contain recognizable wording.
function Core.action_message_text(res, message_id)
    local source = res and res.action_messages and res.action_messages[tonumber(message_id) or -1]
    if not source then return '' end
    return tostring(source.en or source.english or source.name or source.message or ''):lower()
end

function Core.action_outcome(res, action)
    if type(action) ~= 'table' then return 'unknown' end
    local text = Core.action_message_text(res, action.message)
    if text:find('miss', 1, true) then return 'miss' end
    if text:find('resist', 1, true) or text:find('no effect', 1, true) then return 'resist' end
    if text:find('critical', 1, true) then return 'critical' end
    if text:find('recover', 1, true) or text:find('restore', 1, true) or text:find('heals', 1, true) then return 'heal' end
    local amount = tonumber(action.param) or 0
    if amount > 0 then return 'landed' end
    return 'unknown'
end

-- Snapshot current party/alliance state without changing the long-standing
-- by_id/order contract used by existing VanaSuite addons. 0.3.0.0 adds the
-- basic vitals/job fields needed by VanaAware; consumers may ignore them.
function Core.party_snapshot(windower_api)
    local result = {by_id={}, order={}, self_id=nil}
    if not windower_api or not windower_api.ffxi then return result end
    local player = windower_api.ffxi.get_player()
    if player then result.self_id = player.id end
    local party = windower_api.ffxi.get_party and windower_api.ffxi.get_party() or {}
    local party_keys = {'p0','p1','p2','p3','p4','p5'}
    local alliance_keys = {'a10','a11','a12','a13','a14','a15','a20','a21','a22','a23','a24','a25'}
    local function first(member, ...)
        for i=1,select('#',...) do
            local key=select(i,...)
            if member[key]~=nil then return member[key] end
        end
        return nil
    end
    local function add(key, scope, group, slot)
        local member = party and party[key]
        if type(member) ~= 'table' then return end
        local id = member.mob and member.mob.id or member.id
        if not id then return end
        local entry = {
            id=id,
            name=member.name or (member.mob and member.mob.name) or tostring(id),
            scope=scope,
            key=key,
            group=group,
            slot=slot,
            mob=member.mob,
            member=member,
            actor_type=(member.mob and member.mob.is_npc) and 'trust' or 'player',
            hp=tonumber(first(member,'hp','HP')),
            hpp=tonumber(first(member,'hpp','hp_percent','HP%')),
            mp=tonumber(first(member,'mp','MP')),
            mpp=tonumber(first(member,'mpp','mp_percent','MP%')),
            tp=tonumber(first(member,'tp','TP')),
            zone=tonumber(first(member,'zone','zone_id','Zone')),
            main_job=first(member,'main_job','main_job_short','Main Job'),
            main_job_level=tonumber(first(member,'main_job_level','main_job_lvl','Main Job Level')),
            sub_job=first(member,'sub_job','sub_job_short','Sub Job'),
            sub_job_level=tonumber(first(member,'sub_job_level','sub_job_lvl','Sub Job Level')),
            master_level=tonumber(first(member,'master_level','Master Level')),
        }
        -- Some Windower party builds expose percentages but not current values;
        -- preserve explicit max values when they are available for display.
        entry.max_hp=tonumber(first(member,'max_hp','hp_max','Maximum HP'))
        entry.max_mp=tonumber(first(member,'max_mp','mp_max','Maximum MP'))
        result.by_id[id] = entry
        result.order[#result.order + 1] = id
    end
    for i,key in ipairs(party_keys) do add(key, 'party', 1, i) end
    for i,key in ipairs(alliance_keys) do
        local group=i<=6 and 2 or 3
        local slot=((i-1)%6)+1
        add(key, 'alliance', group, slot)
    end
    if player and not result.by_id[player.id] then
        result.by_id[player.id] = {id=player.id, name=player.name, scope='self', key='self', group=1, slot=1, actor_type='player'}
        table.insert(result.order, 1, player.id)
    elseif player and result.by_id[player.id] then
        result.by_id[player.id].scope = 'self'
    end
    if player and result.by_id[player.id] then
        local self=result.by_id[player.id]
        local vitals=player.vitals or {}
        self.hp=tonumber(vitals.hp) or self.hp
        self.max_hp=tonumber(vitals.max_hp) or self.max_hp
        self.hpp=tonumber(vitals.hpp) or self.hpp
        self.mp=tonumber(vitals.mp) or self.mp
        self.max_mp=tonumber(vitals.max_mp) or self.max_mp
        self.mpp=tonumber(vitals.mpp) or self.mpp
        self.tp=tonumber(vitals.tp) or self.tp
        self.main_job=player.main_job or player.main_job_short or self.main_job
        self.main_job_level=tonumber(player.main_job_level) or self.main_job_level
        self.sub_job=player.sub_job or player.sub_job_short or self.sub_job
        self.sub_job_level=tonumber(player.sub_job_level) or self.sub_job_level
        self.master_level=tonumber(player.master_level) or self.master_level
        self.buffs=player.buffs
    end
    return result
end


-- Shared allied-entity classifier.  Owner IDs are preferred, but some FFXI
-- allied constructs (notably Luopans on some Windower builds) are more reliably
-- exposed through an owner's pet index.  Consumers should use this instead of
-- assuming that only direct party IDs are friendly.
function Core.allied_actor(windower_api, actor_id, party)
    actor_id=tonumber(actor_id)
    if not actor_id or actor_id==0 then return false end
    party=party or Core.party_snapshot(windower_api)
    if select(1,Core.actor_scope(windower_api,actor_id,party))~='outside' then return true end
    local mob=Core.mob(windower_api,actor_id)
    -- Luopans do not expose a reliable owner_id/pet_index relationship to every
    -- observing client. Keep the owner/index checks below as the preferred
    -- language-neutral path, but use this conservative final identity fallback
    -- so a friendly GEO construct can never enter a hostile ledger.
    if mob and Core.lower(mob.name or '')=='luopan' then return true end
    local owner_id=mob and tonumber(mob.owner_id or mob.owner or 0) or 0
    if owner_id~=0 and select(1,Core.actor_scope(windower_api,owner_id,party))~='outside' then return true end
    local fellow_owner=Core.fellow_owner(windower_api,actor_id,party)
    if fellow_owner and select(1,Core.actor_scope(windower_api,fellow_owner,party))~='outside' then return true end
    local mob_index=mob and tonumber(mob.index) or nil
    for _,entry in pairs((party and party.by_id) or {}) do
        local emob=entry.mob or Core.mob(windower_api,entry.id)
        local pet_index=tonumber((entry.member and entry.member.pet_index) or (emob and emob.pet_index) or 0) or 0
        if pet_index~=0 and windower_api and windower_api.ffxi and windower_api.ffxi.get_mob_by_index then
            local pet=windower_api.ffxi.get_mob_by_index(pet_index)
            if pet and tonumber(pet.id)==actor_id then return true end
            if mob_index and pet_index==mob_index then return true end
        end
    end
    if windower_api and windower_api.ffxi and windower_api.ffxi.get_mob_by_target then
        local ok,pet=pcall(windower_api.ffxi.get_mob_by_target,'pet')
        if ok and pet and tonumber(pet.id)==actor_id then return true end
    end
    return false
end

-- -------------------------------------------------------------------------
-- Shared allied-status / character-stat vocabulary
-- -------------------------------------------------------------------------
-- VanaAware consumes these helpers, but they deliberately remain data-only so
-- VanaCore still registers no events and owns no HUD.
local NEGATIVE_STATUS_WORDS={
    'sleep','poison','paraly','blind','silence','petrif','disease','curse','bane',
    'stun','bind','weight','gravity','slow','charm','doom','amnesia','terror','plague',
    'addle','bio','dia','burn','frost','choke','rasp','shock','drown','requiem','helix',
    'encumbrance','inhibit','addle','elegy','nocturne','threnody','virus','addle',
}
local SELF_STATUS_NAMES={
    hasso=true,seigan=true,berserk=true,aggressor=true,warcry=true,defender=true,
    retaliation=true,meditate=true,['last resort']=true,souleater=true,
    ['saber dance']=true,['fan dance']=true,['velocity shot']=true,velocity=true,
    composure=true,convert=true,conspirator=true,innin=true,yonin=true,
    ['third eye']=true,sekkanoki=true,hamanoha=true,['desperate blows']=true,
    footwork=true,impetus=true,focus=true,dodge=true,counterstance=true,
    sentinel=true,rampart=true,reprisal=true,cover=true,['divine emblem']=true,
    ['scarlet delirium']=true,nether_void=true,arcane_circle=true,
}

function Core.status_name(res,status_id)
    local r=res and res.buffs and res.buffs[tonumber(status_id) or -1]
    return r and (r.en or r.english or r.name) or nil
end

function Core.status_is_negative(res,status_id,source_relation)
    if source_relation=='enemy' then return true end
    local name=Core.lower(Core.status_name(res,status_id) or '')
    for _,word in ipairs(NEGATIVE_STATUS_WORDS) do if name:find(word,1,true) then return true end end
    return false
end

function Core.status_category(res,status_id,source_kind,source_relation)
    local name=Core.lower(Core.status_name(res,status_id) or '')
    if source_kind=='job_ability' and source_relation=='self' then return 'self' end
    if SELF_STATUS_NAMES[name] then return 'self' end
    if Core.status_is_negative(res,status_id,source_relation) then return 'debuff' end
    return 'buff'
end

local ROMAN_VALUE={i=1,ii=2,iii=3,iv=4,v=5,vi=6,vii=7,viii=8,ix=9,x=10}
local function roman_suffix_number(name)
    local base,roman=tostring(name or ''):match('^(.-)%s+([IVX]+)$')
    if not base then return tostring(name or '') end
    local n=ROMAN_VALUE[Core.lower(roman)]
    return n and (base..' '..tostring(n)) or tostring(name or '')
end

local function compact_status_source(name,canonical)
    name=Core.trim(name or '')
    canonical=Core.trim(canonical or '')
    local l=Core.lower(name)
    if l=='' then name=canonical; l=Core.lower(name) end
    if l:match('^protectra') or l:match('^protect ') or l=='protect' then return 'Protect' end
    if l:match('^shellra') or l:match('^sheltra') or l:match('^shell ') or l=='shell' then return 'Shell' end
    if l=='victory march' then return 'V. March' end
    if l=='honor march' then return 'H. March' end
    if l=='advancing march' then return 'A. March' end
    if l:find('valor minuet',1,true)==1 then return roman_suffix_number(name:gsub('^Valor%s+','')) end
    if l:find("knight's minne",1,true)==1 then return roman_suffix_number(name:gsub("^Knight's%s+",'')) end
    if l=='dragonfoe mambo' then return 'D. Mambo' end
    if l=='sheepfoe mambo' then return 'S. Mambo' end
    if l:find(' roll',1,true) and l:sub(-5)==' roll' then return name:sub(1,-6) end
    if l=='dread spikes' then return 'D. Spikes' end
    if l=='sublimation: activated' or l=='sublimation activated' then return 'Sublimation: Active' end
    if l=='sublimation: complete' or l=='sublimation complete' then return 'Sublimation: Full' end
    if l=='paralysis' then return 'Paralyze' end
    return name
end

local SONG_WORDS={'march','minuet','minne','mambo','madrigal','prelude','ballad','scherzo','paeon','carol','etude','mazurka','threnody','requiem','nocturne','operetta','aubade','pastoral','fantasia','capriccio','gavotte','fugue','aria'}
local WHITE_WORDS={'protect','protectra','shell','shellra','sheltra','auspice','reprisal','barfire','barblizzard','baraero','barstone','barthunder','barwater','barsleep','barpoison','barparalyze','barblind','barsilence','barpetrify','barvirus','baramnesia'}
local ENH_WORDS={'haste','flurry','enfire','enblizzard','enaero','enstone','enthunder','enwater','refresh','regen','phalanx','aquaveil','stoneskin','blink','temper','gain-','boost-','embrava'}
local DARK_WORDS={'dread spikes'}
local function contains_any_word(text,words)
    text=Core.lower(text or '')
    for _,w in ipairs(words) do if text:find(w,1,true) then return true end end
    return false
end

local HIDDEN_AWARENESS_STATUS_NAMES={
    ["emporox's gift"]=true, food=true, ionis=true, sanction=true,
    signet=true, sigil=true, medicine=true,
}
local function awareness_status_hidden(canonical,basis)
    local c=Core.lower(Core.trim(canonical or ''))
    local b=Core.lower(Core.trim(basis or ''))
    return HIDDEN_AWARENESS_STATUS_NAMES[c] or HIDDEN_AWARENESS_STATUS_NAMES[b] or false
end

-- Canonical display vocabulary used by VanaAware and any future status HUD.
-- The source action is retained only when it carries useful variant identity
-- (songs, rolls, tiers); otherwise the active status name is authoritative.
function Core.status_display_descriptor(res,status_id,source_name,source_kind,source_relation)
    local canonical=Core.status_name(res,status_id) or ('Status '..tostring(status_id))
    local source=Core.trim(source_name or '')
    local basis=source~='' and source or canonical
    local negative=Core.status_is_negative(res,status_id,source_relation)
    local category
    if negative then category='debuffs'
    elseif contains_any_word(basis,SONG_WORDS) then category='songs'
    elseif Core.lower(basis):sub(-5)==' roll' then category='rolls'
    elseif contains_any_word(basis,DARK_WORDS) then category='dark'
    elseif contains_any_word(basis,WHITE_WORDS) then category='white'
    elseif contains_any_word(basis,ENH_WORDS) then category='enhancing'
    elseif Core.status_category(res,status_id,source_kind,source_relation)=='self' then category='self'
    else category='enhancing' end
    local label=compact_status_source(basis,canonical)
    return {canonical=canonical,label=label,category=category,source=source,status_id=tonumber(status_id),hidden=awareness_status_hidden(canonical,basis)}
end

-- FFXI's visible HP warnings pivot near 75/50/25 percent. VanaAware uses a
-- continuous interpolation between green, yellow, orange and red so the
-- current-HP numerator communicates urgency without adding another column.
function Core.hp_color(hpp)
    hpp=Core.clamp(tonumber(hpp) or 100,0,100)
    local anchors={
        {100,80,255,120},
        {75,255,230,80},
        {50,255,150,45},
        {25,255,60,60},
        {0,255,35,35},
    }
    for i=1,#anchors-1 do
        local hi,lo=anchors[i],anchors[i+1]
        if hpp<=hi[1] and hpp>=lo[1] then
            local t=(hi[1]-hpp)/(hi[1]-lo[1])
            local function lerp(a,b) return math.floor(a+(b-a)*t+0.5) end
            return lerp(hi[2],lo[2]),lerp(hi[3],lo[3]),lerp(hi[4],lo[4])
        end
    end
    return 255,35,35
end

Core.CharacterStats={}
function Core.CharacterStats.from_packet(parsed,live_player)
    parsed=type(parsed)=='table' and parsed or {}
    local live=live_player or {}
    local vitals=live.vitals or {}
    local out={
        max_hp=tonumber(parsed['Maximum HP']) or tonumber(vitals.max_hp),
        max_mp=tonumber(parsed['Maximum MP']) or tonumber(vitals.max_mp),
        hp=tonumber(vitals.hp),mp=tonumber(vitals.mp),tp=tonumber(vitals.tp),
        main_job=parsed['Main Job'] or live.main_job or live.main_job_short,
        main_job_level=tonumber(parsed['Main Job Level']) or tonumber(live.main_job_level),
        sub_job=parsed['Sub Job'] or live.sub_job or live.sub_job_short,
        sub_job_level=tonumber(parsed['Sub Job Level']) or tonumber(live.sub_job_level),
        master_level=tonumber(parsed['Master Level']) or tonumber(live.master_level),
        attack=tonumber(parsed['Attack']),defense=tonumber(parsed['Defense']),
        maximum_ilevel=tonumber(parsed['Maximum iLevel']),main_hand_ilevel=tonumber(parsed['Main Hand iLevel']),
        resistances={fire=tonumber(parsed['Fire Resistance']),ice=tonumber(parsed['Ice Resistance']),wind=tonumber(parsed['Wind Resistance']),earth=tonumber(parsed['Earth Resistance']),lightning=tonumber(parsed['Lightning Resistance']),water=tonumber(parsed['Water Resistance']),light=tonumber(parsed['Light Resistance']),dark=tonumber(parsed['Dark Resistance'])},
        attributes={},
    }
    for _,stat in ipairs({'STR','DEX','VIT','AGI','INT','MND','CHR'}) do
        local base=tonumber(parsed['Base '..stat])
        local added=tonumber(parsed['Added '..stat])
        out.attributes[stat]={base=base,added=added,total=(base and added) and (base+added) or nil}
    end
    return out
end

function Core.actor_scope(windower_api, actor_id, snapshot)
    snapshot = snapshot or Core.party_snapshot(windower_api)
    local entry = snapshot.by_id[actor_id]
    if entry then return entry.scope, entry end
    return 'outside', nil
end

-- Return the party/alliance owner of an Adventuring Fellow when Windower
-- exposes fellow_index on a party member. Fellows are allied actors in their
-- own right; the owner relationship is used for scope, not damage attribution.
function Core.fellow_owner(windower_api, actor_id, snapshot)
    snapshot = snapshot or Core.party_snapshot(windower_api)
    local mob = Core.mob(windower_api, actor_id)
    if not mob or not mob.index then return nil, mob end
    local index = tonumber(mob.index)
    for owner_id, entry in pairs(snapshot.by_id or {}) do
        local owner_mob = entry and entry.mob
        if owner_mob and tonumber(owner_mob.fellow_index or 0) == index and index ~= 0 then
            return owner_id, mob
        end
    end
    return nil, mob
end

function Core.mob(windower_api, id)
    if not windower_api or not windower_api.ffxi or not windower_api.ffxi.get_mob_by_id then return nil end
    return windower_api.ffxi.get_mob_by_id(id)
end

function Core.mob_name(windower_api, id)
    local mob = Core.mob(windower_api, id)
    return mob and mob.name or tostring(id or '?')
end

function Core.distance_yalms(mob)
    if type(mob) ~= 'table' then return nil end
    local distance = tonumber(mob.distance)
    if not distance or distance < 0 then return nil end
    -- Windower's mob table exposes squared horizontal distance. GearSwap's
    -- target helper square-roots this value before presenting it as yalms.
    return math.sqrt(distance)
end

local function atan2(y, x)
    if math.atan2 then return math.atan2(y, x) end
    if x > 0 then return math.atan(y / x) end
    if x < 0 and y >= 0 then return math.atan(y / x) + math.pi end
    if x < 0 and y < 0 then return math.atan(y / x) - math.pi end
    if x == 0 and y > 0 then return math.pi / 2 end
    if x == 0 and y < 0 then return -math.pi / 2 end
    return 0
end

-- Direction is world-cardinal from the player's horizontal X/Y position to
-- the target. Camera heading is deliberately ignored.
function Core.direction(player_mob, target_mob)
    if type(player_mob) ~= 'table' or type(target_mob) ~= 'table' then return '-' end
    local px, py = tonumber(player_mob.x), tonumber(player_mob.y)
    local tx, ty = tonumber(target_mob.x), tonumber(target_mob.y)
    if not px or not py or not tx or not ty then return '-' end
    local dx, dy = tx - px, ty - py
    if math.abs(dx) < 0.01 and math.abs(dy) < 0.01 then return 'HERE' end
    -- X is east/west and Y is north/south on the game map. atan2(dx, dy)
    -- makes 0° north and increases clockwise through east.
    local angle = math.deg(atan2(dx, dy))
    if angle < 0 then angle = angle + 360 end
    local names = {'N','NE','E','SE','S','SW','W','NW'}
    local index = math.floor((angle + 22.5) / 45) % 8 + 1
    return names[index]
end

function Core.claim_state(windower_api, mob, party_snapshot, known_relevant)
    if type(mob) ~= 'table' then return 'UNKNOWN' end
    if mob.hpp ~= nil and tonumber(mob.hpp) <= 0 then return 'DEAD' end
    local claim_id = tonumber(mob.claim_id or mob.claimed_by or 0) or 0
    if claim_id == 0 then return known_relevant and 'UNCLAIMED' or 'UNKNOWN' end
    party_snapshot = party_snapshot or Core.party_snapshot(windower_api)
    if party_snapshot.by_id[claim_id] then return 'OURS' end
    return 'OTHER'
end

function Core.new_id(prefix)
    return ('%s-%d-%06d'):format(prefix or 'id', os.time(), math.random(0, 999999))
end

function Core.safe_call(label, fn, on_error, ...)
    local args = {...}
    local function run() return fn(unpack(args)) end
    local ok, a, b, c, d = xpcall(run, function(err) return debug.traceback(tostring(err), 2) end)
    if not ok then
        if on_error then pcall(on_error, label, a) end
        return nil, a
    end
    return a, b, c, d
end

function Core.load(windower_api)
    return Core
end


-- -------------------------------------------------------------------------
-- Shared action taxonomy
-- -------------------------------------------------------------------------
local CORE_SOURCE = debug.getinfo(1,'S') and debug.getinfo(1,'S').source or ''
local CORE_DIR = CORE_SOURCE:gsub('^@',''):match('^(.*[/\\])') or ''
local ACTION_OVERRIDES = {}
local function merge_action_override_file(path)
    local loader=loadfile(path); if not loader then return end
    local ok,data=pcall(loader); if not ok or type(data)~='table' then return end
    data=data.actions or data
    for name,row in pairs(data) do
        if type(row)=='table' then
            local key=Core.lower(name); ACTION_OVERRIDES[key]=ACTION_OVERRIDES[key] or {}
            for k,v in pairs(row) do ACTION_OVERRIDES[key][k]=v end
        end
    end
end
merge_action_override_file(CORE_DIR..'data/action_overrides.lua')
merge_action_override_file(CORE_DIR..'data/action_overrides_external.lua')
merge_action_override_file(CORE_DIR..'data/action_overrides_user.lua')

-- Windower resource IDs/categories are the identity layer.  These semantic
-- helpers intentionally use the English resource field only as a stable
-- lookup key supplied by Windower resources; they do not parse the client's
-- localized chat log.  The same IDs therefore work on EN and JA clients.
local HEALING_NAMES = {
    ['benediction']=true,['chakra']=true,['vivacious pulse']=true,['reward']=true,
    ['curing waltz']=true,['curing waltz ii']=true,['curing waltz iii']=true,['curing waltz iv']=true,['curing waltz v']=true,
    ['divine waltz']=true,['divine waltz ii']=true,
    ['healing ruby']=true,['healing ruby ii']=true,['whispering wind']=true,['spring water']=true,
    ['healing breath']=true,['healing breath ii']=true,['healing breath iii']=true,['healing breath iv']=true,
    ['wild carrot']=true,['pollen']=true,['healing breeze']=true,['magic fruit']=true,['plenilune embrace']=true,
    ['white wind']=true,['restoral']=true,['exuviation']=true,['winds of promyvion']=true,
}

local CLEANSE_NAMES = {
    ['healing waltz']=true,['erase']=true,['esuna']=true,['sacrifice']=true,
    ['poisona']=true,['paralyna']=true,['blindna']=true,['silena']=true,['stona']=true,['viruna']=true,['cursna']=true,
    ['exuviation']=true,['winds of promyvion']=true,
}

local DISPEL_NAMES = {
    ['dispel']=true,['dispelga']=true,['magic finale']=true,['blank gaze']=true,['geist wall']=true,
    ['osmosis']=true,['voracious trunk']=true,['lunar roar']=true,
}

local DRAIN_NAMES = {
    ['drain']=true,['drain ii']=true,['drain iii']=true,['drain samba']=true,['drain samba ii']=true,['drain samba iii']=true,
    ['blood saber']=true,['digest']=true,['drainkiss']=true,
}

local ASPIR_NAMES = {
    ['aspir']=true,['aspir ii']=true,['aspir iii']=true,['aspir samba']=true,['aspir samba ii']=true,
}

-- Player job abilities that deal magical/elemental damage rather than ordinary
-- physical melee-type damage.  Unknown damaging player JAs default to Melee,
-- matching VanaParse's inclusive parent model.
local MAGICAL_JA_NAMES = {
    ['quick draw']=true,['fire shot']=true,['ice shot']=true,['wind shot']=true,['earth shot']=true,
    ['thunder shot']=true,['water shot']=true,['light shot']=true,['dark shot']=true,
    ['lunge']=true,['swipe']=true,
}

-- Blood Pact: Rage and other pet abilities are not reliably classifiable from
-- the log verb alone.  Explicit overrides cover well-known magical/hybrid
-- avatar attacks; unlisted damaging pet abilities remain Physical unless the
-- action packet itself is a spell (category 4).
local PET_MAGIC_NAMES = {
    ['aero ii']=true,['aero iv']=true,['stone ii']=true,['stone iv']=true,['water ii']=true,['water iv']=true,
    ['fire ii']=true,['fire iv']=true,['blizzard ii']=true,['blizzard iv']=true,['thunder ii']=true,['thunder iv']=true,
    ['meteor strike']=true,['geocrush']=true,['grand fall']=true,['wind blade']=true,['heavenly strike']=true,
    ['thunderstorm']=true,['nether blast']=true,['night terror']=true,['level ? holy']=true,['holy mist']=true,
    ['lunar bay']=true,['impact']=true,['searing light']=true,['inferno']=true,['earthen fury']=true,
    ['tidal wave']=true,['aerial blast']=true,['diamond dust']=true,['judgment bolt']=true,['howling moon']=true,
    ['ruinous omen']=true,['flaming crush']=true,['conflag strike']=true,['thunderspark']=true,
}

local function resource_label(resource)
    if not resource then return '' end
    return Core.lower(resource.en or resource.english or resource.name or '')
end

function Core.action_resource(res, category, param)
    category, param = tonumber(category) or 0, tonumber(param)
    if not res or not param then return nil, nil end
    if category == 3 and res.weapon_skills then return res.weapon_skills[param], 'weapon_skill' end
    if category == 4 and res.spells then return res.spells[param], 'spell' end
    if category == 6 and res.job_abilities then return res.job_abilities[param], 'job_ability' end
    return nil, nil
end

function Core.action_semantics(res, category, param, is_pet)
    category = tonumber(category) or 0
    local resource, resource_kind = Core.action_resource(res, category, param)
    local name = resource_label(resource)
    local rtype = Core.lower(resource and resource.type or '')
    local out = {
        category=category, param=tonumber(param), resource=resource, resource_kind=resource_kind,
        name=name, healing=false, cleanse=false, dispel=false, drain=false, aspir=false,
        damage_parent=nil, pet_damage_kind=nil, enfeeble=false, crowd=false, dot=false,
        status_id=tonumber(resource and (resource.status or resource.status_id)) or nil,
    }

    if category == 1 then out.damage_parent='melee'; out.pet_damage_kind='melee'
    elseif category == 2 then out.damage_parent='ranged'; out.pet_damage_kind='ranged'
    elseif category == 3 then out.damage_parent='ws'; out.pet_damage_kind='physical'
    elseif category == 4 then out.damage_parent='magic'; out.pet_damage_kind='magic'
    elseif category == 6 then
        out.damage_parent = MAGICAL_JA_NAMES[name] and 'magic' or 'melee'
        out.pet_damage_kind = PET_MAGIC_NAMES[name] and 'magic' or 'physical'
        if rtype:find('corsair',1,true) and rtype:find('shot',1,true) then out.damage_parent='magic' end
        if rtype:find('effusion',1,true) then out.damage_parent='magic' end
        if rtype:find('bloodpactrage',1,true) then out.pet_damage_kind=PET_MAGIC_NAMES[name] and 'magic' or 'physical' end
    end

    if name:match('^cure') or name:match('^curaga') or name:match('^cura ') or name=='cura' or name=='full cure' or HEALING_NAMES[name] then out.healing=true end
    if CLEANSE_NAMES[name] then out.cleanse=true end
    if DISPEL_NAMES[name] then out.dispel=true end
    if DRAIN_NAMES[name] or name:match('^drain ') then out.drain=true; out.damage_parent=out.damage_parent or 'magic' end
    if ASPIR_NAMES[name] or name:match('^aspir ') then out.aspir=true end

    local joined = name .. ' ' .. resource_label(resource and resource.status and nil)
    if name:find('sleep',1,true) or name:find('lullaby',1,true) or name=='break' or name=='breakga' or
       name:find('bind',1,true) or name:find('gravity',1,true) or name:find('terror',1,true) or name:find('stun',1,true) then out.crowd=true end
    if name:find('dia',1,true) or name:find('bio',1,true) or name:find('poison',1,true) or name:find('requiem',1,true) or
       name:find('helix',1,true) or name:find('burn',1,true) or name:find('frost',1,true) or name:find('choke',1,true) or
       name:find('rasp',1,true) or name:find('shock',1,true) or name:find('drown',1,true) then out.dot=true end
    out.enfeeble = out.status_id ~= nil or out.crowd or out.dot
    local override=ACTION_OVERRIDES[name]
    if override then for k,v in pairs(override) do out[k]=v end end
    -- Category 6 defaults to a physical/magical damage parent only for actual
    -- damaging abilities. Pure healing/cleanse/dispel abilities must not carry
    -- a misleading Melee/Pet-Physical parent merely because they are JAs.
    if category==6 and (out.healing or out.cleanse or out.dispel) then out.damage_parent=nil end
    if is_pet and (out.healing or out.cleanse or out.dispel) then out.pet_damage_kind=nil end
    if out.damage_parent==false then out.damage_parent=nil end
    if out.pet_damage_kind==false then out.pet_damage_kind=nil end
    return out
end

function Core.action_result_flags(res, action)
    local text = Core.action_message_text(res, action and action.message)
    local amount = math.max(0, tonumber(action and action.param) or 0)
    return {
        text=text, amount=amount,
        miss=text:find('miss',1,true)~=nil or text:find('evade',1,true)~=nil,
        resist=text:find('resist',1,true)~=nil,
        no_effect=text:find('no effect',1,true)~=nil,
        critical=text:find('critical',1,true)~=nil,
        heal=text:find('recover',1,true)~=nil or text:find('restore',1,true)~=nil or text:find('heals',1,true)~=nil or text:find('regains',1,true)~=nil,
        damage=text:find('damage',1,true)~=nil or text:find('takes',1,true)~=nil or text:find('receives',1,true)~=nil or text:find('drain',1,true)~=nil,
        magic_burst=text:find('magic burst',1,true)~=nil,
        -- Keep status-application detection conservative. These phrases
        -- describe an effect actually being applied; generic "gains" or
        -- "receives" are intentionally avoided because they also describe TP,
        -- damage and other non-status results.
        status_apply=text:find('afflicted',1,true)~=nil
            or text:find('affected by',1,true)~=nil
            or text:find('gains the effect',1,true)~=nil
            or text:find('receives the effect',1,true)~=nil
            or text:find('is enhanced',1,true)~=nil,
        wears_off=text:find('wears off',1,true)~=nil or text:find('no longer',1,true)~=nil,
    }
end

-- -------------------------------------------------------------------------
-- Enemy registry
-- -------------------------------------------------------------------------
-- The registry is deliberately independent of addon releases.  Bundled data,
-- optional user/external data and locally learned observations can coexist.
-- Live game identity/HPP always remains authoritative over static metadata.
local EnemyRegistry = {}
EnemyRegistry.__index = EnemyRegistry

local function core_directory() return CORE_DIR end

local function load_table_file(path)
    local loader = loadfile(path)
    if not loader then return nil end
    local ok, data = pcall(loader)
    if ok and type(data)=='table' then return data end
    return nil
end

local function registry_key(zone_id, name)
    return tostring(tonumber(zone_id) or 0)..'|'..Core.lower(name or '')
end

function EnemyRegistry.new(options)
    options=options or {}
    local base=options.base_path or core_directory()
    local self=setmetatable({base_path=base,bundled={},external={},user={},learned={},dirty=false,version='none'},EnemyRegistry)
    local bundled=load_table_file(base..'data/enemy_registry.lua') or {}
    local external=load_table_file(base..'data/enemy_registry_external.lua') or {}
    local user=load_table_file(base..'data/enemy_registry_user.lua') or {}
    local learned_path=options.learned_path
    local learned=learned_path and load_table_file(learned_path) or {}
    self.bundled=bundled.records or bundled; self.external=external.records or external; self.user=user.records or user
    self.learned=learned.records or learned; self.version=tostring(external.version or bundled.version or 'none'); self.learned_path=learned_path
    return self
end

function EnemyRegistry:lookup(zone_id,name)
    local key=registry_key(zone_id,name)
    local merged={}
    local found=false
    -- Precedence: bundled fallback < local learning < independently updateable
    -- external registry < explicit user override.  A learned estimate therefore
    -- cannot silently replace a later verified registry value.
    for _,layer in ipairs({{'bundled',self.bundled},{'learned',self.learned},{'external',self.external},{'user',self.user}}) do
        local row=layer[2] and layer[2][key]
        if type(row)=='table' then
            for k,v in pairs(row) do merged[k]=v end
            if row.max_hp~=nil then merged.max_hp_source=layer[1] end
            found=true
        end
    end
    if not found then return nil end
    merged.key=key; return merged
end

function EnemyRegistry:observe(zone_id,name,estimate,confidence,metadata)
    estimate=tonumber(estimate)
    if not estimate or estimate<=0 or Core.trim(name)=='' then return nil end
    local key=registry_key(zone_id,name)
    local row=self.learned[key] or {zone_id=tonumber(zone_id) or 0,name=tostring(name),samples={},sample_count=0}
    self.learned[key]=row; row.samples=row.samples or {}
    row.samples[#row.samples+1]=math.floor(estimate+0.5)
    while #row.samples>20 do table.remove(row.samples,1) end
    table.sort(row.samples)
    row.sample_count=(tonumber(row.sample_count) or 0)+1
    local mid=math.floor((#row.samples+1)/2); row.max_hp=row.samples[mid]
    local low=row.samples[1] or row.max_hp; local high=row.samples[#row.samples] or row.max_hp
    row.observed_min=low; row.observed_max=high
    row.spread_pct=row.max_hp>0 and ((high-low)/row.max_hp)*100 or nil
    if confidence=='verified' then row.confidence='verified'
    elseif #row.samples>=5 and (row.spread_pct or 100)<=3 then row.confidence='high'
    elseif #row.samples>=3 and (row.spread_pct or 100)<=5 then row.confidence='medium'
    else row.confidence='low' end
    row.last_observed=os.time()
    if type(metadata)=='table' then for k,v in pairs(metadata) do if k~='samples' then row[k]=v end end end
    self.dirty=true; return row
end

local function lua_quote(value) return string.format('%q',tostring(value or '')) end
local function serialize_value(value,indent)
    indent=indent or ''
    local t=type(value)
    if t=='number' or t=='boolean' then return tostring(value) end
    if t=='string' then return lua_quote(value) end
    if t~='table' then return 'nil' end
    local parts={'{'}; local child=indent..'  '
    local keys={}; for k in pairs(value) do keys[#keys+1]=k end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do
        local key=type(k)=='string' and ('['..lua_quote(k)..']') or ('['..tostring(k)..']')
        parts[#parts+1]='\n'..child..key..'='..serialize_value(value[k],child)..','
    end
    parts[#parts+1]='\n'..indent..'}'; return table.concat(parts)
end

function EnemyRegistry:save()
    if not self.dirty or not self.learned_path then return true end
    local f=io.open(self.learned_path..'.tmp','wb'); if not f then return false end
    f:write('return ',serialize_value({schema=1,updated=os.time(),records=self.learned}), '\n'); f:write('\n'); f:close()
    os.remove(self.learned_path..'.bak'); os.rename(self.learned_path,self.learned_path..'.bak')
    local ok=os.rename(self.learned_path..'.tmp',self.learned_path)
    if ok then self.dirty=false end
    return ok and true or false
end

function EnemyRegistry:status()
    local function count(t) local n=0; for _ in pairs(t or {}) do n=n+1 end; return n end
    return {version=self.version,bundled=count(self.bundled),external=count(self.external),user=count(self.user),learned=count(self.learned),dirty=self.dirty}
end

Core.EnemyRegistry=EnemyRegistry

return Core
