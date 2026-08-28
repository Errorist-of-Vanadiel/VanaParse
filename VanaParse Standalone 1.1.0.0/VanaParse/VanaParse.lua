--[[
VanaParse 1.1.0.0
Copyright (c) 2026 Errorist of Vana'diel
MIT License

Combat analytics for the Vana suite. Raw action events are classified, applied
to bounded aggregate counters/windows, then discarded.
]]

_addon.name = 'VanaParse'
_addon.author = "Errorist of Vana'diel"
_addon.version = '1.1.0.0'
_addon.commands = {'vanaparse','vp'}

local texts = require('texts')
local config = require('config')
local res = require('resources')

local function load_core()
    -- Standalone distribution: VanaCore is private to VanaParse.
    local path = windower.addon_path .. 'core/VanaCore.lua'
    local loader = loadfile(path)
    if loader then
        local ok, core = pcall(loader)
        if ok and type(core) == 'table' then return core end
    end
    error('Embedded VanaCore was not found at '..path..'. Reinstall VanaParse Standalone.')
end
local Core=load_core()

local defaults={
    schema=12, visible=true, paused=false, view='dynamic', scope='alliance', sort='dps', period='session', enemy='all',
    live_seconds=15, rolling_seconds=600, active_timeout=15, encounter_timeout=15, history_limit=10,
    hud={pos={x=470,y=150},padding=3,bg={alpha=135,red=0,green=0,blue=0},text={font='Consolas',size=8,red=255,green=255,blue=255,alpha=255},flags={draggable=true}},
    custom_players={}, max_hidden={}, max_only={}, alliance_limit=18, row_limit=8, debug=false, log_enabled=true, report_delay=0.65, include_trusts=true, include_allied_npcs=true,
    columns={ranged='auto',pet='auto',healing='auto',crits=false,pet_types=false,ws_count=false},
    display={physical=true,ws=true,sc=true,magic=true,mb=true,ranged=true,pet=true,healing=true,recovery=true,defense=true},
    pins={},self_pin=true,target_hp='auto',accuracy_min_attempts=10,highlights=true,highlight_ws_min=5,
    filters={melee=true,ranged=true,ws=true,sc=true,magic=true,pet=true,pet_melee=true,pet_ranged=true,pet_physical=true,pet_magic=true,pet_sc=true,other=true},
    enemy_filter_text='', enemy_filter_ids='', compact_magic_threshold=0.03, compact_pet_threshold=0.03,
}
local settings=Core.merge(config.load(defaults),defaults)
if tonumber(settings.schema or 1)<12 then
    local previous_schema=tonumber(settings.schema or 1)
    settings.schema=12
    settings.columns=Core.merge(settings.columns or {},defaults.columns); settings.display=Core.merge(settings.display or {},defaults.display); settings.pins=settings.pins or {}; settings.self_pin=settings.self_pin~=false
    settings.filters=Core.merge(settings.filters or {},defaults.filters); settings.target_hp=settings.target_hp or 'auto'; settings.accuracy_min_attempts=tonumber(settings.accuracy_min_attempts) or 10
    if settings.highlights==nil then settings.highlights=true end; settings.highlight_ws_min=tonumber(settings.highlight_ws_min) or 5
    if settings.view=='overview' then settings.view='dynamic' end
    -- 9 was the shipped VanaParse 0.1.x default.  Migrate only that stock
    -- value to the new suite default of 8; explicit custom sizes are preserved.
    if settings.hud and settings.hud.text and tonumber(settings.hud.text.size)==9 then settings.hud.text.size=8 end
end
settings.display=Core.merge(settings.display or {},defaults.display)
if settings.highlights==nil then settings.highlights=true end
settings.highlight_ws_min=tonumber(settings.highlight_ws_min) or 5
settings.report_delay=Core.clamp(tonumber(settings.report_delay) or 0.65,0.10,3.00)
if settings.include_trusts==nil then settings.include_trusts=true end
if settings.include_allied_npcs==nil then settings.include_allied_npcs=true end
settings.row_limit=math.max(0,math.floor(tonumber(settings.row_limit) or 8))
settings.enemy_filter_text=tostring(settings.enemy_filter_text or '')
settings.enemy_filter_ids=tostring(settings.enemy_filter_ids or '')
settings.compact_magic_threshold=Core.clamp(tonumber(settings.compact_magic_threshold) or 0.03,0,1)
settings.compact_pet_threshold=Core.clamp(tonumber(settings.compact_pet_threshold) or 0.03,0,1)
local hud=texts.new(settings.hud); if settings.visible then hud:show() else hud:hide() end

local function chat(color,text) windower.add_to_chat(color or 207,'[VanaParse] '..tostring(text)) end
local errors,last_error,event_count=0,nil,0
local last_hud_update=0
local current=nil
local last_fight=nil
local history={}
local session_started=Core.now()
local session_actors={}
local session_activity=Core.Activity.new(settings.active_timeout)
local session_active_committed=0
local session_last_event=nil
local party_cache=Core.party_snapshot(windower)
local party_cache_at=0
local forced_miss_windows={} -- target mob id -> expires_at (e.g. Perfect Dodge)
local function format_parse_dynamic(headers,rows,aligns,options)
    -- Recompute widths from the currently visible rows. Numeric columns are
    -- right-justified against one shared width calculation so color escapes or
    -- a previous layout can never shift a single player by one character.
    return Core.format_dynamic_table(headers,rows,aligns,options,nil)
end
local function registry_character()
    local player=windower.ffxi.get_player and windower.ffxi.get_player() or nil
    return (player and player.name and tostring(player.name):gsub('[^%w_%-]','_')) or 'Unknown'
end
local registry_learned_path=windower.addon_path..'data/enemy_registry_learned_'..registry_character()..'.lua'
local function new_enemy_registry() return Core.EnemyRegistry.new({learned_path=registry_learned_path}) end
local enemy_registry=new_enemy_registry()
local target_learning={}
local target_lives={} -- entity id -> {generation,last_hpp,dead,identity}
local last_target_id=nil

-- A mob ID/index can be reused after death/respawn. Keep an observed lifecycle
-- generation so target damage is reset when the same runtime slot represents a
-- new life even when the client never rendered the exact 0% frame.
local function target_identity(mob,id)
    if not mob then return tostring(id or '?') end
    return table.concat({
        tostring(id or mob.id or '?'),
        tostring(mob.index or mob.mob_index or '?'),
        tostring(mob.name or '?'),
        tostring(mob.spawn_type or mob.type or '?'),
    },':')
end

local function refresh_target_life(mob)
    if not mob or not mob.id then return nil,false end
    local id=tonumber(mob.id) or mob.id
    local hpp=tonumber(mob.hpp)
    local status=tonumber(mob.status)
    local identity=target_identity(mob,id)
    local life=target_lives[id]
    local new_life=false
    if not life then
        new_life=true
    elseif life.identity~=identity then
        new_life=true
    elseif life.dead and ((hpp and hpp>0) or status~=2) then
        new_life=true
    elseif hpp and life.last_hpp and life.last_hpp<=25 and hpp>=75 and (hpp-life.last_hpp)>=50 then
        new_life=true
    end
    if new_life then
        life={generation=(life and (tonumber(life.generation) or 0) or 0)+1,last_hpp=hpp,dead=false,identity=identity}
        target_lives[id]=life
        if current and current.target_damage then current.target_damage[id]=0 end
        target_learning[id]=nil
    end
    if life then
        if hpp~=nil then life.last_hpp=hpp end
        if (hpp~=nil and hpp<=0) or status==2 then life.dead=true end
        life.identity=identity
    end
    return life,new_life
end
local function apply_target_damage(target_id,delta)
    if not current or target_id==nil then return end
    local mob=Core.mob(windower,target_id)
    if mob then refresh_target_life(mob) end
    current.target_damage=current.target_damage or {}
    current.target_damage[target_id]=(tonumber(current.target_damage[target_id]) or 0)+(tonumber(delta) or 0)
end

local report_queue={}
local report_next_at=0
local splits={}
local active_split=nil
local split_counter=0
local split_view=nil -- nil=full session, 'current'=active split, or split id

local log_dir=windower.addon_path..'data/logs/'
local log_file=log_dir..os.date('%Y-%m-%d')..'.tsv'
local log_schema_checked=false
local function ensure_log_dir()
    local data_dir=windower.addon_path..'data/'
    if not windower.dir_exists(data_dir) then pcall(windower.create_dir,data_dir) end
    if not windower.dir_exists(log_dir) then pcall(windower.create_dir,log_dir) end
end
local function clean_field(v)
    -- string.gsub returns both the cleaned string and replacement count. Keep
    -- only the string so TSV fields do not acquire a trailing numeric value.
    local cleaned=tostring(v==nil and '' or v):gsub('[\t\r\n]',' ')
    return cleaned
end
local function ensure_log_schema()
    if log_schema_checked then return end; log_schema_checked=true
    if not windower.file_exists(log_file) then return end
    local f=io.open(log_file,'r'); if not f then return end
    local header=f:read('*l') or ''; f:close()
    if not header:find('\tDispel\tAspir\tCureReceived\tReconcile',1,true) then
        -- Preserve historical files byte-for-byte. New schema rows continue in
        -- a sibling file instead of silently changing the column count mid-file.
        log_file=log_dir..os.date('%Y-%m-%d')..'_v5.tsv'
    end
end
local function append_log(fields)
    if not settings.log_enabled then return end
    ensure_log_dir(); ensure_log_schema()
    local fresh=not windower.file_exists(log_file)
    local f=io.open(log_file,'a')
    if not f then return end
    if fresh then f:write('Type\tTimestamp\tEncounter\tElapsed\tActive\tPlayer\tMasterDamage\tPetDamage\tCombinedDamage\tDPS\tMelee\tRanged\tMagic\tEnspell\tOther\tWSDamage\tWSAtt\tWSHit\tWSMiss\tWSAvg\tAccuracy\tRAccuracy\tLandPct\tSC\tMB\tDHeal\tTaken\tCured\tSelfCure\tCleanse\tDispel\tAspir\tCureReceived\tReconcile\n') end
    for i,v in ipairs(fields) do if i>1 then f:write('\t') end; f:write(clean_field(v)) end
    f:write('\n'); f:close()
end

local function on_error(label,err) errors=errors+1; last_error=tostring(label)..': '..tostring(err); chat(167,'Error in '..tostring(label)..'. Use //vp health.') end

local function fresh_minmax()
    return {low=nil,peak=nil,total=0,count=0}
end
local function add_minmax(mm,value)
    value=tonumber(value) or 0
    if value <= 0 then return end
    mm.total=mm.total+value; mm.count=mm.count+1
    if mm.low==nil or value<mm.low then mm.low=value end
    if mm.peak==nil or value>mm.peak then mm.peak=value end
end
local function avg(mm) if not mm or mm.count==0 then return nil end return mm.total/mm.count end
local function enabled_filter(name)
    return not (settings.filters and settings.filters[name]==false)
end

local function net(value,heal)
    return (tonumber(value) or 0)-(tonumber(heal) or 0)
end

local function player_net_damage(a)
    if not a then return 0 end
    local total=0
    if enabled_filter('melee') then total=total+net(a.melee,a.dheal_melee) end
    if enabled_filter('ranged') then total=total+net(a.ranged,a.dheal_ranged) end
    if enabled_filter('ws') then total=total+net(a.ws_damage,a.dheal_ws) end
    if enabled_filter('sc') then total=total+net(a.skillchain,a.dheal_skillchain) end
    if enabled_filter('magic') then total=total+(tonumber(a.magic) or 0)-(tonumber(a.dheal_magic) or 0)-(tonumber(a.dheal_enspell) or 0) end
    if enabled_filter('other') then total=total+net(a.other,a.dheal_other) end
    return total
end

local function pet_net_damage(a)
    local p=a and a.pet
    if not p or not enabled_filter('pet') then return 0 end
    local total=0
    if enabled_filter('pet_melee') then total=total+net(p.melee,p.dheal_melee) end
    if enabled_filter('pet_ranged') then total=total+net(p.ranged,p.dheal_ranged) end
    local physical=tonumber(p.physical) or 0; if physical==0 then physical=tonumber(p.ws) or 0 end
    if enabled_filter('pet_physical') then total=total+net(physical,p.dheal_physical) end
    if enabled_filter('pet_magic') then total=total+(tonumber(p.magic) or 0)-(tonumber(p.dheal_magic) or 0)-(tonumber(p.dheal_enspell) or 0) end
    if enabled_filter('pet_sc') then total=total+net(p.skillchain,p.dheal_skillchain) end
    if enabled_filter('other') then total=total+net((p.other or 0),p.dheal_other) end
    return total
end

local function filtered_damage(a) return player_net_damage(a)+pet_net_damage(a) end
local function total_dheal(a) return (tonumber(a and a.dheal) or 0)+(tonumber(a and a.pet and a.pet.dheal) or 0) end
local function combined_damage(a) return filtered_damage(a) end

local function new_actor(id,name)
    return {
        id=id,name=name or tostring(id),actor_type='unknown',session_scope='outside',session_order=999,aliases={},weapon_class=nil,
        damage=0, melee=0, ranged=0, magic=0, other=0, skillchain=0, skillchain_count=0, enspell=0,
        dheal=0,dheal_melee=0,dheal_ranged=0,dheal_ws=0,dheal_magic=0,dheal_enspell=0,dheal_mb=0,dheal_skillchain=0,dheal_other=0,accuracy_forced_ignored=0,ws_forced_ignored=0,
        damage_window=Core.Window.new(settings.rolling_seconds),
        melee_attempts=0, melee_hits=0, melee_misses=0, melee_crit=0, melee_mm=fresh_minmax(), crit_mm=fresh_minmax(),
        ranged_attempts=0, ranged_hits=0, ranged_misses=0, ranged_crit=0, ranged_mm=fresh_minmax(),
        ws_damage=0, ws_attempts=0, ws_hits=0, ws_misses=0, ws_mm=fresh_minmax(), ws={},
        magic_damage=0, magic_healing=0, magic_casts=0, magic_targets=0, magic_hits=0, magic_lands=0, magic_resists=0, magic_no_effect=0, magic_mm=fresh_minmax(),
        mb_casts=0, mb_count=0, mb_damage=0, mb_mm=fresh_minmax(), nonmb_casts=0, nonmb_count=0, nonmb_damage=0, nonmb_mm=fresh_minmax(), spells={},
        healing=0, healing_window=Core.Window.new(settings.rolling_seconds), cures=0, cure_mm=fresh_minmax(), mp_spent=0,
        received=0, self_healing=0, drain_healing=0, aspir_recovery=0, cleanses=0, cleanse_actions={}, dispels=0, dispel_actions={}, cure_mp_received=0, healed_targets={}, healed_by={},
        counter_damage=0, retaliation_damage=0, reprisal_damage=0, spikes_damage=0, dread_spikes_damage=0,
        taken=0, taken_physical=0, taken_magical=0, taken_other=0, taken_unknown=0, taken_hits=0, taken_mm=fresh_minmax(),
        evades=0, parries=0, blocks=0, deaths=0,
        pet={damage=0, melee=0, ranged=0, magic=0, ws=0, physical=0, other=0, skillchain=0, enspell=0, healing=0,
            dheal=0,dheal_melee=0,dheal_ranged=0,dheal_physical=0,dheal_magic=0,dheal_enspell=0,dheal_mb=0,dheal_skillchain=0,dheal_other=0,
            attempts=0, hits=0, misses=0, mm=fresh_minmax(),
            melee_attempts=0, melee_hits=0, melee_misses=0, melee_mm=fresh_minmax(),
            ranged_attempts=0, ranged_hits=0, ranged_misses=0, ranged_mm=fresh_minmax(),
            ws_attempts=0, ws_hits=0, ws_misses=0, ws_mm=fresh_minmax(),
            magic_casts=0, magic_targets=0, magic_hits=0, magic_lands=0, magic_resists=0, magic_no_effect=0, magic_mm=fresh_minmax(),
            mb_casts=0, mb_count=0, mb_damage=0, mb_mm=fresh_minmax(), nonmb_casts=0, nonmb_count=0, nonmb_damage=0, nonmb_mm=fresh_minmax(),
            taken=0, taken_hits=0, taken_mm=fresh_minmax(), cleanses=0, dispels=0, aspir_recovery=0, self_healing=0, name=nil},
        enemy={}, enemy_ids={},
    }
end

local function actor_for(store,id,name)
    if not id then return nil end
    if not store[id] then store[id]=new_actor(id,name or Core.mob_name(windower,id)) end
    if name and store[id].name==tostring(id) then store[id].name=name end
    store[id].aliases=store[id].aliases or {}; store[id].aliases[tostring(id)]=true
    return store[id]
end

local function merge_minmax(dst,src)
    if not dst or not src then return end
    dst.total=(dst.total or 0)+(src.total or 0)
    dst.count=(dst.count or 0)+(src.count or 0)
    if src.low and (not dst.low or src.low<dst.low) then dst.low=src.low end
    if src.peak and (not dst.peak or src.peak>dst.peak) then dst.peak=src.peak end
end

local function stronger_scope(a,b)
    local rank={outside=0,alliance=1,party=2,self=3}
    a=a or 'outside'; b=b or 'outside'
    return (rank[b] or 0)>(rank[a] or 0) and b or a
end

local function add_actor_stats(dst,src)
    if not dst or not src then return end
    local simple={'damage','melee','ranged','magic','other','skillchain','skillchain_count','enspell','dheal','dheal_melee','dheal_ranged','dheal_ws','dheal_magic','dheal_enspell','dheal_mb','dheal_skillchain','dheal_other','accuracy_forced_ignored','melee_attempts','melee_hits','melee_misses','melee_crit','ranged_attempts','ranged_hits','ranged_misses','ranged_crit','ws_damage','ws_attempts','ws_hits','ws_misses','magic_damage','magic_healing','magic_casts','magic_targets','magic_hits','magic_lands','magic_resists','magic_no_effect','mb_casts','mb_count','mb_damage','nonmb_casts','nonmb_count','nonmb_damage','healing','cures','mp_spent','received','self_healing','drain_healing','aspir_recovery','cleanses','dispels','cure_mp_received','counter_damage','retaliation_damage','reprisal_damage','spikes_damage','dread_spikes_damage','taken','taken_physical','taken_magical','taken_other','taken_unknown','taken_hits','evades','parries','blocks','deaths'}
    for _,k in ipairs(simple) do dst[k]=(dst[k] or 0)+(src[k] or 0) end
    for _,k in ipairs({'melee_mm','crit_mm','ranged_mm','ws_mm','magic_mm','mb_mm','nonmb_mm','cure_mm','taken_mm'}) do merge_minmax(dst[k],src[k]) end
    for name,sw in pairs(src.ws or {}) do
        local dw=dst.ws[name]
        if not dw then dw={damage=0,attempts=0,hits=0,misses=0,mm=fresh_minmax()}; dst.ws[name]=dw end
        dw.damage=dw.damage+(sw.damage or 0); dw.attempts=dw.attempts+(sw.attempts or 0); dw.hits=dw.hits+(sw.hits or 0); dw.misses=dw.misses+(sw.misses or 0); merge_minmax(dw.mm,sw.mm)
    end
    for name,ss in pairs(src.spells or {}) do
        local ds=dst.spells[name]
        if not ds then
            ds={casts=0,targets=0,lands=0,resists=0,no_effect=0,damage=0,damage_hits=0,damage_mm=fresh_minmax(),
                mb_casts=0,mb_hits=0,mb_damage=0,mb_mm=fresh_minmax(),nonmb_casts=0,nonmb_hits=0,nonmb_damage=0,nonmb_mm=fresh_minmax(),
                healing=0,heal_hits=0,heal_mm=fresh_minmax()}
            dst.spells[name]=ds
        end
        for _,k in ipairs({'casts','targets','lands','resists','no_effect','damage','damage_hits','mb_casts','mb_hits','mb_damage','nonmb_casts','nonmb_hits','nonmb_damage','healing','heal_hits'}) do
            ds[k]=(ds[k] or 0)+(ss[k] or 0)
        end
        for _,k in ipairs({'damage_mm','mb_mm','nonmb_mm','heal_mm'}) do merge_minmax(ds[k],ss[k]) end
        ds.element=ds.element or ss.element; ds.skill=ds.skill or ss.skill; ds.spell_type=ds.spell_type or ss.spell_type
    end
    for name,count in pairs(src.cleanse_actions or {}) do dst.cleanse_actions[name]=(dst.cleanse_actions[name] or 0)+(tonumber(count) or 0) end
    for name,count in pairs(src.dispel_actions or {}) do dst.dispel_actions[name]=(dst.dispel_actions[name] or 0)+(tonumber(count) or 0) end
    for name,count in pairs(src.healed_targets or {}) do dst.healed_targets[name]=(dst.healed_targets[name] or 0)+(tonumber(count) or 0) end
    for name,count in pairs(src.healed_by or {}) do dst.healed_by[name]=(dst.healed_by[name] or 0)+(tonumber(count) or 0) end
    dst.actor_type=(dst.actor_type~='unknown' and dst.actor_type) or src.actor_type or 'unknown'; dst.session_scope=stronger_scope(dst.session_scope,src.session_scope); dst.session_order=math.min(tonumber(dst.session_order) or 999,tonumber(src.session_order) or 999); dst.weapon_class=dst.weapon_class or src.weapon_class
    for alias in pairs(src.aliases or {}) do dst.aliases[alias]=true end
    for _,k in ipairs({'damage','melee','ranged','magic','ws','physical','other','skillchain','enspell','healing','dheal','dheal_melee','dheal_ranged','dheal_physical','dheal_magic','dheal_enspell','dheal_mb','dheal_skillchain','dheal_other','attempts','hits','misses','taken','taken_hits','cleanses','dispels','aspir_recovery','self_healing',
        'melee_attempts','melee_hits','melee_misses','ranged_attempts','ranged_hits','ranged_misses','ws_attempts','ws_hits','ws_misses',
        'magic_casts','magic_targets','magic_hits','magic_lands','magic_resists','magic_no_effect','mb_casts','mb_count','mb_damage','nonmb_casts','nonmb_count','nonmb_damage'}) do
        dst.pet[k]=(dst.pet[k] or 0)+(src.pet and src.pet[k] or 0)
    end
    if src.pet and src.pet.name then dst.pet.name=src.pet.name end
    if src.pet then
        for _,k in ipairs({'mm','melee_mm','ranged_mm','ws_mm','magic_mm','mb_mm','nonmb_mm','taken_mm'}) do merge_minmax(dst.pet[k],src.pet[k]) end
    end
    for enemy_name,sb in pairs(src.enemy or {}) do
        local db=dst.enemy[enemy_name]
        if not db then db={damage=0,melee=0,ranged=0,magic=0,ws=0,skillchain=0,skillchain_count=0,other=0,melee_attempts=0,melee_hits=0,melee_misses=0,ranged_attempts=0,ranged_hits=0,ranged_misses=0,ws_attempts=0,ws_hits=0,ws_misses=0,ws_mm=fresh_minmax(),actions={}}; dst.enemy[enemy_name]=db end
        for _,k in ipairs({'damage','melee','ranged','magic','ws','skillchain','skillchain_count','other','melee_attempts','melee_hits','melee_misses','ranged_attempts','ranged_hits','ranged_misses','ws_attempts','ws_hits','ws_misses'}) do db[k]=(db[k] or 0)+(sb[k] or 0) end
        merge_minmax(db.ws_mm,sb.ws_mm)
        for action_name,sa in pairs(sb.actions or {}) do
            local da=db.actions[action_name]
            if not da then da={damage=0,attempts=0,hits=0,misses=0,mm=fresh_minmax()}; db.actions[action_name]=da end
            da.damage=da.damage+(sa.damage or 0); da.attempts=da.attempts+(sa.attempts or 0); da.hits=da.hits+(sa.hits or 0); da.misses=da.misses+(sa.misses or 0); merge_minmax(da.mm,sa.mm)
        end
    end
    dst.enemy_ids=dst.enemy_ids or {}
    for enemy_id,sb in pairs(src.enemy_ids or {}) do
        local db=dst.enemy_ids[enemy_id]
        if not db then db={name=sb.name,damage=0,melee=0,ranged=0,magic=0,ws=0,skillchain=0,skillchain_count=0,other=0,melee_attempts=0,melee_hits=0,melee_misses=0,ranged_attempts=0,ranged_hits=0,ranged_misses=0,ws_attempts=0,ws_hits=0,ws_misses=0,ws_mm=fresh_minmax(),actions={}}; dst.enemy_ids[enemy_id]=db end
        db.name=db.name or sb.name
        for _,k in ipairs({'damage','melee','ranged','magic','ws','skillchain','skillchain_count','other','melee_attempts','melee_hits','melee_misses','ranged_attempts','ranged_hits','ranged_misses','ws_attempts','ws_hits','ws_misses'}) do db[k]=(db[k] or 0)+(sb[k] or 0) end
        merge_minmax(db.ws_mm,sb.ws_mm)
        for action_name,sa in pairs(sb.actions or {}) do
            local da=db.actions[action_name]
            if not da then da={damage=0,attempts=0,hits=0,misses=0,mm=fresh_minmax()}; db.actions[action_name]=da end
            da.damage=da.damage+(sa.damage or 0); da.attempts=da.attempts+(sa.attempts or 0); da.hits=da.hits+(sa.hits or 0); da.misses=da.misses+(sa.misses or 0); merge_minmax(da.mm,sa.mm)
        end
    end
end

-- Session identity is name-based for player-like actors. Runtime entity IDs can
-- change after zoning or alliance rearrangement and must never split the row.
local function session_key(actor)
    if not actor then return nil end
    local name=Core.lower(actor.name or '')
    if name~='' then return name end
    return tostring(actor.id or '?')
end

local function annotate_actor(actor,entry,actor_type,scope,order)
    if not actor then return actor end
    if entry and entry.name then actor.name=entry.name end
    actor.actor_type=actor_type or (entry and entry.actor_type) or actor.actor_type or 'unknown'
    actor.session_scope=scope or (entry and entry.scope) or actor.session_scope or 'outside'
    actor.session_order=math.min(tonumber(actor.session_order) or 999,tonumber(order) or 999)
    actor.aliases=actor.aliases or {}; if actor.id then actor.aliases[tostring(actor.id)]=true end
    return actor
end

local function session_merge_actor(src)
    if not src or src.actor_type=='enemy' or src.actor_type=='pet' then return end
    local key=session_key(src); if not key then return end
    local dst=session_actors[key]
    if not dst then dst=new_actor(src.id,src.name); dst.actor_type=src.actor_type; dst.session_scope=src.session_scope; dst.session_order=src.session_order; session_actors[key]=dst end
    add_actor_stats(dst,src)
end

local function refresh_party(now)
    now=now or Core.now()
    if now-party_cache_at>=1 then party_cache=Core.party_snapshot(windower); party_cache_at=now end
    return party_cache
end

local function add_active_interval(encounter,start_at,end_at)
    if not encounter then return end
    start_at,end_at=tonumber(start_at),tonumber(end_at)
    if not start_at or not end_at or end_at<=start_at then return end
    encounter.active_intervals=encounter.active_intervals or {}
    local last=encounter.active_intervals[#encounter.active_intervals]
    if last and start_at<=last[2]+0.05 then
        if end_at>last[2] then
            encounter.active_committed=(encounter.active_committed or 0)+(end_at-last[2])
            last[2]=end_at
        end
    else
        encounter.active_intervals[#encounter.active_intervals+1]={start_at,end_at}
        encounter.active_committed=(encounter.active_committed or 0)+(end_at-start_at)
    end
end

local function mark_enemy(encounter,id)
    if not encounter or not id then return end
    encounter.enemy_ids=encounter.enemy_ids or {}
    encounter.enemy_indices=encounter.enemy_indices or {}
    encounter.enemy_ids[id]=true
    local mob=Core.mob(windower,id)
    if mob then
        if mob.index then encounter.enemy_indices[tonumber(mob.index) or mob.index]=true end
        if mob.name then encounter.enemy_names[mob.name]=true end
    end
end

local function new_encounter(now)
    now=now or Core.now()
    return {id=Core.new_id('fight'),started=now,last=now,last_event=nil,last_combat_signal=now,active_committed=0,active_intervals={},active_poll_at=now,activity=Core.Activity.new(settings.active_timeout),actors={},enemy_names={},enemy_ids={},enemy_indices={},target_damage={},events=0}
end

local function alliance_engaged_with_encounter(encounter,party)
    if not encounter then return false end
    party=party or refresh_party(Core.now())
    local engaged_without_target_metadata=false
    for _,id in ipairs(party.order or {}) do
        local mob=Core.mob(windower,id) or (party.by_id[id] and party.by_id[id].mob)
        local status=mob and mob.status
        local engaged=(tonumber(status)==1) or Core.lower(status)=='engaged'
        if engaged then
            local target_id=tonumber(mob.target_id or mob.target or 0) or 0
            local target_index=tonumber(mob.target_index or 0) or 0
            if (target_id~=0 and encounter.enemy_ids and encounter.enemy_ids[target_id]) or
               (target_index~=0 and encounter.enemy_indices and encounter.enemy_indices[target_index]) then
                return true
            end
            if target_id==0 and target_index==0 then engaged_without_target_metadata=true end
        end
    end
    -- Some Windower party/mob snapshots expose engaged state but not the other
    -- member's current target. In that case, favor keeping an already-established
    -- alliance encounter alive rather than splitting a legitimate hold/kite phase.
    return engaged_without_target_metadata
end

local function encounter_has_live_enemy(encounter)
    if not encounter or not encounter.enemy_ids then return false end
    for id in pairs(encounter.enemy_ids) do
        local mob=Core.mob(windower,id)
        if mob and (mob.hpp==nil or tonumber(mob.hpp)>0) then return true end
    end
    return false
end

local function update_shared_clock(encounter,now)
    if not encounter then return false end
    now=now or Core.now()
    local engaged=alliance_engaged_with_encounter(encounter,refresh_party(now))
    local live_enemy=encounter_has_live_enemy(encounter)
    local recent_hostile=encounter.last_hostile and (now-encounter.last_hostile)<=math.min(3,settings.active_timeout)
    local active=live_enemy or engaged or recent_hostile
    local previous=encounter.active_poll_at or now
    if active then add_active_interval(encounter,previous,now); encounter.last_combat_signal=now end
    encounter.active_poll_at=now
    return active
end

local function ensure_encounter(now,hostile)
    now=now or Core.now()
    -- Readiness/support is not battle. A new encounter requires hostile
    -- interaction (engage, attack, hostile spell/JA, or enemy action).
    if not current then
        if not hostile then return nil end
        current=new_encounter(now); current.last_hostile=now
    end
    update_shared_clock(current,now)
    current.last_event=now; current.last=now
    if hostile then current.last_hostile=now; current.last_combat_signal=now; current.activity:mark(now) end
    return current
end

local function encounter_defeated(encounter)
    if not encounter or not encounter.enemy_ids then return false end
    local seen=false
    for id in pairs(encounter.enemy_ids) do
        local mob=Core.mob(windower,id)
        if mob then
            seen=true
            if mob.hpp==nil or tonumber(mob.hpp)>0 then return false end
        end
    end
    return seen
end

local function log_source(record_type,source,now,reason)
    if not source then return end
    now=now or Core.now()
    local elapsed=math.max(0,(source.ended or now)-(source.started or now))
    local active=tonumber(source.active_committed) or elapsed
    if source.activity then source.activity:tick(source.ended or now) end
    local rows={}
    for _,a in pairs(source.actors or {}) do if a and a.actor_type~='enemy' and a.actor_type~='pet' then rows[#rows+1]=a end end
    table.sort(rows,function(a,b) return (tonumber(a.session_order) or 999)<(tonumber(b.session_order) or 999) end)
    for _,a in ipairs(rows) do
        local total=combined_damage(a); local dps=active>0 and total/active or 0
        local acc=a.melee_attempts>0 and (100*a.melee_hits/a.melee_attempts) or ''
        local racc=a.ranged_attempts>0 and (100*a.ranged_hits/a.ranged_attempts) or ''
        local land_denom=(tonumber(a.magic_lands) or 0)+(tonumber(a.magic_resists) or 0); local landpct=land_denom>0 and (100*(tonumber(a.magic_lands) or 0)/land_denom) or ''
        local reconcile=total-(player_net_damage(a)+pet_net_damage(a))
        append_log({record_type,os.date('%Y-%m-%d %H:%M:%S'),reason or source.id or '-',('%.2f'):format(elapsed),('%.2f'):format(active),a.name,a.damage,a.pet and a.pet.damage or 0,total,('%.2f'):format(dps),a.melee,a.ranged,a.magic,a.enspell,a.other,a.ws_damage,a.ws_attempts,a.ws_hits,a.ws_misses,avg(a.ws_mm) and ('%.2f'):format(avg(a.ws_mm)) or '',acc~='' and ('%.2f'):format(acc) or '',racc~='' and ('%.2f'):format(racc) or '',landpct~='' and ('%.2f'):format(landpct) or '',a.skillchain,a.mb_damage,a.dheal,a.taken,a.healing,a.self_healing,a.cleanses,a.dispels,a.aspir_recovery,a.received,reconcile})
    end
end

local function finalize_encounter(now)
    if not current then return end
    now=now or Core.now(); update_shared_clock(current,now); current.ended=now; current.activity:tick(now)
    log_source('FIGHT',current,now,current.id)
    last_fight=current
    history[#history+1]=current
    while #history>settings.history_limit do table.remove(history,1) end
    for _,src in pairs(current.actors or {}) do session_merge_actor(src) end
    session_active_committed=session_active_committed+(tonumber(current.active_committed) or 0)
    current=nil
    target_learning={}; target_lives={}
    enemy_registry:save()
end

local function action_name(category,param)
    param=tonumber(param)
    local r=select(1,Core.action_resource(res,category,param))
    if r then return r.en or r.english or r.name or tostring(param or '-') end
    return tostring(param or '-')
end

local function pet_action_kind(category,param)
    local semantics=Core.action_semantics(res,category,param,true)
    return semantics.pet_damage_kind or 'other'
end

local function record_damage_heal(actor,category,param,sub,amount,is_pet,master_actor)
    amount=math.max(0,tonumber(amount) or 0); if amount<=0 or not actor then return end
    actor.dheal=(actor.dheal or 0)+amount
    if actor.damage_window then actor.damage_window:add(-amount,Core.now()) end
    local semantics=Core.action_semantics(res,category,param,is_pet)
    local parent=semantics and semantics.damage_parent or nil
    local key=category==1 and 'dheal_melee' or category==2 and 'dheal_ranged' or category==3 and 'dheal_ws' or category==4 and 'dheal_magic'
    if not key then key=parent=='melee' and 'dheal_melee' or parent=='ranged' and 'dheal_ranged' or parent=='magic' and 'dheal_magic' or 'dheal_other' end
    actor[key]=(actor[key] or 0)+amount
    if (category==4 or parent=='magic') and Core.action_message_text(res,sub and sub.message):find('magic burst',1,true) then actor.dheal_mb=(actor.dheal_mb or 0)+amount end
    if is_pet and master_actor then
        local p=master_actor.pet; p.dheal=(p.dheal or 0)+amount
        local kind=pet_action_kind(category,param)
        local pk=kind=='melee' and 'dheal_melee' or kind=='ranged' and 'dheal_ranged' or kind=='physical' and 'dheal_physical' or kind=='magic' and 'dheal_magic' or 'dheal_other'
        p[pk]=(p[pk] or 0)+amount
        if kind=='magic' and Core.action_message_text(res,sub and sub.message):find('magic burst',1,true) then p.dheal_mb=(p.dheal_mb or 0)+amount end
    end
end

local function result_text(sub)
    return Core.action_message_text(res,sub and sub.message)
end
local function is_miss(sub)
    local text=result_text(sub)
    return text:find('miss',1,true)~=nil or text:find('evade',1,true)~=nil
end
local function is_resist(sub)
    local text=result_text(sub)
    return text:find('resist',1,true)~=nil
end
local function is_no_effect(sub)
    local text=result_text(sub)
    return text:find('no effect',1,true)~=nil or text:find('has no effect',1,true)~=nil
end
local function is_critical(sub)
    return result_text(sub):find('critical',1,true)~=nil
end
local function is_heal(sub)
    local text=result_text(sub)
    return text:find('recover',1,true)~=nil or text:find('restore',1,true)~=nil or text:find('heals',1,true)~=nil or text:find('regains',1,true)~=nil
end
local function is_damage_text(sub)
    local text=result_text(sub)
    return text:find('damage',1,true)~=nil or text:find('takes',1,true)~=nil or text:find('receives',1,true)~=nil or text:find('hit',1,true)~=nil or text:find('drain',1,true)~=nil
end
local function is_magic_burst(sub)
    local text=result_text(sub)
    return text:find('magic burst',1,true)~=nil
end

local function owner_for(actor_id)
    local mob=Core.mob(windower,actor_id)
    local owner=mob and tonumber(mob.owner_id or 0) or 0
    if owner and owner~=0 then return owner,mob end
    return nil,mob
end

local function allied_relation(actor_id,party)
    local scope,entry=Core.actor_scope(windower,actor_id,party)
    if scope~='outside' then return true,scope,entry,entry and entry.actor_type or 'player',nil,entry and entry.mob or Core.mob(windower,actor_id) end
    local owner,mob=owner_for(actor_id)
    local owner_scope=owner and Core.actor_scope(windower,owner,party) or 'outside'
    if owner_scope~='outside' then return true,owner_scope,party.by_id[owner],'pet',owner,mob end
    local fellow_owner,fellow_mob=Core.fellow_owner(windower,actor_id,party)
    local fellow_scope=fellow_owner and Core.actor_scope(windower,fellow_owner,party) or 'outside'
    if fellow_scope~='outside' then return true,fellow_scope,party.by_id[fellow_owner],'fellow',fellow_owner,fellow_mob end
    return false,'outside',nil,'unknown',nil,mob
end

local function hostile_action_signal(act,party)
    local actor_allied=select(1,allied_relation(act.actor_id,party))
    for _,target in ipairs(act.targets or {}) do
        local target_allied=select(1,allied_relation(target.id,party))
        if actor_allied~=target_allied then return true end
    end
    return false
end

local function damage_type(category)
    if category==1 or category==2 or category==3 then return 'physical' end
    if category==4 then return 'magical' end
    return 'unknown'
end

local function add_enemy_bucket(actor,enemy_name,amount,kind,action_label,landed,target_id,attempted)
    if not actor or not enemy_name then return end
    amount=tonumber(amount) or 0
    local function apply(b)
        b.damage=(b.damage or 0)+amount; b[kind]=(b[kind] or 0)+amount
        if kind=='skillchain' and amount>0 then b.skillchain_count=(tonumber(b.skillchain_count) or 0)+1 end
        if kind=='melee' and attempted then
            b.melee_attempts=(b.melee_attempts or 0)+1
            if landed then b.melee_hits=(b.melee_hits or 0)+1 else b.melee_misses=(b.melee_misses or 0)+1 end
        elseif kind=='ranged' and attempted then
            b.ranged_attempts=(b.ranged_attempts or 0)+1
            if landed then b.ranged_hits=(b.ranged_hits or 0)+1 else b.ranged_misses=(b.ranged_misses or 0)+1 end
        elseif kind=='ws' then
            if amount>0 and landed then add_minmax(b.ws_mm,amount) end
            if attempted then
                b.ws_attempts=(b.ws_attempts or 0)+1
                if landed then b.ws_hits=(b.ws_hits or 0)+1 else b.ws_misses=(b.ws_misses or 0)+1 end
                if action_label then
                    local w=b.actions[action_label] or {damage=0,attempts=0,hits=0,misses=0,mm=fresh_minmax()}; b.actions[action_label]=w
                    w.attempts=w.attempts+1
                    if landed then w.hits=w.hits+1 else w.misses=w.misses+1 end
                end
            end
            if action_label and amount>0 then
                local w=b.actions[action_label] or {damage=0,attempts=0,hits=0,misses=0,mm=fresh_minmax()}; b.actions[action_label]=w
                w.damage=w.damage+amount; if landed then add_minmax(w.mm,amount) end
            end
        end
    end
    local b=actor.enemy[enemy_name]
    if not b then b={damage=0,melee=0,ranged=0,magic=0,ws=0,skillchain=0,skillchain_count=0,other=0,melee_attempts=0,melee_hits=0,melee_misses=0,ranged_attempts=0,ranged_hits=0,ranged_misses=0,ws_attempts=0,ws_hits=0,ws_misses=0,ws_mm=fresh_minmax(),actions={}}; actor.enemy[enemy_name]=b end
    apply(b)
    if target_id then
        actor.enemy_ids=actor.enemy_ids or {}
        local key=tostring(target_id)
        local ib=actor.enemy_ids[key]
        if not ib then ib={name=enemy_name,damage=0,melee=0,ranged=0,magic=0,ws=0,skillchain=0,skillchain_count=0,other=0,melee_attempts=0,melee_hits=0,melee_misses=0,ranged_attempts=0,ranged_hits=0,ranged_misses=0,ws_attempts=0,ws_hits=0,ws_misses=0,ws_mm=fresh_minmax(),actions={}}; actor.enemy_ids[key]=ib end
        apply(ib)
    end
end

local function record_additional_effect(actor,category,action_param,sub,target_id,now,is_pet,master_actor)
    if not actor or not sub or not sub.has_add_effect then return 0,nil end
    local amount=math.max(0,tonumber(sub.add_effect_param) or 0)
    if amount<=0 then return 0,nil end
    local animation=tonumber(sub.add_effect_animation) or 0
    local flags=Core.action_result_flags(res,{message=sub.add_effect_message,param=sub.add_effect_param})
    local message=flags.text
    local is_drain_text=message:find('drain',1,true)~=nil
    local is_mp_drain=is_drain_text and message:find('mp',1,true)~=nil
    if (category==1 or category==2) and is_mp_drain then
        actor.aspir_recovery=(actor.aspir_recovery or 0)+amount
        if is_pet and master_actor then master_actor.pet.aspir_recovery=(master_actor.pet.aspir_recovery or 0)+amount end
        return 0,'aspir'
    end
    if category==3 and animation>=1 and animation<=14 and flags.heal then
        actor.dheal=(actor.dheal or 0)+amount; actor.dheal_skillchain=(actor.dheal_skillchain or 0)+amount; if actor.damage_window then actor.damage_window:add(-amount,now) end
        apply_target_damage(target_id,-amount)
        if is_pet and master_actor then master_actor.pet.dheal=(master_actor.pet.dheal or 0)+amount; master_actor.pet.dheal_skillchain=(master_actor.pet.dheal_skillchain or 0)+amount end
        return 0,'dheal_skillchain'
    end
    if (category==1 or category==2) and flags.heal then
        -- An absorbed Enspell/additional elemental effect heals the enemy.  It
        -- belongs to the Magic parent, not to the triggering melee/ranged hit.
        actor.dheal=(actor.dheal or 0)+amount; actor.dheal_enspell=(actor.dheal_enspell or 0)+amount; if actor.damage_window then actor.damage_window:add(-amount,now) end
        apply_target_damage(target_id,-amount)
        if is_pet and master_actor then master_actor.pet.dheal=(master_actor.pet.dheal or 0)+amount; master_actor.pet.dheal_enspell=(master_actor.pet.dheal_enspell or 0)+amount end
        return 0,'dheal_enspell'
    end
    local kind=nil
    if category==3 and animation>=1 and animation<=14 then
        kind='skillchain'
    elseif (category==1 or category==2) and flags.damage then
        kind='enspell'
    end
    if not kind then return 0,nil end

    if kind=='enspell' then
        actor.enspell=(actor.enspell or 0)+amount
        actor.magic=(actor.magic or 0)+amount -- Magic is the inclusive parent.
    else
        actor[kind]=(actor[kind] or 0)+amount
        if kind=='skillchain' and amount>0 then actor.skillchain_count=(tonumber(actor.skillchain_count) or 0)+1 end
    end
    actor.damage=actor.damage+amount
    actor.damage_window:add(amount,now)
    apply_target_damage(target_id,amount)
    local target_mob=Core.mob(windower,target_id)
    local enemy_name=target_mob and target_mob.name or tostring(target_id)
    add_enemy_bucket(actor,enemy_name,amount,kind=='enspell' and 'magic' or kind,nil,true,target_id,false)
    if current then current.enemy_names[enemy_name]=true end

    if is_pet and master_actor then
        master_actor.pet.damage=master_actor.pet.damage+amount
        if kind=='enspell' then
            master_actor.pet.enspell=(master_actor.pet.enspell or 0)+amount
            master_actor.pet.magic=(master_actor.pet.magic or 0)+amount
        else master_actor.pet[kind]=(master_actor.pet[kind] or 0)+amount end
    end
    if kind=='enspell' and is_drain_text and not is_mp_drain then
        actor.healing=(actor.healing or 0)+amount; actor.self_healing=(actor.self_healing or 0)+amount; actor.drain_healing=(actor.drain_healing or 0)+amount
        if actor.healing_window then actor.healing_window:add(amount,now) end
        if is_pet and master_actor then master_actor.pet.healing=(master_actor.pet.healing or 0)+amount; master_actor.pet.self_healing=(master_actor.pet.self_healing or 0)+amount end
    end
    return amount,kind
end

local function new_spell_stats()
    return {
        casts=0,targets=0,lands=0,resists=0,no_effect=0,
        damage=0,damage_hits=0,damage_mm=fresh_minmax(),
        mb_casts=0,mb_hits=0,mb_damage=0,mb_mm=fresh_minmax(),
        nonmb_casts=0,nonmb_hits=0,nonmb_damage=0,nonmb_mm=fresh_minmax(),
        healing=0,heal_hits=0,heal_mm=fresh_minmax(),
        element=nil,skill=nil,spell_type=nil,
    }
end

local function spell_for(actor,name)
    if not actor.spells[name] then actor.spells[name]=new_spell_stats() end
    return actor.spells[name]
end

local function record_magic_cast(actor,spell_name,outcomes,is_pet,master_actor,spell_id)
    if not actor then return end
    local sp=spell_for(actor,spell_name)
    local sr=res.spells and res.spells[tonumber(spell_id)] or nil
    if sr then
        sp.element=sp.element or sr.element
        sp.skill=sp.skill or sr.skill
        sp.spell_type=sp.spell_type or sr.type or sr.prefix
    end
    actor.magic_casts=actor.magic_casts+1
    sp.casts=sp.casts+1
    local cast_has_mb,cast_has_nonmb=false,false
    local pet=master_actor and master_actor.pet or nil
    if is_pet and pet then pet.magic_casts=pet.magic_casts+1 end

    for _,o in ipairs(outcomes or {}) do
        actor.magic_targets=actor.magic_targets+1; sp.targets=sp.targets+1
        if is_pet and pet then pet.magic_targets=pet.magic_targets+1 end
        if o.no_effect then
            actor.magic_no_effect=actor.magic_no_effect+1; sp.no_effect=sp.no_effect+1
            if is_pet and pet then pet.magic_no_effect=pet.magic_no_effect+1 end
        elseif o.resist then
            actor.magic_resists=actor.magic_resists+1; sp.resists=sp.resists+1
            if is_pet and pet then pet.magic_resists=pet.magic_resists+1 end
        elseif o.success then
            actor.magic_lands=actor.magic_lands+1; sp.lands=sp.lands+1
            if is_pet and pet then pet.magic_lands=pet.magic_lands+1 end
        end

        if o.damage and o.damage>0 then
            sp.damage=sp.damage+o.damage; sp.damage_hits=sp.damage_hits+1; add_minmax(sp.damage_mm,o.damage)
            if o.mb then
                cast_has_mb=true; sp.mb_hits=sp.mb_hits+1; sp.mb_damage=sp.mb_damage+o.damage; add_minmax(sp.mb_mm,o.damage)
            else
                cast_has_nonmb=true; sp.nonmb_hits=sp.nonmb_hits+1; sp.nonmb_damage=sp.nonmb_damage+o.damage; add_minmax(sp.nonmb_mm,o.damage)
            end
        end
        if o.healing and o.healing>0 then actor.magic_healing=actor.magic_healing+o.healing; sp.healing=sp.healing+o.healing; sp.heal_hits=sp.heal_hits+1; add_minmax(sp.heal_mm,o.healing) end
    end
    if cast_has_mb then actor.mb_casts=actor.mb_casts+1; sp.mb_casts=sp.mb_casts+1; if is_pet and pet then pet.mb_casts=pet.mb_casts+1 end end
    if cast_has_nonmb then actor.nonmb_casts=actor.nonmb_casts+1; sp.nonmb_casts=sp.nonmb_casts+1; if is_pet and pet then pet.nonmb_casts=pet.nonmb_casts+1 end end
end

local function record_outgoing(actor,category,action_param,sub,target_id,action_label,now,is_pet,master_actor,target_friendly,semantics)
    if not actor then return 'none',0,nil end
    semantics=semantics or Core.action_semantics(res,category,action_param,is_pet)
    local flags=Core.action_result_flags(res,sub)
    local amount=flags.amount
    local miss=flags.miss
    local heal=target_friendly and semantics.healing and amount>0 and not flags.miss and not flags.resist and not flags.no_effect
    local target_mob=Core.mob(windower,target_id)
    local enemy_name=target_mob and target_mob.name or tostring(target_id)
    if semantics.aspir and not semantics.drain and not target_friendly and amount>0 and not flags.miss and not flags.resist and not flags.no_effect then
        actor.aspir_recovery=(actor.aspir_recovery or 0)+amount
        if is_pet and master_actor then master_actor.pet.aspir_recovery=(master_actor.pet.aspir_recovery or 0)+amount end
        return 'aspir',amount,enemy_name
    end
    if heal then
        if target_friendly then return 'heal',amount,enemy_name end
        -- Enemy recovery caused by this action is negative contribution for the
        -- exact parent category.  It still represents a landed melee/ranged/WS
        -- action for accuracy/frequency purposes rather than a miss.
        record_damage_heal(actor,category,action_param,sub,amount,is_pet,master_actor)
        if category==1 then
            actor.melee_attempts=actor.melee_attempts+1; actor.melee_hits=actor.melee_hits+1
        elseif category==2 then
            actor.ranged_attempts=actor.ranged_attempts+1; actor.ranged_hits=actor.ranged_hits+1
        end
        if is_pet and master_actor and (category==1 or category==2) then
            local p=master_actor.pet; p.attempts=p.attempts+1; p.hits=p.hits+1
            if category==1 then p.melee_attempts=p.melee_attempts+1; p.melee_hits=p.melee_hits+1
            else p.ranged_attempts=p.ranged_attempts+1; p.ranged_hits=p.ranged_hits+1 end
        end
        apply_target_damage(target_id,-amount)
        return 'dheal',amount,enemy_name
    end

    local landed=not miss and amount>0
    if category==1 then
        local forced_miss=miss and forced_miss_windows[target_id] and now<=forced_miss_windows[target_id]
        if not forced_miss then
            actor.melee_attempts=actor.melee_attempts+1
            if landed then actor.melee_hits=actor.melee_hits+1; actor.melee=actor.melee+amount; add_minmax(actor.melee_mm,amount); if flags.critical then actor.melee_crit=actor.melee_crit+1; add_minmax(actor.crit_mm,amount) end else actor.melee_misses=actor.melee_misses+1 end
        else actor.accuracy_forced_ignored=(actor.accuracy_forced_ignored or 0)+1 end
    elseif category==2 then
        actor.ranged_attempts=actor.ranged_attempts+1
        if landed then actor.ranged_hits=actor.ranged_hits+1; actor.ranged=actor.ranged+amount; add_minmax(actor.ranged_mm,amount); if flags.critical then actor.ranged_crit=actor.ranged_crit+1 end else actor.ranged_misses=actor.ranged_misses+1 end
    elseif category==3 then
        -- WS damage is intentionally NOT added to Other here.  The action-level
        -- WS accumulator below records it once in WS Dmg.
    elseif category==4 then
        if landed and flags.damage then
            actor.magic_hits=actor.magic_hits+1; actor.magic_damage=actor.magic_damage+amount; actor.magic=actor.magic+amount; add_minmax(actor.magic_mm,amount)
            if flags.magic_burst then actor.mb_count=actor.mb_count+1; actor.mb_damage=actor.mb_damage+amount; add_minmax(actor.mb_mm,amount)
            else actor.nonmb_count=actor.nonmb_count+1; actor.nonmb_damage=actor.nonmb_damage+amount; add_minmax(actor.nonmb_mm,amount) end
        end
    elseif landed and flags.damage then
        local parent=semantics.damage_parent or 'other'
        if parent=='melee' then actor.melee=actor.melee+amount
        elseif parent=='ranged' then actor.ranged=actor.ranged+amount
        elseif parent=='magic' then actor.magic=actor.magic+amount
        else actor.other=actor.other+amount end
    end

    local counted=0
    if category==1 or category==2 or category==3 then counted=landed and amount or 0
    elseif category==4 and landed and flags.damage then counted=amount
    elseif landed and flags.damage then counted=amount end
    if counted>0 then
        actor.damage=actor.damage+counted; actor.damage_window:add(counted,now)
        apply_target_damage(target_id,counted)
        local kind=semantics.damage_parent or (category==1 and 'melee' or category==2 and 'ranged' or category==3 and 'ws' or category==4 and 'magic' or 'other')
        add_enemy_bucket(actor,enemy_name,counted,kind,action_label,landed,target_id,(category==1 or category==2))
        if current then current.enemy_names[enemy_name]=true end
        if is_pet and master_actor then
            local p=master_actor.pet; local pkind=semantics.pet_damage_kind or pet_action_kind(category,action_param)
            p.damage=p.damage+counted; p.name=actor.name; p[pkind]=(p[pkind] or 0)+counted
            if pkind=='physical' then p.ws=(p.ws or 0)+counted end
            if category==1 then
                p.attempts=p.attempts+1; p.hits=p.hits+1; add_minmax(p.mm,counted); p.melee_attempts=p.melee_attempts+1; p.melee_hits=p.melee_hits+1; add_minmax(p.melee_mm,counted)
            elseif category==2 then
                p.attempts=p.attempts+1; p.hits=p.hits+1; add_minmax(p.mm,counted); p.ranged_attempts=p.ranged_attempts+1; p.ranged_hits=p.ranged_hits+1; add_minmax(p.ranged_mm,counted)
            elseif pkind=='magic' then
                p.magic_hits=p.magic_hits+1; add_minmax(p.magic_mm,counted)
                if flags.magic_burst then p.mb_count=p.mb_count+1; p.mb_damage=p.mb_damage+counted; add_minmax(p.mb_mm,counted)
                else p.nonmb_count=p.nonmb_count+1; p.nonmb_damage=p.nonmb_damage+counted; add_minmax(p.nonmb_mm,counted) end
            elseif pkind=='physical' then add_minmax(p.ws_mm,counted) end
        end
    elseif is_pet and master_actor and (category==1 or category==2) then
        local p=master_actor.pet; local forced_miss=category==1 and forced_miss_windows[target_id] and now<=forced_miss_windows[target_id]
        if not forced_miss then p.attempts=p.attempts+1; p.misses=p.misses+1; if category==1 then p.melee_attempts=p.melee_attempts+1; p.melee_misses=p.melee_misses+1 else p.ranged_attempts=p.ranged_attempts+1; p.ranged_misses=p.ranged_misses+1 end end
    end
    if counted<=0 and not target_friendly and (category==1 or category==2) then
        local forced_miss=category==1 and forced_miss_windows[target_id] and now<=forced_miss_windows[target_id]
        if not forced_miss then add_enemy_bucket(actor,enemy_name,0,category==1 and 'melee' or 'ranged',action_label,false,target_id,true) end
    end
    return 'damage',counted,enemy_name
end

-- Reactive damage is credited to the defender who caused it, not the attacker
-- whose action packet carried the spike result. Child counters remain subsets.
local function record_spike_effect(defender,sub,attacker_id,now)
    if not defender or not sub or not sub.has_spike_effect then return end
    local amount=math.max(0,tonumber(sub.spike_effect_param) or 0); if amount<=0 then return end
    local animation=tonumber(sub.spike_effect_animation) or 0
    local text=Core.action_message_text(res,sub.spike_effect_message)
    local counter=(animation==63) or text:find('counter',1,true)~=nil
    local retaliation=text:find('retaliat',1,true)~=nil
    local reprisal=(animation==6) or text:find('reprisal',1,true)~=nil
    local dread=(animation==3) or text:find('dread',1,true)~=nil or text:find('drain',1,true)~=nil
    if counter or retaliation then
        defender.melee=defender.melee+amount
        if counter then defender.counter_damage=(defender.counter_damage or 0)+amount end
        if retaliation then defender.retaliation_damage=(defender.retaliation_damage or 0)+amount end
    else
        defender.magic=defender.magic+amount; defender.magic_damage=defender.magic_damage+amount
        if reprisal then defender.reprisal_damage=(defender.reprisal_damage or 0)+amount
        elseif dread then defender.dread_spikes_damage=(defender.dread_spikes_damage or 0)+amount
        else defender.spikes_damage=(defender.spikes_damage or 0)+amount end
    end
    defender.damage=defender.damage+amount; defender.damage_window:add(amount,now)
    apply_target_damage(attacker_id,amount)
    local enemy=Core.mob(windower,attacker_id); add_enemy_bucket(defender,enemy and enemy.name or tostring(attacker_id),amount,(counter or retaliation) and 'melee' or 'magic',(counter and 'Counter') or (retaliation and 'Retaliation') or (reprisal and 'Reprisal') or (dread and 'Dread Spikes') or 'Spikes',true)
    if dread then
        defender.healing=defender.healing+amount; defender.received=defender.received+amount; defender.self_healing=defender.self_healing+amount; defender.drain_healing=(defender.drain_healing or 0)+amount; defender.healing_window:add(amount,now)
        defender.healed_targets[defender.name]=(defender.healed_targets[defender.name] or 0)+amount; defender.healed_by[defender.name]=(defender.healed_by[defender.name] or 0)+amount
    end
end

local function record_taken(target,category,sub,amount)
    amount=math.max(0,tonumber(amount) or 0)
    if is_heal(sub) then return end
    if amount<=0 then
        local text=result_text(sub)
        if text:find('parr',1,true) then target.parries=target.parries+1
        elseif text:find('block',1,true) then target.blocks=target.blocks+1
        elseif text:find('miss',1,true) or text:find('evade',1,true) then target.evades=target.evades+1 end
        return
    end
    -- Many successful spells carry a non-damage parameter (for example a
    -- status/effect identifier). Never treat that parameter as damage taken.
    if not is_damage_text(sub) then return end
    target.taken=target.taken+amount; target.taken_hits=target.taken_hits+1; add_minmax(target.taken_mm,amount)
    local dtype=damage_type(category)
    if dtype=='physical' then target.taken_physical=target.taken_physical+amount elseif dtype=='magical' then target.taken_magical=target.taken_magical+amount else target.taken_unknown=target.taken_unknown+amount end
end

local note_weapon_class_from_ws

local function process_action(act)
    if settings.paused or type(act)~='table' then return end
    local now=Core.now(); local party=refresh_party(now); local category=tonumber(act.category) or 0
    if category==6 and current and current.enemy_ids and current.enemy_ids[act.actor_id] then
        local label=action_name(category,act.param)
        if Core.lower(label)=='perfect dodge' then
            local ja=res.job_abilities and res.job_abilities[tonumber(act.param)]
            forced_miss_windows[act.actor_id]=now+(tonumber(ja and ja.duration) or 30)
        end
    end
    for id,expires in pairs(forced_miss_windows) do if now>expires+2 then forced_miss_windows[id]=nil end end
    local relevant_actor,actor_scope,actor_entry,actor_type,related_owner,actor_mob=allied_relation(act.actor_id,party)
    local owner_id=actor_type=='pet' and related_owner or nil
    local owner_scope=owner_id and actor_scope or 'outside'
    local relevant_target=false
    for _,target in ipairs(act.targets or {}) do if select(1,allied_relation(target.id,party)) then relevant_target=true; break end end
    if not relevant_actor and not relevant_target then return end

    local hostile=hostile_action_signal(act,party)
    local encounter=ensure_encounter(now,hostile)
    if not encounter then return end
    if hostile then session_last_event=now; session_activity:mark(now) end
    encounter.events=encounter.events+1; event_count=event_count+1
    if relevant_actor then
        for _,target in ipairs(act.targets or {}) do
            if not select(1,allied_relation(target.id,party)) then mark_enemy(encounter,target.id) end
        end
    elseif relevant_target then
        mark_enemy(encounter,act.actor_id)
    end
    local actor_name=actor_mob and actor_mob.name or actor_entry and actor_entry.name or Core.mob_name(windower,act.actor_id)
    local actor=actor_for(encounter.actors,act.actor_id,actor_name)
    local party_order=999; for i,id in ipairs(party.order or {}) do if id==act.actor_id or id==related_owner then party_order=i; break end end
    annotate_actor(actor,actor_entry,actor_type,actor_scope,party_order)
    if not relevant_actor then actor.actor_type='enemy'; actor.session_scope='outside' end
    local is_pet=actor_type=='pet'
    local master_actor=is_pet and actor_for(encounter.actors,owner_id,party.by_id[owner_id] and party.by_id[owner_id].name or Core.mob_name(windower,owner_id)) or nil
    if master_actor then annotate_actor(master_actor,party.by_id[owner_id],party.by_id[owner_id] and party.by_id[owner_id].actor_type or 'player',owner_scope,party_order) end
    local action_label=action_name(category,act.param)
    local semantics=Core.action_semantics(res,category,act.param,is_pet)
    local heal_targets={}; local total_healing=0; local drain_healing=0; local cleanse_targets=0; local dispel_targets=0
    local ws_action_damage=0; local ws_any_hit=false; local ws_seen=false; local ws_all_forced=true; local ws_hostile_targets=0
    local ws_enemy_targets={}
    local magic_outcomes={}

    for _,target_packet in ipairs(act.targets or {}) do
        local target_party=party.by_id[target_packet.id]
        local target_is_allied=select(1,allied_relation(target_packet.id,party))
        local target_ws_seen,target_ws_hit=false,false
        local magic_outcome=category==4 and {damage=0,healing=0,mb=false,resist=false,no_effect=false,success=false,seen=false} or nil
        for _,sub in ipairs(target_packet.actions or {}) do
            local target_is_allied,target_scope,target_entry,target_type,target_owner_id,target_mob=allied_relation(target_packet.id,party)
            local target_owner_scope=target_owner_id and target_scope or 'outside'
            local target_friendly=target_is_allied
            local mode,amount=record_outgoing(actor,category,act.param,sub,target_packet.id,action_label,now,is_pet,master_actor,target_friendly,semantics)
            if magic_outcome then
                magic_outcome.seen=true
                magic_outcome.mb=magic_outcome.mb or is_magic_burst(sub)
                magic_outcome.resist=magic_outcome.resist or is_resist(sub)
                magic_outcome.no_effect=magic_outcome.no_effect or is_no_effect(sub)
                if mode=='heal' and amount>0 then magic_outcome.healing=magic_outcome.healing+amount; magic_outcome.success=true
                elseif not is_miss(sub) and amount>0 and is_damage_text(sub) then magic_outcome.damage=magic_outcome.damage+amount; magic_outcome.success=true
                elseif not is_miss(sub) and not is_resist(sub) and not is_no_effect(sub) then magic_outcome.success=true end
            end
            record_additional_effect(actor,category,act.param,sub,target_packet.id,now,is_pet,master_actor)
            if mode=='heal' and amount>0 then heal_targets[#heal_targets+1]={id=target_packet.id,amount=amount}; total_healing=total_healing+amount end
            if semantics.drain and not target_friendly and mode=='damage' and amount>0 then drain_healing=drain_healing+amount end
            if semantics.cleanse and target_friendly and not is_miss(sub) and not is_resist(sub) and not is_no_effect(sub) then cleanse_targets=cleanse_targets+1 end
            if semantics.dispel and not target_friendly and not is_miss(sub) and not is_resist(sub) and not is_no_effect(sub) then dispel_targets=dispel_targets+1 end
            if category==3 then
                ws_seen=true; target_ws_seen=true
                if not target_friendly then ws_hostile_targets=ws_hostile_targets+1; if not (forced_miss_windows[target_packet.id] and now<=forced_miss_windows[target_packet.id]) then ws_all_forced=false end end
                if not is_miss(sub) and amount>0 then
                    ws_any_hit=true; target_ws_hit=true
                    if mode=='damage' then ws_action_damage=ws_action_damage+amount end
                end
            end
            if target_party and mode~='heal' then
                local target_actor=actor_for(encounter.actors,target_packet.id,target_party.name); annotate_actor(target_actor,target_party,target_party.actor_type or 'player',target_party.scope,999); record_taken(target_actor,category,sub,tonumber(sub.param) or 0); record_spike_effect(target_actor,sub,act.actor_id,now)
            elseif mode~='heal' then
                local target_is_allied,target_scope,target_entry,target_type,target_owner,target_mob=allied_relation(target_packet.id,party)
                if target_is_allied then
                    local target_actor=actor_for(encounter.actors,target_packet.id,target_mob and target_mob.name or Core.mob_name(windower,target_packet.id))
                    annotate_actor(target_actor,target_entry,target_type,target_scope,999)
                    local before=target_actor.taken; record_taken(target_actor,category,sub,tonumber(sub.param) or 0); record_spike_effect(target_actor,sub,act.actor_id,now); local delta=math.max(0,target_actor.taken-before)
                    if target_type=='pet' and target_owner then
                        local owner_actor=actor_for(encounter.actors,target_owner,party.by_id[target_owner] and party.by_id[target_owner].name or Core.mob_name(windower,target_owner)); annotate_actor(owner_actor,party.by_id[target_owner],party.by_id[target_owner] and party.by_id[target_owner].actor_type or 'player',target_scope,999)
                        if delta>0 then owner_actor.pet.taken=owner_actor.pet.taken+delta; owner_actor.pet.taken_hits=owner_actor.pet.taken_hits+1; add_minmax(owner_actor.pet.taken_mm,delta) end
                    end
                end
            end
        end
        if magic_outcome and magic_outcome.seen then magic_outcomes[#magic_outcomes+1]=magic_outcome end
        if category==3 and target_ws_seen and not target_is_allied then
            local tm=Core.mob(windower,target_packet.id)
            ws_enemy_targets[#ws_enemy_targets+1]={id=target_packet.id,name=(tm and tm.name or tostring(target_packet.id)),hit=target_ws_hit}
        end
    end

    if category==4 and relevant_actor then record_magic_cast(actor,action_label,magic_outcomes,is_pet,master_actor,act.param) end

    -- A WS is one attempt per use, even if an AoE WS has several target rows.
    if category==3 and ws_seen then
        note_weapon_class_from_ws(actor,act.param)
        local forced_ws_miss=(not ws_any_hit) and ws_hostile_targets>0 and ws_all_forced
        if forced_ws_miss then
            actor.ws_forced_ignored=(actor.ws_forced_ignored or 0)+1
        else
            actor.ws_attempts=actor.ws_attempts+1
            local w=actor.ws[action_label] or {damage=0,attempts=0,hits=0,misses=0,mm=fresh_minmax()}; actor.ws[action_label]=w; w.attempts=w.attempts+1
            if ws_any_hit then
                actor.ws_hits=actor.ws_hits+1; actor.ws_damage=actor.ws_damage+ws_action_damage; w.hits=w.hits+1; w.damage=w.damage+ws_action_damage
                if ws_action_damage>0 then add_minmax(actor.ws_mm,ws_action_damage); add_minmax(w.mm,ws_action_damage) end
            else actor.ws_misses=actor.ws_misses+1; w.misses=w.misses+1 end
            if is_pet and master_actor then local p=master_actor.pet; p.ws_attempts=p.ws_attempts+1; if ws_any_hit then p.ws_hits=p.ws_hits+1; add_minmax(p.ws_mm,ws_action_damage) else p.ws_misses=p.ws_misses+1 end end
            for _,wr in ipairs(ws_enemy_targets) do
                add_enemy_bucket(actor,wr.name,0,'ws',action_label,wr.hit,wr.id,true)
            end
        end
    end

    if drain_healing>0 and (actor_scope~='outside' or is_pet) then
        actor.healing=actor.healing+drain_healing; actor.received=actor.received+drain_healing; actor.self_healing=actor.self_healing+drain_healing; actor.drain_healing=(actor.drain_healing or 0)+drain_healing; actor.healing_window:add(drain_healing,now); actor.healed_targets[actor.name]=(actor.healed_targets[actor.name] or 0)+drain_healing; actor.healed_by[actor.name]=(actor.healed_by[actor.name] or 0)+drain_healing
        if is_pet and master_actor then master_actor.pet.healing=(master_actor.pet.healing or 0)+drain_healing; master_actor.pet.self_healing=(master_actor.pet.self_healing or 0)+drain_healing end
    end
    if cleanse_targets>0 and (actor_scope~='outside' or is_pet) then
        actor.cleanses=(actor.cleanses or 0)+cleanse_targets; actor.cleanse_actions[action_label]=(actor.cleanse_actions[action_label] or 0)+cleanse_targets
        if is_pet and master_actor then master_actor.pet.cleanses=(master_actor.pet.cleanses or 0)+cleanse_targets end
    end
    if dispel_targets>0 and (actor_scope~='outside' or is_pet) then
        actor.dispels=(actor.dispels or 0)+dispel_targets; actor.dispel_actions[action_label]=(actor.dispel_actions[action_label] or 0)+dispel_targets
        if is_pet and master_actor then master_actor.pet.dispels=(master_actor.pet.dispels or 0)+dispel_targets end
    end

    if total_healing>0 and (actor_scope~='outside' or is_pet) then
        actor.healing=actor.healing+total_healing;
        if is_pet and master_actor then master_actor.pet.healing=(master_actor.pet.healing or 0)+total_healing end
        actor.healing_window:add(total_healing,now); actor.cures=actor.cures+1; add_minmax(actor.cure_mm,total_healing)
        local spell=category==4 and res.spells and res.spells[tonumber(act.param)] or nil
        local mp=spell and tonumber(spell.mp_cost or spell.mp) or 0; actor.mp_spent=actor.mp_spent+mp
        for _,h in ipairs(heal_targets) do
            local allied,target_scope,target_entry,target_type,target_owner,target_mob=allied_relation(h.id,party)
            if allied then
                local t=actor_for(encounter.actors,h.id,target_entry and target_entry.name or target_mob and target_mob.name or Core.mob_name(windower,h.id)); annotate_actor(t,target_entry,target_type,target_scope,999)
                t.received=t.received+h.amount
                if h.id==act.actor_id then t.self_healing=t.self_healing+h.amount end
                if total_healing>0 and mp>0 then t.cure_mp_received=t.cure_mp_received+mp*(h.amount/total_healing) end
                actor.healed_targets[t.name]=(actor.healed_targets[t.name] or 0)+h.amount
                t.healed_by[actor.name]=(t.healed_by[actor.name] or 0)+h.amount
            end
        end
    end
end

local function current_source()
    if settings.period=='last' then return last_fight end
    if settings.period=='session' then
        local now=Core.now(); session_activity:tick(now)
        local actors={}
        for key,src in pairs(session_actors) do local dst=new_actor(src.id,src.name); dst.actor_type=src.actor_type; dst.session_scope=src.session_scope; dst.session_order=src.session_order; actors[key]=dst; add_actor_stats(dst,src) end
        if current then
            for _,src in pairs(current.actors or {}) do
                if src.actor_type~='enemy' and src.actor_type~='pet' then
                    local key=session_key(src); local dst=actors[key]
                    if not dst then dst=new_actor(src.id,src.name); dst.actor_type=src.actor_type; dst.session_scope=src.session_scope; dst.session_order=src.session_order; actors[key]=dst end
                    add_actor_stats(dst,src)
                    dst.damage_window=src.damage_window; dst.healing_window=src.healing_window
                end
            end
        end
        local current_active=0
        if current then update_shared_clock(current,now); current_active=tonumber(current.active_committed) or 0 end
        return {started=session_started,last=now,activity=session_activity,active_committed=session_active_committed+current_active,actors=actors,enemy_names={}}
    end
    return current
end

-- Stopwatch-style split intervals and composable enemy filters.  Splits are
-- views over one uninterrupted authoritative session; they never reset the raw
-- counters underneath.
local function split_copy(value,depth)
    depth=depth or 0
    if depth>12 then return nil end
    local t=type(value)
    if t=='number' or t=='string' or t=='boolean' then return value end
    if t~='table' then return nil end
    local out={}
    for k,v in pairs(value) do
        if k~='damage_window' and k~='healing_window' and k~='activity' then
            out[k]=split_copy(v,depth+1)
        end
    end
    return out
end

local function source_active_value(source,now)
    if not source then return 0 end
    local active=tonumber(source.active_committed)
    if active~=nil then return math.max(0,active) end
    if source.activity and source.activity.active_seconds then
        local ok,value=pcall(source.activity.active_seconds,source.activity,source.ended or now or Core.now())
        if ok then return math.max(0,tonumber(value) or 0) end
    end
    return math.max(0,(tonumber(source.ended or now) or 0)-(tonumber(source.started) or 0))
end

local function snapshot_source(source,now)
    if not source then return {captured_at=now or Core.now(),active=0,actors={}} end
    now=now or Core.now()
    local snap={captured_at=now,started=source.started,active=source_active_value(source,now),actors={}}
    for key,a in pairs(source.actors or {}) do snap.actors[key]=split_copy(a) end
    return snap
end

local function delta_mm(cur,base)
    cur,base=cur or {},base or {}
    return {total=(tonumber(cur.total) or 0)-(tonumber(base.total) or 0),count=(tonumber(cur.count) or 0)-(tonumber(base.count) or 0),low=nil,peak=nil}
end

local function delta_fill(dst,cur,base,depth)
    depth=depth or 0; if depth>12 or type(cur)~='table' then return end
    base=type(base)=='table' and base or {}
    for k,v in pairs(cur) do
        if k~='damage_window' and k~='healing_window' and k~='activity' and k~='id' and k~='session_order' then
            local tv=type(v)
            if tv=='number' then
                dst[k]=(tonumber(v) or 0)-(tonumber(base[k]) or 0)
            elseif tv=='string' or tv=='boolean' then
                dst[k]=v
            elseif tv=='table' then
                if k=='aliases' then dst[k]=split_copy(v)
                elseif v.total~=nil and v.count~=nil and (v.low~=nil or v.peak~=nil or base[k] and base[k].total~=nil) then
                    dst[k]=delta_mm(v,base[k])
                else
                    if type(dst[k])~='table' then dst[k]={} end
                    delta_fill(dst[k],v,base[k],depth+1)
                end
            end
        end
    end
end

local function delta_source_from_snapshots(cur,base)
    if not cur or not base then return nil end
    local out={started=base.captured_at,last=cur.captured_at,ended=cur.ended,active_committed=math.max(0,(tonumber(cur.active) or 0)-(tonumber(base.active) or 0)),actors={},enemy_names={}}
    for key,a in pairs(cur.actors or {}) do
        local b=base.actors and base.actors[key] or nil
        local d=new_actor(a.id,a.name); d.actor_type=a.actor_type or d.actor_type; d.session_scope=a.session_scope or d.session_scope; d.session_order=a.session_order or d.session_order; d.weapon_class=a.weapon_class
        delta_fill(d,a,b or {})
        d.id=a.id; d.name=a.name; d.actor_type=a.actor_type or d.actor_type; d.session_scope=a.session_scope or d.session_scope; d.session_order=a.session_order or d.session_order; d.weapon_class=a.weapon_class
        out.actors[key]=d
    end
    return out
end

local function session_source_for_split()
    local old=settings.period; settings.period='session'; local src=current_source(); settings.period=old; return src
end

local function finish_active_split(now)
    if not active_split then return end
    local raw=session_source_for_split(); active_split.end_snapshot=snapshot_source(raw,now or Core.now()); active_split.ended_at=now or Core.now(); active_split.active=false
    active_split.source=delta_source_from_snapshots(active_split.end_snapshot,active_split.baseline)
    active_split=nil
end

local function find_split(token)
    token=Core.lower(token or '')
    if token=='' then return nil end
    local number=tonumber(token)
    for i,sp in ipairs(splits) do
        if (number and (i==number or sp.id==number)) or Core.lower(sp.name)==token then return sp,i end
    end
    return nil
end

local function split_source(raw)
    if not split_view then return raw end
    local sp
    if split_view=='current' then sp=active_split else sp=find_split(tostring(split_view)) end
    if not sp then return raw end
    if sp.active then return delta_source_from_snapshots(snapshot_source(raw,Core.now()),sp.baseline) end
    return sp.source or (sp.end_snapshot and delta_source_from_snapshots(sp.end_snapshot,sp.baseline)) or raw
end

local function parse_filter_terms()
    local out={}
    for term in tostring(settings.enemy_filter_text or ''):gmatch('[^;]+') do term=term:gsub('^%s+',''):gsub('%s+$',''); if term~='' then out[#out+1]=term end end
    return out
end
local function parse_filter_ids()
    local out={}
    for token in tostring(settings.enemy_filter_ids or ''):gmatch('[^,]+') do local id=tonumber(token); if id then out[id]=true end end
    return out
end
local function save_filter_terms(terms)
    local seen,out={},{}
    for _,term in ipairs(terms or {}) do local key=Core.lower(term); if key~='' and not seen[key] then seen[key]=true; out[#out+1]=term end end
    settings.enemy_filter_text=table.concat(out,';')
end
local function enemy_filter_active()
    return tostring(settings.enemy_filter_text or '')~='' or tostring(settings.enemy_filter_ids or '')~=''
end
local function enemy_name_matches(name,terms)
    local lname=Core.lower(name or '')
    for _,term in ipairs(terms or {}) do if lname:find(Core.lower(term),1,true) then return true end end
    return false
end
local function add_bucket_to_filtered(dst,b)
    if not b then return end
    dst.damage=(dst.damage or 0)+(tonumber(b.damage) or 0)
    dst.melee=(dst.melee or 0)+(tonumber(b.melee) or 0); dst.ranged=(dst.ranged or 0)+(tonumber(b.ranged) or 0); dst.magic=(dst.magic or 0)+(tonumber(b.magic) or 0); dst.ws_damage=(dst.ws_damage or 0)+(tonumber(b.ws) or 0); dst.skillchain=(dst.skillchain or 0)+(tonumber(b.skillchain) or 0); dst.skillchain_count=(dst.skillchain_count or 0)+(tonumber(b.skillchain_count) or 0); dst.other=(dst.other or 0)+(tonumber(b.other) or 0)
    for _,k in ipairs({'melee_attempts','melee_hits','melee_misses','ranged_attempts','ranged_hits','ranged_misses','ws_attempts','ws_hits','ws_misses'}) do dst[k]=(dst[k] or 0)+(tonumber(b[k]) or 0) end
    merge_minmax(dst.ws_mm,b.ws_mm)
end
local function enemy_filtered_source(source)
    if not source or not enemy_filter_active() then return source end
    local terms,ids=parse_filter_terms(),parse_filter_ids(); local any_ids=next(ids)~=nil
    local out={started=source.started,last=source.last,ended=source.ended,active_committed=source.active_committed,actors={},enemy_names={}}
    for key,a in pairs(source.actors or {}) do
        local d=new_actor(a.id,a.name); d.actor_type=a.actor_type; d.session_scope=a.session_scope; d.session_order=a.session_order; d.weapon_class=a.weapon_class
        local used=false
        if type(a.enemy_ids)=='table' and next(a.enemy_ids)~=nil then
            for idstr,b in pairs(a.enemy_ids) do local id=tonumber(idstr); if (id and ids[id]) or enemy_name_matches(b.name,terms) then add_bucket_to_filtered(d,b); used=true end end
        elseif not any_ids then
            for name,b in pairs(a.enemy or {}) do if enemy_name_matches(name,terms) then add_bucket_to_filtered(d,b); used=true end end
        end
        if used then out.actors[key]=d end
    end
    return out
end

local function selected_source()
    local raw=split_view and session_source_for_split() or current_source()
    local split=split_source(raw)
    return enemy_filtered_source(split)
end

local function scope_ids(source)
    local party=refresh_party(Core.now()); local ids={}
    if not source then return ids,party end
    local self_name=party.self_id and party.by_id[party.self_id] and Core.lower(party.by_id[party.self_id].name) or nil
    local custom={}; for _,name in ipairs(settings.custom_players or {}) do custom[Core.lower(name)]=true end
    for id,a in pairs(source.actors or {}) do
        if a and a.actor_type~='enemy' and a.actor_type~='pet' then
            local t=a.actor_type or 'unknown'
            local allowed=(t~='trust' or settings.include_trusts~=false) and ((t~='fellow' and t~='allied_npc') or settings.include_allied_npcs~=false)
            local scope=a.session_scope or 'outside'; local name=Core.lower(a.name)
            if allowed and ((settings.scope=='self' and self_name and name==self_name)
                or (settings.scope=='party' and (scope=='self' or scope=='party'))
                or (settings.scope=='alliance' and scope~='outside')
                or (settings.scope=='custom' and custom[name])) then ids[id]=true end
        end
    end
    return ids,party
end

local function performance_sort(rows,party)
    local order={}; for i,id in ipairs(party.order or {}) do order[id]=i end
    table.sort(rows,function(a,b)
        local function ratio(hit,attempt) attempt=tonumber(attempt) or 0; return attempt>0 and (tonumber(hit) or 0)/attempt or -1 end
        if settings.sort=='damage' or settings.sort=='dps' then return combined_damage(a)>combined_damage(b)
        elseif settings.sort=='melee' then return net(a.melee,a.dheal_melee)>net(b.melee,b.dheal_melee)
        elseif settings.sort=='accuracy' or settings.sort=='acc' then return ratio(a.melee_hits,a.melee_attempts)>ratio(b.melee_hits,b.melee_attempts)
        elseif settings.sort=='ranged' then return net(a.ranged,a.dheal_ranged)>net(b.ranged,b.dheal_ranged)
        elseif settings.sort=='racc' then return ratio(a.ranged_hits,a.ranged_attempts)>ratio(b.ranged_hits,b.ranged_attempts)
        elseif settings.sort=='ws' then return net(a.ws_damage,a.dheal_ws)>net(b.ws_damage,b.dheal_ws)
        elseif settings.sort=='wsacc' then return ratio(a.ws_hits,a.ws_attempts)>ratio(b.ws_hits,b.ws_attempts)
        elseif settings.sort=='wsavg' then return (avg(a.ws_mm) or 0)>(avg(b.ws_mm) or 0)
        elseif settings.sort=='sc' then return net(a.skillchain,a.dheal_skillchain)>net(b.skillchain,b.dheal_skillchain)
        elseif settings.sort=='magic' then return ((a.magic or 0)-(a.dheal_magic or 0)-(a.dheal_enspell or 0))>((b.magic or 0)-(b.dheal_magic or 0)-(b.dheal_enspell or 0))
        elseif settings.sort=='pet' then return pet_net_damage(a)>pet_net_damage(b)
        elseif settings.sort=='healing' then return (a.healing+(a.pet and a.pet.healing or 0))>(b.healing+(b.pet and b.pet.healing or 0))
        elseif settings.sort=='cleanse' or settings.sort=='cleanses' then return (a.cleanses or 0)>(b.cleanses or 0)
        elseif settings.sort=='dispel' or settings.sort=='dispels' then return (a.dispels or 0)>(b.dispels or 0)
        elseif settings.sort=='taken' then return a.taken>b.taken end
        return (order[a.id] or tonumber(a.session_order) or 999)<(order[b.id] or tonumber(b.session_order) or 999)
    end)
end

local function apply_pins(rows,party)
    local by_name={}; for _,a in ipairs(rows) do by_name[Core.lower(a.name)]=a end
    local fixed,soft,ordinary={}, {}, {}
    local used={}
    for name,slot in pairs(settings.pins or {}) do
        local a=by_name[Core.lower(name)]
        if a and tonumber(slot) then fixed[math.max(1,math.floor(tonumber(slot)))]=a; used[a]=true end
    end
    local self_actor=party.self_id and party.by_id[party.self_id] and by_name[Core.lower(party.by_id[party.self_id].name)] or nil
    if settings.self_pin~=false and self_actor and not used[self_actor] then soft[#soft+1]=self_actor; used[self_actor]=true end
    for _,a in ipairs(rows) do
        local pin=settings.pins and settings.pins[Core.lower(a.name)]
        if pin and not tonumber(pin) and not used[a] then soft[#soft+1]=a; used[a]=true end
    end
    -- Self remains first in the soft-pin group; all other unnumbered pins retain
    -- the already-computed performance order.
    for _,a in ipairs(rows) do if not used[a] then ordinary[#ordinary+1]=a end end
    local out={}; local si,oi=1,1; local total=#rows
    for slot=1,total do
        local a=fixed[slot]
        if not a then a=soft[si]; if a then si=si+1 end end
        if not a then a=ordinary[oi]; if a then oi=oi+1 end end
        if a then out[#out+1]=a end
    end
    -- Fixed slots beyond current row count still belong at the end.
    local extra={}; for slot,a in pairs(fixed) do if slot>total then extra[#extra+1]={slot=slot,a=a} end end
    table.sort(extra,function(x,y) return x.slot<y.slot end); for _,x in ipairs(extra) do out[#out+1]=x.a end
    return out
end

local function display_actors(source,expand)
    if not source then return {} end
    local ids,party=scope_ids(source); local rows={}
    for id in pairs(ids) do if source.actors[id] then rows[#rows+1]=source.actors[id] end end
    performance_sort(rows,party)
    rows=apply_pins(rows,party)
    if settings.scope=='alliance' then while #rows>(settings.alliance_limit or 18) do table.remove(rows) end end
    local row_limit=math.max(0,math.floor(tonumber(settings.row_limit) or 8))
    if not expand and row_limit>0 then while #rows>row_limit do table.remove(rows) end end
    return rows
end

local function elapsed_active(source,now)
    if not source then return 0,0 end
    now=now or Core.now()
    if source==current then update_shared_clock(current,now) end
    local elapsed=math.max(0,(source.ended or now)-(source.started or now))
    if source.activity then source.activity:tick(now) end
    local active=tonumber(source.active_committed)
    if active==nil then active=source.activity and source.activity:active_seconds(source.ended or now) or elapsed end
    return elapsed,math.max(0,active)
end

local function dps(actor,source,now)
    local _,active=elapsed_active(source,now); if active<=0 then return nil end; return player_net_damage(actor)/active
end
local function combined_dps(actor,source,now)
    local _,active=elapsed_active(source,now); if active<=0 then return nil end; return combined_damage(actor)/active
end
local function live_dps(actor,now)
    if not actor.damage_window:ready(settings.live_seconds,now) then return nil end; return actor.damage_window:sum(settings.live_seconds,now)/settings.live_seconds
end
local function ten_dps(actor,now)
    if not actor.damage_window:ready(settings.rolling_seconds,now) then return nil end; return actor.damage_window:sum(settings.rolling_seconds,now)/settings.rolling_seconds
end
local function hps(actor,source,now) local _,active=elapsed_active(source,now); if active<=0 then return nil end; return actor.healing/active end

local function dash(value,formatter)
    if value==nil then return '-' end
    return formatter and formatter(value) or tostring(value)
end
local function n(value) return Core.compact(value or 0) end
local function f1(value) return value and ('%.1f'):format(value) or '-' end
local function pct(hit,attempt) return Core.percent_text(hit,attempt,1) end

local MAX_SECTIONS={'general','melee','ws','sc','ranged','magic','pet','defense','healing','recovery'}
local function section_on(name)
    local only=settings.max_only or {}; local has_only=false; for _ in pairs(only) do has_only=true; break end
    if has_only then return only[name]==true end
    return not (settings.max_hidden and settings.max_hidden[name])
end

local ONE_HANDED_SKILLS={ [1]=true,[2]=true,[3]=true,[5]=true,[9]=true,[11]=true }
local TWO_HANDED_SKILLS={ [4]=true,[6]=true,[7]=true,[8]=true,[10]=true,[12]=true }
note_weapon_class_from_ws=function(actor,ws_id)
    local ws=res.weapon_skills and res.weapon_skills[tonumber(ws_id)] or nil
    local skill=tonumber(ws and ws.skill)
    if not actor or not skill then return end
    if ONE_HANDED_SKILLS[skill] then actor.weapon_class=(skill==1) and 'h2h' or '1h'
    elseif TWO_HANDED_SKILLS[skill] then actor.weapon_class='2h' end
end

local function accuracy_pair_text(attempts,hits,weapon_class)
    attempts=tonumber(attempts) or 0; hits=tonumber(hits) or 0
    if attempts<=0 then return '-' end
    local value=100*hits/attempts
    local text=('%.1f%%'):format(value)
    local min_attempts=tonumber(settings.accuracy_min_attempts) or 10
    if attempts<min_attempts then return text end
    local high=(weapon_class=='1h' or weapon_class=='h2h') and 96.5 or 93.5
    local yellow=(weapon_class=='1h' or weapon_class=='h2h') and 93.0 or 90.0
    if value>=high then return Core.color_text(text,96,255,96)
    elseif value>=yellow then return Core.color_text(text,255,215,0)
    else return Core.color_text(text,255,96,96) end
end
local function accuracy_text(actor,ranged)
    return accuracy_pair_text(ranged and actor.ranged_attempts or actor.melee_attempts,ranged and actor.ranged_hits or actor.melee_hits,ranged and '2h' or actor.weapon_class)
end

local function local_player_name()
    local p=windower.ffxi.get_player(); return p and p.name and Core.lower(p.name) or nil
end
local function hud_player_name(a)
    local name=a.name
    if local_player_name() and Core.lower(name)==local_player_name() then return Core.color_text(name,96,176,255) end
    return name
end

local LEADER_BLUE={96,176,255}
local function leader_text(text,value,leader,eligible)
    if settings.highlights==false or eligible==false then return text end
    value,leader=tonumber(value),tonumber(leader)
    if value==nil or leader==nil or leader<=0 then return text end
    local tolerance=math.max(0.000001,math.abs(leader)*0.0000001)
    if math.abs(value-leader)<=tolerance then return Core.color_text(text,LEADER_BLUE[1],LEADER_BLUE[2],LEADER_BLUE[3]) end
    return text
end

local function overview_leaders(actors,source,now,show_ranged,show_pet)
    local leaders={}
    local function take(key,value,eligible)
        value=tonumber(value)
        if eligible~=false and value~=nil and value>0 and (leaders[key]==nil or value>leaders[key]) then leaders[key]=value end
    end
    local total=0; for _,a in ipairs(actors or {}) do total=total+combined_damage(a) end
    for _,a in ipairs(actors or {}) do
        local dmg=combined_damage(a); local share=total~=0 and 100*dmg/total or nil
        local melee=net(a.melee,a.dheal_melee); local ws=net(a.ws_damage,a.dheal_ws); local sc=net(a.skillchain,a.dheal_skillchain); local magic=(tonumber(a.magic) or 0)-(tonumber(a.dheal_magic) or 0)-(tonumber(a.dheal_enspell) or 0)
        take('share',share); take('damage',dmg); take('dps',combined_dps(a,source,now)); take('melee',melee); take('melee_share',total~=0 and 100*melee/total or nil)
        if show_ranged then local r=net(a.ranged,a.dheal_ranged); take('ranged',r); take('ranged_share',total~=0 and 100*r/total or nil) end
        take('ws_damage',ws); take('ws_share',total~=0 and 100*ws/total or nil); take('ws_count',a.ws_attempts); take('ws_avg',avg(a.ws_mm),(a.ws_mm and a.ws_mm.count or 0)>=(tonumber(settings.highlight_ws_min) or 5))
        take('sc',sc); take('sc_share',total~=0 and 100*sc/total or nil); take('magic',magic); take('magic_share',total~=0 and 100*magic/total or nil); take('mb',net(a.mb_damage,a.dheal_mb))
        if show_pet then local pd=pet_net_damage(a); take('pet_damage',pd); take('pet_share',total~=0 and 100*pd/total or nil) end
    end
    return leaders,total
end

local function share_text(value,total)
    if not total or total==0 then return '-' end
    return ('%.1f%%'):format(100*(tonumber(value) or 0)/total)
end

local CATEGORY_ALIASES={
    physical='physical',melee='physical',attack='physical',
    magic='magic',magical='magic',spell='magic',spells='magic',
    mb='mb',['magic burst']='mb',['magic bursts']='mb',
    ranged='ranged',range='ranged',shoot='ranged',shooting='ranged',['ranged attack']='ranged',ra='ranged',
    healing='healing',heal='healing',cure='healing',curing='healing',waltz='healing',walz='healing',['curing waltz']='healing',
    recovery='recovery',status='recovery',cleanse='recovery',['status recovery']='recovery',['remove status']='recovery',['healing waltz']='recovery',
    defense='defense',def='defense',
    pet='pet',automaton='pet',wyvern='pet',jug='pet',avatar='pet',luopan='pet',
    ['pet physical']='pet_physical',['pet melee']='pet_physical',
    ['pet magic']='pet_magic',['pet magical']='pet_magic',
    ['pet ranged']='pet_ranged',['pet range']='pet_ranged',['pet shooting']='pet_ranged',
    ['pet healing']='pet_healing',['pet cure']='pet_healing',
    ws='ws',weaponskill='ws',['weapon skill']='ws',
    sc='sc',skillchain='sc',['skill chain']='sc',
    crit='crits',crits='crits',critical='crits',
}
local function normalize_category(value)
    value=Core.lower(tostring(value or '')):gsub('^%s+',''):gsub('%s+$',''):gsub('%s+',' ')
    return CATEGORY_ALIASES[value] or value
end
local function display_enabled(name)
    settings.display=settings.display or Core.deepcopy and Core.deepcopy(defaults.display) or defaults.display
    if name=='pet_physical' or name=='pet_magic' or name=='pet_ranged' or name=='pet_healing' then return settings.display.pet~=false end
    return settings.display[name]~=false
end
local function set_display_category(name,value)
    name=normalize_category(name); settings.display=settings.display or {}
    if name=='physical' then settings.display.physical=value; settings.display.ws=value; settings.display.sc=value
    elseif name=='magic' then settings.display.magic=value; settings.display.mb=value
    elseif name=='crits' then settings.columns.crits=value
    elseif defaults.display[name]~=nil then settings.display[name]=value
    elseif name=='pet_physical' or name=='pet_magic' or name=='pet_ranged' or name=='pet_healing' then settings.display.pet=value
    else return false end
    return true
end
local function display_status_text()
    local out={}
    for _,k in ipairs({'physical','ws','sc','magic','mb','ranged','pet','healing','recovery','defense'}) do if display_enabled(k) then out[#out+1]=Core.display_word(k) end end
    return #out>0 and table.concat(out,', ') or 'None'
end

local function hud_overview(source,actors,now)
    -- Dynamic keeps a stable core and caps itself at 18 visible columns.
    -- Text identity columns are left-aligned; quantitative fields are right-aligned.
    local total=0
    for _,a in ipairs(actors or {}) do total=total+combined_damage(a) end
    local headers={'#','Player','Tot Dmg%','Tot Dmg','DPS'}
    local aligns={'right','left','right','right','right'}
    local fields={'rank','player','share','damage','dps'}
    local function add(key,label)
        if #headers>=18 then return false end
        fields[#fields+1]=key; headers[#headers+1]=label; aligns[#aligns+1]='right'; return true
    end
    if display_enabled('physical') and enabled_filter('melee') then add('melee','Melee'); add('acc','Acc') end
    if display_enabled('ws') and enabled_filter('ws') then
        add('ws_damage','WS Dmg'); add('ws_share','WS Dmg%'); add('ws_hm','WS H/M'); add('ws_acc','WS Acc'); add('ws_avg','WS Avg')
    end
    if display_enabled('sc') and enabled_filter('sc') then add('sc_count','SC#'); add('sc_damage','SC Dmg'); add('sc_share','SC Dmg%') end
    -- Magic is a normal Dynamic column by default. It disappears only when the
    -- user hides/removes Magic or excludes Magic from the active calculation.
    if display_enabled('magic') and enabled_filter('magic') then add('magic','Magic Dmg') end

    local candidates={}
    local function candidate(key,label,score,enabled)
        if enabled and math.abs(tonumber(score) or 0)>0 then candidates[#candidates+1]={key=key,label=label,score=math.abs(score)} end
    end
    local sums={ranged=0,pet=0,mb=0,crit=0}
    for _,a in ipairs(actors or {}) do
        sums.ranged=sums.ranged+(enabled_filter('ranged') and math.abs(net(a.ranged,a.dheal_ranged)) or 0)
        sums.pet=sums.pet+(enabled_filter('pet') and math.abs(pet_net_damage(a)) or 0)
        sums.mb=sums.mb+(enabled_filter('magic') and math.abs(net(a.mb_damage,a.dheal_mb)) or 0)
        sums.crit=sums.crit+(tonumber(a.melee_crit) or 0)
    end
    candidate('ranged','Ranged Dmg',sums.ranged,display_enabled('ranged') and settings.columns.ranged~=false and enabled_filter('ranged'))
    candidate('pet','Pet Dmg',sums.pet,display_enabled('pet') and settings.columns.pet~=false and enabled_filter('pet'))
    candidate('mb','MB Dmg',sums.mb,display_enabled('magic') and display_enabled('mb') and enabled_filter('magic'))
    candidate('crit','Crit%',sums.crit,settings.columns.crits==true and display_enabled('physical') and enabled_filter('melee'))
    table.sort(candidates,function(a,b) if a.score==b.score then return a.label<b.label end return a.score>b.score end)
    while #headers<18 and #candidates>0 do local c=table.remove(candidates,1); add(c.key,c.label) end

    local rows={}
    local totals={damage=0,melee=0,melee_hits=0,melee_attempts=0,ws_damage=0,ws_hits=0,ws_misses=0,ws_attempts=0,sc_count=0,sc_damage=0,magic=0,ranged=0,pet=0,mb=0,crit=0}
    local function values_for(a,rank)
        local dmg=combined_damage(a); local share=total~=0 and 100*dmg/total or 0
        local melee=net(a.melee,a.dheal_melee); local ws=net(a.ws_damage,a.dheal_ws); local sc=net(a.skillchain,a.dheal_skillchain)
        local magic=(tonumber(a.magic) or 0)-(tonumber(a.dheal_magic) or 0)-(tonumber(a.dheal_enspell) or 0)
        local vals={rank=rank,player=hud_player_name(a),share=('%.1f%%'):format(share),damage=n(dmg),dps=dash(combined_dps(a,source,now),n),
            melee=n(melee),acc=accuracy_text(a,false),ws_damage=n(ws),ws_share=share_text(ws,total),
            ws_hm=('%d/%d'):format(tonumber(a.ws_hits) or 0,tonumber(a.ws_misses) or 0),ws_acc=accuracy_pair_text(a.ws_attempts,a.ws_hits),ws_avg=dash(avg(a.ws_mm),n),
            sc_count=tostring(tonumber(a.skillchain_count) or 0),sc_damage=n(sc),sc_share=share_text(sc,total),magic=n(magic),
            ranged=n(net(a.ranged,a.dheal_ranged)),pet=n(pet_net_damage(a)),mb=n(net(a.mb_damage,a.dheal_mb)),
            crit=(tonumber(a.melee_hits) or 0)>0 and pct(a.melee_crit,a.melee_hits) or '-'}
        totals.damage=totals.damage+dmg; totals.melee=totals.melee+melee; totals.melee_hits=totals.melee_hits+(tonumber(a.melee_hits) or 0); totals.melee_attempts=totals.melee_attempts+(tonumber(a.melee_attempts) or 0)
        totals.ws_damage=totals.ws_damage+ws; totals.ws_hits=totals.ws_hits+(tonumber(a.ws_hits) or 0); totals.ws_misses=totals.ws_misses+(tonumber(a.ws_misses) or 0); totals.ws_attempts=totals.ws_attempts+(tonumber(a.ws_attempts) or 0)
        totals.sc_count=totals.sc_count+(tonumber(a.skillchain_count) or 0); totals.sc_damage=totals.sc_damage+sc; totals.magic=totals.magic+magic; totals.ranged=totals.ranged+net(a.ranged,a.dheal_ranged); totals.pet=totals.pet+pet_net_damage(a); totals.mb=totals.mb+net(a.mb_damage,a.dheal_mb); totals.crit=totals.crit+(tonumber(a.melee_crit) or 0)
        local row={}; for _,k in ipairs(fields) do row[#row+1]=vals[k] or '-' end; return row
    end
    for i,a in ipairs(actors or {}) do rows[#rows+1]=values_for(a,i) end
    if #actors>0 then
        local _,active=elapsed_active(source,now); local represented_share=total~=0 and 100*totals.damage/total or 0
        local tv={rank='',player='TOTAL',share=('%.1f%%'):format(represented_share),damage=n(totals.damage),dps=active>0 and n(totals.damage/active) or '-',
            melee=n(totals.melee),acc=accuracy_pair_text(totals.melee_attempts,totals.melee_hits),ws_damage=n(totals.ws_damage),ws_share=share_text(totals.ws_damage,total),
            ws_hm=('%d/%d'):format(totals.ws_hits,totals.ws_misses),ws_acc=accuracy_pair_text(totals.ws_attempts,totals.ws_hits),ws_avg=totals.ws_hits>0 and n(totals.ws_damage/totals.ws_hits) or '-',
            sc_count=tostring(totals.sc_count),sc_damage=n(totals.sc_damage),sc_share=share_text(totals.sc_damage,total),magic=n(totals.magic),ranged=n(totals.ranged),pet=n(totals.pet),mb=n(totals.mb),crit=totals.melee_hits>0 and pct(totals.crit,totals.melee_hits) or '-'}
        local row={}; for _,k in ipairs(fields) do row[#row+1]=tv[k] or '-' end; rows[#rows+1]=row
    end
    return format_parse_dynamic(headers,rows,aligns,{gap=1,min_widths={1,6,7,7,4}})
end

local function hud_compact(source,actors,now)
    local magic_threshold=tonumber(settings.compact_magic_threshold) or 0.03
    local pet_threshold=tonumber(settings.compact_pet_threshold) or 0.03
    local show_magic,show_pet=false,false
    for _,a in ipairs(actors or {}) do
        local atotal=math.abs(combined_damage(a)); if atotal>0 then
            local magic=math.abs((tonumber(a.magic) or 0)-(tonumber(a.dheal_magic) or 0)-(tonumber(a.dheal_enspell) or 0))
            local pet=math.abs(pet_net_damage(a))
            if display_enabled('magic') and enabled_filter('magic') and magic/atotal>=magic_threshold then show_magic=true end
            if display_enabled('pet') and enabled_filter('pet') and pet/atotal>=pet_threshold then show_pet=true end
        end
    end
    local headers={'#','Player','Tot Dmg','DPS','Acc','WS H/M','WS Avg','SC Dmg'}
    local aligns={'right','left','right','right','right','right','right','right'}
    if show_magic then headers[#headers+1]='Magic Dmg'; aligns[#aligns+1]='right' end
    if show_pet then headers[#headers+1]='Pet Dmg'; aligns[#aligns+1]='right' end
    local rows={}; local t={dmg=0,hits=0,att=0,wsh=0,wsm=0,wsa=0,wsd=0,sc=0,magic=0,pet=0}
    for i,a in ipairs(actors or {}) do
        local dmg=combined_damage(a); local magic=(tonumber(a.magic) or 0)-(tonumber(a.dheal_magic) or 0)-(tonumber(a.dheal_enspell) or 0); local pet=pet_net_damage(a)
        local row={tostring(i),hud_player_name(a),n(dmg),dash(combined_dps(a,source,now),n),accuracy_text(a,false),('%d/%d'):format(tonumber(a.ws_hits) or 0,tonumber(a.ws_misses) or 0),dash(avg(a.ws_mm),n),n(net(a.skillchain,a.dheal_skillchain))}
        if show_magic then row[#row+1]=n(magic) end; if show_pet then row[#row+1]=n(pet) end; rows[#rows+1]=row
        t.dmg=t.dmg+dmg; t.hits=t.hits+(tonumber(a.melee_hits) or 0); t.att=t.att+(tonumber(a.melee_attempts) or 0); t.wsh=t.wsh+(tonumber(a.ws_hits) or 0); t.wsm=t.wsm+(tonumber(a.ws_misses) or 0); t.wsa=t.wsa+(tonumber(a.ws_attempts) or 0); t.wsd=t.wsd+net(a.ws_damage,a.dheal_ws); t.sc=t.sc+net(a.skillchain,a.dheal_skillchain); t.magic=t.magic+magic; t.pet=t.pet+pet
    end
    if #actors>0 then
        local _,active=elapsed_active(source,now); local row={'','TOTAL',n(t.dmg),active>0 and n(t.dmg/active) or '-',accuracy_pair_text(t.att,t.hits),('%d/%d'):format(t.wsh,t.wsm),t.wsh>0 and n(t.wsd/t.wsh) or '-',n(t.sc)}
        if show_magic then row[#row+1]=n(t.magic) end; if show_pet then row[#row+1]=n(t.pet) end; rows[#rows+1]=row
    end
    return format_parse_dynamic(headers,rows,aligns,{gap=1,min_widths={1,6,7,4,5,5,6,6}})
end

local function hud_ws(source,actors,full)
    local lines={Core.format_row({'Player','WS','Att','Hit','Miss','Acc','Low','Avg','Peak','Total'}, {13,20,5,5,5,7,8,8,8,10},{'left','left','right','right','right','right','right','right','right','right'})}
    for _,a in ipairs(actors) do
        lines[#lines+1]=Core.format_row({a.name,'ALL',a.ws_attempts,a.ws_hits,a.ws_misses,pct(a.ws_hits,a.ws_attempts),dash(a.ws_mm.low,n),dash(avg(a.ws_mm),n),dash(a.ws_mm.peak,n),n(a.ws_damage)}, {13,20,5,5,5,7,8,8,8,10},{'left','left','right','right','right','right','right','right','right','right'})
        if full then
            local list={}; for name,w in pairs(a.ws) do list[#list+1]={name=name,w=w} end; table.sort(list,function(x,y) return x.w.damage>y.w.damage end)
            for _,entry in ipairs(list) do local w=entry.w; lines[#lines+1]=Core.format_row({'','  '..entry.name,w.attempts,w.hits,w.misses,pct(w.hits,w.attempts),dash(w.mm.low,n),dash(avg(w.mm),n),dash(w.mm.peak,n),n(w.damage)}, {13,20,5,5,5,7,8,8,8,10},{'left','left','right','right','right','right','right','right','right','right'}) end
        end
    end
    return lines
end

local function spell_success_pct(sp)
    -- Land% is intentionally limited to confirmed land vs explicit resist.
    -- No Effect remains a separate outcome because it is not necessarily an
    -- accuracy failure. This is an observed outcome rate, never Magic Accuracy.
    local lands=tonumber(sp and sp.lands) or 0
    local resists=tonumber(sp and sp.resists) or 0
    local attempts=lands+resists
    return attempts>0 and pct(lands,attempts) or '-'
end

local function hud_magic(source,actors,full)
    local widths={13,20,5,5,5,5,5,7,9,8,8,8,5,9,8,8,5,9,8,8,9}
    local aligns={'left','left','right','right','right','right','right','right','right','right','right','right','right','right','right','right','right','right','right','right','right'}
    local lines={Core.format_row({'Player','Spell','Cast','Tgt','Land','Res','NoEf','Land%','Dmg','Low','Avg','Peak','MB#','MB Dmg','MBAvg','MBPk','N#','N Dmg','NAvg','NPk','Heal'},widths,aligns)}
    for _,a in ipairs(actors) do
        local aggregate={casts=a.magic_casts,targets=a.magic_targets,lands=a.magic_lands,resists=a.magic_resists,no_effect=a.magic_no_effect}
        lines[#lines+1]=Core.format_row({a.name,'ALL',a.magic_casts>0 and a.magic_casts or '-',a.magic_targets>0 and a.magic_targets or '-',a.magic_targets>0 and a.magic_lands or '-',a.magic_targets>0 and a.magic_resists or '-',a.magic_targets>0 and a.magic_no_effect or '-',spell_success_pct(aggregate),a.magic_damage>0 and n(a.magic_damage) or '-',dash(a.magic_mm.low,n),dash(avg(a.magic_mm),n),dash(a.magic_mm.peak,n),a.mb_count>0 and a.mb_count or '-',a.mb_damage>0 and n(a.mb_damage) or '-',dash(avg(a.mb_mm),n),dash(a.mb_mm.peak,n),a.nonmb_count>0 and a.nonmb_count or '-',a.nonmb_damage>0 and n(a.nonmb_damage) or '-',dash(avg(a.nonmb_mm),n),dash(a.nonmb_mm.peak,n),a.magic_healing>0 and n(a.magic_healing) or '-'},widths,aligns)
        if full then
            local list={}
            for name,sp in pairs(a.spells or {}) do list[#list+1]={name=name,sp=sp} end
            table.sort(list,function(x,y)
                local xd=(x.sp.damage or 0)+(x.sp.healing or 0); local yd=(y.sp.damage or 0)+(y.sp.healing or 0)
                if xd==yd then return (x.sp.casts or 0)>(y.sp.casts or 0) end
                return xd>yd
            end)
            for _,entry in ipairs(list) do
                local sp=entry.sp
                lines[#lines+1]=Core.format_row({'','  '..entry.name,sp.casts>0 and sp.casts or '-',sp.targets>0 and sp.targets or '-',sp.targets>0 and sp.lands or '-',sp.targets>0 and sp.resists or '-',sp.targets>0 and sp.no_effect or '-',spell_success_pct(sp),sp.damage>0 and n(sp.damage) or '-',dash(sp.damage_mm.low,n),dash(avg(sp.damage_mm),n),dash(sp.damage_mm.peak,n),sp.mb_hits>0 and sp.mb_hits or '-',sp.mb_damage>0 and n(sp.mb_damage) or '-',dash(avg(sp.mb_mm),n),dash(sp.mb_mm.peak,n),sp.nonmb_hits>0 and sp.nonmb_hits or '-',sp.nonmb_damage>0 and n(sp.nonmb_damage) or '-',dash(avg(sp.nonmb_mm),n),dash(sp.nonmb_mm.peak,n),sp.healing>0 and n(sp.healing) or '-'},widths,aligns)
            end
        end
    end
    return lines
end

local function hud_defense(source,actors)
    local lines={Core.format_row({'Player','Taken','Phys','Magic','Other','Hits','AvgHit','Low','Peak','Evd','Par','Blk','KO'}, {14,9,8,8,8,6,8,8,8,5,5,5,4},{'left','right','right','right','right','right','right','right','right','right','right','right','right'})}
    for _,a in ipairs(actors) do lines[#lines+1]=Core.format_row({a.name,n(a.taken),n(a.taken_physical),n(a.taken_magical),n(a.taken_other+a.taken_unknown),a.taken_hits,dash(avg(a.taken_mm),n),dash(a.taken_mm.low,n),dash(a.taken_mm.peak,n),a.evades,a.parries,a.blocks,a.deaths}, {14,9,8,8,8,6,8,8,8,5,5,5,4},{'left','right','right','right','right','right','right','right','right','right','right','right','right'}) end
    return lines
end

local function hud_healing(source,actors,now)
    local total_taken,total_recv,total_mp=0,0,0; for _,a in ipairs(actors) do total_taken=total_taken+a.taken; total_recv=total_recv+a.received; total_mp=total_mp+a.cure_mp_received end
    local widths={14,9,7,10,8,9,8,8,9,9,7,7,8,8,9,8,8}
    local aligns={'left','right','right','right','right','right','right','right','right','right','right','right','right','right','right','right','right'}
    local lines={Core.format_row({'Player','Taken','Dmg%','Cure R\'cvd','Recv%','MP Load','Burden','Cured','Self Cure','Cleanse','Dispel','Aspir','HPS','Cure#','CureAvg','Peak','HP/MP'},widths,aligns)}
    for _,a in ipairs(actors) do
        local dmgload=total_taken>0 and a.taken/total_taken or nil; local recvload=total_recv>0 and a.received/total_recv or nil; local mpload=total_mp>0 and a.cure_mp_received/total_mp or nil; local burden=dmgload and dmgload>0 and mpload and mpload/dmgload or nil; local hpmp=a.mp_spent>0 and a.healing/a.mp_spent or nil
        lines[#lines+1]=Core.format_row({a.name,n(a.taken),dmgload and ('%.1f%%'):format(dmgload*100) or '-',n(a.received),recvload and ('%.1f%%'):format(recvload*100) or '-',mpload and ('%.1f%%'):format(mpload*100) or '-',burden and ('%.2f'):format(burden) or '-',n(a.healing),n(a.self_healing or 0),a.cleanses or 0,a.dispels or 0,n(a.aspir_recovery or 0),dash(hps(a,source,now),n),a.cures or 0,dash(avg(a.cure_mm),n),dash(a.cure_mm.peak,n),hpmp and ('%.1f'):format(hpmp) or '-'},widths,aligns)
    end
    return lines
end

local function hud_pet(source,actors,now)
    local headers={'Player','Master','P.Dmg','P.Dmg%','Combined','Melee','Acc','Ranged','R.Acc','Phys','Magic','SC','MB','Cured','Taken'}
    local aligns={'left','right','right','right','right','right','right','right','right','right','right','right','right','right','right'}
    local rows={}; local grand=0; for _,a in ipairs(actors) do grand=grand+combined_damage(a) end
    for _,a in ipairs(actors) do
        local p=a.pet; local master=player_net_damage(a); local pd=pet_net_damage(a); local combined=master+pd; local pphys=tonumber(p.physical) or 0; if pphys==0 then pphys=tonumber(p.ws) or 0 end
        rows[#rows+1]={hud_player_name(a),n(master),n(pd),grand~=0 and ('%.1f%%'):format(100*pd/grand) or '-',n(combined),n(net(p.melee,p.dheal_melee)),accuracy_pair_text(p.melee_attempts,p.melee_hits),n(net(p.ranged,p.dheal_ranged)),accuracy_pair_text(p.ranged_attempts,p.ranged_hits),n(net(pphys,p.dheal_physical)),n((tonumber(p.magic) or 0)-(tonumber(p.dheal_magic) or 0)-(tonumber(p.dheal_enspell) or 0)),n(net(p.skillchain,p.dheal_skillchain)),n(net(p.mb_damage,p.dheal_mb)),n(p.healing or 0),n(p.taken or 0)}
    end
    return format_parse_dynamic(headers,rows,aligns,{gap=3,min_widths={6,6,5,6,8}})
end

local function hud_max(source,actors,now)
    local cols,widths,aligns={'Player'},{14},{'left'}
    local rows={}; for i,a in ipairs(actors) do rows[i]={a.name} end
    local function section(names,ws,vals)
        for i,name in ipairs(names) do cols[#cols+1]=name; widths[#widths+1]=ws[i] or 8; aligns[#aligns+1]='right' end
        for r,a in ipairs(actors) do local v=vals(a); for _,x in ipairs(v) do rows[r][#rows[r]+1]=x end end
    end
    if section_on('general') then section({'Dmg','D.Heal','Live','Avg','10m'},{9,8,8,8,8},function(a) return {n(combined_damage(a)),total_dheal(a)>0 and n(total_dheal(a)) or '-',dash(live_dps(a,now),n),dash(combined_dps(a,source,now),n),dash(ten_dps(a,now),n)} end) end
    if section_on('melee') then section({'Melee','Att','Hit','Miss','Acc','Low','Avg','Peak','Crit','C.Avg','C.Peak'},{9,6,6,6,7,8,8,8,7,8,8},function(a) return {a.melee>0 and n(a.melee) or '-',a.melee_attempts>0 and a.melee_attempts or '-',a.melee_attempts>0 and a.melee_hits or '-',a.melee_attempts>0 and a.melee_misses or '-',a.melee_attempts>0 and pct(a.melee_hits,a.melee_attempts) or '-',dash(a.melee_mm.low,n),dash(avg(a.melee_mm),n),dash(a.melee_mm.peak,n),a.melee_hits>0 and pct(a.melee_crit,a.melee_hits) or '-',dash(avg(a.crit_mm),n),dash(a.crit_mm.peak,n)} end) end
    if section_on('ws') then section({'WS','Att','Hit','Miss','WS%','Low','Avg','Peak'},{9,5,5,5,7,8,8,8},function(a) return {a.ws_damage>0 and n(a.ws_damage) or '-',a.ws_attempts>0 and a.ws_attempts or '-',a.ws_attempts>0 and a.ws_hits or '-',a.ws_attempts>0 and a.ws_misses or '-',a.ws_attempts>0 and pct(a.ws_hits,a.ws_attempts) or '-',dash(a.ws_mm.low,n),dash(avg(a.ws_mm),n),dash(a.ws_mm.peak,n)} end) end
    if section_on('sc') then section({'SC'},{8},function(a) return {a.skillchain>0 and n(a.skillchain) or '-'} end) end
    if section_on('ranged') then section({'Rng','Shot','Hit','Miss','RAcc','Low','Avg','Peak','RCrit'},{9,6,6,6,7,8,8,8,7},function(a) return {a.ranged>0 and n(a.ranged) or '-',a.ranged_attempts>0 and a.ranged_attempts or '-',a.ranged_attempts>0 and a.ranged_hits or '-',a.ranged_attempts>0 and a.ranged_misses or '-',a.ranged_attempts>0 and pct(a.ranged_hits,a.ranged_attempts) or '-',dash(a.ranged_mm.low,n),dash(avg(a.ranged_mm),n),dash(a.ranged_mm.peak,n),a.ranged_hits>0 and pct(a.ranged_crit,a.ranged_hits) or '-'} end) end
    if section_on('magic') then section({'Magic','Cast','Tgt','Land','Res','NoEf','Land%','Low','Avg','Peak','MB','MB#','MBAvg','MBPk','NMB','N#','NAvg','NPk','MHeal','Ensp'},{9,6,6,6,6,6,7,8,8,8,9,6,8,8,9,6,8,8,9,8},function(a) return {a.magic>0 and n((tonumber(a.magic) or 0)-(tonumber(a.dheal_magic) or 0)-(tonumber(a.dheal_enspell) or 0)) or '-',a.magic_casts>0 and a.magic_casts or '-',a.magic_targets>0 and a.magic_targets or '-',a.magic_targets>0 and a.magic_lands or '-',a.magic_targets>0 and a.magic_resists or '-',a.magic_targets>0 and a.magic_no_effect or '-',((a.magic_lands or 0)+(a.magic_resists or 0))>0 and pct(a.magic_lands,(a.magic_lands or 0)+(a.magic_resists or 0)) or '-',dash(a.magic_mm.low,n),dash(avg(a.magic_mm),n),dash(a.magic_mm.peak,n),a.mb_damage>0 and n(a.mb_damage) or '-',a.mb_count>0 and a.mb_count or '-',dash(avg(a.mb_mm),n),dash(a.mb_mm.peak,n),a.nonmb_damage>0 and n(a.nonmb_damage) or '-',a.nonmb_count>0 and a.nonmb_count or '-',dash(avg(a.nonmb_mm),n),dash(a.nonmb_mm.peak,n),a.magic_healing>0 and n(a.magic_healing) or '-',a.enspell>0 and n(a.enspell) or '-'} end) end
    if section_on('pet') then section({'P.Dmg','Melee','Acc','Ranged','R.Acc','Phys','Magic','SC','MB','Heal','Taken'},{9,9,7,9,7,9,9,8,8,9,9},function(a) local p=a.pet; local ph=tonumber(p.physical) or 0; if ph==0 then ph=tonumber(p.ws) or 0 end; return {n(pet_net_damage(a)),n(net(p.melee,p.dheal_melee)),accuracy_pair_text(p.melee_attempts,p.melee_hits),n(net(p.ranged,p.dheal_ranged)),accuracy_pair_text(p.ranged_attempts,p.ranged_hits),n(net(ph,p.dheal_physical)),n((tonumber(p.magic) or 0)-(tonumber(p.dheal_magic) or 0)-(tonumber(p.dheal_enspell) or 0)),n(net(p.skillchain,p.dheal_skillchain)),n(net(p.mb_damage,p.dheal_mb)),n(p.healing or 0),n(p.taken or 0)} end) end
    if section_on('defense') then section({'Taken','Phys','MagicT','Other','Hits','LowHit','AvgHit','PeakHit','Evd','Par','Blk','KO'},{9,8,8,8,6,8,8,8,5,5,5,4},function(a) return {n(a.taken),a.taken_physical>0 and n(a.taken_physical) or '-',a.taken_magical>0 and n(a.taken_magical) or '-',(a.taken_other+a.taken_unknown)>0 and n(a.taken_other+a.taken_unknown) or '-',a.taken_hits>0 and a.taken_hits or '-',dash(a.taken_mm.low,n),dash(avg(a.taken_mm),n),dash(a.taken_mm.peak,n),a.evades,a.parries,a.blocks,a.deaths} end) end
    if section_on('healing') then section({'Cured','HPS','Cure#','Cure Rcvd','Self Cure','CureLow','CureAvg','CurePk','MP','HP/MP'},{9,8,6,9,9,8,8,8,8,8},function(a) return {a.healing>0 and n(a.healing) or '-',dash(hps(a,source,now),n),a.cures>0 and a.cures or '-',a.received>0 and n(a.received) or '-',a.self_healing>0 and n(a.self_healing) or '-',dash(a.cure_mm.low,n),dash(avg(a.cure_mm),n),dash(a.cure_mm.peak,n),a.mp_spent>0 and n(a.mp_spent) or '-',a.mp_spent>0 and ('%.1f'):format(a.healing/a.mp_spent) or '-'} end) end
    if section_on('recovery') then section({'Status','Dispel','Aspir'},{7,7,8},function(a) return {a.cleanses>0 and a.cleanses or '-',a.dispels>0 and a.dispels or '-',a.aspir_recovery>0 and n(a.aspir_recovery) or '-'} end) end
    local lines={Core.format_row(cols,widths,aligns)}; for _,r in ipairs(rows) do lines[#lines+1]=Core.format_row(r,widths,aligns) end; return lines
end

local function target_hp_color(text,hpp)
    hpp=tonumber(hpp) or 100
    if hpp<=5 then return Core.color_text(text,255,64,64)
    elseif hpp<=25 then return Core.color_text(text,255,150,40)
    elseif hpp<=50 then return Core.color_text(text,255,215,0)
    elseif hpp<=75 then return Core.color_text(text,180,235,90)
    else return Core.color_text(text,96,255,96) end
end

local function observe_target_learning(mob)
    if not mob or not mob.id or not current then return end
    local hpp=tonumber(mob.hpp); if hpp==nil then return end
    local zone=(windower.ffxi.get_info() or {}).zone
    local life,new_life=refresh_target_life(mob)
    if not life then return end
    local dealt=tonumber(current.target_damage and current.target_damage[mob.id]) or 0
    local state=target_learning[mob.id]
    if not state or new_life or tonumber(state.generation)~=tonumber(life.generation) then
        state={name=mob.name,zone=zone,first_hpp=hpp,last_hpp=hpp,last_damage=dealt,generation=life.generation}
        target_learning[mob.id]=state
        return
    end
    local dh=(tonumber(state.last_hpp) or hpp)-hpp; local dd=dealt-(tonumber(state.last_damage) or dealt)
    if dh>=2 and dd>0 then
        local estimate=dd*100/dh
        if estimate>=1000 and estimate<=1000000000000 then enemy_registry:observe(zone,mob.name,estimate,'low',{source='hpp_delta'}) end
    end
    if hpp<=0 and (tonumber(state.first_hpp) or 0)>=99 and dealt>0 then
        enemy_registry:observe(zone,mob.name,dealt,'medium',{source='full_observed_fight'})
    end
    state.last_hpp=hpp; state.last_damage=dealt
end

local function session_total_damage()
    local totals={}
    for key,a in pairs(session_actors or {}) do totals[key]=combined_damage(a) end
    if current then for _,a in pairs(current.actors or {}) do if a.actor_type~='enemy' and a.actor_type~='pet' then local key=session_key(a); totals[key]=(totals[key] or 0)+combined_damage(a) end end end
    local total=0; for _,v in pairs(totals) do total=total+(tonumber(v) or 0) end; return total
end

local function target_header(source,actors)
    if settings.target_hp=='off' or not source then return nil end
    local mob=windower.ffxi.get_mob_by_target and (windower.ffxi.get_mob_by_target('t') or windower.ffxi.get_mob_by_target('bt')) or nil
    if not mob or not mob.id or refresh_party(Core.now()).by_id[mob.id] then last_target_id=nil; return nil end
    local hpp=tonumber(mob.hpp)
    refresh_target_life(mob)
    observe_target_learning(mob)
    last_target_id=mob.id
    local target_damage=current and current.target_damage and tonumber(current.target_damage[mob.id]) or 0
    local total=session_total_damage()
    local zone=(windower.ffxi.get_info() or {}).zone; local known=enemy_registry:lookup(zone,mob.name)
    local hptext
    local learned_ok=known and known.max_hp_source=='learned' and (known.confidence=='medium' or known.confidence=='high' or known.confidence=='verified')
    local static_ok=known and known.max_hp_source and known.max_hp_source~='learned'
    if hpp and known and tonumber(known.max_hp) and (learned_ok or static_ok) then
        local maxhp=tonumber(known.max_hp); local currenthp=maxhp*Core.clamp(hpp,0,100)/100
        -- Enemy HPP is percentage-based, so current HP is an estimate even when
        -- the registry max HP is authoritative.
        hptext=target_hp_color(('~%s/%s (%d%%)'):format(n(currenthp),n(maxhp),math.max(0,math.min(100,math.floor(hpp+0.5)))),hpp)
    else
        hptext=hpp and target_hp_color(('%d%%'):format(math.max(0,math.min(100,math.floor(hpp+0.5)))),hpp) or '?'
    end
    return ('Target: %s | %s | Dmg Dealt: %s | Total Dmg: %s'):format(mob.name or tostring(mob.id),hptext,n(target_damage),n(total))
end

local function start_from_engagement(now)
    if current then return false end
    local party=refresh_party(now)
    for _,id in ipairs(party.order or {}) do
        local e=party.by_id[id]; local mob=e and (e.mob or Core.mob(windower,id))
        if mob and (mob.status==1 or Core.lower(mob.status)=='engaged') then
            local target_id=tonumber(mob.target_id or 0) or 0
            local target_index=tonumber(mob.target_index or 0) or 0
            local target=target_id~=0 and Core.mob(windower,target_id) or nil
            if not target and target_index~=0 and windower.ffxi.get_mob_by_index then target=windower.ffxi.get_mob_by_index(target_index) end
            if not target and id==party.self_id and windower.ffxi.get_mob_by_target then target=windower.ffxi.get_mob_by_target('bt') end
            if target and target.id and not select(1,allied_relation(target.id,party)) then
                local enc=ensure_encounter(now,true); if enc then mark_enemy(enc,target.id); session_activity:mark(now); session_last_event=now; return true end
            end
        end
    end
    return false
end

local function parsing_scope_text()
    local names=parse_filter_terms()
    local ids=parse_filter_ids()
    local shown={}
    for _,name in ipairs(names) do shown[#shown+1]=name end
    for id in pairs(ids) do
        local mob=Core.mob(windower,id)
        shown[#shown+1]=(mob and mob.name) or ('Target '..tostring(id))
    end
    if #shown==0 then return 'All' end
    return table.concat(shown,', ')
end

local function view_display_name(value)
    local names={
        dynamic='Dynamic', overview='Dynamic', compact='Compact',
        physical='Physical', ranged='Ranged', combo='Combo',
        ['magic-overall']='Magic', ['magic-full']='Magic Full', magic='Magic',
        defense='Defense', healing='Cure', pet='Pet',
        ['ws-overall']='WS', ['ws-full']='WS Full', ws='WS',
        max='Combo',
    }
    return names[value] or Core.display_word(value)
end

local function update_hud(force)
    local now=Core.now(); if not force and now-last_hud_update<0.20 then return end; last_hud_update=now
    if not current then start_from_engagement(now) end
    if current then
        local active=update_shared_clock(current,now)
        local live=encounter_has_live_enemy(current)
        if encounter_defeated(current) then
            finalize_encounter(now)
        elseif not live and not active and current.last_hostile and (now-current.last_hostile)>=settings.encounter_timeout then
            finalize_encounter(now)
        end
    end
    local source=selected_source(); local actors=display_actors(source); local lines={}
    local elapsed,active=elapsed_active(source,now)
    local context=''
    if split_view then
        local sp=(split_view=='current') and active_split or find_split(tostring(split_view))
        context=sp and (' | Split: '..sp.name) or ' | Split'
    elseif settings.period and settings.period~='session' then
        context=' | '..Core.display_word(settings.period)
    end
    local title=('VanaParse | %s | %s%s | Elapsed %s | Active %s'):format(
        settings.scope:upper(),view_display_name(settings.view),context,Core.duration(elapsed),Core.duration(active))
    lines[#lines+1]=title
    local th=target_header(source,actors); if th then lines[#lines+1]=th end
    lines[#lines+1]='Parsing: '..parsing_scope_text()
    if source then
        local other,total=0,0; for _,a in ipairs(actors or {}) do other=other+math.abs(net(a.other,a.dheal_other)); total=total+math.abs(combined_damage(a)) end
        if other>=10000 and total>0 and other/total>=0.02 then lines[#lines+1]=Core.color_text(('Audit: Unclassified/Other damage %s (%.1f%%)'):format(n(other),100*other/total),255,150,40) end
    end
    if not source then lines[#lines+1]='No combat encounter yet.'
    elseif settings.view=='ws' or settings.view=='ws-overall' then local x=hud_ws(source,actors,false); for _,l in ipairs(x) do lines[#lines+1]=l end
    elseif settings.view=='ws-full' then local x=hud_ws(source,actors,true); for _,l in ipairs(x) do lines[#lines+1]=l end
    elseif settings.view=='magic' or settings.view=='magic-overall' then local x=hud_magic(source,actors,false); for _,l in ipairs(x) do lines[#lines+1]=l end
    elseif settings.view=='magic-full' then local x=hud_magic(source,actors,true); for _,l in ipairs(x) do lines[#lines+1]=l end
    elseif settings.view=='defense' then local x=hud_defense(source,actors); for _,l in ipairs(x) do lines[#lines+1]=l end
    elseif settings.view=='healing' then local x=hud_healing(source,actors,now); for _,l in ipairs(x) do lines[#lines+1]=l end
    elseif settings.view=='pet' then local x=hud_pet(source,actors,now); for _,l in ipairs(x) do lines[#lines+1]=l end
    elseif settings.view=='max' or settings.view=='combo' then local x=hud_max(source,actors,now); for _,l in ipairs(x) do lines[#lines+1]=l end
    elseif settings.view=='physical' then
        local old_only=settings.max_only; settings.max_only={general=true,melee=true,ws=true,sc=true}; local x=hud_max(source,actors,now); settings.max_only=old_only; for _,l in ipairs(x) do lines[#lines+1]=l end
    elseif settings.view=='ranged' then
        local old_only=settings.max_only; settings.max_only={general=true,ranged=true,ws=true,sc=true}; local x=hud_max(source,actors,now); settings.max_only=old_only; for _,l in ipairs(x) do lines[#lines+1]=l end
    elseif settings.view=='compact' then local x=hud_compact(source,actors,now); for _,l in ipairs(x) do lines[#lines+1]=l end
    else local x=hud_overview(source,actors,now); for _,l in ipairs(x) do lines[#lines+1]=l end end
    if settings.paused then lines[#lines+1]='PAUSED' end
    hud:text(table.concat(lines,'\n'))
end

local function plain_text(value)
    return tostring(value or ''):gsub('\\cs%b()',''):gsub('\\cr',''):gsub(';',',')
end

local function send_game_line(destination,line,tell_name)
    line=plain_text(line)
    local cmd=nil
    if destination=='p' or destination=='party' then cmd='/p '
    elseif destination=='a' or destination=='alliance' then cmd='/a '
    elseif destination=='l' or destination=='l1' or destination=='linkshell' then cmd='/l '
    elseif destination=='l2' or destination=='linkshell2' then cmd='/l2 '
    elseif destination=='s' or destination=='say' then cmd='/s '
    elseif destination=='y' or destination=='yell' then cmd='/yell '
    elseif destination=='t' or destination=='tell' then if tell_name and tell_name~='' then cmd='/t '..tell_name..' ' end end
    if cmd then report_queue[#report_queue+1]='input '..cmd..line; return true end
    return false
end

local function process_report_queue(now)
    now=now or Core.now(); if #report_queue==0 or now<report_next_at then return end
    local command=table.remove(report_queue,1); windower.send_command(command); report_next_at=now+(tonumber(settings.report_delay) or 0.65)
end

local Report={}
Report.DESTINATIONS={
    p='party',party='party',a='alliance',alliance='alliance',
    l='linkshell',l1='linkshell',linkshell='linkshell',
    l2='linkshell2',linkshell2='linkshell2',
    s='say',say='say',y='yell',yell='yell',
    t='tell',tell='tell',['local']='local',console='local',self='local',
}
Report.SCOPE_PHRASES={
    {'pet','physical','pet_physical'},{'pet','melee','pet_physical'},
    {'pet','magic','pet_magic'},{'pet','magical','pet_magic'},
    {'pet','ranged','pet_ranged'},{'pet','range','pet_ranged'},{'pet','shooting','pet_ranged'},
    {'pet','healing','pet_healing'},{'pet','cure','pet_healing'},
    {'magic','burst','mb'},{'magic','bursts','mb'},
    {'status','recovery','recovery'},{'remove','status','recovery'},
    {'healing','waltz','recovery'},{'curing','waltz','healing'},
    {'ranged','attack','ranged'},{'weapon','skill','ws'},
}
Report.SCOPE_SINGLE={
    full='full',dps='dps',damage='dps',dmg='dps',offense='dps',
    physical='physical',melee='physical',attack='physical',
    magic='magic',magical='magic',spell='magic',spells='magic',mb='mb',
    ranged='ranged',range='ranged',shoot='ranged',shooting='ranged',ra='ranged',
    healing='healing',heal='healing',cure='healing',curing='healing',waltz='healing',
    recovery='recovery',status='recovery',cleanse='recovery',
    defense='defense',def='defense',pet='pet',automaton='pet',wyvern='pet',jug='pet',avatar='pet',
    percent='percent',percentage='percent',percentages='percent',['%']='percent',
    performance='performance',perform='performance',stat='performance',stats='performance',
    ws='ws',weaponskill='ws',sc='sc',skillchain='sc',
}

local function report_emit(destination,tell_name,line)
    if destination=='local' or not destination then chat(207,line); return true end
    return send_game_line(destination,line,tell_name)
end
local function report_element_name(id)
    local e=res.elements and res.elements[tonumber(id)] or nil
    return e and (e.en or e.name) or nil
end
local function report_skill_name(id)
    local e=res.skills and res.skills[tonumber(id)] or nil
    return e and (e.en or e.name) or nil
end
local function spell_meta_text(sp)
    local out={}; local e=report_element_name(sp and sp.element); local sk=report_skill_name(sp and sp.skill)
    if e then out[#out+1]=e end; if sk then out[#out+1]=sk end
    if sp and sp.spell_type~=nil then out[#out+1]=tostring(sp.spell_type) end
    return #out>0 and table.concat(out,'/') or nil
end
function Report.report_scope_label()
    if split_view then local sp=(split_view=='current') and active_split or find_split(tostring(split_view)); return sp and ('Split '..sp.name) or 'Split' end
    if settings.period and settings.period~='session' then return Core.display_word(settings.period) end
    return 'Full Parse'
end
function Report.find_actor(source,name)
    if not source or not name or name=='' then return nil end
    local wanted=Core.lower(name); local exact=nil; local partial={}
    for _,a in ipairs(display_actors(source,true)) do
        local low=Core.lower(a.name or '')
        if low==wanted then exact=a break end
        if low:find(wanted,1,true) then partial[#partial+1]=a end
    end
    if exact then return exact end
    if #partial==1 then return partial[1] end
    return nil
end
function Report.report_actors(source,show_all,actor_name)
    if actor_name and actor_name~='' then local a=Report.find_actor(source,actor_name); return a and {a} or {} end
    local actors=display_actors(source,true); local limit=show_all and #actors or math.min(#actors,9)
    while #actors>limit do table.remove(actors) end; return actors
end
function Report.offense_values(a)
    local melee=enabled_filter('melee') and net(a.melee,a.dheal_melee) or 0
    local ranged=enabled_filter('ranged') and net(a.ranged,a.dheal_ranged) or 0
    local ws=enabled_filter('ws') and net(a.ws_damage,a.dheal_ws) or 0
    local sc=enabled_filter('sc') and net(a.skillchain,a.dheal_skillchain) or 0
    local magic=enabled_filter('magic') and ((tonumber(a.magic) or 0)-(tonumber(a.dheal_magic) or 0)-(tonumber(a.dheal_enspell) or 0)) or 0
    local pet=enabled_filter('pet') and pet_net_damage(a) or 0
    return melee,ranged,ws,sc,magic,pet
end
function Report.report_denominator(source)
    local total=0; for _,a in ipairs(display_actors(source,true)) do total=total+combined_damage(a) end; return total
end
function Report.header(destination,tell_name,scope,source,count,actor_name)
    local _,active=elapsed_active(source,Core.now())
    local who=actor_name and (' | Player: '..actor_name) or ''
    report_emit(destination,tell_name,('VP %s | %s | Parsing: %s%s | Active %s | Actors %d'):format(view_display_name(settings.view),Report.report_scope_label(),parsing_scope_text(),who,Core.duration(active),count or 0))
end
local function report_significant(value,total,exhaustive)
    value=math.abs(tonumber(value) or 0); if value==0 then return false end; if exhaustive then return true end
    total=math.abs(tonumber(total) or 0); return total==0 or value/total>=0.01
end
function Report.percent(destination,tell_name,actors,source)
    local denom=Report.report_denominator(source); local share_sum=0
    for i,a in ipairs(actors) do
        local dmg=combined_damage(a); local _,ranged,ws,sc,magic,pet=Report.offense_values(a); local share=denom~=0 and 100*dmg/denom or 0; share_sum=share_sum+share
        local parts={('#%d %s'):format(i,a.name),('Tot %.1f%%'):format(share),('WS %.1f%%'):format(denom~=0 and 100*ws/denom or 0),('SC %.1f%%'):format(denom~=0 and 100*sc/denom or 0)}
        if display_enabled('magic') and magic~=0 then parts[#parts+1]=('Magic %.1f%%'):format(denom~=0 and 100*magic/denom or 0) end
        if display_enabled('ranged') and ranged~=0 then parts[#parts+1]=('Ranged %.1f%%'):format(denom~=0 and 100*ranged/denom or 0) end
        if display_enabled('pet') and pet~=0 then parts[#parts+1]=('Pet %.1f%%'):format(denom~=0 and 100*pet/denom or 0) end
        report_emit(destination,tell_name,table.concat(parts,' | '))
    end
    report_emit(destination,tell_name,('Represented Share %.1f%% | Avg Share %.1f%%'):format(share_sum,#actors>0 and share_sum/#actors or 0))
end
function Report.physical(destination,tell_name,actors,source,extra_mode)
    local denom=Report.report_denominator(source); local t={dmg=0,melee=0,hits=0,att=0,ws=0,wsh=0,wsm=0,wsa=0,sc=0,scc=0}
    for i,a in ipairs(actors) do
        local dmg=combined_damage(a); local melee,ranged,ws,sc,magic,pet=Report.offense_values(a); local share=denom~=0 and 100*dmg/denom or 0
        report_emit(destination,tell_name,('#%d %s | Tot Dmg%% %.1f%% | Tot Dmg %s | DPS %s | Melee %s | Acc %s'):format(i,a.name,share,n(dmg),dash(combined_dps(a,source,Core.now()),n),n(melee),accuracy_text(a,false)))
        report_emit(destination,tell_name,('WS Dmg %s | WS Dmg%% %.1f%% | WS H/M %d/%d | WS Acc %s | WS Avg %s | SC# %d | SC Dmg %s | SC Dmg%% %.1f%%'):format(n(ws),denom~=0 and 100*ws/denom or 0,tonumber(a.ws_hits) or 0,tonumber(a.ws_misses) or 0,pct(a.ws_hits,a.ws_attempts),dash(avg(a.ws_mm),n),tonumber(a.skillchain_count) or 0,n(sc),denom~=0 and 100*sc/denom or 0))
        if extra_mode then
            local extra={}
            if display_enabled('magic') and enabled_filter('magic') and magic~=0 then extra[#extra+1]='Magic '..n(magic) end
            if display_enabled('mb') and display_enabled('magic') and net(a.mb_damage,a.dheal_mb)~=0 then extra[#extra+1]='MB Dmg '..n(net(a.mb_damage,a.dheal_mb)) end
            if display_enabled('ranged') and ranged~=0 then extra[#extra+1]='Ranged '..n(ranged)..' | RAcc '..accuracy_text(a,true) end
            if display_enabled('pet') and pet~=0 then extra[#extra+1]='Pet '..n(pet) end
            if extra_mode=='full' and display_enabled('healing') and (tonumber(a.healing) or 0)>0 then extra[#extra+1]='Cured '..n(a.healing) end
            if extra_mode=='full' and display_enabled('recovery') and ((tonumber(a.cleanses) or 0)>0 or (tonumber(a.dispels) or 0)>0) then extra[#extra+1]=('Recovery %d | Dispel %d'):format(tonumber(a.cleanses) or 0,tonumber(a.dispels) or 0) end
            if extra_mode=='full' and display_enabled('defense') and (tonumber(a.taken) or 0)>0 then extra[#extra+1]='Taken '..n(a.taken) end
            if #extra>0 then report_emit(destination,tell_name,table.concat(extra,' | ')) end
        end
        t.dmg=t.dmg+dmg; t.melee=t.melee+melee; t.hits=t.hits+(tonumber(a.melee_hits) or 0); t.att=t.att+(tonumber(a.melee_attempts) or 0); t.ws=t.ws+ws; t.wsh=t.wsh+(tonumber(a.ws_hits) or 0); t.wsm=t.wsm+(tonumber(a.ws_misses) or 0); t.wsa=t.wsa+(tonumber(a.ws_attempts) or 0); t.sc=t.sc+sc; t.scc=t.scc+(tonumber(a.skillchain_count) or 0)
    end
    local _,active=elapsed_active(source,Core.now())
    report_emit(destination,tell_name,('TOTAL | Dmg %s | DPS %s | Acc %s | WS %s | WS Acc %s | WS Avg %s | SC# %d | SC %s'):format(n(t.dmg),active>0 and n(t.dmg/active) or '-',accuracy_pair_text(t.att,t.hits),n(t.ws),accuracy_pair_text(t.wsa,t.wsh),t.wsh>0 and n(t.ws/t.wsh) or '-',t.scc,n(t.sc)))
end
function Report.ws(destination,tell_name,actors,source,detailed)
    local denom=Report.report_denominator(source); local total_damage,total_hits,total_misses,total_attempts=0,0,0,0
    for i,a in ipairs(actors) do
        local ws=enabled_filter('ws') and net(a.ws_damage,a.dheal_ws) or 0
        local attempts=tonumber(a.ws_attempts) or 0; local hits=tonumber(a.ws_hits) or 0; local misses=tonumber(a.ws_misses) or 0
        if ws~=0 or attempts>0 then
            report_emit(destination,tell_name,('#%d %s | WS Dmg %s | WS Dmg%% %.1f%% | H/M %d/%d | Acc %s | Avg %s'):format(i,a.name,n(ws),denom~=0 and 100*ws/denom or 0,hits,misses,pct(hits,attempts),dash(avg(a.ws_mm),n)))
            if detailed then
                local list={}; for name,w in pairs(a.ws or {}) do if (tonumber(w.attempts) or 0)>0 then list[#list+1]={name=name,w=w} end end
                table.sort(list,function(x,y) return (tonumber(x.w.damage) or 0)>(tonumber(y.w.damage) or 0) end)
                for _,e in ipairs(list) do local w=e.w; report_emit(destination,tell_name,('  %s | Use %d | Dmg %s | Avg %s | H/M %d/%d | Acc %s'):format(e.name,tonumber(w.attempts) or 0,n(w.damage or 0),dash(avg(w.mm),n),tonumber(w.hits) or 0,tonumber(w.misses) or 0,pct(w.hits,w.attempts))) end
            end
        end
        total_damage=total_damage+ws; total_hits=total_hits+hits; total_misses=total_misses+misses; total_attempts=total_attempts+attempts
    end
    report_emit(destination,tell_name,('TOTAL WS | Dmg %s | Dmg%% %.1f%% | H/M %d/%d | Acc %s | Avg %s'):format(n(total_damage),denom~=0 and 100*total_damage/denom or 0,total_hits,total_misses,accuracy_pair_text(total_attempts,total_hits),total_hits>0 and n(total_damage/total_hits) or '-'))
end
function Report.sc(destination,tell_name,actors,source)
    local denom=Report.report_denominator(source); local total_damage,total_count=0,0
    for i,a in ipairs(actors) do
        local damage=enabled_filter('sc') and net(a.skillchain,a.dheal_skillchain) or 0; local count=tonumber(a.skillchain_count) or 0
        if damage~=0 or count>0 then report_emit(destination,tell_name,('#%d %s | SC# %d | SC Dmg %s | SC Dmg%% %.1f%% | Avg %s'):format(i,a.name,count,n(damage),denom~=0 and 100*damage/denom or 0,count>0 and n(damage/count) or '-')) end
        total_damage=total_damage+damage; total_count=total_count+count
    end
    report_emit(destination,tell_name,('TOTAL SC | SC# %d | Dmg %s | Dmg%% %.1f%% | Avg %s'):format(total_count,n(total_damage),denom~=0 and 100*total_damage/denom or 0,total_count>0 and n(total_damage/total_count) or '-'))
end

function Report.magic(destination,tell_name,actors,source,detailed)
    local total=0
    for i,a in ipairs(actors) do
        local _,_,_,_,magic=Report.offense_values(a); total=total+magic
        if magic~=0 or (tonumber(a.magic_casts) or 0)>0 then
            report_emit(destination,tell_name,('#%d %s | Magic %s | Cast %d | Land/Res %d/%d | MB Cast %d | MB Dmg %s | Avg %s'):format(i,a.name,n(magic),tonumber(a.magic_casts) or 0,tonumber(a.magic_lands) or 0,tonumber(a.magic_resists) or 0,tonumber(a.mb_casts) or 0,n(a.mb_damage or 0),dash(avg(a.magic_mm),n)))
            if detailed then
                local list={}; for name,sp in pairs(a.spells or {}) do if (tonumber(sp.casts) or 0)>0 then list[#list+1]={name=name,sp=sp} end end
                table.sort(list,function(x,y) return (tonumber(x.sp.damage) or 0)>(tonumber(y.sp.damage) or 0) end)
                for _,e in ipairs(list) do local sp=e.sp; local meta=spell_meta_text(sp); report_emit(destination,tell_name,('  %s | Cast %d | Dmg %s | Avg %s | MB %d/%s%s'):format(e.name,tonumber(sp.casts) or 0,n(sp.damage or 0),dash(avg(sp.damage_mm),n),tonumber(sp.mb_hits) or 0,n(sp.mb_damage or 0),meta and (' | '..meta) or '')) end
            end
        end
    end
    report_emit(destination,tell_name,'TOTAL Magic '..n(total))
end
function Report.mb(destination,tell_name,actors,source)
    local total_hits,total_damage=0,0
    for _,a in ipairs(actors) do
        if (tonumber(a.mb_count) or 0)>0 or (tonumber(a.mb_damage) or 0)>0 then
            report_emit(destination,tell_name,('%s | MB Casts %d | MB Hits %d | MB Dmg %s | Avg %s'):format(a.name,tonumber(a.mb_casts) or 0,tonumber(a.mb_count) or 0,n(a.mb_damage or 0),dash(avg(a.mb_mm),n)))
            local list={}; for name,sp in pairs(a.spells or {}) do if (tonumber(sp.mb_hits) or 0)>0 then list[#list+1]={name=name,sp=sp} end end
            table.sort(list,function(x,y) return (tonumber(x.sp.mb_damage) or 0)>(tonumber(y.sp.mb_damage) or 0) end)
            for _,e in ipairs(list) do local sp=e.sp; local meta=spell_meta_text(sp); report_emit(destination,tell_name,('  %s (%d) Avg %s | Dmg %s%s'):format(e.name,tonumber(sp.mb_hits) or 0,dash(avg(sp.mb_mm),n),n(sp.mb_damage or 0),meta and (' | '..meta) or '')) end
            total_hits=total_hits+(tonumber(a.mb_count) or 0); total_damage=total_damage+(tonumber(a.mb_damage) or 0)
        end
    end
    report_emit(destination,tell_name,('TOTAL MB | Hits %d | Dmg %s | Avg %s'):format(total_hits,n(total_damage),total_hits>0 and n(total_damage/total_hits) or '-'))
end
function Report.ranged(destination,tell_name,actors,source)
    local total,hits,att=0,0,0
    for i,a in ipairs(actors) do local value=net(a.ranged,a.dheal_ranged); total=total+value; hits=hits+(tonumber(a.ranged_hits) or 0); att=att+(tonumber(a.ranged_attempts) or 0); report_emit(destination,tell_name,('#%d %s | Ranged %s | RAcc %s | H/M %d/%d | Avg %s'):format(i,a.name,n(value),accuracy_text(a,true),tonumber(a.ranged_hits) or 0,tonumber(a.ranged_misses) or 0,dash(avg(a.ranged_mm),n))) end
    report_emit(destination,tell_name,('TOTAL Ranged %s | Acc %s'):format(n(total),accuracy_pair_text(att,hits)))
end
function Report.healing(destination,tell_name,actors,source)
    local cured,received=0,0
    for i,a in ipairs(actors) do if (tonumber(a.healing) or 0)>0 or (tonumber(a.received) or 0)>0 then report_emit(destination,tell_name,('#%d %s | Cured %s | Cure Rcvd %s | Self %s | Cure# %d | Avg %s'):format(i,a.name,n(a.healing),n(a.received),n(a.self_healing),tonumber(a.cures) or 0,dash(avg(a.cure_mm),n))) end; cured=cured+(tonumber(a.healing) or 0); received=received+(tonumber(a.received) or 0) end
    report_emit(destination,tell_name,('TOTAL Healing | Cured %s | Cure Rcvd %s'):format(n(cured),n(received)))
end
function Report.recovery(destination,tell_name,actors,source)
    local cleanses,dispels=0,0
    for i,a in ipairs(actors) do
        if (tonumber(a.cleanses) or 0)>0 or (tonumber(a.dispels) or 0)>0 then
            local actions={}; for name,count in pairs(a.cleanse_actions or {}) do actions[#actions+1]=name..' '..tostring(count) end; for name,count in pairs(a.dispel_actions or {}) do actions[#actions+1]=name..' '..tostring(count) end; table.sort(actions)
            report_emit(destination,tell_name,('#%d %s | Recovery %d | Dispel %d%s'):format(i,a.name,tonumber(a.cleanses) or 0,tonumber(a.dispels) or 0,#actions>0 and (' | '..table.concat(actions,', ')) or ''))
        end
        cleanses=cleanses+(tonumber(a.cleanses) or 0); dispels=dispels+(tonumber(a.dispels) or 0)
    end
    report_emit(destination,tell_name,('TOTAL Recovery %d | Dispel %d'):format(cleanses,dispels))
end
function Report.defense(destination,tell_name,actors,source)
    local taken,hits,evades,parries,blocks,deaths=0,0,0,0,0,0
    for i,a in ipairs(actors) do report_emit(destination,tell_name,('#%d %s | Taken %s | Phys %s | Magic %s | Hits %d | AvgHit %s | Evd %d | Par %d | Blk %d | KO %d'):format(i,a.name,n(a.taken),n(a.taken_physical),n(a.taken_magical),tonumber(a.taken_hits) or 0,dash(avg(a.taken_mm),n),tonumber(a.evades) or 0,tonumber(a.parries) or 0,tonumber(a.blocks) or 0,tonumber(a.deaths) or 0)); taken=taken+(tonumber(a.taken) or 0); hits=hits+(tonumber(a.taken_hits) or 0); evades=evades+(tonumber(a.evades) or 0); parries=parries+(tonumber(a.parries) or 0); blocks=blocks+(tonumber(a.blocks) or 0); deaths=deaths+(tonumber(a.deaths) or 0) end
    report_emit(destination,tell_name,('TOTAL Defense | Taken %s | Hits %d | AvgHit %s | Evd %d | Par %d | Blk %d | KO %d'):format(n(taken),hits,hits>0 and n(taken/hits) or '-',evades,parries,blocks,deaths))
end
function Report.pet(destination,tell_name,actors,source,subtype)
    local total=0
    for i,a in ipairs(actors) do local p=a.pet or {}; local value=0; local label='Pet'
        if subtype=='pet_physical' then value=net(p.melee,p.dheal_melee)+net((tonumber(p.physical) or tonumber(p.ws) or 0),p.dheal_physical); label='Pet Physical'
        elseif subtype=='pet_magic' then value=(tonumber(p.magic) or 0)-(tonumber(p.dheal_magic) or 0)-(tonumber(p.dheal_enspell) or 0); label='Pet Magic'
        elseif subtype=='pet_ranged' then value=net(p.ranged,p.dheal_ranged); label='Pet Ranged'
        elseif subtype=='pet_healing' then value=tonumber(p.healing) or 0; label='Pet Healing'
        else value=pet_net_damage(a) end
        if value~=0 then report_emit(destination,tell_name,('#%d %s | %s %s'):format(i,a.name,label,n(value))) end; total=total+value
    end
    report_emit(destination,tell_name,('TOTAL %s %s'):format(Core.display_word((subtype or 'pet'):gsub('_',' ')),n(total)))
end
function Report.performance(destination,tell_name,a,source,exhaustive)
    local denom=Report.report_denominator(source); local dmg=combined_damage(a); local melee,ranged,ws,sc,magic,pet=Report.offense_values(a); local _,active=elapsed_active(source,Core.now())
    report_emit(destination,tell_name,('%s PERFORMANCE | Tot Dmg %s (%.1f%%) | DPS %s | Active %s'):format(a.name,n(dmg),denom~=0 and 100*dmg/denom or 0,dash(combined_dps(a,source,Core.now()),n),Core.duration(active)))
    if report_significant(melee,dmg,exhaustive) or (tonumber(a.melee_attempts) or 0)>0 then report_emit(destination,tell_name,('Physical | Melee %s | Acc %s | Crit %s'):format(n(melee),accuracy_text(a,false),(tonumber(a.melee_hits) or 0)>0 and pct(a.melee_crit,a.melee_hits) or '-')) end
    if report_significant(ws,dmg,exhaustive) or (tonumber(a.ws_attempts) or 0)>0 then report_emit(destination,tell_name,('WS | Dmg %s | H/M %d/%d | Acc %s | Avg %s | SC %d/%s'):format(n(ws),tonumber(a.ws_hits) or 0,tonumber(a.ws_misses) or 0,pct(a.ws_hits,a.ws_attempts),dash(avg(a.ws_mm),n),tonumber(a.skillchain_count) or 0,n(sc))) end
    if report_significant(ranged,dmg,exhaustive) then report_emit(destination,tell_name,('Ranged | Dmg %s | Acc %s | Avg %s'):format(n(ranged),accuracy_text(a,true),dash(avg(a.ranged_mm),n))) end
    if report_significant(magic,dmg,exhaustive) or (tonumber(a.magic_casts) or 0)>0 then report_emit(destination,tell_name,('Magic | Dmg %s | Cast %d | MB %d/%s | Avg %s'):format(n(magic),tonumber(a.magic_casts) or 0,tonumber(a.mb_count) or 0,n(a.mb_damage or 0),dash(avg(a.magic_mm),n))) end
    if report_significant(pet,dmg,exhaustive) then report_emit(destination,tell_name,('Pet | Dmg %s | Melee %s | Ranged %s | Magic %s | Heal %s'):format(n(pet),n(net(a.pet.melee,a.pet.dheal_melee)),n(net(a.pet.ranged,a.pet.dheal_ranged)),n((tonumber(a.pet.magic) or 0)-(tonumber(a.pet.dheal_magic) or 0)-(tonumber(a.pet.dheal_enspell) or 0)),n(a.pet.healing or 0))) end
    if (tonumber(a.healing) or 0)>0 then report_emit(destination,tell_name,('Healing | Cured %s | Cure Rcvd %s | Self %s | Cure# %d | Avg %s'):format(n(a.healing),n(a.received),n(a.self_healing),tonumber(a.cures) or 0,dash(avg(a.cure_mm),n))) end
    if (tonumber(a.cleanses) or 0)>0 or (tonumber(a.dispels) or 0)>0 then report_emit(destination,tell_name,('Recovery | Status %d | Dispel %d'):format(tonumber(a.cleanses) or 0,tonumber(a.dispels) or 0)) end
    if (tonumber(a.taken) or 0)>0 or (tonumber(a.evades) or 0)>0 or (tonumber(a.parries) or 0)>0 or (tonumber(a.blocks) or 0)>0 then report_emit(destination,tell_name,('Defense | Taken %s | AvgHit %s | Evd %d | Par %d | Blk %d | KO %d'):format(n(a.taken),dash(avg(a.taken_mm),n),tonumber(a.evades) or 0,tonumber(a.parries) or 0,tonumber(a.blocks) or 0,tonumber(a.deaths) or 0)) end
    if exhaustive then
        local wslist={}; for name,w in pairs(a.ws or {}) do if (tonumber(w.attempts) or 0)>0 then wslist[#wslist+1]={name=name,w=w} end end; table.sort(wslist,function(x,y) return (tonumber(x.w.damage) or 0)>(tonumber(y.w.damage) or 0) end)
        for _,e in ipairs(wslist) do report_emit(destination,tell_name,('  WS %s | %d use | Dmg %s | Avg %s | Acc %s'):format(e.name,tonumber(e.w.attempts) or 0,n(e.w.damage or 0),dash(avg(e.w.mm),n),pct(e.w.hits,e.w.attempts))) end
        local splist={}; for name,sp in pairs(a.spells or {}) do if (tonumber(sp.casts) or 0)>0 then splist[#splist+1]={name=name,sp=sp} end end; table.sort(splist,function(x,y) return (tonumber(x.sp.damage) or 0)>(tonumber(y.sp.damage) or 0) end)
        for _,e in ipairs(splist) do local sp=e.sp; local meta=spell_meta_text(sp); report_emit(destination,tell_name,('  Spell %s | Cast %d | Dmg %s | Avg %s | MB %d/%s%s'):format(e.name,tonumber(sp.casts) or 0,n(sp.damage or 0),dash(avg(sp.damage_mm),n),tonumber(sp.mb_hits) or 0,n(sp.mb_damage or 0),meta and (' | '..meta) or '')) end
        local acts={}; for name,count in pairs(a.cleanse_actions or {}) do acts[#acts+1]='Recovery '..name..' '..count end; for name,count in pairs(a.dispel_actions or {}) do acts[#acts+1]='Dispel '..name..' '..count end; table.sort(acts); for _,line in ipairs(acts) do report_emit(destination,tell_name,'  '..line) end
    end
end
function Report.parse_args(args)
    local tokens={}; for i=2,#args do tokens[#tokens+1]=args[i] end
    local destination,tell_name='local',nil
    local i=1
    while i<=#tokens do
        local low=Core.lower(tokens[i] or '')
        if Report.DESTINATIONS[low] then
            destination=Report.DESTINATIONS[low]
            table.remove(tokens,i)
            if destination=='tell' then if not tokens[i] then return nil,'Tell requires a player name.' end; tell_name=tokens[i]; table.remove(tokens,i) end
            break
        end
        i=i+1
    end
    local all_requested=false
    for j=#tokens,1,-1 do if Core.lower(tokens[j])=='all' then all_requested=true; table.remove(tokens,j) end end
    local scope,consumed=nil,0
    local low={}; for j,v in ipairs(tokens) do low[j]=Core.lower(v) end
    for _,p in ipairs(Report.SCOPE_PHRASES) do
        local count=#p-1; local ok=#low>=count
        if ok then for j=1,count do if low[j]~=p[j] then ok=false break end end end
        if ok then scope=p[#p]; consumed=count; break end
    end
    if not scope and low[1] and Report.SCOPE_SINGLE[low[1]] then scope=Report.SCOPE_SINGLE[low[1]]; consumed=1 end
    if not scope then if #tokens>0 then scope='performance'; consumed=0 else scope='full' end end
    local actor_parts={}; for j=consumed+1,#tokens do actor_parts[#actor_parts+1]=tokens[j] end
    local actor_name=#actor_parts>0 and table.concat(actor_parts,' ') or nil
    local exhaustive=(scope=='performance' and actor_name and all_requested) or false
    local show_all=(not exhaustive) and all_requested or false
    return {destination=destination,tell_name=tell_name,scope=scope,actor_name=actor_name,show_all=show_all,exhaustive=exhaustive},nil
end
function Report.send(args)
    local req,err=Report.parse_args(args); if err then chat(167,err); return end
    local source=selected_source(); if not source then chat(167,'No report data available.'); return end
    local actors=Report.report_actors(source,req.show_all,req.actor_name)
    if req.actor_name and #actors==0 then chat(167,'Player not found in selected parse: '..req.actor_name); return end
    if #actors==0 then chat(167,'No actors to report.'); return end
    Report.header(req.destination,req.tell_name,req.scope,source,#actors,req.actor_name)
    if req.scope=='percent' then Report.percent(req.destination,req.tell_name,actors,source)
    elseif req.scope=='full' then Report.physical(req.destination,req.tell_name,actors,source,'full')
    elseif req.scope=='dps' then Report.physical(req.destination,req.tell_name,actors,source,'dps')
    elseif req.scope=='physical' then Report.physical(req.destination,req.tell_name,actors,source,false)
    elseif req.scope=='ws' then Report.ws(req.destination,req.tell_name,actors,source,req.actor_name~=nil)
    elseif req.scope=='sc' then Report.sc(req.destination,req.tell_name,actors,source)
    elseif req.scope=='magic' then Report.magic(req.destination,req.tell_name,actors,source,req.actor_name~=nil)
    elseif req.scope=='mb' then Report.mb(req.destination,req.tell_name,actors,source)
    elseif req.scope=='ranged' then Report.ranged(req.destination,req.tell_name,actors,source)
    elseif req.scope=='healing' then Report.healing(req.destination,req.tell_name,actors,source)
    elseif req.scope=='recovery' then Report.recovery(req.destination,req.tell_name,actors,source)
    elseif req.scope=='defense' then Report.defense(req.destination,req.tell_name,actors,source)
    elseif req.scope=='pet' or req.scope=='pet_physical' or req.scope=='pet_magic' or req.scope=='pet_ranged' or req.scope=='pet_healing' then Report.pet(req.destination,req.tell_name,actors,source,req.scope)
    elseif req.scope=='performance' then for _,a in ipairs(actors) do Report.performance(req.destination,req.tell_name,a,source,req.exhaustive) end
    else Report.physical(req.destination,req.tell_name,actors,source,true) end
    if req.destination~='local' then chat(207,('Queued %s report to %s%s (%d actor%s, %.2fs delay).'):format(req.scope,req.destination,req.tell_name and (' '..req.tell_name) or '',#actors,#actors==1 and '' or 's',tonumber(settings.report_delay) or 0.65)) end
end

local function set_column(option,value)
    settings.columns=settings.columns or {}
    if option=='ranged' then settings.columns.ranged=value
    elseif option=='pet' then settings.columns.pet=value
    elseif option=='healing' then settings.columns.healing=value
    elseif option=='crits' then settings.columns.crits=value==true
    elseif option=='pet_types' then settings.columns.pet_types=value==true end
end

local FILTER_ALIASES={
    melee='melee',ranged='ranged',range='ranged',ws='ws',sc='sc',skillchain='sc',magic='magic',other='other',pet='pet',
    petmelee='pet_melee',['pet-melee']='pet_melee',pmelee='pet_melee',petranged='pet_ranged',['pet-ranged']='pet_ranged',pranged='pet_ranged',
    petphysical='pet_physical',['pet-physical']='pet_physical',pphys='pet_physical',petmagic='pet_magic',['pet-magic']='pet_magic',pmagic='pet_magic',
    petsc='pet_sc',['pet-sc']='pet_sc',psc='pet_sc',
}

local function set_view(value)
    value=Core.lower(value)
    local aliases={overview='dynamic',general='dynamic',dynamic='dynamic',physical='physical',melee='physical',combo='combo',ws='ws-overall',['ws-overall']='ws-overall',full='ws-full',['ws-full']='ws-full',ranged='ranged',range='ranged',magic='magic-overall',['magic-overall']='magic-overall',['magic-full']='magic-full',defense='defense',healing='healing',cure='healing',pet='pet',max='combo',compact='compact'}
    if aliases[value] then settings.view=aliases[value]; return true end; return false
end
local function set_scope(value)
    value=Core.lower(value); if value=='self' or value=='party' or value=='alliance' or value=='custom' then settings.scope=value; return true end; return false
end


local function apply_max_command(args)
    settings.view='max'
    local i=2
    local token=Core.lower(args[i])
    if token=='self' or token=='party' or token=='alliance' then
        settings.scope=token; i=i+1
        if token=='alliance' and tonumber(args[i]) then settings.alliance_limit=Core.clamp(math.floor(tonumber(args[i])),1,18); i=i+1 end
    elseif token=='player' and args[i+1] then
        settings.custom_players={args[i+1]}; settings.scope='custom'; i=i+2
    elseif token=='players' then
        settings.custom_players={}; settings.scope='custom'; i=i+1
        while i<=#args do
            local t=Core.lower(args[i]); if t=='ignore' or t=='only' or t=='clear' then break end
            settings.custom_players[#settings.custom_players+1]=args[i]; i=i+1
        end
    end
    local op=Core.lower(args[i])
    if op=='clear' then settings.max_hidden={}; settings.max_only={}
    elseif op=='ignore' then
        settings.max_hidden={}; settings.max_only={}
        for j=i+1,#args do settings.max_hidden[Core.lower(args[j])]=true end
    elseif op=='only' then
        settings.max_only={}; settings.max_hidden={}
        for j=i+1,#args do settings.max_only[Core.lower(args[j])]=true end
    end
end

local function help_line(text) chat(207,Core.humanize_command_text(text)) end
local function print_help()
    help_line('Pattern: //vp <action> <what> [player] [where]')
    help_line('HUD: show | hide | add | remove <hud | physical | ws | sc | magic | mb | ranged | pet | healing | recovery | defense>')
    help_line('Parse math: include | exclude <physical | ranged | ws | sc | magic | pet | pet physical | pet magic | pet ranged | trusts | allies | other | all>')
    help_line('Enemy scope: filter <enemy | current | damage type> | unfilter <enemy | current | all> | show filters')
    help_line('View: view <dynamic | compact | physical | magic | ranged | defense | combo | healing | pet | ws>')
    help_line('Report: report <full | dps | physical | magic | mb | ranged | healing | recovery | defense | pet [physical|magic|ranged|healing] | % | performance> [player] <party | alliance | linkshell | linkshell2 | say | yell | tell <name> | local> [all]')
    help_line('Player detail: performance <player> [all] | stat <player> [all]')
    help_line('Session: split [name] | unsplit | pause | continue | reset | clear | reload | show splits')
    help_line('Setup: set rows <1-18 | all | default> | set delay <seconds> | set scope <self|party|alliance|custom> | set size <5-36>')
    help_line('Other: sort <metric> | pin <player> [slot] | unpin <player | all> | show status | show pins')
end

local function all_damage_filters(value)
    for k in pairs(defaults.filters or {}) do settings.filters[k]=value==true end
end
local function filter_status_text()
    local cats={}; for k,v in pairs(settings.filters or {}) do if v then cats[#cats+1]=k end end; table.sort(cats)
    local terms=parse_filter_terms(); local ids=parse_filter_ids(); local idlist={}; for id in pairs(ids) do idlist[#idlist+1]=tostring(id) end; table.sort(idlist)
    return 'Damage: '..(#cats>0 and table.concat(cats,', ') or 'None')..' | Enemy: '..(#terms>0 and table.concat(terms,', ') or 'All')..(#idlist>0 and (' | Target IDs: '..table.concat(idlist,',')) or '')
end
local function add_enemy_filter_text(value)
    value=tostring(value or ''):gsub('^%s+',''):gsub('%s+$',''); if value=='' then return false end
    local terms=parse_filter_terms(); local low=Core.lower(value); for _,v in ipairs(terms) do if Core.lower(v)==low then return true end end
    terms[#terms+1]=value; save_filter_terms(terms); return true
end
local function remove_enemy_filter_text(value)
    local low=Core.lower(value or ''); local out={}; local removed=false
    for _,v in ipairs(parse_filter_terms()) do if Core.lower(v)==low then removed=true else out[#out+1]=v end end
    save_filter_terms(out); return removed
end
local function add_current_target_filter()
    local mob=windower.ffxi.get_mob_by_target and windower.ffxi.get_mob_by_target('t') or nil
    if not mob or not mob.id then chat(167,'No current target to filter.'); return false end
    local ids=parse_filter_ids(); ids[tonumber(mob.id)]=true; local out={}; for id in pairs(ids) do out[#out+1]=tostring(id) end; table.sort(out); settings.enemy_filter_ids=table.concat(out,',')
    chat(207,('Target filter added: %s [%s].'):format(mob.name or 'Target',tostring(mob.id))); return true
end
local function handle_filter_command(args,undo)
    local value=Core.join({select(2,unpack(args))},' '):gsub('^%s+',''):gsub('%s+$','')
    local token=Core.lower(value)
    if value=='' or token=='list' or token=='status' then chat(207,filter_status_text()); return end
    if undo and (token=='all' or token=='clear' or token=='reset') then settings.enemy_filter_text=''; settings.enemy_filter_ids=''; all_damage_filters(true); chat(207,'All filters cleared.'); return end
    if not undo and (token=='all' or token=='clear' or token=='reset') then settings.enemy_filter_text=''; settings.enemy_filter_ids=''; all_damage_filters(true); chat(207,'All filters cleared.'); return end
    local canonical=FILTER_ALIASES[token] or FILTER_ALIASES[token:gsub('%s+','')]
    if not canonical then
        local cat=normalize_category(value)
        canonical=FILTER_ALIASES[cat] or FILTER_ALIASES[cat:gsub('_','')]
        if cat=='physical' then canonical='melee' elseif cat=='pet_physical' then canonical='pet_physical' elseif cat=='pet_magic' then canonical='pet_magic' elseif cat=='pet_ranged' then canonical='pet_ranged' end
    end
    if canonical or normalize_category(value)=='physical' then
        local cat=normalize_category(value)
        if undo then all_damage_filters(true); chat(207,'Damage filter removed: '..Core.display_word(cat=='physical' and 'physical' or canonical))
        else
            all_damage_filters(false)
            if cat=='physical' then settings.filters.melee=true; settings.filters.ws=true; settings.filters.sc=true
            else settings.filters[canonical]=true; if canonical:find('^pet_') then settings.filters.pet=true end end
            chat(207,'Filtering damage: '..Core.display_word(cat=='physical' and 'physical' or canonical))
        end
        return
    end
    if token=='current' then
        if undo then settings.enemy_filter_ids=''; chat(207,'Current-target filter removed.') else add_current_target_filter() end
        return
    end
    if undo then
        if remove_enemy_filter_text(value) then chat(207,'Enemy filter removed: '..value) else chat(167,'Enemy filter not found: '..value) end
    else add_enemy_filter_text(value); chat(207,'Enemy filter added: '..value) end
end

local function full_reset(reason)
    local snap=current_source(); if snap then log_source('SESSION',snap,Core.now(),reason or 'manual-reset') end
    current=nil; last_fight=nil; history={}; session_actors={}; session_activity=Core.Activity.new(settings.active_timeout); session_active_committed=0; session_last_event=nil; session_started=Core.now(); forced_miss_windows={}; target_learning={}; target_lives={}; last_target_id=nil; splits={}; active_split=nil; split_counter=0; split_view=nil
end

local function split_label(sp,index)
    if not sp then return '-' end
    local src=sp.active and delta_source_from_snapshots(snapshot_source(session_source_for_split(),Core.now()),sp.baseline) or sp.source
    local active=src and source_active_value(src,Core.now()) or 0
    local total=0; for _,a in pairs(src and src.actors or {}) do if a.actor_type~='enemy' and a.actor_type~='pet' then total=total+combined_damage(a) end end
    return ('%d. %s | %s | Tot %s%s'):format(index or sp.id,sp.name,Core.duration(active),n(total),sp.active and ' | ACTIVE' or '')
end
local function handle_split_command(args)
    local sub=Core.lower(args[2] or '')
    if sub=='list' or sub=='status' then if #splits==0 then chat(207,'No splits.') else for i,sp in ipairs(splits) do chat(207,split_label(sp,i)) end end; return end
    if sub=='show' then local token=Core.join({select(3,unpack(args))},' '); local sp=find_split(token); if sp then split_view=sp.id; chat(207,'Showing split: '..sp.name) else chat(167,'Split not found.') end; return end
    if sub=='current' then if active_split then split_view=active_split.id; chat(207,'Showing current split: '..active_split.name) else chat(167,'No active split.') end; return end
    if sub=='delete' then local token=Core.join({select(3,unpack(args))},' '); local sp,index=find_split(token); if not sp then chat(167,'Split not found.'); return end; if sp==active_split then active_split=nil end; table.remove(splits,index); if split_view==sp.id then split_view=nil end; chat(207,'Split deleted: '..sp.name); return end
    if sub=='clear' then splits={}; active_split=nil; split_view=nil; chat(207,'Split history cleared.'); return end
    local name=Core.join({select(2,unpack(args))},' ')
    if name=='' then split_counter=split_counter+1; name='Split '..split_counter else split_counter=split_counter+1 end
    finish_active_split(Core.now())
    local raw=session_source_for_split(); local rec={id=split_counter,name=name,baseline=snapshot_source(raw,Core.now()),started_at=Core.now(),active=true}; splits[#splits+1]=rec; active_split=rec; split_view=rec.id
    chat(207,'Split started: '..name)
end

windower.register_event('action',function(act) Core.safe_call('action',process_action,on_error,act) end)
windower.register_event('prerender',function() Core.safe_call('report-queue',process_report_queue,on_error,Core.now()); Core.safe_call('prerender',update_hud,on_error,false) end)
windower.register_event('zone change',function() enemy_registry:save(); target_learning={}; target_lives={}; if current then finalize_encounter(Core.now()) end; log_source('SESSION',current_source(),Core.now(),'zone-change'); update_hud(true) end)
windower.register_event('load','login',function() party_cache=Core.party_snapshot(windower); party_cache_at=Core.now(); update_hud(true) end)

windower.register_event('addon command',function(...)
    local args={...}; local cmd=Core.lower(args[1] or 'help')
    if cmd=='help' or cmd=='?' then print_help(); return
    elseif cmd=='show' or cmd=='hide' or cmd=='add' or cmd=='remove' then
        local visible=(cmd=='show' or cmd=='add'); local subject=Core.join({select(2,unpack(args))},' '); local token=Core.lower(subject)
        if subject=='' or token=='hud' then settings.visible=visible; if visible then hud:show() else hud:hide() end
        elseif token=='status' and visible then chat(207,('VanaParse %s | Core %s | View %s | Parsing %s | HUD %s | Display %s'):format(_addon.version,Core.VERSION,view_display_name(settings.view),parsing_scope_text(),settings.visible and 'On' or 'Off',display_status_text()))
        elseif token=='filters' and visible then chat(207,filter_status_text())
        elseif token=='pins' and visible then local list={}; for name,slot in pairs(settings.pins or {}) do list[#list+1]=name..(tonumber(slot) and ('@'..slot) or '') end; table.sort(list); chat(207,'Pins: '..(#list>0 and table.concat(list,', ') or 'None'))
        elseif token=='splits' and visible then handle_split_command({'split','list'})
        elseif token=='target' then settings.target_hp=visible and 'auto' or 'off'; chat(207,'Target line '..(visible and 'On' or 'Off')..'.')
        elseif token=='highlights' then settings.highlights=visible; chat(207,'Highlights '..(visible and 'On' or 'Off')..'.')
        elseif set_display_category(subject,visible) then chat(207,(visible and 'Showing ' or 'Hiding ')..Core.display_word(normalize_category(subject))..'.')
        else chat(167,'Unknown HUD item: '..subject) end
    elseif cmd=='include' or cmd=='exclude' then
        local include=cmd=='include'; local subject=Core.join({select(2,unpack(args))},' '); local token=Core.lower(subject)
        if token=='trust' or token=='trusts' then settings.include_trusts=include; chat(207,(include and 'Included' or 'Excluded')..' Trust rows.')
        elseif token=='ally' or token=='allies' or token=='allied' or token=='allied npc' or token=='allied npcs' then settings.include_allied_npcs=include; chat(207,(include and 'Included' or 'Excluded')..' allied NPC rows.')
        elseif token=='all' then all_damage_filters(include); chat(207,(include and 'Included: ' or 'Excluded: ')..'all damage categories')
        else
            local cat=normalize_category(subject); local canonical=FILTER_ALIASES[token] or FILTER_ALIASES[token:gsub('%s+','')]
            if cat=='physical' then
                settings.filters.melee=include; settings.filters.ws=include; settings.filters.sc=include; canonical='physical'
            elseif cat=='pet_physical' then canonical='pet_physical'
            elseif cat=='pet_magic' then canonical='pet_magic'
            elseif cat=='pet_ranged' then canonical='pet_ranged' end
            if canonical and canonical~='physical' then settings.filters[canonical]=include; if include and canonical:find('^pet_') then settings.filters.pet=true end
            elseif not canonical then chat(167,'Unknown parse category: '..subject); return end
            chat(207,(include and 'Included: ' or 'Excluded: ')..subject)
        end
    elseif cmd=='filter' then handle_filter_command(args,false)
    elseif cmd=='unfilter' then handle_filter_command(args,true)
    elseif cmd=='set' then
        local item=Core.lower(args[2] or '')
        if item=='rows' or item=='row' then
            local value=Core.lower(args[3] or 'default')
            if value=='all' or value=='off' then settings.row_limit=0
            elseif value=='default' or value=='reset' then settings.row_limit=8
            else local nrows=tonumber(args[3]); if nrows then settings.row_limit=Core.clamp(math.floor(nrows),1,18) else chat(167,'Use //vp set rows <1-18 | all | default>.'); return end end
            chat(207,'Visible actor rows: '..(settings.row_limit==0 and 'All' or tostring(settings.row_limit)))
        elseif item=='delay' or (item=='report' and Core.lower(args[3] or '')=='delay') then
            local idx=(item=='report') and 4 or 3; settings.report_delay=Core.clamp(tonumber(args[idx]) or 0.65,0.10,3.00); chat(207,('Report delay %.2fs.'):format(settings.report_delay))
        elseif item=='scope' then if not set_scope(args[3]) then chat(167,'Use //vp set scope <self | party | alliance | custom>.'); return end
        elseif item=='size' then local size=Core.clamp(tonumber(args[3]) or 8,5,36); hud:size(size); settings.hud.text.size=size; chat(207,'HUD size '..tostring(size)..'.')
        elseif item=='position' or item=='pos' then local x,y=tonumber(args[3]),tonumber(args[4]); if x and y then hud:pos(x,y); chat(207,('HUD position %d %d.'):format(x,y)) else chat(167,'Use //vp set position <x> <y>.'); return end
        elseif item=='target' then local mode=Core.lower(args[3] or 'auto'); if mode=='on' or mode=='off' or mode=='auto' then settings.target_hp=mode; chat(207,'Target line '..Core.display_word(mode)..'.') else chat(167,'Use //vp set target <on | off | auto>.'); return end
        else chat(167,'Set: rows | delay | scope | size | position | target'); return end
    elseif cmd=='view' then
        local value=Core.lower(args[2] or 'dynamic'); if not set_view(value) then chat(167,'View: dynamic | compact | physical | magic | ranged | defense | combo | healing | pet | ws') end
    elseif cmd=='performance' or cmd=='stat' or cmd=='stats' then
        local source=selected_source(); if not source then chat(167,'No performance data available.'); return end
        local exhaustive=false; local parts={}; for i=2,#args do if Core.lower(args[i])=='all' then exhaustive=true else parts[#parts+1]=args[i] end end
        local name=table.concat(parts,' '); if name=='' then local p=windower.ffxi.get_player(); name=p and p.name or '' end
        local a=Report.find_actor(source,name); if not a then chat(167,'Player not found in selected parse: '..tostring(name)); return end
        Report.performance('local',nil,a,source,exhaustive)
    elseif cmd=='report' then Report.send(args)
    elseif cmd=='split' then handle_split_command(args)
    elseif cmd=='unsplit' then split_view=nil; chat(207,'Showing full session.')
    elseif cmd=='pause' or cmd=='stop' then settings.paused=true; chat(207,'Paused.')
    elseif cmd=='continue' or cmd=='resume' or cmd=='start' then settings.paused=false; chat(207,'Active.')
    elseif cmd=='reset' or cmd=='clear' then full_reset('manual-reset'); chat(207,'Full parse session cleared.')
    elseif cmd=='sort' then
        local srt=Core.lower(args[2] or 'dps'); local valid={party=true,damage=true,dps=true,melee=true,accuracy=true,acc=true,ranged=true,racc=true,ws=true,wsacc=true,wsavg=true,sc=true,magic=true,pet=true,healing=true,cleanse=true,cleanses=true,dispel=true,dispels=true,taken=true}
        if valid[srt] then settings.sort=srt else chat(167,'Sort: party | damage | dps | melee | acc | ranged | racc | ws | wsacc | wsavg | sc | magic | pet | healing | recovery | taken') end
    elseif cmd=='pin' then
        local name=args[2]; if not name then chat(167,'Use //vp pin me | <player> [slot].') else local p=windower.ffxi.get_player(); if Core.lower(name)=='me' then name=p and p.name or name end; settings.pins[Core.lower(name)]=tonumber(args[3]) or true; chat(207,'Pinned '..name..'.') end
    elseif cmd=='unpin' then local name=args[2]; if name and Core.lower(name)=='all' then settings.pins={} elseif name then local p=windower.ffxi.get_player(); if Core.lower(name)=='me' then name=p and p.name or name end; settings.pins[Core.lower(name)]=nil end
    elseif cmd=='lock' then settings.hud.flags.draggable=false; hud:draggable(false)
    elseif cmd=='unlock' then settings.hud.flags.draggable=true; hud:draggable(true)
    elseif cmd=='save' then settings.hud=hud:settings(); config.save(settings); enemy_registry:save(); chat(207,'Settings saved.')
    elseif cmd=='reload' then settings.hud=hud:settings(); config.save(settings); enemy_registry:save(); windower.send_command('lua reload VanaParse'); return
    elseif cmd=='unload' then settings.hud=hud:settings(); config.save(settings); enemy_registry:save(); windower.send_command('lua unload VanaParse'); return
    else chat(167,'Unknown command. Use //vp help.') end
    settings.hud=hud:settings(); config.save(settings); update_hud(true)
end)

windower.register_event('unload',function() log_source('SESSION',current_source(),Core.now(),'unload'); enemy_registry:save(); settings.hud=hud:settings(); config.save(settings) end)
