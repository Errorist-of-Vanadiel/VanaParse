--[[
VanaParse 2.1.4
Copyright (c) 2026 Errorist of Vana'diel
MIT License

Combat analytics for the Vana suite. Raw action events are classified, applied
to bounded aggregate counters/windows, then discarded.
]]

_addon.name = 'VanaParse'
_addon.author = "Errorist of Vana'diel"
_addon.version = '2.1.4'
_addon.commands = {'vanaparse','vp'}

local texts = require('texts')
local config = require('config')
local res = require('resources')
require('chat')

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
Core.VP=Core.VP or {}

local defaults={
    schema=24, visible=true, paused=false, view='dynamic', scope='alliance', sort='dps', sort_direction='desc', period='session', enemy='all',
    live_seconds=15, rolling_seconds=600, active_timeout=60, encounter_timeout=60, history_limit=10,
    hud={pos={x=470,y=150},padding=3,bg={alpha=135,red=0,green=0,blue=0},text={font='Consolas',size=8,red=255,green=255,blue=255,alpha=255},flags={draggable=true}},
    custom_players={}, local_players={}, max_hidden={}, max_only={}, alliance_limit=18, row_limit=8, debug=false, log_enabled=true, report_delay=1.05, include_trusts=true, include_allied_npcs=true,
    report_destination='party', report_tell='', report_content='view', job_column=true, subjob=false, job_sub_mode='auto', theme='dark', bg_opacity=53, contrast_bg_opacity=80, dps_refresh_seconds=5,
    transition_full_min=5, transition_full_max=30, transition_micro_min=2, transition_micro_max=10, registry_save_seconds=120,
    idle_detect_seconds=30, idle_timeout_seconds=60, notice_seconds=15,
    observer_stale_seconds=180, observer_max_encounters=24,
    secondary_huds={
        all={visible=false,view='dynamic',row_limit=8,hud={pos={x=470,y=385},padding=3,bg={alpha=135,red=0,green=0,blue=0},text={font='Consolas',size=8,red=255,green=255,blue=255,alpha=255},flags={draggable=true}}},
        allparties={visible=false,view='dynamic',row_limit=8,hud={pos={x=470,y=620},padding=3,bg={alpha=135,red=0,green=0,blue=0},text={font='Consolas',size=8,red=255,green=255,blue=255,alpha=255},flags={draggable=true}}},
    },
    profiles={}, active_profile='',
    theme_colors={
        dark={bg={red=0,green=0,blue=0},text={red=255,green=255,blue=255},stroke={red=0,green=0,blue=0}},
        light={bg={red=248,green=248,blue=248},text={red=20,green=20,blue=20},stroke={red=255,green=255,blue=255}},
        contrastdark={bg={red=0,green=0,blue=0},text={red=255,green=255,blue=255},stroke={red=0,green=0,blue=0}},
        contrastlight={bg={red=255,green=255,blue=255},text={red=0,green=0,blue=0},stroke={red=255,green=255,blue=255}},
    },
    columns={ranged='auto',pet='auto',healing='auto',crits=false,pet_types=false,ws_count=false,ws_avg=true,accuracy=true,ranged_accuracy=true,ws_accuracy=true,ws_hm=true},
    display={physical=true,melee=true,ws=true,sc=true,magic=true,mb=true,ranged=true,pet=true,healing=true,recovery=true,defense=true},
    controls={hidden_fields={},excluded_fields={},hidden_actions={},excluded_actions={},hidden_categories={},excluded_categories={}},
    pins={},self_pin=true,pin_local=false,pin_party=false,pin_alliance=false,target_hp='auto',accuracy_min_attempts=10,highlights=true,highlight_ws_min=5,
    filters={melee=true,ranged=true,ws=true,sc=true,magic=true,pet=true,pet_melee=true,pet_ranged=true,pet_physical=true,pet_magic=true,pet_sc=true,other=true},
    enemy_filter_text='', enemy_filter_ids='', compact_magic_threshold=0.03, compact_pet_threshold=0.03,
}
local settings=Core.merge(config.load(defaults),defaults)
if tonumber(settings.schema or 1)<24 then
    local previous_schema=tonumber(settings.schema or 1)
    settings.columns=Core.merge(settings.columns or {},defaults.columns); settings.display=Core.merge(settings.display or {},defaults.display); settings.pins=settings.pins or {}; settings.self_pin=settings.self_pin~=false
    settings.filters=Core.merge(settings.filters or {},defaults.filters); settings.target_hp=settings.target_hp or 'auto'; settings.accuracy_min_attempts=tonumber(settings.accuracy_min_attempts) or 10
    if settings.highlights==nil then settings.highlights=true end; settings.highlight_ws_min=tonumber(settings.highlight_ws_min) or 5
    if settings.view=='overview' then settings.view='dynamic' end
    if math.abs((tonumber(settings.report_delay) or 0.65)-0.65)<0.001 then settings.report_delay=1.05 end
    settings.report_destination=settings.report_destination or 'party'; settings.report_tell=settings.report_tell or ''; settings.report_content=settings.report_content or 'view'
    if settings.job_column==nil then settings.job_column=true end
    settings.job_sub_mode=settings.job_sub_mode or 'auto'
    settings.local_players=settings.local_players or {}; if settings.pin_local==nil then settings.pin_local=false end; if settings.pin_party==nil then settings.pin_party=false end; if settings.pin_alliance==nil then settings.pin_alliance=false end
    settings.theme=Core.lower(settings.theme or 'dark'); if settings.theme=='highcontrast' or settings.theme=='hc' then settings.theme='contrastdark' elseif settings.theme=='inverse' then settings.theme='light' end
    settings.theme_colors=Core.merge(settings.theme_colors or {},defaults.theme_colors)
    local previous_alpha=settings.hud and settings.hud.bg and tonumber(settings.hud.bg.alpha) or 135
    settings.bg_opacity=tonumber(settings.bg_opacity) or math.floor((previous_alpha/255)*100+0.5)
    if settings.hud and settings.hud.text and tonumber(settings.hud.text.size)==9 then settings.hud.text.size=8 end
    settings.secondary_huds=Core.merge(settings.secondary_huds or {},defaults.secondary_huds)
    settings.profiles=settings.profiles or {}; settings.active_profile=settings.active_profile or ''
    settings.idle_detect_seconds=tonumber(settings.idle_detect_seconds) or 30; settings.idle_timeout_seconds=tonumber(settings.idle_timeout_seconds) or 60; settings.notice_seconds=tonumber(settings.notice_seconds) or 15
    settings.observer_stale_seconds=tonumber(settings.observer_stale_seconds) or 180; settings.observer_max_encounters=tonumber(settings.observer_max_encounters) or 24
    settings.contrast_bg_opacity=tonumber(settings.contrast_bg_opacity) or 80
    -- One-time saved-setting migration only. Old implementation view values are
    -- converted to the new canonical model and are not retained as commands.
    if settings.view=='ws-full' then settings.view='ws-details' elseif settings.view=='magic-full' then settings.view='magic-details' elseif settings.view=='ws-overall' then settings.view='ws' elseif settings.view=='magic-overall' then settings.view='magic' elseif settings.view=='combo' or settings.view=='max' then settings.view='full' end
    if settings.secondary_huds then for _,cfg in pairs(settings.secondary_huds) do if cfg.view=='ws-full' then cfg.view='ws-details' elseif cfg.view=='magic-full' then cfg.view='magic-details' elseif cfg.view=='ws-overall' then cfg.view='ws' elseif cfg.view=='magic-overall' then cfg.view='magic' elseif cfg.view=='combo' or cfg.view=='max' then cfg.view='full' end end end
    settings.dps_refresh_seconds=tonumber(settings.dps_refresh_seconds) or 5
    settings.controls=Core.merge(settings.controls or {},defaults.controls)
    if settings.display.melee==nil then settings.display.melee=settings.display.physical~=false end
    settings.schema=24
end
settings.columns=Core.merge(settings.columns or {},defaults.columns)
settings.display=Core.merge(settings.display or {},defaults.display)
settings.controls=Core.merge(settings.controls or {},defaults.controls)
if settings.display.melee==nil then settings.display.melee=settings.display.physical~=false end
if settings.highlights==nil then settings.highlights=true end
settings.highlight_ws_min=tonumber(settings.highlight_ws_min) or 5
settings.report_delay=Core.clamp(tonumber(settings.report_delay) or 1.05,0.10,3.00)
settings.report_destination=Core.lower(settings.report_destination or 'party'); settings.report_tell=tostring(settings.report_tell or ''); settings.report_content=Core.lower(settings.report_content or 'view')
if settings.report_destination=='say' or settings.report_destination=='yell' or settings.report_destination=='shout' or settings.report_destination=='unity' or settings.report_destination=='assist' or settings.report_destination=='jp' or settings.report_destination=='en' or settings.report_destination=='eu' then settings.report_destination='party'; settings.report_tell='' end
if settings.job_column==nil then settings.job_column=true end
settings.job_sub_mode=Core.lower(settings.job_sub_mode or 'auto'); if settings.job_sub_mode~='auto' and settings.job_sub_mode~='on' and settings.job_sub_mode~='off' then settings.job_sub_mode='auto' end
settings.subjob=(settings.job_sub_mode=='on')
settings.local_players=settings.local_players or {}; settings.pin_local=settings.pin_local==true; settings.pin_party=settings.pin_party==true; settings.pin_alliance=settings.pin_alliance==true
settings.theme=Core.lower(settings.theme or 'dark'); if settings.theme=='inverse' then settings.theme='light' elseif settings.theme=='hc' or settings.theme=='highcontrast' then settings.theme='contrastdark' end
if settings.theme~='dark' and settings.theme~='light' and settings.theme~='contrastdark' and settings.theme~='contrastlight' then settings.theme='dark' end
settings.theme_colors=Core.merge(settings.theme_colors or {},defaults.theme_colors)
settings.bg_opacity=Core.clamp(tonumber(settings.bg_opacity) or 53,0,100)
settings.contrast_bg_opacity=Core.clamp(tonumber(settings.contrast_bg_opacity) or 80,0,100)
settings.dps_refresh_seconds=Core.clamp(tonumber(settings.dps_refresh_seconds) or 5,1,30)
if settings.include_trusts==nil then settings.include_trusts=true end
if settings.include_allied_npcs==nil then settings.include_allied_npcs=true end
settings.row_limit=math.max(0,math.floor(tonumber(settings.row_limit) or 8))
settings.sort_direction=Core.lower(settings.sort_direction or 'desc'); if settings.sort_direction~='asc' and settings.sort_direction~='desc' then settings.sort_direction='desc' end
settings.enemy_filter_text=tostring(settings.enemy_filter_text or '')
settings.enemy_filter_ids=tostring(settings.enemy_filter_ids or '')
settings.compact_magic_threshold=Core.clamp(tonumber(settings.compact_magic_threshold) or 0.03,0,1)
settings.compact_pet_threshold=Core.clamp(tonumber(settings.compact_pet_threshold) or 0.03,0,1)
settings.transition_full_min=Core.clamp(tonumber(settings.transition_full_min) or 5,1,30); settings.transition_full_max=Core.clamp(tonumber(settings.transition_full_max) or 30,settings.transition_full_min,60)
settings.transition_micro_min=Core.clamp(tonumber(settings.transition_micro_min) or 2,0.5,10); settings.transition_micro_max=Core.clamp(tonumber(settings.transition_micro_max) or 10,settings.transition_micro_min,30)
settings.registry_save_seconds=Core.clamp(tonumber(settings.registry_save_seconds) or 120,30,600)
settings.idle_detect_seconds=Core.clamp(tonumber(settings.idle_detect_seconds) or 30,5,120); settings.idle_timeout_seconds=Core.clamp(tonumber(settings.idle_timeout_seconds) or 60,settings.idle_detect_seconds,300); settings.notice_seconds=Core.clamp(tonumber(settings.notice_seconds) or 15,1,60)
settings.observer_stale_seconds=Core.clamp(tonumber(settings.observer_stale_seconds) or 180,30,900); settings.observer_max_encounters=Core.clamp(math.floor(tonumber(settings.observer_max_encounters) or 24),4,100)
settings.secondary_huds=Core.merge(settings.secondary_huds or {},defaults.secondary_huds); settings.profiles=settings.profiles or {}; settings.active_profile=tostring(settings.active_profile or '')

-- Font families are approved only after they are confirmed to preserve the
-- fixed-character parser table in the actual Windower/FFXI renderer.
-- Do not infer approval from the Windows font category or font name alone.
Core.VP.APPROVED_FONTS={'Consolas','Courier New','Cascadia Code','Lucida Console'}
Core.VP.APPROVED_FONT_MAP={['consolas']='Consolas',['courier new']='Courier New',['cascadia code']='Cascadia Code',['lucida console']='Lucida Console'}
function Core.VP.approved_font_name(name)
    local key=Core.lower(tostring(name or '')):gsub('^%s+',''):gsub('%s+$',''):gsub('%s+',' ')
    return Core.VP.APPROVED_FONT_MAP[key]
end
function Core.VP.approved_fonts_text()
    return table.concat(Core.VP.APPROVED_FONTS,' | ')
end
function Core.VP.normalize_font_settings()
    local current=settings.hud and settings.hud.text and settings.hud.text.font or defaults.hud.text.font
    local approved=Core.VP.approved_font_name(current) or 'Consolas'
    settings.hud=settings.hud or {}; settings.hud.text=settings.hud.text or {}; settings.hud.text.font=approved
    for _,cfg in pairs(settings.secondary_huds or {}) do
        cfg.hud=cfg.hud or {}; cfg.hud.text=cfg.hud.text or {}; cfg.hud.text.font=approved
    end
    return approved
end
Core.VP.normalize_font_settings()

function Core.VP.theme_palette(name)
    name=Core.lower(name or 'dark')
    local light=(name=='light' or name=='contrastlight')
    local fallback=light and {bg={255,255,255},text={0,0,0},stroke={255,255,255}} or {bg={0,0,0},text={255,255,255},stroke={0,0,0}}
    local custom=settings.theme_colors and settings.theme_colors[name] or nil
    local function triplet(which)
        local v=custom and custom[which] or nil; local f=fallback[which]
        if type(v)~='table' then return f end
        return {Core.clamp(tonumber(v.red) or f[1],0,255),Core.clamp(tonumber(v.green) or f[2],0,255),Core.clamp(tonumber(v.blue) or f[3],0,255)}
    end
    return {bg=triplet('bg'),text=triplet('text'),stroke=triplet('stroke')}
end
function Core.VP.effective_bg_opacity()
    if settings.theme=='contrastdark' or settings.theme=='contrastlight' then return Core.clamp(tonumber(settings.contrast_bg_opacity) or 80,0,100) end
    return Core.clamp(tonumber(settings.bg_opacity) or 53,0,100)
end
function Core.VP.set_active_bg_opacity(value)
    value=Core.clamp(tonumber(value) or Core.VP.effective_bg_opacity(),0,100)
    if settings.theme=='contrastdark' or settings.theme=='contrastlight' then settings.contrast_bg_opacity=value else settings.bg_opacity=value end
    return value
end
function Core.VP.apply_theme_to_hud_settings(hs)
    if type(hs)~='table' then return end
    local pal=Core.VP.theme_palette(settings.theme); hs.bg=hs.bg or {}; hs.text=hs.text or {}; hs.text.stroke=hs.text.stroke or {}
    hs.bg.alpha=math.floor(255*Core.VP.effective_bg_opacity()/100+0.5)
    hs.bg.red,hs.bg.green,hs.bg.blue=pal.bg[1],pal.bg[2],pal.bg[3]
    hs.text.red,hs.text.green,hs.text.blue=pal.text[1],pal.text[2],pal.text[3]
    hs.text.stroke.red,hs.text.stroke.green,hs.text.stroke.blue=pal.stroke[1],pal.stroke[2],pal.stroke[3]
end
function Core.VP.apply_theme_to_settings()
    Core.VP.apply_theme_to_hud_settings(settings.hud)
    for _,cfg in pairs(settings.secondary_huds or {}) do Core.VP.apply_theme_to_hud_settings(cfg.hud) end
    Core.THEME=(settings.theme=='light' or settings.theme=='contrastlight') and 'light' or 'dark'
end
Core.VP.apply_theme_to_settings()

-- Selective bold rendering uses exactly one transparent companion text object
-- per HUD. The normal/base HUD has the bold characters replaced by spaces and
-- the companion contains only those characters in the exact same monospace
-- positions. This avoids per-cell/per-row overlays, pixel Y calculations and
-- duplicate full-text rendering.
Core.VP.bold_huds={}
function Core.VP.bold_overlay_settings(hs)
    local out=Core.copy(hs or {})
    out.bg=out.bg or {}; out.bg.alpha=0; out.bg.visible=false
    out.flags=out.flags or {}; out.flags.draggable=false; out.flags.bold=true; out.flags.italic=false
    return out
end
function Core.VP.create_bold_huds()
    Core.VP.bold_huds={}
    Core.VP.bold_huds.main=texts.new(Core.VP.bold_overlay_settings(settings.hud))
    Core.VP.bold_huds.all=texts.new(Core.VP.bold_overlay_settings(settings.secondary_huds.all.hud))
    Core.VP.bold_huds.allparties=texts.new(Core.VP.bold_overlay_settings(settings.secondary_huds.allparties.hud))
    for _,obj in pairs(Core.VP.bold_huds) do if obj then obj:bold(true); obj:bg_visible(false); obj:draggable(false) end end
    if settings.visible then Core.VP.bold_huds.main:show() else Core.VP.bold_huds.main:hide() end
    if settings.secondary_huds.all.visible then Core.VP.bold_huds.all:show() else Core.VP.bold_huds.all:hide() end
    if settings.secondary_huds.allparties.visible then Core.VP.bold_huds.allparties:show() else Core.VP.bold_huds.allparties:hide() end
end
function Core.VP.sync_bold_hud(key,base)
    local bold=Core.VP.bold_huds and Core.VP.bold_huds[key]
    if not bold or not base then return end
    local x,y=base:pos(); bold:pos(x,y)
end

local hud=texts.new(settings.hud); if settings.visible then hud:show() else hud:hide() end
Core.VP.huds={main=hud,all=texts.new(settings.secondary_huds.all.hud),allparties=texts.new(settings.secondary_huds.allparties.hud)}
if settings.secondary_huds.all.visible then Core.VP.huds.all:show() else Core.VP.huds.all:hide() end
if settings.secondary_huds.allparties.visible then Core.VP.huds.allparties:show() else Core.VP.huds.allparties:hide() end
Core.VP.create_bold_huds()
function Core.VP.apply_theme_runtime()
    Core.VP.apply_theme_to_settings(); local pal=Core.VP.theme_palette(settings.theme); local alpha=math.floor(255*Core.VP.effective_bg_opacity()/100+0.5)
    for _,obj in pairs(Core.VP.huds or {}) do if obj then obj:bg_alpha(alpha); obj:bg_color(pal.bg[1],pal.bg[2],pal.bg[3]); obj:color(pal.text[1],pal.text[2],pal.text[3]) end end
    for _,obj in pairs(Core.VP.bold_huds or {}) do if obj then obj:bg_visible(false); obj:color(pal.text[1],pal.text[2],pal.text[3]) end end
end

-- Hard HUD lifecycle helpers. These intentionally destroy the underlying
-- Windower text primitives before new ones are created so //vp default can
-- never leave a stale render behind.
function Core.VP.destroy_huds()
    for _,bucket in ipairs({Core.VP.bold_huds or {},Core.VP.huds or {}}) do
        for _,obj in pairs(bucket) do
            if obj then
                pcall(function() obj:hide() end)
                pcall(function() obj:destroy() end)
            end
        end
    end
    Core.VP.bold_huds={}
    Core.VP.huds={}
    hud=nil
end

function Core.VP.create_huds_from_settings()
    Core.VP.apply_theme_to_settings()
    hud=texts.new(settings.hud)
    Core.VP.huds={main=hud,all=texts.new(settings.secondary_huds.all.hud),allparties=texts.new(settings.secondary_huds.allparties.hud)}
    if settings.visible then hud:show() else hud:hide() end
    if settings.secondary_huds.all.visible then Core.VP.huds.all:show() else Core.VP.huds.all:hide() end
    if settings.secondary_huds.allparties.visible then Core.VP.huds.allparties:show() else Core.VP.huds.allparties:hide() end
    Core.VP.create_bold_huds()
end

function Core.VP.apply_font_runtime(font_name,font_size)
    local requested=font_name
    if requested~=nil then
        font_name=Core.VP.approved_font_name(requested)
        if not font_name then
            return nil,Core.VP.font_size(),false,'Unsupported font. Approved: '..Core.VP.approved_fonts_text()
        end
    else
        font_name=Core.VP.approved_font_name((settings.hud and settings.hud.text and settings.hud.text.font) or '') or 'Consolas'
    end
    font_size=tonumber(font_size or (settings.hud and settings.hud.text and settings.hud.text.size) or 8) or 8
    font_size=Core.clamp(math.floor(font_size*4+0.5)/4,5,36)
    settings.hud.text=settings.hud.text or {}; settings.hud.text.font=font_name; settings.hud.text.size=font_size
    for _,cfg in pairs(settings.secondary_huds or {}) do cfg.hud=cfg.hud or {}; cfg.hud.text=cfg.hud.text or {}; cfg.hud.text.font=font_name; cfg.hud.text.size=font_size end
    for _,bucket in ipairs({Core.VP.huds or {},Core.VP.bold_huds or {}}) do
        for _,obj in pairs(bucket) do
            if obj then
                if obj.font then pcall(function() obj:font(font_name) end) end
                if obj.size then pcall(function() obj:size(font_size) end) end
            end
        end
    end
    return font_name,font_size,true
end
function Core.VP.font_name() return tostring((settings.hud and settings.hud.text and settings.hud.text.font) or 'Consolas') end
function Core.VP.font_size() return tonumber(settings.hud and settings.hud.text and settings.hud.text.size) or 8 end
function Core.VP.font_size_label(value)
    local n=tonumber(value or Core.VP.font_size()) or 8
    local text=string.format('%.2f',n):gsub('0+$',''):gsub('%.$','')
    return text
end
function Core.VP.parse_font_size(value)
    local text=(tostring(value or ''):gsub('[Pp][Tt]$',''))
    local n=tonumber(text)
    if not n then return nil end
    return Core.clamp(math.floor(n*4+0.5)/4,5,36)
end

function Core.VP.capture_hud_settings()
    settings.hud=hud:settings()
    if Core.VP.huds and Core.VP.huds.all then settings.secondary_huds.all.hud=Core.VP.huds.all:settings() end
    if Core.VP.huds and Core.VP.huds.allparties then settings.secondary_huds.allparties.hud=Core.VP.huds.allparties:settings() end
end

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

-- The local player's row uses blue as a secondary/default row color. Existing
-- semantic colors (accuracy thresholds, leaders, warnings, etc.) remain primary
-- and are never overwritten.
function Core.VP.apply_local_row_secondary_color(headers,rows)
    local p=windower.ffxi.get_player and windower.ffxi.get_player() or nil
    local local_name=p and p.name and Core.lower(p.name) or nil
    if not local_name or local_name=='' then return rows end
    local player_col=nil
    for i,h in ipairs(headers or {}) do
        local plain=tostring(h or ''):gsub('\\cs%b()',''):gsub('\\cr','')
        if Core.lower(plain)=='player' then player_col=i; break end
    end
    if not player_col then return rows end
    for _,row in ipairs(rows or {}) do
        local raw=tostring(row[player_col] or '')
        local plain=raw:gsub('\\cs%b()',''):gsub('\\cr','')
        if Core.lower(plain)==local_name then
            for i,value in ipairs(row) do
                local text=tostring(value==nil and '' or value)
                if text~='' and not text:find('\\cs%(') then row[i]=Core.color_text(text,96,176,255) end
            end
        end
    end
    return rows
end

local function format_parse_dynamic(headers,rows,aligns,options)
    -- Recompute widths from the currently visible rows. Numeric columns are
    -- right-justified against one shared width calculation so color escapes or
    -- a previous layout can never shift a single player by one character.
    -- Universal field controls are applied immediately before formatting so
    -- every View inherits the same Show/Hide and Include/Exclude behavior.
    rows=Core.VP.apply_local_row_secondary_color(headers,rows)
    if Core.VP.apply_table_controls then headers,rows,aligns,options=Core.VP.apply_table_controls(headers,rows,aligns,options) end
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
local incoming_action=nil -- {actor_id,name,started,resolved_at}
local INCOMING_TIMEOUT=15
local INCOMING_FLASH_STEP=0.16
local INCOMING_FLASHES=2

-- Transition/job state lives under Core.VP to avoid pushing the
-- main Lua chunk toward Lua 5.1's local-variable ceiling.
Core.VP.transition={active=false,state='ready',generation=1,reason=nil,started=0,min_until=0,max_until=0,last_probe=0,stable=0,pending_finalize=false,last_zone=nil,last_submap=nil,last_x=nil,last_y=nil,last_z=nil}
Core.VP.registry_dirty=false; Core.VP.registry_next_save=Core.now()+(tonumber(settings.registry_save_seconds) or 120)
Core.VP.job_cache={}
Core.VP.observer={encounters={},order={},focus=nil,actor_to_encounter={},last_cleanup=0}
Core.VP.packets=require('packets')

-- Master Level 50 raises the support-job ceiling to 59.  Job inference must
-- never treat an action/spell available by level 59 as proof of a main job.
Core.VP.SUBJOB_LEVEL_CAP=59

-- High-confidence support-job evidence.  These are job-specific actions that
-- are available while that job is used as a support job at the current cap.
-- The list intentionally favors unambiguous actions over speculative guesses.
Core.VP.SUBJOB_ACTION_EVIDENCE={
    -- WAR
    ['provoke']='WAR',['berserk']='WAR',['defender']='WAR',['warcry']='WAR',['aggressor']='WAR',
    -- MNK
    ['boost']='MNK',['dodge']='MNK',['focus']='MNK',['chakra']='MNK',['counterstance']='MNK',
    -- WHM / BLM / RDM
    ['divine seal']='WHM',
    ['elemental seal']='BLM',
    ['convert']='RDM',['composure']='RDM',
    -- THF
    ['steal']='THF',['sneak attack']='THF',['flee']='THF',['trick attack']='THF',['hide']='THF',
    -- PLD / DRK / BST
    ['shield bash']='PLD',['sentinel']='PLD',['cover']='PLD',
    ['arcane circle']='DRK',['last resort']='DRK',['weapon bash']='DRK',['souleater']='DRK',
    ['charm']='BST',['gauge']='BST',['tame']='BST',['reward']='BST',['call beast']='BST',
    -- BRD / RNG
    ['pianissimo']='BRD',
    ['scavenge']='RNG',['sharpshot']='RNG',['camouflage']='RNG',['barrage']='RNG',['shadowbind']='RNG',
    -- SAM
    ['warding circle']='SAM',['third eye']='SAM',['hasso']='SAM',['meditate']='SAM',['seigan']='SAM',['sekkanoki']='SAM',
    -- NIN
    ['yonin']='NIN',['innin']='NIN',
    -- DRG
    ['ancient circle']='DRG',['jump']='DRG',['spirit link']='DRG',['high jump']='DRG',['super jump']='DRG',
    -- SMN / BLU / COR / PUP
    ['elemental siphon']='SMN',
    ['chain affinity']='BLU',['burst affinity']='BLU',
    ['phantom roll']='COR',['double-up']='COR',['quick draw']='COR',['random deal']='COR',['fold']='COR',
    ['activate']='PUP',['repair']='PUP',['deactivate']='PUP',
    -- SCH
    ['light arts']='SCH',['dark arts']='SCH',['sublimation']='SCH',['addendum: white']='SCH',['addendum: black']='SCH',
    -- GEO / RUN
    ['full circle']='GEO',['lasting emanation']='GEO',['ecliptic attrition']='GEO',['life cycle']='GEO',['dematerialize']='GEO',
    ['vallation']='RUN',['swordplay']='RUN',['pflug']='RUN',['lunge']='RUN',['swipe']='RUN',['liement']='RUN',
}

-- Some resource action types identify the job more safely than individual
-- names.  This also covers all Waltz/Jig/Step/Samba/Flourish variants without
-- having to hard-code every Dancer action.
Core.VP.SUBJOB_ACTION_TYPE_EVIDENCE={
    waltz='DNC',jig='DNC',step='DNC',samba='DNC',flourish1='DNC',flourish2='DNC',flourish3='DNC',
    corsairroll='COR',scholar='SCH',
}

-- Conservative job evidence. Main-job inference requires an action that cannot
-- be obtained from a level-59 support job. Lower-level evidence is used only to
-- infer a support job after the main job is already known to be different.
Core.VP.JOB_EVIDENCE={
    ['brazen rush']={'WAR',96},['tomahawk']={'WAR',75},['restraint']={'WAR',77},['blood rage']={'WAR',87},
    ['inner strength']={'MNK',96},['mantra']={'MNK',75},['formless strikes']={'MNK',75},['impetus']={'MNK',88},
    ['asylum']={'WHM',96},['divine caress']={'WHM',83},['sacrosanctity']={'WHM',95},
    ['subtle sorcery']={'BLM',96},['mana wall']={'BLM',76},['enmity douse']={'BLM',87},['manawell']={'BLM',95},
    ['stymie']={'RDM',96},['saboteur']={'RDM',83},['spontaneity']={'RDM',95},
    ['larceny']={'THF',96},['collaborator']={'THF',65},['accomplice']={'THF',65},['conspirator']={'THF',87},['bully']={'THF',93},
    ['intervene']={'PLD',96},['chivalry']={'PLD',75},['divine emblem']={'PLD',78},['sepulcher']={'PLD',87},['palisade']={'PLD',95},
    ['soul enslavement']={'DRK',96},['dark seal']={'DRK',75},['nether void']={'DRK',78},['arcane crest']={'DRK',87},['scarlet delirium']={'DRK',95},
    ['unleash']={'BST',96},['feral howl']={'BST',75},['killer instinct']={'BST',76},['spur']={'BST',83},['run wild']={'BST',93},
    ['clarion call']={'BRD',96},['nightingale']={'BRD',75},['troubadour']={'BRD',75},['marcato']={'BRD',95},
    ['overkill']={'RNG',96},['stealth shot']={'RNG',75},['flashy shot']={'RNG',75},['double shot']={'RNG',79},['decoy shot']={'RNG',95},
    ['yaegasumi']={'SAM',96},['sengikori']={'SAM',77},['hamanoha']={'SAM',87},['hagakure']={'SAM',95},['hasso']={'SAM',25},['seigan']={'SAM',35},['sekkanoki']={'SAM',40},
    ['mikage']={'NIN',96},['sange']={'NIN',75},['futae']={'NIN',77},['issekigan']={'NIN',95},['yonin']={'NIN',40},['innin']={'NIN',40},
    ['fly high']={'DRG',96},['angon']={'DRG',75},['deep breathing']={'DRG',75},
    ['astral conduit']={'SMN',96},['elemental siphon']={'SMN',50},['mana cede']={'SMN',87},
    ['unbridled wisdom']={'BLU',96},['efflux']={'BLU',83},['unbridled learning']={'BLU',95},['chain affinity']={'BLU',40},['burst affinity']={'BLU',40},
    ['cutting cards']={'COR',96},['fold']={'COR',50},['random deal']={'COR',50},['snake eye']={'COR',74},['crooked cards']={'COR',95},
    ['heady artifice']={'PUP',96},['ventriloquy']={'PUP',75},['role reversal']={'PUP',75},['tactical switch']={'PUP',79},['cooldown']={'PUP',95},
    ['grand pas']={'DNC',96},['saber dance']={'DNC',75},['fan dance']={'DNC',75},['no foot rise']={'DNC',75},['climactic flourish']={'DNC',80},['striking flourish']={'DNC',89},['ternary flourish']={'DNC',93},
    ['caper emissarius']={'SCH',96},['enlightenment']={'SCH',75},['libra']={'SCH',76},['perpetuance']={'SCH',87},['immanence']={'SCH',87},
    ['widened compass']={'GEO',96},['blaze of glory']={'GEO',60},
    ['odyllic subterfuge']={'RUN',96},['liement']={'RUN',50},['gambit']={'RUN',70},['rayke']={'RUN',75},['battuta']={'RUN',75},['one for all']={'RUN',95},
}

-- Main-job-only SP abilities and uniquely identifying Weapon Skills are
-- authoritative evidence.  Never infer a job from broadly shared WS such as
-- Savage Blade.
for label,entry in pairs({
    ['mighty strikes']={'WAR',99},['hundred fists']={'MNK',99},['benediction']={'WHM',99},['manafont']={'BLM',99},['chainspell']={'RDM',99},['perfect dodge']={'THF',99},
    ['invincible']={'PLD',99},['blood weapon']={'DRK',99},['familiar']={'BST',99},['soul voice']={'BRD',99},['eagle eye shot']={'RNG',99},['meikyo shisui']={'SAM',99},
    ['mijin gakure']={'NIN',99},['spirit surge']={'DRG',99},['astral flow']={'SMN',99},['azure lore']={'BLU',99},['wild card']={'COR',99},['overdrive']={'PUP',99},
    ['trance']={'DNC',99},['tabula rasa']={'SCH',99},['bolster']={'GEO',99},['elemental sforzo']={'RUN',99},['tachi: fudo']={'SAM',99},
}) do Core.VP.JOB_EVIDENCE[label]=entry end

Core.VP.ZONE_SHORT={
    ["Aht Urhgan Whitegate"]='Whitegate',["The Shrine of Ru'Avitau"]="Ru'Avitau",["The Garden of Ru'Hmet"]="Ru'Hmet",
}

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

function Core.VP.append_log_batch(rows)
    if not settings.log_enabled or type(rows)~='table' or #rows==0 then return end
    ensure_log_dir(); ensure_log_schema(); local fresh=not windower.file_exists(log_file); local f=io.open(log_file,'a'); if not f then return end
    if fresh then f:write('Type\tTimestamp\tEncounter\tElapsed\tActive\tPlayer\tMasterDamage\tPetDamage\tCombinedDamage\tDPS\tMelee\tRanged\tMagic\tEnspell\tOther\tWSDamage\tWSAtt\tWSHit\tWSMiss\tWSAvg\tAccuracy\tRAccuracy\tLandPct\tSC\tMB\tDHeal\tTaken\tCured\tSelfCure\tCleanse\tDispel\tAspir\tCureReceived\tReconcile\n') end
    for _,fields in ipairs(rows) do for i,v in ipairs(fields) do if i>1 then f:write('\t') end; f:write(clean_field(v)) end; f:write('\n') end
    f:close()
end

Core.VP.error_state=Core.VP.error_state or {}
local function on_error(label,err)
    errors=errors+1; last_error=tostring(label)..': '..tostring(err)
    local now=Core.now(); local e=Core.VP.error_state[label] or {count=0,last_chat=0}; e.count=e.count+1; Core.VP.error_state[label]=e
    if now-(e.last_chat or 0)>=10 then e.last_chat=now; chat(167,'Error in '..tostring(label)..'. VanaParse skipped the unsafe operation. Use //vp health.') end
end

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
    name=tostring(name or '')
    if Core.VP.category_included and not Core.VP.category_included(name) then return false end
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
    if enabled_filter('ws') then total=total+Core.VP.ws_net(a) end
    if enabled_filter('sc') then total=total+net(a.skillchain,a.dheal_skillchain) end
    if enabled_filter('magic') then total=total+Core.VP.magic_net(a) end
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
    if enabled_filter('pet_magic') then
        local pmagic=(tonumber(p.magic) or 0)-(tonumber(p.dheal_magic) or 0)-(tonumber(p.dheal_enspell) or 0)
        if not enabled_filter('pet_mb') then pmagic=pmagic-net(p.mb_damage,p.dheal_mb) end
        total=total+math.max(0,pmagic)
    end
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
        healing=0, healing_window=Core.Window.new(settings.rolling_seconds), cures=0, cure_mm=fresh_minmax(), healing_actions={}, mp_spent=0,
        received=0, self_healing=0, drain_healing=0, aspir_recovery=0, cleanses=0, cleanse_actions={}, dispels=0, dispel_actions={}, cure_mp_received=0, healed_targets={}, healed_by={},
        counter_damage=0, retaliation_damage=0, reprisal_damage=0, spikes_damage=0, dread_spikes_damage=0,
        taken=0, taken_physical=0, taken_magical=0, taken_other=0, taken_unknown=0, taken_hits=0, taken_mm=fresh_minmax(), taken_physical_hits=0, taken_magical_hits=0, taken_other_hits=0, taken_physical_mm=fresh_minmax(), taken_magical_mm=fresh_minmax(), taken_other_mm=fresh_minmax(),
        evades=0, parries=0, blocks=0, deaths=0,
        pet={damage=0, melee=0, ranged=0, magic=0, ws=0, physical=0, other=0, skillchain=0, enspell=0, healing=0, instances={},
            dheal=0,dheal_melee=0,dheal_ranged=0,dheal_physical=0,dheal_magic=0,dheal_enspell=0,dheal_mb=0,dheal_skillchain=0,dheal_other=0,
            attempts=0, hits=0, misses=0, mm=fresh_minmax(),
            melee_attempts=0, melee_hits=0, melee_misses=0, melee_mm=fresh_minmax(),
            ranged_attempts=0, ranged_hits=0, ranged_misses=0, ranged_mm=fresh_minmax(),
            ws_attempts=0, ws_hits=0, ws_misses=0, ws_mm=fresh_minmax(),
            magic_casts=0, magic_targets=0, magic_hits=0, magic_lands=0, magic_resists=0, magic_no_effect=0, magic_mm=fresh_minmax(),
            mb_casts=0, mb_count=0, mb_damage=0, mb_mm=fresh_minmax(), nonmb_casts=0, nonmb_count=0, nonmb_damage=0, nonmb_mm=fresh_minmax(),
            taken=0, taken_hits=0, taken_mm=fresh_minmax(), cleanses=0, dispels=0, aspir_recovery=0, self_healing=0, name=nil},
        enemy={}, enemy_ids={}, inferred_job=nil, inferred_subjob=nil, job_evidence=nil, mainjob_evidence_score=0, subjob_evidence_score=0, subjob_evidence=nil, subjob_source=nil, subjob_conflicts=0, subjob_observed_at=0, job_state={},
    }
end

function Core.VP.add_healing_action(actor,label,amount,uses,kind,now)
    if not actor or not label or tostring(label)=='' then return end
    amount=tonumber(amount) or 0; uses=tonumber(uses) or 1
    actor.healing_actions=actor.healing_actions or {}
    local h=actor.healing_actions[label]
    if not h then h={healing=0,uses=0,mm=fresh_minmax(),kind=kind or 'cure',window=Core.Window.new(settings.rolling_seconds)}; actor.healing_actions[label]=h end
    h.kind=h.kind or kind or 'cure'; h.healing=h.healing+math.max(0,amount); h.uses=h.uses+math.max(0,uses)
    if amount>0 then add_minmax(h.mm,amount); if h.window then h.window:add(amount,now or Core.now()) end end
end

local function actor_for(store,id,name)
    if not id then return nil end
    if not store[id] then store[id]=new_actor(id,name or Core.mob_name(windower,id)) end
    if name and store[id].name==tostring(id) then store[id].name=name end
    local cache=Core.VP.job_cache and Core.VP.job_cache[Core.lower(store[id].name or name or '')] or nil
    if cache then store[id].inferred_job=store[id].inferred_job or cache.main; store[id].inferred_subjob=store[id].inferred_subjob or cache.sub; store[id].job_evidence=store[id].job_evidence or cache.evidence; store[id].mainjob_evidence_score=math.max(tonumber(store[id].mainjob_evidence_score) or 0,tonumber(cache.main_score) or 0); store[id].subjob_evidence_score=math.max(tonumber(store[id].subjob_evidence_score) or 0,tonumber(cache.sub_score) or 0); store[id].subjob_evidence=store[id].subjob_evidence or cache.sub_evidence; store[id].subjob_source=store[id].subjob_source or cache.sub_source end
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


function Core.VP.merge_job_identity(dst,src)
    if not dst or not src then return end
    dst.main_job=src.main_job or src.inferred_job or dst.main_job
    dst.inferred_job=src.inferred_job or dst.inferred_job
    dst.job_evidence=src.job_evidence or dst.job_evidence
    dst.mainjob_evidence_score=math.max(tonumber(dst.mainjob_evidence_score) or 0,tonumber(src.mainjob_evidence_score) or 0)
    local priority={['live-self']=5,observed=4,check=3,party=2,inferred=1}
    local ss=tonumber(src.subjob_evidence_score) or 0; local ds=tonumber(dst.subjob_evidence_score) or 0
    local sp=priority[src.subjob_source] or 0; local dp=priority[dst.subjob_source] or 0
    local src_sub=src.sub_job or src.inferred_subjob
    if src_sub and (not (dst.sub_job or dst.inferred_subjob) or sp>dp or (sp==dp and ss>=ds)) then
        dst.sub_job=src.sub_job or src.inferred_subjob
        dst.inferred_subjob=src.inferred_subjob or src.sub_job
        dst.subjob_evidence_score=ss
        dst.subjob_evidence=src.subjob_evidence or dst.subjob_evidence
        dst.subjob_source=src.subjob_source or dst.subjob_source
        dst.subjob_observed_at=math.max(tonumber(dst.subjob_observed_at) or 0,tonumber(src.subjob_observed_at) or 0)
    end
    dst.subjob_conflicts=math.max(tonumber(dst.subjob_conflicts) or 0,tonumber(src.subjob_conflicts) or 0)
    dst.job_state=dst.job_state or {}; for k,v in pairs(src.job_state or {}) do if v then dst.job_state[k]=v end end
end

local function add_actor_stats(dst,src)
    if not dst or not src then return end
    local simple={'damage','melee','ranged','magic','other','skillchain','skillchain_count','enspell','dheal','dheal_melee','dheal_ranged','dheal_ws','dheal_magic','dheal_enspell','dheal_mb','dheal_skillchain','dheal_other','accuracy_forced_ignored','melee_attempts','melee_hits','melee_misses','melee_crit','ranged_attempts','ranged_hits','ranged_misses','ranged_crit','ws_damage','ws_attempts','ws_hits','ws_misses','magic_damage','magic_healing','magic_casts','magic_targets','magic_hits','magic_lands','magic_resists','magic_no_effect','mb_casts','mb_count','mb_damage','nonmb_casts','nonmb_count','nonmb_damage','healing','cures','mp_spent','received','self_healing','drain_healing','aspir_recovery','cleanses','dispels','cure_mp_received','counter_damage','retaliation_damage','reprisal_damage','spikes_damage','dread_spikes_damage','taken','taken_physical','taken_magical','taken_other','taken_unknown','taken_hits','taken_physical_hits','taken_magical_hits','taken_other_hits','evades','parries','blocks','deaths'}
    for _,k in ipairs(simple) do dst[k]=(dst[k] or 0)+(src[k] or 0) end
    for _,k in ipairs({'melee_mm','crit_mm','ranged_mm','ws_mm','magic_mm','mb_mm','nonmb_mm','cure_mm','taken_mm','taken_physical_mm','taken_magical_mm','taken_other_mm'}) do merge_minmax(dst[k],src[k]) end
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
    for name,sh in pairs(src.healing_actions or {}) do
        local dh=dst.healing_actions[name]; if not dh then dh={healing=0,uses=0,mm=fresh_minmax(),kind=sh.kind}; dst.healing_actions[name]=dh end
        dh.kind=dh.kind or sh.kind; dh.healing=dh.healing+(tonumber(sh.healing) or 0); dh.uses=dh.uses+(tonumber(sh.uses) or 0); merge_minmax(dh.mm,sh.mm)
    end
    for name,count in pairs(src.healed_targets or {}) do dst.healed_targets[name]=(dst.healed_targets[name] or 0)+(tonumber(count) or 0) end
    for name,count in pairs(src.healed_by or {}) do dst.healed_by[name]=(dst.healed_by[name] or 0)+(tonumber(count) or 0) end
    dst.actor_type=(dst.actor_type~='unknown' and dst.actor_type) or src.actor_type or 'unknown'; dst.session_scope=stronger_scope(dst.session_scope,src.session_scope); dst.session_order=math.min(tonumber(dst.session_order) or 999,tonumber(src.session_order) or 999); dst.weapon_class=dst.weapon_class or src.weapon_class
    Core.VP.merge_job_identity(dst,src)
    for alias in pairs(src.aliases or {}) do dst.aliases[alias]=true end
    for _,k in ipairs({'damage','melee','ranged','magic','ws','physical','other','skillchain','enspell','healing','dheal','dheal_melee','dheal_ranged','dheal_physical','dheal_magic','dheal_enspell','dheal_mb','dheal_skillchain','dheal_other','attempts','hits','misses','taken','taken_hits','cleanses','dispels','aspir_recovery','self_healing',
        'melee_attempts','melee_hits','melee_misses','ranged_attempts','ranged_hits','ranged_misses','ws_attempts','ws_hits','ws_misses',
        'magic_casts','magic_targets','magic_hits','magic_lands','magic_resists','magic_no_effect','mb_casts','mb_count','mb_damage','nonmb_casts','nonmb_count','nonmb_damage'}) do
        dst.pet[k]=(dst.pet[k] or 0)+(src.pet and src.pet[k] or 0)
    end
    if src.pet and src.pet.name then dst.pet.name=src.pet.name end
    dst.pet.instances=dst.pet.instances or {}
    for key,si in pairs((src.pet and src.pet.instances) or {}) do
        local di=dst.pet.instances[key] or {id=si.id,name=si.name,damage=0,melee=0,ranged=0,physical=0,magic=0,skillchain=0,other=0}; dst.pet.instances[key]=di
        for _,pk in ipairs({'damage','melee','ranged','physical','magic','skillchain','other'}) do di[pk]=(di[pk] or 0)+(tonumber(si[pk]) or 0) end
    end
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
    if entry then
        if entry.main_job then
            local incoming_main=Core.VP.normalize_job(entry.main_job); local current_main=Core.VP.normalize_job(actor.main_job or actor.inferred_job)
            if current_main~='-' and incoming_main~='-' and current_main~=incoming_main then
                actor.sub_job=nil; actor.inferred_subjob=nil; actor.subjob_evidence_score=0; actor.subjob_evidence=nil; actor.subjob_source=nil; actor.subjob_observed_at=0; actor.job_state={}
            end
            actor.main_job=incoming_main
        end
        if entry.sub_job then
            local incoming=Core.VP.normalize_job(entry.sub_job); local current_sub=Core.VP.normalize_job(actor.sub_job or actor.inferred_subjob)
            if entry.scope=='self' or actor.subjob_source~='observed' or current_sub==incoming then
                actor.sub_job=incoming; actor.inferred_subjob=actor.inferred_subjob or incoming; actor.subjob_source=(entry.scope=='self') and 'live-self' or (actor.subjob_source or 'party')
                if entry.scope=='self' then actor.subjob_evidence_score=2000; actor.inferred_subjob=incoming end
            end
        end
        actor.main_job_level=entry.main_job_level or actor.main_job_level; actor.sub_job_level=entry.sub_job_level or actor.sub_job_level
    end
    actor.aliases=actor.aliases or {}; if actor.id then actor.aliases[tostring(actor.id)]=true end
    return actor
end

local function session_merge_actor(src)
    if not src or src.actor_type=='enemy' or src.actor_type=='pet' then return end
    local key=session_key(src); if not key then return end
    local dst=session_actors[key]
    if not dst then dst=new_actor(src.id,src.name); dst.actor_type=src.actor_type; dst.session_scope=src.session_scope; dst.session_order=src.session_order; session_actors[key]=dst end
    dst.main_job_level=src.main_job_level or dst.main_job_level; dst.sub_job_level=src.sub_job_level or dst.sub_job_level
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
    return {id=Core.new_id('fight'),started=now,last=now,last_event=nil,last_combat_signal=now,active_committed=0,active_intervals={},active_poll_at=now,active_segment_started=now,idle_state='active',idle_since=nil,notice_text=nil,notice_until=0,activity=Core.Activity.new(settings.active_timeout),actors={},enemy_names={},enemy_ids={},enemy_indices={},target_damage={},events=0,generation=Core.VP.transition and Core.VP.transition.generation or 0}
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

function Core.VP.mark_combat_signal(encounter,now,reason)
    if not encounter then return end
    now=now or Core.now()
    local prior=encounter.last_combat_signal or now
    local quiet=math.max(0,now-prior)
    if encounter.idle_state=='paused' or not encounter.active_segment_started then
        encounter.active_segment_started=now
        encounter.idle_state='active'; encounter.idle_since=nil
        encounter.notice_text='Resumed'; encounter.notice_until=now+(tonumber(settings.notice_seconds) or 15)
    elseif encounter.idle_state=='idle' then
        encounter.idle_state='active'; encounter.idle_since=nil
        encounter.notice_text=('Restored %ds'):format(math.max(0,math.floor(quiet+0.5))); encounter.notice_until=now+(tonumber(settings.notice_seconds) or 15)
    end
    encounter.last_combat_signal=now; encounter.last_activity_reason=reason or encounter.last_activity_reason
    if encounter.activity then encounter.activity:mark(now) end
end

function Core.VP.active_value(encounter,now)
    if not encounter then return 0 end
    now=now or Core.now()
    local committed=tonumber(encounter.active_committed) or 0
    local started=tonumber(encounter.active_segment_started)
    if started then return math.max(0,committed+math.max(0,now-started)) end
    return math.max(0,committed)
end

function Core.VP.close_active_segment(encounter,end_at)
    if not encounter or not encounter.active_segment_started then return end
    end_at=tonumber(end_at) or Core.now()
    local started=tonumber(encounter.active_segment_started) or end_at
    if end_at>started then encounter.active_committed=(tonumber(encounter.active_committed) or 0)+(end_at-started) end
    encounter.active_segment_started=nil
end

local function update_shared_clock(encounter,now)
    if not encounter then return false end
    now=now or Core.now()
    -- Being actively engaged with an established encounter is itself battle
    -- evidence, even if no damage packet has arrived during a mechanic/sleep.
    if not encounter.observer and alliance_engaged_with_encounter(encounter,refresh_party(now)) then Core.VP.mark_combat_signal(encounter,now,'engaged') end
    if not encounter.active_segment_started then
        if encounter.notice_until and now>=encounter.notice_until then encounter.notice_text=nil end
        encounter.active_poll_at=now; return false
    end
    local quiet=math.max(0,now-(tonumber(encounter.last_combat_signal) or now))
    local detect=tonumber(settings.idle_detect_seconds) or 30
    local timeout=tonumber(settings.idle_timeout_seconds) or 60
    if quiet>=timeout then
        -- The whole provisional idle gap is omitted. Commit only through the
        -- last qualifying battle signal and immediately enter Paused state.
        Core.VP.close_active_segment(encounter,encounter.last_combat_signal or now)
        encounter.idle_state='paused'; encounter.idle_since=encounter.last_combat_signal
        encounter.notice_text=('Idle %ds Omitted'):format(math.floor(timeout+0.5)); encounter.notice_until=now+(tonumber(settings.notice_seconds) or 15)
    elseif quiet>=detect then
        encounter.idle_state='idle'; encounter.idle_since=encounter.last_combat_signal
    else
        encounter.idle_state='active'; encounter.idle_since=nil
    end
    if encounter.notice_until and now>=encounter.notice_until then encounter.notice_text=nil end
    encounter.active_poll_at=now
    return encounter.active_segment_started~=nil
end

function Core.VP.active_display_text(source,now)
    now=now or Core.now()
    local encounter=source and source._active_ref or (source==current and current or nil)
    local active
    if source and source~=current and tonumber(source.active_committed)~=nil then active=tonumber(source.active_committed)
    elseif encounter then active=Core.VP.active_value(encounter,now)
    else active=tonumber(source and source.active_committed) or 0 end
    local base=Core.VP.duration_hms and Core.VP.duration_hms(active) or Core.duration(active)
    if not encounter then return base end
    local quiet=math.max(0,now-(tonumber(encounter.last_combat_signal) or now))
    local detect=tonumber(settings.idle_detect_seconds) or 30; local timeout=tonumber(settings.idle_timeout_seconds) or 60
    if encounter.idle_state=='idle' and quiet>=detect and quiet<timeout then
        local confirmed=math.max(0,active-quiet)
        return (Core.VP.duration_hms and Core.VP.duration_hms(confirmed) or Core.duration(confirmed))..' +'..Core.VP.delta_duration(quiet)..' (Idle)'
    elseif encounter.idle_state=='paused' then
        local suffix=encounter.notice_text and (' (Paused | '..encounter.notice_text..')') or ' (Paused)'; return base..suffix
    elseif encounter.notice_text then return base..' ('..encounter.notice_text..')' end
    return base
end

local function ensure_encounter(now,hostile)
    now=now or Core.now()
    if not current then
        if not hostile then return nil end
        current=new_encounter(now); current.last_hostile=now
    end
    update_shared_clock(current,now)
    current.last_event=now; current.last=now
    if hostile then current.last_hostile=now; Core.VP.mark_combat_signal(current,now,'hostile') end
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
    local batch={}
    for _,a in ipairs(rows) do
        local total=combined_damage(a); local dps=active>0 and total/active or 0
        local acc=a.melee_attempts>0 and (100*a.melee_hits/a.melee_attempts) or ''
        local racc=a.ranged_attempts>0 and (100*a.ranged_hits/a.ranged_attempts) or ''
        local land_denom=(tonumber(a.magic_lands) or 0)+(tonumber(a.magic_resists) or 0); local landpct=land_denom>0 and (100*(tonumber(a.magic_lands) or 0)/land_denom) or ''
        local reconcile=total-(player_net_damage(a)+pet_net_damage(a))
        batch[#batch+1]={record_type,os.date('%Y-%m-%d %H:%M:%S'),reason or source.id or '-',('%.2f'):format(elapsed),('%.2f'):format(active),a.name,a.damage,a.pet and a.pet.damage or 0,total,('%.2f'):format(dps),a.melee,a.ranged,a.magic,a.enspell,a.other,a.ws_damage,a.ws_attempts,a.ws_hits,a.ws_misses,avg(a.ws_mm) and ('%.2f'):format(avg(a.ws_mm)) or '',acc~='' and ('%.2f'):format(acc) or '',racc~='' and ('%.2f'):format(racc) or '',landpct~='' and ('%.2f'):format(landpct) or '',a.skillchain,a.mb_damage,a.dheal,a.taken,a.healing,a.self_healing,a.cleanses,a.dispels,a.aspir_recovery,a.received,reconcile}
    end
    Core.VP.append_log_batch(batch)
end

local function finalize_encounter(now)
    if not current then return end
    now=now or Core.now(); update_shared_clock(current,now)
    if current.active_segment_started then Core.VP.close_active_segment(current,math.min(now,tonumber(current.last_combat_signal) or now)) end
    current.ended=now; if current.activity then current.activity:tick(now) end
    log_source('FIGHT',current,now,current.id)
    last_fight=current
    history[#history+1]=current
    while #history>settings.history_limit do table.remove(history,1) end
    for _,src in pairs(current.actors or {}) do session_merge_actor(src) end
    session_active_committed=session_active_committed+(tonumber(current.active_committed) or 0)
    current=nil
    target_learning={}; target_lives={}
    Core.VP.registry_dirty=true
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

local function owner_for(actor_id,party)
    local mob=Core.mob(windower,actor_id)
    local owner=mob and tonumber(mob.owner_id or mob.owner or 0) or 0
    if owner and owner~=0 then return owner,mob end
    local mob_index=mob and tonumber(mob.index or mob.mob_index or 0) or 0
    for owner_id,entry in pairs((party and party.by_id) or {}) do
        local emob=entry and (entry.mob or Core.mob(windower,owner_id)) or nil
        local pet_index=tonumber((entry and entry.member and entry.member.pet_index) or (emob and emob.pet_index) or 0) or 0
        if pet_index~=0 then
            if mob_index~=0 and pet_index==mob_index then return owner_id,mob end
            if windower.ffxi.get_mob_by_index then
                local pet=windower.ffxi.get_mob_by_index(pet_index)
                if pet and tonumber(pet.id)==tonumber(actor_id) then return owner_id,mob end
            end
        end
    end
    if windower.ffxi.get_mob_by_target and party and party.self_id then
        local ok,pet=pcall(windower.ffxi.get_mob_by_target,'pet')
        if ok and pet and tonumber(pet.id)==tonumber(actor_id) then return party.self_id,mob end
    end
    return nil,mob
end

local function allied_relation(actor_id,party)
    local scope,entry=Core.actor_scope(windower,actor_id,party)
    if scope~='outside' then return true,scope,entry,entry and entry.actor_type or 'player',nil,entry and entry.mob or Core.mob(windower,actor_id) end
    local owner,mob=owner_for(actor_id,party)
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

-- Outside-observed collection is intentionally encounter-bound. VanaParse does
-- not turn every nearby fight into parse data: an outside player/pet is admitted
-- only after the local party/alliance has established the encounter and that
-- actor directly acts on an already-known encounter enemy.
function Core.VP.action_targets_encounter(act,encounter)
    if not encounter or not encounter.enemy_ids then return false end
    for _,target in ipairs(act.targets or {}) do
        if encounter.enemy_ids[target.id] then return true end
    end
    return false
end

function Core.VP.observed_outside_relation(actor_id,party)
    local scope,entry=Core.actor_scope(windower,actor_id,party)
    if scope~='outside' then
        return true,scope,entry,entry and entry.actor_type or 'player',nil,entry and entry.mob or Core.mob(windower,actor_id)
    end
    local owner,mob=owner_for(actor_id,party)
    if owner then
        local owner_scope,owner_entry=Core.actor_scope(windower,owner,party)
        if owner_scope~='outside' then
            return true,owner_scope,owner_entry,'pet',owner,mob
        end
        local owner_mob=Core.mob(windower,owner)
        if owner_mob and owner_mob.is_npc==false then
            return true,'outside',nil,'pet',owner,mob
        end
    end
    if mob and mob.is_npc==false then
        return true,'outside',nil,'player',nil,mob
    end
    return false,'outside',nil,'unknown',nil,mob
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
            p.damage=p.damage+counted; p.name=actor.name; p[pkind]=(p[pkind] or 0)+counted; Core.VP.note_pet_instance(master_actor,actor,counted,pkind)
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
    if dtype=='physical' then target.taken_physical=target.taken_physical+amount; target.taken_physical_hits=(target.taken_physical_hits or 0)+1; add_minmax(target.taken_physical_mm,amount)
    elseif dtype=='magical' then target.taken_magical=target.taken_magical+amount; target.taken_magical_hits=(target.taken_magical_hits or 0)+1; add_minmax(target.taken_magical_mm,amount)
    else target.taken_unknown=target.taken_unknown+amount; target.taken_other_hits=(target.taken_other_hits or 0)+1; add_minmax(target.taken_other_mm,amount) end
end

local note_weapon_class_from_ws

function Core.VP.incoming_resource_name(category,act)
    local first=act and act.targets and act.targets[1] and act.targets[1].actions and act.targets[1].actions[1] or nil
    local id=tonumber(first and first.param) or tonumber(act and act.param)
    if not id or id==28787 then return nil end
    local r=nil
    if category==8 then r=res.spells and res.spells[id]
    elseif category==7 then r=(res.monster_abilities and res.monster_abilities[id]) or (res.weapon_skills and res.weapon_skills[id]) or (res.job_abilities and res.job_abilities[id]) end
    return r and (r.en or r.english or r.name) or (id and ('Action '..tostring(id)) or nil)
end
function Core.VP.note_incoming_start(act,party,now)
    local category=tonumber(act and act.category) or 0
    if category~=7 and category~=8 then return end
    local allied=select(1,allied_relation(act.actor_id,party)); if allied then return end
    local relevant=false
    for _,t in ipairs(act.targets or {}) do if select(1,allied_relation(t.id,party)) then relevant=true break end end
    if not relevant then return end
    local name=Core.VP.incoming_resource_name(category,act); if not name then
        if tonumber(act.param)==28787 then if incoming_action and incoming_action.actor_id==act.actor_id then incoming_action.resolved_at=now end end
        return
    end
    incoming_action={actor_id=act.actor_id,name=name,started=now,resolved_at=nil}
end
function Core.VP.note_incoming_resolution(act,now)
    if not incoming_action or incoming_action.actor_id~=act.actor_id then return end
    local category=tonumber(act.category) or 0
    if category==3 or category==4 or category==6 or category==11 or category==13 or category==14 or category==15 then incoming_action.resolved_at=now end
end
function Core.VP.incoming_display_for(actor_id,now)
    if not incoming_action or incoming_action.actor_id~=actor_id then return nil end
    now=now or Core.now()
    if not incoming_action.resolved_at and now-(incoming_action.started or now)>INCOMING_TIMEOUT then incoming_action.resolved_at=now end
    if incoming_action.resolved_at then
        local e=now-incoming_action.resolved_at; local total=INCOMING_FLASH_STEP*INCOMING_FLASHES*2
        if e>=total then incoming_action=nil; return nil end
        local phase=math.floor(e/INCOMING_FLASH_STEP)
        if phase%2==1 then return '' end
    end
    return Core.color_text(incoming_action.name,255,64,64)
end


function Core.VP.cache_job(actor,job,is_sub,evidence,score,decisive)
    if not actor or not job or job=='' then return false end
    job=tostring(job):upper():sub(1,3)
    score=tonumber(score) or (is_sub and 700 or 800)
    decisive=decisive==true
    local main=Core.VP.normalize_job and Core.VP.normalize_job(actor.main_job or actor.inferred_job) or tostring(actor.main_job or actor.inferred_job or ''):upper():sub(1,3)
    local key=Core.lower(actor.name or tostring(actor.id or ''))
    local accepted=false
    if is_sub then
        if main~='' and main~='-' and main==job then return false end
        local current=Core.VP.normalize_job and Core.VP.normalize_job(actor.sub_job or actor.inferred_subjob) or tostring(actor.sub_job or actor.inferred_subjob or ''):upper():sub(1,3)
        local current_score=tonumber(actor.subjob_evidence_score) or 0
        local player=windower.ffxi.get_player and windower.ffxi.get_player() or nil
        local live_self=player and tonumber(player.id)==tonumber(actor.id)
        -- The local player's live subjob is authoritative. Remote party/check
        -- metadata can be stale, so a job-exclusive observed action/spell is
        -- allowed to correct it immediately.
        if live_self and actor.sub_job and current~='-' and current~=job then return false end
        local conflict=current~='' and current~='-' and current~=job
        local replace=not conflict or decisive or (not actor.sub_job and score>=current_score)
        if replace then
            if conflict then actor.subjob_conflicts=(tonumber(actor.subjob_conflicts) or 0)+1 end
            actor.inferred_subjob=job
            if decisive and not live_self then actor.sub_job=job end
            actor.subjob_evidence_score=decisive and score or math.max(current_score,score)
            actor.subjob_evidence=evidence or actor.subjob_evidence
            actor.subjob_source=decisive and 'observed' or (actor.subjob_source or 'inferred')
            if decisive then actor.subjob_observed_at=Core.now() end
            accepted=true
        end
    else
        if actor.main_job then return Core.VP.normalize_job(actor.main_job)==job end
        local current_score=tonumber(actor.mainjob_evidence_score) or 0
        if actor.inferred_job==job or score>=current_score then
            actor.inferred_job=job
            actor.mainjob_evidence_score=math.max(current_score,score)
            actor.job_evidence=evidence or actor.job_evidence
            accepted=true
        end
    end
    if key~='' and accepted then
        local c=Core.VP.job_cache[key] or {}; Core.VP.job_cache[key]=c
        if is_sub then
            c.sub=job
            c.sub_score=decisive and score or math.max(tonumber(c.sub_score) or 0,score)
            c.sub_evidence=evidence or c.sub_evidence
            c.sub_source=decisive and 'observed' or (c.sub_source or 'inferred')
        else c.main=job; c.main_score=math.max(tonumber(c.main_score) or 0,score) end
        c.evidence=evidence or c.evidence; c.at=Core.now()
    end
    return accepted
end

function Core.VP.note_job_state(actor,label)
    if not actor then return end
    actor.job_state=actor.job_state or {}
    local l=Core.lower(label or '')
    if l=='light arts' then actor.job_state.scholar=true; actor.job_state.light_arts=true
    elseif l=='dark arts' then actor.job_state.scholar=true; actor.job_state.dark_arts=true
    elseif l=='addendum: white' then actor.job_state.scholar=true; actor.job_state.light_arts=true; actor.job_state.addendum_white=true
    elseif l=='addendum: black' then actor.job_state.scholar=true; actor.job_state.dark_arts=true; actor.job_state.addendum_black=true
    elseif l=='sublimation' then actor.job_state.scholar=true end
end

function Core.VP.resource_job_abbrev(job_key)
    local jid=tonumber(job_key)
    local j=jid and res.jobs and res.jobs[jid] or nil
    if j then return tostring(j.ens or j.en or j.english_short or j.english or ''):upper():sub(1,3) end
    local raw=tostring(job_key or ''):upper()
    if #raw<=3 then return raw end
    if res.jobs then
        for _,r in pairs(res.jobs) do
            local short=tostring(r.ens or r.english_short or ''):upper()
            if short==raw or Core.lower(r.en or r.english or '')==Core.lower(raw) then return short:sub(1,3) end
        end
    end
    return raw:sub(1,3)
end

function Core.VP.spell_job_candidates(spell)
    local out={}
    local levels=spell and (spell.levels or spell.jobs) or nil
    if type(levels)~='table' then return out end
    for jid,lvl in pairs(levels) do
        lvl=tonumber(lvl)
        if lvl and lvl>0 then
            local job=Core.VP.resource_job_abbrev(jid)
            if job and job~='' and job~='NON' then out[#out+1]={job=job,level=lvl} end
        end
    end
    table.sort(out,function(a,b) if a.level==b.level then return a.job<b.job end return a.level<b.level end)
    return out
end

function Core.VP.infer_job_from_action(actor,category,param,label)
    if not actor or actor.actor_type~='player' then return end
    label=tostring(label or '')
    local lower=Core.lower(label)
    Core.VP.note_job_state(actor,label)
    local cap=tonumber(Core.VP.SUBJOB_LEVEL_CAP) or 59
    local main=Core.VP.normalize_job and Core.VP.normalize_job(actor.main_job or actor.inferred_job) or tostring(actor.main_job or actor.inferred_job or ''):upper():sub(1,3)

    -- Existing explicit evidence table. Anything above the current support-job
    -- cap is main-job evidence; lower actions are support-job evidence once a
    -- different main job is known.
    local entry=Core.VP.JOB_EVIDENCE[lower]
    if entry then
        local job,level=entry[1],tonumber(entry[2]) or 99
        if level>cap then Core.VP.cache_job(actor,job,false,label,900)
        elseif main~='' and main~='-' and main~=job then Core.VP.cache_job(actor,job,true,label,850,true) end
    end

    -- Job abilities that are safe support-job identifiers. Resource action
    -- types cover whole DNC/COR/SCH families; named evidence covers other jobs.
    local ja=res.job_abilities and res.job_abilities[tonumber(param)] or nil
    local ja_type=ja and Core.lower(ja.type or '') or ''
    local subjob=Core.VP.SUBJOB_ACTION_EVIDENCE[lower] or Core.VP.SUBJOB_ACTION_TYPE_EVIDENCE[ja_type]
    if subjob and main~='' and main~='-' and main~=subjob then
        Core.VP.cache_job(actor,subjob,true,label,900,true)
    end

    if tonumber(category)==4 then
        local sp=res.spells and res.spells[tonumber(param)] or nil
        local candidates=Core.VP.spell_job_candidates(sp)
        if #candidates>0 then
            -- Main-job proof is conservative: a spell only proves a main job
            -- when exactly one job can use it and its required level is above
            -- the support-job ceiling.
            if #candidates==1 and candidates[1].level>cap then
                Core.VP.cache_job(actor,candidates[1].job,false,label,880)
                main=Core.VP.normalize_job and Core.VP.normalize_job(actor.main_job or actor.inferred_job) or candidates[1].job
            end

            if main~='' and main~='-' then
                local subs={}
                for _,c in ipairs(candidates) do if c.job~=main and c.level<=cap then subs[#subs+1]=c end end
                if #subs==1 then
                    Core.VP.cache_job(actor,subs[1].job,true,label,820,true)
                elseif #subs>1 then
                    -- Reraise is WHM25 or SCH35 with Addendum: White. Treat
                    -- observed Scholar state as /SCH; without Scholar state a
                    -- non-WHM/non-SCH main resolves to /WHM. This also repairs
                    -- a stale prior inference after reload.
                    if lower=='reraise' then
                        if actor.job_state and actor.job_state.scholar then Core.VP.cache_job(actor,'SCH',true,label..' + Scholar state',900,true)
                        else
                            for _,c in ipairs(subs) do if c.job=='WHM' then Core.VP.cache_job(actor,'WHM',true,label..' (no Scholar state observed)',600,true); break end end
                        end
                    else
                        -- For other ambiguous spells, preserve a currently
                        -- compatible support job until unique evidence appears.
                        local known=Core.VP.normalize_job and Core.VP.normalize_job(actor.sub_job or actor.inferred_subjob) or tostring(actor.sub_job or actor.inferred_subjob or ''):upper():sub(1,3)
                        for _,c in ipairs(subs) do if known==c.job then return end end
                    end
                end
            end
        end
    end
end

function Core.VP.apply_job_metadata(actor_id,main_job,sub_job,evidence)
    actor_id=tonumber(actor_id); if not actor_id then return end
    local mob=Core.mob(windower,actor_id); local name=mob and mob.name or nil
    local player=windower.ffxi.get_player and windower.ffxi.get_player() or nil
    local live_self=player and tonumber(player.id)==actor_id
    local function apply_to(store)
        for _,a in pairs(store or {}) do
            if a and (tonumber(a.id)==actor_id or (name and Core.lower(a.name)==Core.lower(name))) then
                if main_job~=nil then a.main_job=Core.VP.normalize_job(main_job); a.inferred_job=a.main_job; a.mainjob_evidence_score=1000 end
                if sub_job~=nil then
                    local sj=Core.VP.normalize_job(sub_job)
                    -- An observed job-exclusive action is stronger than stale
                    -- remote metadata. The local player's live job remains authoritative.
                    if live_self or a.subjob_source~='observed' or Core.VP.normalize_job(a.sub_job or a.inferred_subjob)==sj then
                        a.sub_job=sj; a.inferred_subjob=sj; a.subjob_evidence_score=1000; a.subjob_evidence=evidence or 'Check metadata'; a.subjob_source=live_self and 'live-self' or 'check'
                    end
                end
                a.job_evidence=evidence or 'Check metadata'
            end
        end
    end
    if current then apply_to(current.actors) end; apply_to(session_actors)
    for _,enc in pairs(Core.VP.observer and Core.VP.observer.encounters or {}) do apply_to(enc.actors) end
    local key=Core.lower(name or tostring(actor_id)); local c=Core.VP.job_cache[key] or {}; Core.VP.job_cache[key]=c
    if main_job~=nil then c.main=Core.VP.normalize_job(main_job); c.main_score=1000 end
    if sub_job~=nil then
        local sj=Core.VP.normalize_job(sub_job)
        if live_self or c.sub_source~='observed' or c.sub==sj then c.sub=sj; c.sub_score=1000; c.sub_evidence=evidence or 'Check metadata'; c.sub_source=live_self and 'live-self' or 'check' end
    end
    c.evidence=evidence or 'Check metadata'; c.at=Core.now()
end

function Core.VP.process_check_chunk(original)
    local ok,pkt=pcall(Core.VP.packets.parse,'incoming',original); if not ok or type(pkt)~='table' then return end
    local typ=tonumber(pkt['Type'] or pkt['Check Type'] or pkt['Subtype'] or pkt['_type'])
    if typ and typ~=1 then return end
    local actor_id=tonumber(pkt['Target ID'] or pkt['Target'] or pkt['Player'] or pkt['ID'])
    local main=pkt['Main Job'] or pkt['Main job'] or pkt['Main Job ID']
    local sub=pkt['Sub Job'] or pkt['Sub job'] or pkt['Sub Job ID']
    if actor_id and (main~=nil or sub~=nil) then Core.VP.apply_job_metadata(actor_id,main,sub,'/check metadata') end
end

function Core.VP.with_current(temp,fn)
    local old=current; current=temp
    local ok,a,b,c=pcall(fn)
    current=old
    if not ok then error(a) end
    return a,b,c
end
function Core.VP.observer_mob_kind(mob)
    if not mob then return 'unknown',nil end
    local owner=tonumber(mob.owner_id or mob.owner or 0) or 0
    if owner~=0 then return 'pet',owner end
    local st=tonumber(mob.spawn_type)
    if mob.is_npc==false or st==1 or st==4 or st==8 or st==13 then return 'player',nil end
    if st==14 then return 'trust',nil end
    if st==16 then return 'enemy',nil end
    if mob.is_npc and mob.id then
        local mod=tonumber(mob.id)%4096
        if mod<2048 then return 'enemy',nil end
    end
    return 'unknown',nil
end
function Core.VP.observer_enemy_key(mob)
    if not mob or not mob.id then return nil end
    return table.concat({tostring(mob.id),tostring(mob.index or '?'),tostring(mob.name or '?')},':')
end
function Core.VP.observer_get(enemy,now)
    local key=Core.VP.observer_enemy_key(enemy); if not key then return nil,nil end
    local o=Core.VP.observer; local enc=o.encounters[key]
    if not enc then
        enc=new_encounter(now); enc.observer=true; enc.observer_key=key; enc.enemy_names={[enemy.name or tostring(enemy.id)]=true}; enc.enemy_ids={[enemy.id]=true}; enc.enemy_indices={[enemy.index or -1]=true}; enc.target_damage={}; enc.display_name=enemy.name or tostring(enemy.id)
        o.encounters[key]=enc; o.order[#o.order+1]=key
    end
    enc.last=now; o.focus=key
    return enc,key
end
function Core.VP.observer_actor(enc,actor_id,mob,kind,owner_id)
    local actor=actor_for(enc.actors,actor_id,mob and mob.name or Core.mob_name(windower,actor_id))
    annotate_actor(actor,nil,kind or 'player','outside',999)
    if kind=='pet' and owner_id then
        local om=Core.mob(windower,owner_id); local master=actor_for(enc.actors,owner_id,om and om.name or Core.mob_name(windower,owner_id)); annotate_actor(master,nil,'player','outside',999)
        return actor,master
    end
    if kind=='pet' then actor.actor_type='allied_npc'; actor.name=(actor.name or 'Pet')..' ['..tostring(actor.id or '?')..']' end
    return actor,nil
end
function Core.VP.observer_cleanup(now)
    local o=Core.VP.observer; now=now or Core.now()
    if now-(tonumber(o.last_cleanup) or 0)<2 then return end; o.last_cleanup=now
    local stale=tonumber(settings.observer_stale_seconds) or 180; local keep={}
    for _,key in ipairs(o.order or {}) do
        local enc=o.encounters[key]
        if enc then
            update_shared_clock(enc,now)
            if now-(tonumber(enc.last) or now)<=stale then keep[#keep+1]=key else o.encounters[key]=nil end
        end
    end
    o.order=keep
    while #o.order>(tonumber(settings.observer_max_encounters) or 24) do local key=table.remove(o.order,1); o.encounters[key]=nil end
    if o.focus and not o.encounters[o.focus] then o.focus=o.order[#o.order] end
    for actor_id,key in pairs(o.actor_to_encounter or {}) do if not o.encounters[key] then o.actor_to_encounter[actor_id]=nil end end
end
function Core.VP.observer_selected_source()
    Core.VP.observer_cleanup(Core.now()); local o=Core.VP.observer
    if o.focus and o.encounters[o.focus] then return o.encounters[o.focus] end
    local key=o.order[#o.order]; return key and o.encounters[key] or nil
end
function Core.VP.observer_focus(direction_or_name)
    local o=Core.VP.observer; Core.VP.observer_cleanup(Core.now()); if #o.order==0 then return false,'No observed encounters.' end
    local token=Core.lower(direction_or_name or '')
    if token=='' or token=='current' or token=='target' then
        local t=windower.ffxi.get_mob_by_target and windower.ffxi.get_mob_by_target('t') or nil; local key=t and Core.VP.observer_enemy_key(t) or nil
        if key and o.encounters[key] then o.focus=key; return true,'Observing '..tostring(o.encounters[key].display_name or t.name)..'.' end
        return false,'Current target is not in the observer ledger.'
    end
    local idx=1; for i,key in ipairs(o.order) do if key==o.focus then idx=i break end end
    if token=='next' then idx=idx%#o.order+1
    elseif token=='previous' or token=='prev' then idx=(idx-2)%#o.order+1
    else
        local found=nil; for i,key in ipairs(o.order) do local e=o.encounters[key]; if e and Core.lower(e.display_name or ''):find(token,1,true) then found=i break end end
        if not found then return false,'Observed encounter not found: '..tostring(direction_or_name) end; idx=found
    end
    o.focus=o.order[idx]; local e=o.encounters[o.focus]; return true,'Observing '..tostring(e and e.display_name or o.focus)..'.'
end
function Core.VP.observer_record(act,now)
    if type(act)~='table' then return end; now=now or Core.now()
    local actor_mob=Core.mob(windower,act.actor_id); if not actor_mob then return end
    local kind,owner_id=Core.VP.observer_mob_kind(actor_mob); local category=tonumber(act.category) or 0
    if kind=='enemy' then
        local key=Core.VP.observer_enemy_key(actor_mob); local enc=key and Core.VP.observer.encounters[key] or nil
        if enc then Core.VP.mark_combat_signal(enc,now,'enemy action'); enc.last=now end
        return
    end
    if kind~='player' and kind~='pet' and kind~='trust' then return end
    local enemy_targets={}
    for _,tp in ipairs(act.targets or {}) do local tm=Core.mob(windower,tp.id); local tk=Core.VP.observer_mob_kind(tm); if tk=='enemy' then enemy_targets[#enemy_targets+1]={packet=tp,mob=tm} end end
    if #enemy_targets==0 then
        local key=Core.VP.observer.actor_to_encounter[act.actor_id] or (owner_id and Core.VP.observer.actor_to_encounter[owner_id])
        if not key then for _,tp in ipairs(act.targets or {}) do key=Core.VP.observer.actor_to_encounter[tp.id]; if key then break end end end
        local enc=key and Core.VP.observer.encounters[key] or nil
        if enc then
            Core.VP.mark_combat_signal(enc,now,'support'); enc.last=now; Core.VP.observer.actor_to_encounter[act.actor_id]=key; if owner_id then Core.VP.observer.actor_to_encounter[owner_id]=key end
            local actor,master=Core.VP.observer_actor(enc,act.actor_id,actor_mob,kind,owner_id); if kind=='player' then Core.VP.infer_job_from_action(actor,category,act.param,action_name(category,act.param)) end
            local is_pet=(kind=='pet' and master~=nil); local semantics=Core.action_semantics(res,category,act.param,is_pet); local total_heal=0; local cures=0; local cleanses=0
            Core.VP.with_current(enc,function()
                for _,tp in ipairs(act.targets or {}) do
                    if Core.VP.observer.actor_to_encounter[tp.id]==key or tp.id==act.actor_id then
                        for _,sub in ipairs(tp.actions or {}) do
                            local mode,amount=record_outgoing(actor,category,act.param,sub,tp.id,action_name(category,act.param),now,is_pet,master,true,semantics)
                            if mode=='heal' and amount>0 then total_heal=total_heal+amount; cures=cures+1 end
                            if semantics.cleanse and not is_miss(sub) and not is_resist(sub) and not is_no_effect(sub) then cleanses=cleanses+1 end
                        end
                    end
                end
            end)
            if total_heal>0 then actor.healing=actor.healing+total_heal; actor.cures=actor.cures+1; add_minmax(actor.cure_mm,total_heal); Core.VP.add_healing_action(actor,action_name(category,act.param),total_heal,1,'cure',now); actor.healing_window:add(total_heal,now); if is_pet and master then master.pet.healing=(master.pet.healing or 0)+total_heal end end
            if cleanses>0 then actor.cleanses=(actor.cleanses or 0)+cleanses end
        end
        return
    end
    local label=action_name(category,act.param)
    for _,et in ipairs(enemy_targets) do
        local enc,key=Core.VP.observer_get(et.mob,now); if enc then
            Core.VP.mark_combat_signal(enc,now,'observed combat')
            Core.VP.observer.actor_to_encounter[act.actor_id]=key; if owner_id then Core.VP.observer.actor_to_encounter[owner_id]=key end
            local actor,master=Core.VP.observer_actor(enc,act.actor_id,actor_mob,kind,owner_id)
            if kind=='player' then Core.VP.infer_job_from_action(actor,category,act.param,label) end
            local is_pet=(kind=='pet' and master~=nil); local semantics=Core.action_semantics(res,category,act.param,is_pet)
            local ws_damage,ws_hit,ws_seen=0,false,false; local magic_outcomes={}; local magic_outcome=category==4 and {damage=0,healing=0,mb=false,resist=false,no_effect=false,success=false,seen=false} or nil
            Core.VP.with_current(enc,function()
                for _,sub in ipairs(et.packet.actions or {}) do
                    local mode,amount=record_outgoing(actor,category,act.param,sub,et.packet.id,label,now,is_pet,master,false,semantics)
                    if category==3 then ws_seen=true; if mode=='damage' and amount>0 and not is_miss(sub) then ws_hit=true; ws_damage=ws_damage+amount end end
                    if magic_outcome then
                        magic_outcome.seen=true; magic_outcome.mb=magic_outcome.mb or is_magic_burst(sub); magic_outcome.resist=magic_outcome.resist or is_resist(sub); magic_outcome.no_effect=magic_outcome.no_effect or is_no_effect(sub)
                        if mode=='damage' and amount>0 then magic_outcome.damage=magic_outcome.damage+amount; magic_outcome.success=true elseif not is_miss(sub) and not is_resist(sub) and not is_no_effect(sub) then magic_outcome.success=true end
                    end
                    record_additional_effect(actor,category,act.param,sub,et.packet.id,now,is_pet,master)
                end
            end)
            if category==4 and magic_outcome and magic_outcome.seen then record_magic_cast(actor,label,{magic_outcome},is_pet,master,act.param) end
            if category==3 and ws_seen then
                note_weapon_class_from_ws(actor,act.param); actor.ws_attempts=actor.ws_attempts+1
                local w=actor.ws[label] or {damage=0,attempts=0,hits=0,misses=0,mm=fresh_minmax()}; actor.ws[label]=w; w.attempts=w.attempts+1
                if ws_hit then actor.ws_hits=actor.ws_hits+1; actor.ws_damage=actor.ws_damage+ws_damage; w.hits=w.hits+1; w.damage=w.damage+ws_damage; if ws_damage>0 then add_minmax(actor.ws_mm,ws_damage); add_minmax(w.mm,ws_damage) end
                else actor.ws_misses=actor.ws_misses+1; w.misses=w.misses+1 end
            end
            enc.events=(enc.events or 0)+1
        end end
    Core.VP.observer_cleanup(now)
end

function Core.VP.note_pet_instance(master,pet_actor,amount,kind)
    if not master or not master.pet or not pet_actor then return end
    master.pet.instances=master.pet.instances or {}
    local key=tostring(pet_actor.id or '?')..':'..tostring(pet_actor.name or 'Pet')
    local rec=master.pet.instances[key]
    if not rec then rec={id=pet_actor.id,name=pet_actor.name or 'Pet',damage=0,melee=0,ranged=0,physical=0,magic=0,skillchain=0,other=0}; master.pet.instances[key]=rec end
    amount=tonumber(amount) or 0; rec.damage=rec.damage+amount; kind=kind or 'other'; rec[kind]=(rec[kind] or 0)+amount
end

function Core.VP.transition_begin(reason,min_seconds,max_seconds)
    local t=Core.VP.transition; local now=Core.now(); t.active=true; t.state='settling'; t.generation=(tonumber(t.generation) or 0)+1; t.reason=reason or 'transition'; t.started=now
    t.min_until=now+(tonumber(min_seconds) or settings.transition_full_min); t.max_until=now+(tonumber(max_seconds) or settings.transition_full_max); t.last_probe=0; t.stable=0
    incoming_action=nil; last_target_id=nil; target_learning={}; target_lives={}; forced_miss_windows={}
    if Core.VP.observer then Core.VP.observer.encounters={}; Core.VP.observer.order={}; Core.VP.observer.focus=nil; Core.VP.observer.actor_to_encounter={} end
end
function Core.VP.transition_valid()
    local info=windower.ffxi.get_info and windower.ffxi.get_info() or nil; local player=windower.ffxi.get_player and windower.ffxi.get_player() or nil
    if not (info and info.logged_in and tonumber(info.zone) and player and tonumber(player.id) and tonumber(player.index)) then return false end
    if not Core.mob(windower,player.id) then return false end
    local ok,snap=pcall(Core.party_snapshot,windower); if not ok or type(snap)~='table' or not snap.self_id then return false end
    return true
end
function Core.VP.transition_finish(now)
    local t=Core.VP.transition; t.active=false; t.state='ready'; t.stable=0; party_cache=Core.party_snapshot(windower); party_cache_at=now or Core.now()
    if t.pending_finalize then t.pending_finalize=false; if current then finalize_encounter(now or Core.now()) end end
end
function Core.VP.transition_tick(now)
    local t=Core.VP.transition; now=now or Core.now()
    if not t.active then return false end
    if now<t.min_until then return true end
    if now-t.last_probe>=0.35 then
        t.last_probe=now
        if Core.VP.transition_valid() then t.stable=t.stable+1 else t.stable=0 end
    end
    if t.stable>=3 then Core.VP.transition_finish(now); return false end
    if now>=t.max_until and Core.VP.transition_valid() then Core.VP.transition_finish(now); return false end
    return true
end
function Core.VP.detect_micro_transition(now)
    local t=Core.VP.transition; now=now or Core.now(); if t.active then return true end
    local info=windower.ffxi.get_info and windower.ffxi.get_info() or nil; local player=windower.ffxi.get_player and windower.ffxi.get_player() or nil
    if not info or not player then return false end
    local mob=Core.mob(windower,player.id); if not mob then return false end
    local submap=nil; if windower.ffxi.get_map_data then local ok,a=pcall(windower.ffxi.get_map_data,player.index); if ok then submap=a end end
    local zone=tonumber(info.zone); local x,y,z=tonumber(mob.x),tonumber(mob.y),tonumber(mob.z)
    if t.last_zone and zone==t.last_zone and t.last_x and x and y then
        local dx=x-t.last_x; local dy=y-t.last_y; local dz=(z or 0)-(t.last_z or 0); local dist=math.sqrt(dx*dx+dy*dy+dz*dz)
        if dist>=80 or (submap and t.last_submap and submap~=t.last_submap) then
            t.last_zone,t.last_submap,t.last_x,t.last_y,t.last_z=zone,submap,x,y,z
            t.pending_finalize=current~=nil; Core.VP.transition_begin('teleport',settings.transition_micro_min,settings.transition_micro_max); t.pending_finalize=current~=nil; return true
        end
    end
    t.last_zone,t.last_submap,t.last_x,t.last_y,t.last_z=zone,submap,x,y,z
    return false
end

local function process_action(act)
    if settings.paused or type(act)~='table' then return end
    local now=Core.now(); if Core.VP.transition_tick(now) or Core.VP.detect_micro_transition(now) then return end
    local party=refresh_party(now); local category=tonumber(act.category) or 0
    Core.safe_call('observer-action',Core.VP.observer_record,on_error,act,now)
    Core.VP.note_incoming_start(act,party,now); Core.VP.note_incoming_resolution(act,now)
    if category==6 and current and current.enemy_ids and current.enemy_ids[act.actor_id] then
        local label=action_name(category,act.param)
        if Core.lower(label)=='perfect dodge' then
            local ja=res.job_abilities and res.job_abilities[tonumber(act.param)]
            forced_miss_windows[act.actor_id]=now+(tonumber(ja and ja.duration) or 30)
        end
    end
    for id,expires in pairs(forced_miss_windows) do if now>expires+2 then forced_miss_windows[id]=nil end end
    local relevant_actor,actor_scope,actor_entry,actor_type,related_owner,actor_mob=allied_relation(act.actor_id,party)
    local outside_observed=false
    if not relevant_actor and Core.VP.action_targets_encounter(act,current) then
        relevant_actor,actor_scope,actor_entry,actor_type,related_owner,actor_mob=Core.VP.observed_outside_relation(act.actor_id,party)
        outside_observed=relevant_actor and actor_scope=='outside'
    end
    local owner_id=actor_type=='pet' and related_owner or nil
    local owner_scope=owner_id and actor_scope or 'outside'
    local relevant_target=false
    for _,target in ipairs(act.targets or {}) do if select(1,allied_relation(target.id,party)) then relevant_target=true; break end end
    local encounter_enemy_actor=current and current.enemy_ids and current.enemy_ids[act.actor_id] or false
    if not relevant_actor and not relevant_target and not encounter_enemy_actor then return end

    local hostile=hostile_action_signal(act,party) or outside_observed or encounter_enemy_actor
    local encounter=ensure_encounter(now,hostile)
    if not encounter then return end
    if hostile then session_last_event=now; session_activity:mark(now)
    elseif (relevant_actor or relevant_target or encounter_enemy_actor) and encounter_has_live_enemy(encounter) then
        Core.VP.mark_combat_signal(encounter,now,'support'); session_last_event=now; session_activity:mark(now)
    end
    encounter.events=encounter.events+1; event_count=event_count+1
    if relevant_actor and not outside_observed then
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
    if relevant_actor and actor_type=='player' then Core.VP.infer_job_from_action(actor,category,act.param,action_label) end
    local semantics=Core.action_semantics(res,category,act.param,is_pet)
    local action_targets=act.targets or {}
    if outside_observed then
        local filtered={}
        for _,target in ipairs(action_targets) do
            if encounter.enemy_ids and encounter.enemy_ids[target.id] then filtered[#filtered+1]=target end
        end
        action_targets=filtered
    end
    local heal_targets={}; local total_healing=0; local drain_healing=0; local cleanse_targets=0; local dispel_targets=0
    local ws_action_damage=0; local ws_any_hit=false; local ws_seen=false; local ws_all_forced=true; local ws_hostile_targets=0
    local ws_enemy_targets={}
    local magic_outcomes={}

    for _,target_packet in ipairs(action_targets) do
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
        actor.healing=actor.healing+drain_healing; actor.received=actor.received+drain_healing; actor.self_healing=actor.self_healing+drain_healing; actor.drain_healing=(actor.drain_healing or 0)+drain_healing; Core.VP.add_healing_action(actor,action_label,drain_healing,1,'drain',now); actor.healing_window:add(drain_healing,now); actor.healed_targets[actor.name]=(actor.healed_targets[actor.name] or 0)+drain_healing; actor.healed_by[actor.name]=(actor.healed_by[actor.name] or 0)+drain_healing
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
        actor.healing=actor.healing+total_healing; Core.VP.add_healing_action(actor,action_label,total_healing,1,'cure',now);
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
        if current then update_shared_clock(current,now); current_active=Core.VP.active_value(current,now) end
        return {started=session_started,last=now,activity=session_activity,active_committed=session_active_committed+current_active,actors=actors,enemy_names={},_active_ref=current}
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
    if source._active_ref then return Core.VP.active_value(source._active_ref,now or Core.now()) end
    if source==current then return Core.VP.active_value(current,now or Core.now()) end
    local active=tonumber(source.active_committed)
    if active~=nil then return math.max(0,active) end
    if source.activity then return source.activity:active_seconds(now or Core.now()) end
    return math.max(0,(source.ended or now or Core.now())-(source.started or now or Core.now()))
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
        d.id=a.id; d.name=a.name; d.actor_type=a.actor_type or d.actor_type; d.session_scope=a.session_scope or d.session_scope; d.session_order=a.session_order or d.session_order; d.weapon_class=a.weapon_class; d.main_job=a.main_job or a.inferred_job; d.sub_job=a.sub_job or a.inferred_subjob; d.inferred_job=a.inferred_job; d.inferred_subjob=a.inferred_subjob; d.job_evidence=a.job_evidence
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
function Core.VP.add_enemy_filter_text(term)
    term=tostring(term or ''):gsub('^%s+',''):gsub('%s+$',''); if term=='' then return false end
    local terms=parse_filter_terms(); local wanted=Core.lower(term)
    for _,v in ipairs(terms) do if Core.lower(v)==wanted then return false end end
    terms[#terms+1]=term; save_filter_terms(terms); return true
end
function Core.VP.remove_enemy_filter_text(term)
    term=Core.lower(term or ''); if term=='' then return false end
    local out={}; local removed=false
    for _,v in ipairs(parse_filter_terms()) do if Core.lower(v)==term then removed=true else out[#out+1]=v end end
    if removed then save_filter_terms(out) end; return removed
end
function Core.VP.filter_status_text()
    local enemy={}; for _,v in ipairs(parse_filter_terms()) do enemy[#enemy+1]=v end
    for id in pairs(parse_filter_ids()) do local mob=Core.mob(windower,id); enemy[#enemy+1]=(mob and mob.name) or ('Target '..tostring(id)) end
    table.sort(enemy,function(a,b) return Core.lower(a)<Core.lower(b) end)
    local damage={}; for _,k in ipairs({'melee','ranged','ws','sc','magic','pet','pet_melee','pet_ranged','pet_physical','pet_magic','pet_sc','other'}) do if settings.filters[k]~=false then damage[#damage+1]=Core.display_word(k) end end
    return 'Filter: '..(#enemy>0 and table.concat(enemy,', ') or 'None')..' | Damage: '..(#damage>0 and table.concat(damage,', ') or 'None')
end
function Core.VP.all_damage_filters(value)
    value=value==true
    settings.filters=settings.filters or {}
    for k in pairs(defaults.filters or {}) do settings.filters[k]=value end
    return value
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
    if Core.lower(settings.scope or '')=='allparties' then return Core.VP.observer_selected_source() end
    local raw=split_view and session_source_for_split() or current_source()
    local split=split_source(raw)
    return enemy_filtered_source(split)
end

function Core.VP.local_name_set(party)
    local set={}; local p=party or refresh_party(Core.now())
    if p.self_id and p.by_id[p.self_id] then set[Core.lower(p.by_id[p.self_id].name)]=true end
    for _,name in ipairs(settings.local_players or {}) do set[Core.lower(name)]=true end
    return set
end
local function scope_ids(source,scope_override)
    local party=refresh_party(Core.now()); local ids={}
    if not source then return ids,party end
    local wanted=Core.lower(scope_override or settings.scope or 'alliance')
    local self_name=party.self_id and party.by_id[party.self_id] and Core.lower(party.by_id[party.self_id].name) or nil
    local custom={}; for _,name in ipairs(settings.custom_players or {}) do custom[Core.lower(name)]=true end
    local locals=Core.VP.local_name_set(party)
    for id,a in pairs(source.actors or {}) do
        if a and a.actor_type~='enemy' and a.actor_type~='pet' then
            local t=a.actor_type or 'unknown'
            local allowed=(t~='trust' or settings.include_trusts~=false) and ((t~='fellow' and t~='allied_npc') or settings.include_allied_npcs~=false)
            local scope=a.session_scope or 'outside'; local name=Core.lower(a.name)
            if allowed and ((wanted=='self' and self_name and name==self_name)
                or (wanted=='local' and locals[name])
                or (wanted=='party' and (scope=='self' or scope=='party'))
                or (wanted=='alliance' and scope~='outside')
                or (wanted=='all')
                or (wanted=='allparties')
                or (wanted=='custom' and custom[name])) then ids[id]=true end
        end
    end
    return ids,party
end

function Core.VP.sort_ratio(hit,attempt)
    attempt=tonumber(attempt) or 0
    return attempt>0 and (tonumber(hit) or 0)/attempt or -1
end
function Core.VP.sort_action_value(a,name)
    if not a or not name then return 0 end
    local wanted=Core.VP.action_key(name)
    for label,w in pairs(a.ws or {}) do if Core.VP.action_key(label)==wanted then return tonumber(w.damage) or 0 end end
    for label,sp in pairs(a.spells or {}) do if Core.VP.action_key(label)==wanted then return math.max(tonumber(sp.damage) or 0,tonumber(sp.healing) or 0,tonumber(sp.mb_damage) or 0) end end
    for label,h in pairs(a.healing_actions or {}) do if Core.VP.action_key(label)==wanted then return tonumber(h.healing) or tonumber(h.uses) or 0 end end
    for label,count in pairs(a.cleanse_actions or {}) do if Core.VP.action_key(label)==wanted then return tonumber(count) or 0 end end
    for label,count in pairs(a.dispel_actions or {}) do if Core.VP.action_key(label)==wanted then return tonumber(count) or 0 end end
    if wanted=='aspir' then return tonumber(a.aspir_recovery) or 0 end
    return 0
end
function Core.VP.sort_category_value(a,cat)
    cat=normalize_category(cat)
    if cat=='physical' then return net(a.melee,a.dheal_melee)+Core.VP.ws_net(a)+net(a.skillchain,a.dheal_skillchain) end
    if cat=='melee' then return net(a.melee,a.dheal_melee) end
    if cat=='ws' then return Core.VP.ws_net(a) end
    if cat=='sc' then return net(a.skillchain,a.dheal_skillchain) end
    if cat=='ranged' then return net(a.ranged,a.dheal_ranged) end
    if cat=='magic' then return Core.VP.magic_net(a) end
    if cat=='magic_mb' or cat=='mb' then return tonumber((Core.VP.magic_stats(a) or {}).mb_damage) or 0 end
    if cat=='magic_nonmb' then return tonumber((Core.VP.magic_stats(a) or {}).nonmb_damage) or 0 end
    if cat=='pet' then return pet_net_damage(a) end
    if cat=='pet_melee' then return net(a.pet and a.pet.melee,a.pet and a.pet.dheal_melee) end
    if cat=='pet_ranged' then return net(a.pet and a.pet.ranged,a.pet and a.pet.dheal_ranged) end
    if cat=='pet_physical' then local p=a.pet or {}; local v=tonumber(p.physical) or 0; if v==0 then v=tonumber(p.ws) or 0 end; return net(v,p.dheal_physical) end
    if cat=='pet_magic' then local p=a.pet or {}; return math.max(0,(tonumber(p.magic) or 0)-(tonumber(p.dheal_magic) or 0)-(tonumber(p.dheal_enspell) or 0)) end
    if cat=='pet_sc' then return net(a.pet and a.pet.skillchain,a.pet and a.pet.dheal_skillchain) end
    if cat=='pet_mb' then return net(a.pet and a.pet.mb_damage,a.pet and a.pet.dheal_mb) end
    if cat=='pet_healing' then return tonumber(a.pet and a.pet.healing) or 0 end
    if cat=='healing' or cat=='healing_cure' then return tonumber((Core.VP.healing_stats(a) or {}).healing) or 0 end
    if cat=='recovery' then local r=Core.VP.recovery_stats(a); return (tonumber(r.cleanse) or 0)+(tonumber(r.dispel) or 0)+(tonumber(r.aspir) or 0) end
    if cat=='recovery_cleanse' then return tonumber((Core.VP.recovery_stats(a) or {}).cleanse) or 0 end
    if cat=='recovery_dispel' then return tonumber((Core.VP.recovery_stats(a) or {}).dispel) or 0 end
    if cat=='recovery_aspir' then return tonumber((Core.VP.recovery_stats(a) or {}).aspir) or 0 end
    if cat=='defense' then return tonumber((Core.VP.defense_stats(a) or {}).taken) or 0 end
    if cat=='defense_physical' then return tonumber((Core.VP.defense_stats(a) or {}).physical) or 0 end
    if cat=='defense_magic' then return tonumber((Core.VP.defense_stats(a) or {}).magic) or 0 end
    if cat=='defense_other' then return tonumber((Core.VP.defense_stats(a) or {}).other) or 0 end
    return combined_damage(a)
end
function Core.VP.sort_field_value(a,key)
    key=tostring(key or '')
    local r=Core.VP.sort_ratio
    local w=Core.VP.ws_stats(a); local m=Core.VP.magic_stats(a); local h=Core.VP.healing_stats(a); local rc=Core.VP.recovery_stats(a); local d=Core.VP.defense_stats(a); local p=a.pet or {}
    local map={
        ['general.damage']=combined_damage(a),['general.avg']=combined_damage(a),['general.share']=combined_damage(a),['general.dheal']=tonumber(a.dheal) or 0,
        ['melee.damage']=net(a.melee,a.dheal_melee),['melee.attempts']=tonumber(a.melee_attempts) or 0,['melee.hit']=tonumber(a.melee_hits) or 0,['melee.miss']=tonumber(a.melee_misses) or 0,['melee.acc']=r(a.melee_hits,a.melee_attempts),['melee.low']=tonumber(a.melee_mm and a.melee_mm.low) or 0,['melee.avg']=avg(a.melee_mm) or 0,['melee.peak']=tonumber(a.melee_mm and a.melee_mm.peak) or 0,['melee.crit']=r(a.melee_crit,a.melee_hits),['melee.crit.avg']=avg(a.crit_mm) or 0,['melee.crit.peak']=tonumber(a.crit_mm and a.crit_mm.peak) or 0,
        ['ws.damage']=tonumber(w.damage) or 0,['ws.total']=tonumber(w.damage) or 0,['ws.attempts']=tonumber(w.attempts) or 0,['ws.hit']=tonumber(w.hits) or 0,['ws.miss']=tonumber(w.misses) or 0,['ws.acc']=r(w.hits,w.attempts),['ws.hm']=tonumber(w.hits) or 0,['ws.low']=tonumber(w.mm and w.mm.low) or 0,['ws.avg']=avg(w.mm) or 0,['ws.peak']=tonumber(w.mm and w.mm.peak) or 0,['ws.share']=tonumber(w.damage) or 0,
        ['sc.damage']=net(a.skillchain,a.dheal_skillchain),['sc.count']=tonumber(a.skillchain_count) or 0,['sc.share']=net(a.skillchain,a.dheal_skillchain),
        ['ranged.damage']=net(a.ranged,a.dheal_ranged),['ranged.attempts']=tonumber(a.ranged_attempts) or 0,['ranged.hit']=tonumber(a.ranged_hits) or 0,['ranged.miss']=tonumber(a.ranged_misses) or 0,['ranged.acc']=r(a.ranged_hits,a.ranged_attempts),['ranged.low']=tonumber(a.ranged_mm and a.ranged_mm.low) or 0,['ranged.avg']=avg(a.ranged_mm) or 0,['ranged.peak']=tonumber(a.ranged_mm and a.ranged_mm.peak) or 0,['ranged.crit']=r(a.ranged_crit,a.ranged_hits),
        ['magic.damage']=Core.VP.magic_net(a),['magic.cast']=tonumber(m.casts) or 0,['magic.targets']=tonumber(m.targets) or 0,['magic.land']=tonumber(m.lands) or 0,['magic.resist']=tonumber(m.resists) or 0,['magic.noeffect']=tonumber(m.no_effect) or 0,['magic.landpct']=r(m.lands,(tonumber(m.lands) or 0)+(tonumber(m.resists) or 0)),['magic.low']=tonumber(m.mm and m.mm.low) or 0,['magic.avg']=avg(m.mm) or 0,['magic.peak']=tonumber(m.mm and m.mm.peak) or 0,['magic.mb.damage']=tonumber(m.mb_damage) or 0,['magic.mb.count']=tonumber(m.mb_count) or 0,['magic.mb.avg']=avg(m.mb_mm) or 0,['magic.mb.peak']=tonumber(m.mb_mm and m.mb_mm.peak) or 0,['magic.nonmb.damage']=tonumber(m.nonmb_damage) or 0,['magic.nonmb.count']=tonumber(m.nonmb_count) or 0,['magic.nonmb.avg']=avg(m.nonmb_mm) or 0,['magic.nonmb.peak']=tonumber(m.nonmb_mm and m.nonmb_mm.peak) or 0,['magic.healing']=tonumber(m.healing) or 0,['magic.enspell']=tonumber(a.enspell) or 0,
        ['pet.damage']=pet_net_damage(a),['pet.combined']=combined_damage(a),['pet.melee.damage']=net(p.melee,p.dheal_melee),['pet.melee.acc']=r(p.melee_hits,p.melee_attempts),['pet.melee.attempts']=tonumber(p.melee_attempts) or 0,['pet.melee.hit']=tonumber(p.melee_hits) or 0,['pet.melee.miss']=tonumber(p.melee_misses) or 0,['pet.ranged.damage']=net(p.ranged,p.dheal_ranged),['pet.ranged.acc']=r(p.ranged_hits,p.ranged_attempts),['pet.ranged.attempts']=tonumber(p.ranged_attempts) or 0,['pet.ranged.hit']=tonumber(p.ranged_hits) or 0,['pet.ranged.miss']=tonumber(p.ranged_misses) or 0,['pet.physical.damage']=net((tonumber(p.physical) or tonumber(p.ws) or 0),p.dheal_physical),['pet.magic.damage']=math.max(0,(tonumber(p.magic) or 0)-(tonumber(p.dheal_magic) or 0)-(tonumber(p.dheal_enspell) or 0)),['pet.sc.damage']=net(p.skillchain,p.dheal_skillchain),['pet.mb.damage']=net(p.mb_damage,p.dheal_mb),['pet.healing']=tonumber(p.healing) or 0,['pet.taken']=tonumber(p.taken) or 0,
        ['healing.cured']=tonumber(h.healing) or 0,['healing.hps']=tonumber(h.healing) or 0,['healing.cure.count']=tonumber(h.cures) or 0,['healing.cure.low']=tonumber(h.mm and h.mm.low) or 0,['healing.cure.avg']=avg(h.mm) or 0,['healing.cure.peak']=tonumber(h.mm and h.mm.peak) or 0,['healing.received']=tonumber(a.received) or 0,['healing.selfcure']=tonumber(a.self_healing) or 0,['healing.cleanse']=tonumber(rc.cleanse) or 0,['healing.dispel']=tonumber(rc.dispel) or 0,['healing.aspir']=tonumber(rc.aspir) or 0,['healing.mp']=tonumber(a.mp_spent) or 0,['healing.hpmp']=(tonumber(a.mp_spent) or 0)>0 and (tonumber(h.healing) or 0)/(tonumber(a.mp_spent) or 1) or 0,
        ['recovery.cleanse']=tonumber(rc.cleanse) or 0,['recovery.dispel']=tonumber(rc.dispel) or 0,['recovery.aspir']=tonumber(rc.aspir) or 0,
        ['defense.taken']=tonumber(d.taken) or 0,['defense.physical']=tonumber(d.physical) or 0,['defense.magic']=tonumber(d.magic) or 0,['defense.other']=tonumber(d.other) or 0,['defense.hits']=tonumber(d.hits) or 0,['defense.lowhit']=tonumber(d.mm and d.mm.low) or 0,['defense.avghit']=avg(d.mm) or 0,['defense.peakhit']=tonumber(d.mm and d.mm.peak) or 0,['defense.evade']=tonumber(a.evades) or 0,['defense.parry']=tonumber(a.parries) or 0,['defense.block']=tonumber(a.blocks) or 0,['defense.ko']=tonumber(a.deaths) or 0,
    }
    return tonumber(map[key]) or 0
end
function Core.VP.sort_target_value(a,target)
    target=tostring(target or settings.sort or 'field:general.avg')
    local kind,value=target:match('^(%a+)%:(.+)$')
    if kind=='field' then return Core.VP.sort_field_value(a,value) end
    if kind=='category' then return Core.VP.sort_category_value(a,value) end
    if kind=='action' then return Core.VP.sort_action_value(a,value) end
    local legacy={damage='general.damage',dps='general.avg',melee='melee.damage',accuracy='melee.acc',acc='melee.acc',ranged='ranged.damage',racc='ranged.acc',ws='ws.damage',wsacc='ws.acc',wsavg='ws.avg',sc='sc.damage',magic='magic.damage',pet='pet.damage',healing='healing.cured',cleanse='recovery.cleanse',cleanses='recovery.cleanse',dispel='recovery.dispel',dispels='recovery.dispel',taken='defense.taken'}
    if legacy[target] then return Core.VP.sort_field_value(a,legacy[target]) end
    return 0
end
local function performance_sort(rows,party)
    local order={}; for i,id in ipairs(party.order or {}) do order[id]=i end
    if settings.sort=='party' then table.sort(rows,function(a,b) return (order[a.id] or tonumber(a.session_order) or 999)<(order[b.id] or tonumber(b.session_order) or 999) end); return end
    local direction=(settings.sort_direction=='asc') and 1 or -1
    table.sort(rows,function(a,b)
        local av,bv=Core.VP.sort_target_value(a,settings.sort),Core.VP.sort_target_value(b,settings.sort)
        if av~=bv then return direction==1 and av<bv or av>bv end
        return (order[a.id] or tonumber(a.session_order) or 999)<(order[b.id] or tonumber(b.session_order) or 999)
    end)
end

local function apply_pins(rows,party)
    local by_name={}; for _,a in ipairs(rows) do by_name[Core.lower(a.name)]=a end
    local fixed,soft,ordinary={}, {}, {}; local used={}
    for name,slot in pairs(settings.pins or {}) do
        local a=by_name[Core.lower(name)]; if a and tonumber(slot) then fixed[math.max(1,math.floor(tonumber(slot)))]=a; used[a]=true end
    end
    local locals=Core.VP.local_name_set(party)
    local function group_pin(a)
        local name=Core.lower(a.name); local scope=a.session_scope or 'outside'
        if settings.self_pin~=false and party.self_id and party.by_id[party.self_id] and name==Core.lower(party.by_id[party.self_id].name) then return true end
        if settings.pin_local and locals[name] then return true end
        if settings.pin_party and (scope=='self' or scope=='party') then return true end
        if settings.pin_alliance and scope~='outside' then return true end
        return settings.pins and settings.pins[name] and not tonumber(settings.pins[name])
    end
    -- Soft pins keep their natural metric order.
    for _,a in ipairs(rows) do if not used[a] and group_pin(a) then soft[#soft+1]=a; used[a]=true end end
    for _,a in ipairs(rows) do if not used[a] then ordinary[#ordinary+1]=a end end
    local out={}; local si,oi=1,1; local total=#rows
    for slot=1,total do
        local a=fixed[slot]; if not a then a=soft[si]; if a then si=si+1 end end; if not a then a=ordinary[oi]; if a then oi=oi+1 end end; if a then out[#out+1]=a end
    end
    local extra={}; for slot,a in pairs(fixed) do if slot>total then extra[#extra+1]={slot=slot,a=a} end end
    table.sort(extra,function(x,y) return x.slot<y.slot end); for _,x in ipairs(extra) do out[#out+1]=x.a end
    return out
end

local function display_actors(source,expand,use_pins,scope_override)
    if not source then return {} end
    local ids,party=scope_ids(source,scope_override); local rows={}
    for id in pairs(ids) do if source.actors[id] then rows[#rows+1]=source.actors[id] end end
    performance_sort(rows,party)
    for i,a in ipairs(rows) do a._vp_rank=i end
    if use_pins~=false then rows=apply_pins(rows,party) end
    local wanted=Core.lower(scope_override or settings.scope or 'alliance')
    if wanted=='alliance' then while #rows>(settings.alliance_limit or 18) do table.remove(rows) end end
    local row_limit=math.max(0,math.floor(tonumber(settings.row_limit) or 8))
    if not expand and row_limit>0 then while #rows>row_limit do table.remove(rows) end end
    return rows
end

function Core.VP.hud_scope_total(source,visible_actors)
    if Core.VP.report_scope_total_override~=nil then return Core.VP.report_scope_total_override end
    local total=0
    local actors=visible_actors or {}
    local sw=Core.lower(settings.scope or 'alliance'); if sw=='all' or sw=='allparties' then actors=display_actors(source,true,false,sw) end
    for _,a in ipairs(actors or {}) do total=total+combined_damage(a) end
    return total
end

local function elapsed_active(source,now)
    if not source then return 0,0 end
    now=now or Core.now()
    local ref=source._active_ref or (source==current and current or nil)
    if ref then update_shared_clock(ref,now) end
    local elapsed=math.max(0,(source.ended or now)-(source.started or now))
    if source.activity then source.activity:tick(now) end
    local active=ref and Core.VP.active_value(ref,now) or tonumber(source.active_committed)
    if active==nil then active=source.activity and source.activity:active_seconds(source.ended or now) or elapsed end
    return elapsed,math.max(0,active)
end

local function dps(actor,source,now)
    local _,active=elapsed_active(source,now); if active<=0 then return nil end; return player_net_damage(actor)/active
end
local function combined_dps(actor,source,now)
    local _,active=elapsed_active(source,now); if active<=0 then return nil end; return combined_damage(actor)/active
end
Core.VP.dps_cache=setmetatable({}, {__mode='k'})
local function hud_combined_dps(actor,source,now)
    if Core.VP.report_render_exact then return combined_dps(actor,source,now) end
    if not actor or not source then return combined_dps(actor,source,now) end
    now=now or Core.now(); local bucket=Core.VP.dps_cache[source]; if not bucket then bucket={}; Core.VP.dps_cache[source]=bucket end
    local key=tostring(actor.id or actor.name or '?'); local cached=bucket[key]; local refresh=tonumber(settings.dps_refresh_seconds) or 5
    if not cached or now-(cached.at or 0)>=refresh then cached={at=now,value=combined_dps(actor,source,now)}; bucket[key]=cached end
    return cached.value
end
local function hud_total_dps(total_damage,source,now,cache_key)
    if Core.VP.report_render_exact then local _,active=elapsed_active(source,now); return active>0 and total_damage/active or nil end
    if not source then return nil end
    now=now or Core.now(); local bucket=Core.VP.dps_cache[source]; if not bucket then bucket={}; Core.VP.dps_cache[source]=bucket end
    local key='__total__:'..tostring(cache_key or settings.view or 'view'); local cached=bucket[key]; local refresh=tonumber(settings.dps_refresh_seconds) or 5
    if not cached or now-(cached.at or 0)>=refresh then local _,active=elapsed_active(source,now); cached={at=now,value=active>0 and total_damage/active or nil}; bucket[key]=cached end
    return cached.value
end
local function live_dps(actor,now)
    if not actor.damage_window:ready(settings.live_seconds,now) then return nil end; return actor.damage_window:sum(settings.live_seconds,now)/settings.live_seconds
end
local function ten_dps(actor,now)
    if not actor.damage_window:ready(settings.rolling_seconds,now) then return nil end; return actor.damage_window:sum(settings.rolling_seconds,now)/settings.rolling_seconds
end
local function hps(actor,source,now) local _,active=elapsed_active(source,now); if active<=0 then return nil end; return Core.VP.healing_stats(actor).healing/active end

local function dash(value,formatter)
    if value==nil then return '-' end
    return formatter and formatter(value) or tostring(value)
end
local function n(value) return Core.compact(value or 0) end
local function count_text(value)
    local v=math.max(0,math.floor(tonumber(value) or 0))
    local raw=tostring(v)
    if v<10000 then return raw end
    local out=raw
    while true do
        local next_out,changed=out:gsub('^(%-?%d+)(%d%d%d)', '%1,%2')
        out=next_out
        if changed==0 then break end
    end
    return out
end
local function count_pair(hits,misses) return count_text(hits)..'/'..count_text(misses) end
local function f1(value) return value and ('%.1f'):format(value) or '-' end
local function pct(hit,attempt) return Core.percent_text(hit,attempt,1) end

local MAX_SECTIONS={'general','melee','ws','sc','ranged','magic','pet','defense','healing','recovery'}
Core.VP.SECTION_DISPLAY_KEY={melee='melee',ws='ws',sc='sc',ranged='ranged',magic='magic',pet='pet',defense='defense',healing='healing',recovery='recovery'}
local function section_on(name)
    local only=settings.max_only or {}; local has_only=false; for _ in pairs(only) do has_only=true; break end
    if has_only and only[name]~=true then return false end
    if not has_only and settings.max_hidden and settings.max_hidden[name] then return false end
    local key=Core.VP.SECTION_DISPLAY_KEY[name]
    if key and settings.display and settings.display[key]==false then return false end
    if key and Core.VP.category_included and not Core.VP.category_included(key) then return false end
    return true
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
        local melee=net(a.melee,a.dheal_melee); local ws=Core.VP.ws_net(a); local sc=net(a.skillchain,a.dheal_skillchain); local magic=Core.VP.magic_net(a)
        take('share',share); take('damage',dmg); take('dps',hud_combined_dps(a,source,now)); take('melee',melee); take('melee_share',total~=0 and 100*melee/total or nil)
        if show_ranged then local r=net(a.ranged,a.dheal_ranged); take('ranged',r); take('ranged_share',total~=0 and 100*r/total or nil) end
        local wst=Core.VP.ws_stats(a); take('ws_damage',ws); take('ws_share',total~=0 and 100*ws/total or nil); take('ws_count',wst.attempts); take('ws_avg',avg(wst.mm),(wst.mm and wst.mm.count or 0)>=(tonumber(settings.highlight_ws_min) or 5))
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
    physical='physical',melee='melee',attack='melee',
    magic='magic',magical='magic',spell='magic',spells='magic',
    mb='mb',['magic burst']='mb',['magic bursts']='mb',
    ranged='ranged',range='ranged',shoot='ranged',shooting='ranged',['ranged attack']='ranged',ra='ranged',
    healing='healing',heal='healing',curing='healing',waltz='healing',walz='healing',['curing waltz']='healing',
    recovery='recovery',status='recovery',cleanse='recovery',['status recovery']='recovery',['remove status']='recovery',['healing waltz']='recovery',
    defense='defense',def='defense',
    pet='pet',automaton='pet',wyvern='pet',jug='pet',avatar='pet',luopan='pet',
    ['pet physical']='pet_physical',['pet ws']='pet_physical',['pet weaponskill']='pet_physical',['pet weapon skill']='pet_physical',
    ['pet melee']='pet_melee',
    ['pet magic']='pet_magic',['pet magical']='pet_magic',
    ['pet ranged']='pet_ranged',['pet range']='pet_ranged',['pet shooting']='pet_ranged',
    ['pet healing']='pet_healing',['pet cure']='pet_healing',
    ['pet sc']='pet_sc',['pet skillchain']='pet_sc',['pet skill chain']='pet_sc',['pet mb']='pet_mb',['pet magic burst']='pet_mb',
    ['magic mb']='magic_mb',['magic burst damage']='magic_mb',['magic nonmb']='magic_nonmb',['magic non mb']='magic_nonmb',['nonmb']='magic_nonmb',['non mb']='magic_nonmb',
    ['healing cure']='healing_cure',['cure healing']='healing_cure',
    ['recovery cleanse']='recovery_cleanse',['recovery dispel']='recovery_dispel',['recovery aspir']='recovery_aspir',
    ['defense physical']='defense_physical',['defense magic']='defense_magic',['defense other']='defense_other',
    ws='ws',weaponskill='ws',['weapon skill']='ws',
    sc='sc',skillchain='sc',['skill chain']='sc',
    crit='crits',crits='crits',critical='crits',
}
local function normalize_category(value)
    value=Core.lower(tostring(value or '')):gsub('^%s+',''):gsub('%s+$',''):gsub('%s+',' ')
    return CATEGORY_ALIASES[value] or value
end
Core.VP.CATEGORY_PARENT={
    magic_mb='magic',magic_nonmb='magic',
    pet_melee='pet',pet_ranged='pet',pet_physical='pet',pet_magic='pet',pet_sc='pet',pet_mb='pet',pet_healing='pet',
    healing_cure='healing',recovery_cleanse='recovery',recovery_dispel='recovery',recovery_aspir='recovery',
    defense_physical='defense',defense_magic='defense',defense_other='defense',
}
function Core.VP.category_state_match(bucket,name)
    if not bucket then return false end
    name=normalize_category(name)
    local cur=name
    while cur and cur~='' do
        if bucket[cur]==true then return true end
        cur=Core.VP.CATEGORY_PARENT[cur]
    end
    return false
end
function Core.VP.category_hidden(name)
    settings.controls=settings.controls or Core.merge({},defaults.controls)
    return Core.VP.category_state_match(settings.controls.hidden_categories,name)
end
local function display_enabled(name)
    name=normalize_category(name)
    settings.display=settings.display or Core.deepcopy and Core.deepcopy(defaults.display) or defaults.display
    if Core.VP.category_hidden(name) then return false end
    local parent=Core.VP.CATEGORY_PARENT[name]
    if parent and not display_enabled(parent) then return false end
    if name=='physical' then return settings.display.melee~=false or settings.display.ws~=false or settings.display.sc~=false end
    if name=='crits' then return settings.columns.crits==true end
    if defaults.display[name]~=nil then return settings.display[name]~=false end
    if parent then return true end
    return true
end
local function set_display_category(name,value)
    name=normalize_category(name); settings.display=settings.display or {}; settings.controls=settings.controls or Core.merge({},defaults.controls)
    settings.controls.hidden_categories=settings.controls.hidden_categories or {}
    if name=='physical' then
        settings.display.physical=value; settings.display.melee=value; settings.display.ws=value; settings.display.sc=value
        for _,k in ipairs({'physical','melee','ws','sc'}) do settings.controls.hidden_categories[k]=value and nil or true end
    elseif name=='crits' then settings.columns.crits=value
    elseif defaults.display[name]~=nil then
        settings.display[name]=value; settings.controls.hidden_categories[name]=value and nil or true
    elseif Core.VP.CATEGORY_PARENT[name] then
        settings.controls.hidden_categories[name]=value and nil or true
        if value then
            local parent=Core.VP.CATEGORY_PARENT[name]
            while parent do
                settings.controls.hidden_categories[parent]=nil
                if defaults.display[parent]~=nil then settings.display[parent]=true end
                parent=Core.VP.CATEGORY_PARENT[parent]
            end
        end
    else return false end
    return true
end
Core.VP.DISPLAY_COLUMN_ALIASES={
    acc='accuracy',accuracy='accuracy',['melee accuracy']='accuracy',
    racc='ranged_accuracy',['r.acc']='ranged_accuracy',['ranged acc']='ranged_accuracy',['ranged accuracy']='ranged_accuracy',
    wsacc='ws_accuracy',['ws acc']='ws_accuracy',['ws accuracy']='ws_accuracy',['weaponskill accuracy']='ws_accuracy',['weapon skill accuracy']='ws_accuracy',
    wshm='ws_hm',['ws h/m']='ws_hm',['ws hm']='ws_hm',['ws hit/miss']='ws_hm',['weapon skill h/m']='ws_hm',
    wsavg='ws_avg',['ws avg']='ws_avg',['ws average']='ws_avg',['weaponskill average']='ws_avg',['weapon skill average']='ws_avg',
}
function Core.VP.normalize_display_item(value)
    local raw=Core.lower(tostring(value or '')):gsub('^%s+',''):gsub('%s+$',''):gsub('%s+',' ')
    local compact=raw:gsub('%s+','')
    return Core.VP.DISPLAY_COLUMN_ALIASES[raw] or Core.VP.DISPLAY_COLUMN_ALIASES[compact] or normalize_category(raw)
end
function Core.VP.set_display_item(name,value)
    local item=Core.VP.normalize_display_item(name)
    if item=='accuracy' or item=='ranged_accuracy' or item=='ws_accuracy' or item=='ws_hm' or item=='ws_avg' then settings.columns[item]=value; return true,item end
    if set_display_category(item,value) then return true,item end
    return false,item
end
function Core.VP.display_item_enabled(name)
    local item=Core.VP.normalize_display_item(name)
    if item=='accuracy' or item=='ranged_accuracy' or item=='ws_accuracy' or item=='ws_hm' or item=='ws_avg' then return settings.columns[item]~=false,item end
    if defaults.display[item]~=nil or item=='crits' or Core.VP.CATEGORY_PARENT[item]~=nil or item=='physical' then return display_enabled(item),item end
    return nil,item
end

-- Universal parser controls. Raw capture is never modified. Show/Hide changes
-- presentation only; Include/Exclude changes the calculated/readout layer and
-- can be reversed at any time without resetting the parse.
Core.VP.CONTROL_FIELD_ALIASES={
    ['#']='rank',rank='rank',player='player',name='player',job='job',['job/sub']='job',jobsub='job',
    ['tot dmg%']='totdmgpct',totdmgpct='totdmgpct',['total damage%']='totdmgpct',['total damage pct']='totdmgpct',
    ['tot dmg']='totdmg',totdmg='totdmg',['total damage']='totdmg',dps='dps',
    melee='melee',acc='acc',accuracy='acc',['melee accuracy']='acc',
    ['ws dmg']='wsdmg',wsdmg='wsdmg',['ws dmg%']='wsdmgpct',['ws%']='wsacc',wsdmgpct='wsdmgpct',['ws h/m']='wshm',wshm='wshm',['ws acc']='wsacc',wsacc='wsacc',['ws avg']='wsavg',wsavg='wsavg',
    ['sc#']='sccount',sccount='sccount',['sc dmg']='scdmg',scdmg='scdmg',['sc dmg%']='scdmgpct',scdmgpct='scdmgpct',
    ['magic dmg']='magicdmg',magicdmg='magicdmg',['ranged dmg']='rangeddmg',rangeddmg='rangeddmg',['pet dmg']='petdmg',petdmg='petdmg',['mb dmg']='mbdmg',mbdmg='mbdmg',['crit%']='critpct',critpct='critpct',
    ws='ws',att='attempts',attempt='attempts',attempts='attempts',hit='hit',hits='hit',miss='miss',misses='miss',low='low',minimum='low',min='low',avg='avg',average='avg',high='peak',peak='peak',maximum='peak',max='peak',total='total',
    spell='spell',cast='cast',casts='cast',tgt='targets',target='targets',targets='targets',land='land',lands='land',res='resist',resist='resist',resists='resist',noef='noeffect',['no effect']='noeffect',noeffect='noeffect',['land%']='landpct',landpct='landpct',dmg='dmg',damage='dmg',
    ['mb#']='mbcount',mbcount='mbcount',mbavg='mbavg',mbpk='mbpeak',['mb peak']='mbpeak',['n#']='ncount',ncount='ncount',['n dmg']='ndmg',ndmg='ndmg',navg='navg',npk='npeak',['n peak']='npeak',heal='heal',
    taken='taken',phys='phys',physicaltaken='phys',magict='magict',['magic taken']='magict',other='other',hits='hits',avghit='avghit',['avg hit']='avghit',lowhit='lowhit',['low hit']='lowhit',peakhit='peakhit',['peak hit']='peakhit',highhit='peakhit',['high hit']='peakhit',
    evd='evade',evade='evade',evades='evade',par='parry',parry='parry',parries='parry',blk='block',block='block',blocks='block',ko='ko',death='ko',deaths='ko',
    ['dmg%']='dmgpct',dmgpct='dmgpct',["cure r'cvd"]='curereceived',['cure rcvd']='curereceived',['cure received']='curereceived',recv='curereceived',['recv%']='recvpct',recvpct='recvpct',['mp load']='mpload',mpload='mpload',burden='burden',cured='cured',['self cure']='selfcure',selfcure='selfcure',cleanse='cleanse',dispel='dispel',aspir='aspir',hps='hps',['cure#']='curecount',curecount='curecount',cureavg='cureavg',['cure avg']='cureavg',curelow='curelow',['cure low']='curelow',curepk='curepeak',['cure peak']='curepeak',mp='mp',['hp/mp']='hpmp',hpmp='hpmp',
    action='action',use='use',healed='healed',type='type',count='count',master='master',['p.dmg']='pdmg',pdmg='pdmg',['p.dmg%']='pdmgpct',pdmgpct='pdmgpct',combined='combined',ranged='ranged',['r.acc']='racc',racc='racc',sc='sc',mb='mb',magic='magic',
    ['d.heal']='dheal',dheal='dheal',live='live',['10m']='tenmin',tenmin='tenmin',crit='crit',['c.avg']='critavg',critavg='critavg',['c.peak']='critpeak',critpeak='critpeak',rng='ranged',shot='shot',rcrit='rcrit',nmb='nmb',mheal='mheal',ensp='ensp',status='status'
}
Core.VP.CONTROL_FIELD_KEYS={}
for _,key in pairs(Core.VP.CONTROL_FIELD_ALIASES) do Core.VP.CONTROL_FIELD_KEYS[key]=true end

-- Hierarchical field namespace. Repeated labels such as Low/Avg/Peak remain
-- globally addressable, while a parent path narrows the exact statistic.
-- Examples: low, ws low, magic mb avg, pet melee acc, defense low.
Core.VP.CONTROL_CONTEXT_FIELDS={
    general={dmg='general.damage',damage='general.damage',['tot dmg']='general.damage',['total damage']='general.damage',['d.heal']='general.dheal',dheal='general.dheal',live='general.live',avg='general.avg',average='general.avg',['10m']='general.tenmin',['10 min']='general.tenmin',dps='general.avg',share='general.share'},
    melee={dmg='melee.damage',damage='melee.damage',melee='melee.damage',att='melee.attempts',attempt='melee.attempts',attempts='melee.attempts',hit='melee.hit',hits='melee.hit',miss='melee.miss',misses='melee.miss',acc='melee.acc',accuracy='melee.acc',low='melee.low',min='melee.low',minimum='melee.low',avg='melee.avg',average='melee.avg',peak='melee.peak',high='melee.peak',max='melee.peak',maximum='melee.peak',crit='melee.crit',['crit%']='melee.crit',['c.avg']='melee.crit.avg',['crit avg']='melee.crit.avg',['c.peak']='melee.crit.peak',['crit peak']='melee.crit.peak'},
    ws={ws='ws.action',action='ws.action',dmg='ws.damage',damage='ws.damage',total='ws.total',att='ws.attempts',attempt='ws.attempts',attempts='ws.attempts',hit='ws.hit',hits='ws.hit',miss='ws.miss',misses='ws.miss',acc='ws.acc',accuracy='ws.acc',['h/m']='ws.hm',hm='ws.hm',low='ws.low',min='ws.low',minimum='ws.low',avg='ws.avg',average='ws.avg',peak='ws.peak',high='ws.peak',max='ws.peak',maximum='ws.peak',share='ws.share'},
    sc={sc='sc.damage',dmg='sc.damage',damage='sc.damage',count='sc.count',['#']='sc.count',share='sc.share'},
    ranged={rng='ranged.damage',ranged='ranged.damage',dmg='ranged.damage',damage='ranged.damage',shot='ranged.attempts',att='ranged.attempts',attempts='ranged.attempts',hit='ranged.hit',hits='ranged.hit',miss='ranged.miss',misses='ranged.miss',acc='ranged.acc',racc='ranged.acc',low='ranged.low',avg='ranged.avg',peak='ranged.peak',high='ranged.peak',crit='ranged.crit',rcrit='ranged.crit'},
    magic={magic='magic.damage',dmg='magic.damage',damage='magic.damage',spell='magic.action',action='magic.action',cast='magic.cast',casts='magic.cast',tgt='magic.targets',target='magic.targets',targets='magic.targets',land='magic.land',lands='magic.land',res='magic.resist',resist='magic.resist',resists='magic.resist',noef='magic.noeffect',['no effect']='magic.noeffect',['land%']='magic.landpct',low='magic.low',avg='magic.avg',peak='magic.peak',high='magic.peak',mb='magic.mb.damage',['mb dmg']='magic.mb.damage',['mb#']='magic.mb.count',mbavg='magic.mb.avg',mbpk='magic.mb.peak',nmb='magic.nonmb.damage',['n dmg']='magic.nonmb.damage',['n#']='magic.nonmb.count',navg='magic.nonmb.avg',npk='magic.nonmb.peak',heal='magic.healing',healing='magic.healing',mheal='magic.healing',ensp='magic.enspell',enspell='magic.enspell'},
    ['magic mb']={mb='magic.mb.damage',dmg='magic.mb.damage',damage='magic.mb.damage',count='magic.mb.count',['#']='magic.mb.count',avg='magic.mb.avg',average='magic.mb.avg',peak='magic.mb.peak',high='magic.mb.peak'},
    ['magic nonmb']={nmb='magic.nonmb.damage',dmg='magic.nonmb.damage',damage='magic.nonmb.damage',count='magic.nonmb.count',['#']='magic.nonmb.count',avg='magic.nonmb.avg',average='magic.nonmb.avg',peak='magic.nonmb.peak',high='magic.nonmb.peak'},
    pet={master='pet.master',dmg='pet.damage',damage='pet.damage',['p.dmg']='pet.damage',['p.dmg%']='pet.share',share='pet.share',combined='pet.combined',melee='pet.melee.damage',acc='pet.melee.acc',ranged='pet.ranged.damage',['r.acc']='pet.ranged.acc',racc='pet.ranged.acc',phys='pet.physical.damage',physical='pet.physical.damage',magic='pet.magic.damage',sc='pet.sc.damage',mb='pet.mb.damage',heal='pet.healing',healing='pet.healing',cured='pet.healing',taken='pet.taken'},
    ['pet melee']={melee='pet.melee.damage',dmg='pet.melee.damage',damage='pet.melee.damage',acc='pet.melee.acc',accuracy='pet.melee.acc',att='pet.melee.attempts',attempts='pet.melee.attempts',hit='pet.melee.hit',hits='pet.melee.hit',miss='pet.melee.miss',misses='pet.melee.miss'},
    ['pet ranged']={ranged='pet.ranged.damage',dmg='pet.ranged.damage',damage='pet.ranged.damage',acc='pet.ranged.acc',racc='pet.ranged.acc',accuracy='pet.ranged.acc',att='pet.ranged.attempts',attempts='pet.ranged.attempts',hit='pet.ranged.hit',hits='pet.ranged.hit',miss='pet.ranged.miss',misses='pet.ranged.miss'},
    ['pet physical']={phys='pet.physical.damage',physical='pet.physical.damage',dmg='pet.physical.damage',damage='pet.physical.damage'},
    ['pet magic']={magic='pet.magic.damage',dmg='pet.magic.damage',damage='pet.magic.damage'},
    ['pet sc']={sc='pet.sc.damage',dmg='pet.sc.damage',damage='pet.sc.damage'},
    ['pet mb']={mb='pet.mb.damage',dmg='pet.mb.damage',damage='pet.mb.damage'},
    ['pet healing']={heal='pet.healing',healing='pet.healing',cured='pet.healing'},
    healing={taken='healing.taken',['dmg%']='healing.dmgpct',['cure rcvd']='healing.received',["cure r'cvd"]='healing.received',['recv%']='healing.recvpct',['mp load']='healing.mpload',burden='healing.burden',cured='healing.cured',['self cure']='healing.selfcure',cleanse='healing.cleanse',dispel='healing.dispel',aspir='healing.aspir',hps='healing.hps',['cure#']='healing.cure.count',curecount='healing.cure.count',curelow='healing.cure.low',['cure low']='healing.cure.low',cureavg='healing.cure.avg',['cure avg']='healing.cure.avg',curepk='healing.cure.peak',['cure peak']='healing.cure.peak',mp='healing.mp',['hp/mp']='healing.hpmp'},
    ['healing cure']={action='healing.cure.action',use='healing.cure.count',uses='healing.cure.count',healed='healing.cure.healed',low='healing.cure.low',avg='healing.cure.avg',average='healing.cure.avg',peak='healing.cure.peak',high='healing.cure.peak',count='healing.cure.count',['#']='healing.cure.count'},
    recovery={status='recovery.cleanse',cleanse='recovery.cleanse',dispel='recovery.dispel',aspir='recovery.aspir',action='recovery.action',type='recovery.type',count='recovery.count'},
    defense={taken='defense.taken',phys='defense.physical',physical='defense.physical',magict='defense.magic',['magic taken']='defense.magic',other='defense.other',hits='defense.hits',low='defense.lowhit',lowhit='defense.lowhit',avg='defense.avghit',avghit='defense.avghit',peak='defense.peakhit',high='defense.peakhit',peakhit='defense.peakhit',evd='defense.evade',evade='defense.evade',par='defense.parry',parry='defense.parry',blk='defense.block',block='defense.block',ko='defense.ko'},
}
Core.VP.CONTROL_CONTEXT_ORDER={'magic nonmb','magic mb','pet physical','pet healing','pet ranged','pet melee','pet magic','pet sc','pet mb','healing cure','general','melee','ranged','magic','pet','healing','recovery','defense','ws','sc'}
Core.VP.CONTROL_CONTEXT_ALIASES={
    ['weapon skill']='ws',weaponskill='ws',['ws']='ws',['skill chain']='sc',skillchain='sc',sc='sc',
    ['magic burst']='magic mb',mb='magic mb',['non mb']='magic nonmb',nonmb='magic nonmb',nmb='magic nonmb',
    ['pet ws']='pet physical',['pet weaponskill']='pet physical',['pet weapon skill']='pet physical',
    ['cure']='healing cure',
}
function Core.VP.control_context(value)
    value=Core.VP.control_token(value)
    return Core.VP.CONTROL_CONTEXT_ALIASES[value] or value
end
function Core.VP.control_token(value)
    return Core.lower(tostring(value or '')):gsub('^%s+',''):gsub('%s+$',''):gsub('%s+',' ')
end
function Core.VP.resolve_field_key(value)
    local raw=Core.VP.control_token(value); if raw=='' then return nil end
    local compact=raw:gsub('%s+','')
    -- Longest parent context first so "magic mb avg" cannot collapse to
    -- generic Magic Avg.
    for _,ctx_raw in ipairs(Core.VP.CONTROL_CONTEXT_ORDER or {}) do
        local ctx=Core.VP.control_context(ctx_raw)
        local prefix=ctx_raw..' '
        if raw:sub(1,#prefix)==prefix then
            local metric=Core.VP.control_token(raw:sub(#prefix+1))
            local fields=Core.VP.CONTROL_CONTEXT_FIELDS[ctx]
            local leaf=Core.VP.CONTROL_FIELD_ALIASES[metric] or Core.VP.CONTROL_FIELD_ALIASES[metric:gsub('%s+','')] or metric
            if fields and fields[metric] then return fields[metric] end
            if fields and fields[leaf] then return fields[leaf] end
        end
    end
    -- Context synonyms such as "weapon skill low" or "magic burst avg".
    for alias,ctx in pairs(Core.VP.CONTROL_CONTEXT_ALIASES or {}) do
        local prefix=alias..' '
        if raw:sub(1,#prefix)==prefix then
            local metric=Core.VP.control_token(raw:sub(#prefix+1))
            local fields=Core.VP.CONTROL_CONTEXT_FIELDS[ctx]
            local leaf=Core.VP.CONTROL_FIELD_ALIASES[metric] or Core.VP.CONTROL_FIELD_ALIASES[metric:gsub('%s+','')] or metric
            if fields and fields[metric] then return fields[metric] end
            if fields and fields[leaf] then return fields[leaf] end
        end
    end
    -- Explicit path is accepted for power users/help testing.
    if raw:find('%.',1,true) then return raw end
    return Core.VP.CONTROL_FIELD_ALIASES[raw] or Core.VP.CONTROL_FIELD_ALIASES[compact]
end

function Core.VP.control_keys_for_headers(headers,context)
    local out={}
    for i,h in ipairs(headers or {}) do
        local plain=Core.strip_colors and Core.strip_colors(tostring(h or '')) or tostring(h or '')
        local global=Core.VP.resolve_field_key(plain)
        local scoped=context and Core.VP.resolve_field_key(tostring(context)..' '..plain) or nil
        if global=='rank' or global=='player' or global=='job' then out[i]=global else out[i]=scoped or global end
    end
    return out
end

function Core.VP.field_state_match(bucket,key)
    if not bucket or not key then return false end
    if bucket[key]==true then return true end
    local leaf=tostring(key):match('([^.]+)$')
    return leaf and bucket[leaf]==true or false
end
function Core.VP.field_suppressed(key)
    settings.controls=settings.controls or Core.merge({},defaults.controls)
    return Core.VP.field_state_match(settings.controls.hidden_fields,key) or Core.VP.field_state_match(settings.controls.excluded_fields,key)
end
function Core.VP.set_field_hidden(key,hidden)
    if not key then return false end; settings.controls.hidden_fields[key]=hidden and true or nil; return true
end
function Core.VP.set_field_excluded(key,excluded)
    if not key then return false end; settings.controls.excluded_fields[key]=excluded and true or nil; return true
end
function Core.VP.header_control_key(header,context)
    if context and context~='' then return context end
    return Core.VP.resolve_field_key(Core.strip_colors and Core.strip_colors(tostring(header or '')) or tostring(header or ''))
end
function Core.VP.apply_table_controls(headers,rows,aligns,options)
    headers=headers or {}; rows=rows or {}; aligns=aligns or {}; options=options or {}
    local keep={}; local changed=false; local keys=options.control_keys or {}
    for i,h in ipairs(headers) do
        local key=Core.VP.header_control_key(h,keys[i])
        if key and Core.VP.field_suppressed(key) then changed=true else keep[#keep+1]=i end
    end
    if not changed then return headers,rows,aligns,options end
    local nh,na,nr,nkeys={},{},{},{}
    for _,i in ipairs(keep) do nh[#nh+1]=headers[i]; na[#na+1]=aligns[i]; nkeys[#nkeys+1]=keys[i] end
    for r,row in ipairs(rows) do local out={}; for _,i in ipairs(keep) do out[#out+1]=row[i] end; nr[r]=out end
    local no={}; for k,v in pairs(options) do no[k]=v end; no.control_keys=nkeys
    if type(options.min_widths)=='table' then local mw={}; for _,i in ipairs(keep) do mw[#mw+1]=options.min_widths[i] end; no.min_widths=mw end
    if type(options.max_widths)=='table' then local mw={}; for _,i in ipairs(keep) do mw[#mw+1]=options.max_widths[i] end; no.max_widths=mw end
    return nh,nr,na,no
end
function Core.VP.action_key(name) return Core.VP.control_token(name) end
function Core.VP.action_hidden(name) return settings.controls and settings.controls.hidden_actions and settings.controls.hidden_actions[Core.VP.action_key(name)]==true end
function Core.VP.action_excluded(name) return settings.controls and settings.controls.excluded_actions and settings.controls.excluded_actions[Core.VP.action_key(name)]==true end
function Core.VP.set_action_hidden(name,hidden) settings.controls.hidden_actions[Core.VP.action_key(name)]=hidden and true or nil end
function Core.VP.set_action_excluded(name,excluded) settings.controls.excluded_actions[Core.VP.action_key(name)]=excluded and true or nil end
function Core.VP.category_included(name)
    settings.controls=settings.controls or Core.merge({},defaults.controls)
    return not Core.VP.category_state_match(settings.controls.excluded_categories,name)
end
function Core.VP.set_category_excluded(name,excluded)
    name=normalize_category(name); settings.controls.excluded_categories[name]=excluded and true or nil
end
function Core.VP.resolve_action_name(subject)
    local raw=Core.VP.control_token(subject); if raw=='' then return nil end
    local kind=nil
    local prefixes={
        {'weapon skill ','ws'},{'weaponskill ','ws'},{'ws ','ws'},
        {'spell ','spell'},{'magic ','spell'},
        {'job ability ','ja'},{'ability ','ja'},{'ja ','ja'},
        {'action ','action'},
    }
    for _,pfx in ipairs(prefixes) do
        if raw:sub(1,#pfx[1])==pfx[1] then kind=pfx[2]; raw=Core.VP.control_token(raw:sub(#pfx[1]+1)); break end
    end
    local wanted=Core.VP.action_key(raw); if wanted=='' then return nil end
    local found=nil
    local function scan_actor(a)
        if not a or found then return end
        if kind==nil or kind=='ws' or kind=='action' then for name in pairs(a.ws or {}) do if Core.VP.action_key(name)==wanted then found=name; return end end end
        if kind==nil or kind=='spell' or kind=='action' then for name in pairs(a.spells or {}) do if Core.VP.action_key(name)==wanted then found=name; return end end end
        if kind==nil or kind=='action' then
            for name in pairs(a.cleanse_actions or {}) do if Core.VP.action_key(name)==wanted then found=name; return end end
            for name in pairs(a.dispel_actions or {}) do if Core.VP.action_key(name)==wanted then found=name; return end end
            if wanted=='aspir' and (tonumber(a.aspir_recovery) or 0)>0 then found='Aspir'; return end
        end
    end
    for _,a in pairs(session_actors or {}) do scan_actor(a) end
    if current and current.actors then for _,a in pairs(current.actors) do scan_actor(a) end end
    if last_fight and last_fight.actors then for _,a in pairs(last_fight.actors) do scan_actor(a) end end
    if found then return found end

    -- Resolve known FFXI resources even before the action has been observed in
    -- the current parse. This makes filters such as `//vp exclude ws Savage Blade`
    -- deterministic at session start rather than requiring one use first.
    local function resource_name(r)
        if type(r)~='table' then return nil end
        return r.en or r.english or r.name
    end
    local function scan_resource(tbl)
        for _,r in pairs(tbl or {}) do
            local name=resource_name(r)
            if name and Core.VP.action_key(name)==wanted then return tostring(name) end
        end
        return nil
    end
    if kind==nil or kind=='ws' or kind=='action' then found=scan_resource(res.weapon_skills); if found then return found end end
    if kind==nil or kind=='spell' or kind=='action' then found=scan_resource(res.spells); if found then return found end end
    if kind==nil or kind=='ja' or kind=='action' then found=scan_resource(res.job_abilities); if found then return found end end
    -- Recovery aliases are useful even if the specific resource table has not
    -- been populated by this Windower build yet.
    if wanted=='aspir' then return 'Aspir' end
    return nil
end

function Core.VP.ws_stats(a)
    if not a then return {damage=0,attempts=0,hits=0,misses=0,mm=fresh_minmax()} end
    local affected=false; for name in pairs(a.ws or {}) do if Core.VP.action_excluded(name) then affected=true break end end
    if not affected then return {damage=tonumber(a.ws_damage) or 0,attempts=tonumber(a.ws_attempts) or 0,hits=tonumber(a.ws_hits) or 0,misses=tonumber(a.ws_misses) or 0,mm=a.ws_mm or fresh_minmax()} end
    local out={damage=0,attempts=0,hits=0,misses=0,mm=fresh_minmax()}
    for name,w in pairs(a.ws or {}) do if not Core.VP.action_excluded(name) then
        out.damage=out.damage+(tonumber(w.damage) or 0); out.attempts=out.attempts+(tonumber(w.attempts) or 0); out.hits=out.hits+(tonumber(w.hits) or 0); out.misses=out.misses+(tonumber(w.misses) or 0)
        local mm=w.mm or {}; if tonumber(mm.count) and mm.count>0 then out.mm.total=out.mm.total+(tonumber(mm.total) or 0); out.mm.count=out.mm.count+mm.count; if mm.low and (not out.mm.low or mm.low<out.mm.low) then out.mm.low=mm.low end; if mm.peak and (not out.mm.peak or mm.peak>out.mm.peak) then out.mm.peak=mm.peak end end
    end end
    return out
end
function Core.VP.ws_net(a)
    local st=Core.VP.ws_stats(a); return math.max(0,(tonumber(st.damage) or 0)-(tonumber(a and a.dheal_ws) or 0))
end
function Core.VP.magic_stats(a)
    a=a or {}
    local include_mb=Core.VP.category_included('magic_mb') and Core.VP.category_included('mb')
    local include_nonmb=Core.VP.category_included('magic_nonmb')
    local out={casts=0,targets=0,lands=0,resists=0,no_effect=0,damage=0,mm=fresh_minmax(),mb_count=0,mb_damage=0,mb_mm=fresh_minmax(),nonmb_count=0,nonmb_damage=0,nonmb_mm=fresh_minmax(),healing=0}
    local function merge_mm(dst,src)
        src=src or {}; if (tonumber(src.count) or 0)<=0 then return end
        dst.total=dst.total+(tonumber(src.total) or 0); dst.count=dst.count+(tonumber(src.count) or 0)
        if src.low and (not dst.low or src.low<dst.low) then dst.low=src.low end
        if src.peak and (not dst.peak or src.peak>dst.peak) then dst.peak=src.peak end
    end
    for name,sp in pairs(a.spells or {}) do if not Core.VP.action_excluded(name) then
        out.casts=out.casts+(tonumber(sp.casts) or 0); out.targets=out.targets+(tonumber(sp.targets) or 0); out.lands=out.lands+(tonumber(sp.lands) or 0); out.resists=out.resists+(tonumber(sp.resists) or 0); out.no_effect=out.no_effect+(tonumber(sp.no_effect) or 0)
        local total=tonumber(sp.damage) or 0; local mbd=tonumber(sp.mb_damage) or 0; local nmbd=tonumber(sp.nonmb_damage) or 0; local residual=math.max(0,total-mbd-nmbd)
        local allowed=residual+(include_mb and mbd or 0)+(include_nonmb and nmbd or 0); out.damage=out.damage+allowed
        if include_mb and include_nonmb then merge_mm(out.mm,sp.damage_mm)
        else
            if include_mb then merge_mm(out.mm,sp.mb_mm) end
            if include_nonmb then merge_mm(out.mm,sp.nonmb_mm) end
        end
        if include_mb then out.mb_count=out.mb_count+(tonumber(sp.mb_hits) or 0); out.mb_damage=out.mb_damage+mbd; merge_mm(out.mb_mm,sp.mb_mm) end
        if include_nonmb then out.nonmb_count=out.nonmb_count+(tonumber(sp.nonmb_hits) or 0); out.nonmb_damage=out.nonmb_damage+nmbd; merge_mm(out.nonmb_mm,sp.nonmb_mm) end
        out.healing=out.healing+(tonumber(sp.healing) or 0)
    end end
    return out
end
function Core.VP.magic_excluded_damage(a)
    local raw=tonumber(a and a.magic_damage) or 0
    return math.max(0,raw-(Core.VP.magic_stats(a).damage or 0))
end
function Core.VP.magic_net(a)
    a=a or {}; local st=Core.VP.magic_stats(a)
    local extra=math.max(0,(tonumber(a.magic) or 0)-(tonumber(a.magic_damage) or 0))
    if Core.VP.field_suppressed and Core.VP.field_state_match(settings.controls and settings.controls.excluded_fields,'magic.enspell') then extra=math.max(0,extra-(tonumber(a.enspell) or 0)) end
    return math.max(0,extra+(tonumber(st.damage) or 0)-(tonumber(a.dheal_magic) or 0)-(tonumber(a.dheal_enspell) or 0))
end

function Core.VP.healing_stats(a,now)
    if not Core.VP.category_included('healing') then return {healing=0,cures=0,mm=fresh_minmax(),rolling=0} end
    a=a or {}; local actions=a.healing_actions or {}; local have_actions=next(actions)~=nil
    if not have_actions then
        local mm=a.cure_mm or fresh_minmax()
        return {healing=tonumber(a.healing) or 0,cures=tonumber(a.cures) or 0,mm=mm,rolling=a.healing_window and a.healing_window:sum(now or Core.now()) or 0}
    end
    local out={healing=0,cures=0,mm=fresh_minmax(),rolling=0}
    for name,h in pairs(actions) do
        local kind=h.kind or 'cure'
        local allowed=not Core.VP.action_excluded(name)
        if kind=='cure' and not Core.VP.category_included('healing_cure') then allowed=false end
        if allowed then
            out.healing=out.healing+(tonumber(h.healing) or 0)
            if kind=='cure' then
                out.cures=out.cures+(tonumber(h.uses) or 0)
                merge_minmax(out.mm,h.mm)
            end
            if h.window then out.rolling=out.rolling+(tonumber(h.window:sum(now or Core.now())) or 0) end
        end
    end
    return out
end

function Core.VP.recovery_stats(a)
    if not Core.VP.category_included('recovery') then return {cleanse=0,dispel=0,aspir=0} end
    local cleanse,dispel=0,0
    if Core.VP.category_included('recovery_cleanse') then
        for name,count in pairs((a and a.cleanse_actions) or {}) do if not Core.VP.action_excluded(name) then cleanse=cleanse+(tonumber(count) or 0) end end
    end
    if Core.VP.category_included('recovery_dispel') then
        for name,count in pairs((a and a.dispel_actions) or {}) do if not Core.VP.action_excluded(name) then dispel=dispel+(tonumber(count) or 0) end end
    end
    local aspir=(Core.VP.category_included('recovery_aspir') and not Core.VP.action_excluded('Aspir')) and (tonumber(a and a.aspir_recovery) or 0) or 0
    return {cleanse=cleanse,dispel=dispel,aspir=aspir}
end

function Core.VP.defense_stats(a)
    a=a or {}; local out={taken=0,physical=0,magic=0,other=0,hits=0,mm=fresh_minmax()}
    local function add(amount,hits,mm,key)
        if not Core.VP.category_included(key) then return end
        out.taken=out.taken+(tonumber(amount) or 0); out.hits=out.hits+(tonumber(hits) or 0); merge_minmax(out.mm,mm)
    end
    if Core.VP.category_included('defense_physical') then out.physical=tonumber(a.taken_physical) or 0; add(a.taken_physical,a.taken_physical_hits,a.taken_physical_mm,'defense_physical') end
    if Core.VP.category_included('defense_magic') then out.magic=tonumber(a.taken_magical) or 0; add(a.taken_magical,a.taken_magical_hits,a.taken_magical_mm,'defense_magic') end
    if Core.VP.category_included('defense_other') then out.other=(tonumber(a.taken_other) or 0)+(tonumber(a.taken_unknown) or 0); add(out.other,a.taken_other_hits,a.taken_other_mm,'defense_other') end
    return out
end

local function display_status_text()
    local out={}
    for _,k in ipairs({'melee','ws','sc','magic','mb','ranged','pet','healing','recovery','defense'}) do if display_enabled(k) then out[#out+1]=Core.display_word(k) end end
    return #out>0 and table.concat(out,', ') or 'None'
end

function Core.VP.normalize_job(value)
    if value==nil then return '-' end
    local id=tonumber(value); local j=id and res.jobs and res.jobs[id] or nil
    if j then return tostring(j.ens or j.en or j.english or '-'):upper():sub(1,3) end
    local text=tostring(value):upper(); if #text<=3 then return text end
    if res.jobs then for _,r in pairs(res.jobs) do local name=Core.lower(r.en or r.english or ''); if name==Core.lower(text) then return tostring(r.ens or text):upper():sub(1,3) end end end
    return text:sub(1,3)
end
function Core.VP.show_subjob(view)
    local mode=Core.lower(settings.job_sub_mode or 'auto')
    if mode=='on' then return true end
    if mode=='off' then return false end
    return Core.lower(view or settings.view or 'compact')~='compact'
end
function Core.VP.job_header(view)
    return Core.VP.show_subjob(view) and 'Job/Sub' or 'Job'
end
function Core.VP.actor_job_text(a,view)
    if not settings.job_column then return nil end
    local party=refresh_party(Core.now()); local entry=a and party.by_id[a.id] or nil
    if not entry and a and a.name then for _,e in pairs(party.by_id or {}) do if Core.lower(e.name)==Core.lower(a.name) then entry=e break end end end
    local main=Core.VP.normalize_job((entry and entry.main_job) or (a and (a.main_job or a.inferred_job)))
    if not Core.VP.show_subjob(view) then return main end
    local sub_source=nil
    if a and a.subjob_source=='observed' then sub_source=a.sub_job or a.inferred_subjob else sub_source=(entry and entry.sub_job) or (a and (a.sub_job or a.inferred_subjob)) end
    local sub=Core.VP.normalize_job(sub_source); if sub=='-' then return main~='-' and (main..'/-') or '-' end
    return main..'/'..sub
end

local function hud_overview(source,actors,now)
    -- Dynamic keeps a stable core and caps itself at 18 visible columns.
    -- Text identity columns are left-aligned; quantitative fields are right-aligned.
    local total=Core.VP.hud_scope_total(source,actors)
    local headers={'#','Player'}
    local aligns={'right','left'}
    local fields={'rank','player'}
    if settings.job_column then headers[#headers+1]=Core.VP.job_header('dynamic'); aligns[#aligns+1]='left'; fields[#fields+1]='job' end
    for _,spec in ipairs({{'share','Tot Dmg%'},{'damage','Tot Dmg'},{'dps','DPS'}}) do fields[#fields+1]=spec[1]; headers[#headers+1]=spec[2]; aligns[#aligns+1]='right' end
    local function add(key,label)
        if #headers>=18 then return false end
        fields[#fields+1]=key; headers[#headers+1]=label; aligns[#aligns+1]='right'; return true
    end
    if display_enabled('melee') and enabled_filter('melee') then add('melee','Melee'); if settings.columns.accuracy~=false then add('acc','Acc') end end
    if display_enabled('ws') and enabled_filter('ws') then
        add('ws_damage','WS Dmg'); add('ws_share','WS Dmg%'); if settings.columns.ws_hm~=false then add('ws_hm','WS H/M') end; if settings.columns.ws_accuracy~=false then add('ws_acc','WS Acc') end; if settings.columns.ws_avg~=false then add('ws_avg','WS Avg') end
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
    candidate('crit','Crit%',sums.crit,settings.columns.crits==true and display_enabled('melee') and enabled_filter('melee'))
    table.sort(candidates,function(a,b) if a.score==b.score then return a.label<b.label end return a.score>b.score end)
    while #headers<18 and #candidates>0 do local c=table.remove(candidates,1); add(c.key,c.label) end

    local rows={}
    local totals={damage=0,melee=0,melee_hits=0,melee_attempts=0,ws_damage=0,ws_hits=0,ws_misses=0,ws_attempts=0,sc_count=0,sc_damage=0,magic=0,ranged=0,pet=0,mb=0,crit=0}
    local function values_for(a,rank)
        local dmg=combined_damage(a); local share=total~=0 and 100*dmg/total or 0
        local melee=net(a.melee,a.dheal_melee); local ws=Core.VP.ws_net(a); local sc=net(a.skillchain,a.dheal_skillchain)
        local magic=Core.VP.magic_net(a)
        local vals={rank=a._vp_rank or rank,player=hud_player_name(a),job=Core.VP.actor_job_text(a,'dynamic') or '-',share=('%.1f%%'):format(share),damage=n(dmg),dps=dash(hud_combined_dps(a,source,now),n),
            melee=n(melee),acc=accuracy_text(a,false),ws_damage=n(ws),ws_share=share_text(ws,total),
            ws_hm=count_pair(Core.VP.ws_stats(a).hits,Core.VP.ws_stats(a).misses),ws_acc=accuracy_pair_text(Core.VP.ws_stats(a).attempts,Core.VP.ws_stats(a).hits),ws_avg=dash(avg(Core.VP.ws_stats(a).mm),n),
            sc_count=tostring(tonumber(a.skillchain_count) or 0),sc_damage=n(sc),sc_share=share_text(sc,total),magic=n(magic),
            ranged=n(net(a.ranged,a.dheal_ranged)),pet=n(pet_net_damage(a)),mb=n(net(a.mb_damage,a.dheal_mb)),
            crit=(tonumber(a.melee_hits) or 0)>0 and pct(a.melee_crit,a.melee_hits) or '-'}
        totals.damage=totals.damage+dmg; totals.melee=totals.melee+melee; totals.melee_hits=totals.melee_hits+(tonumber(a.melee_hits) or 0); totals.melee_attempts=totals.melee_attempts+(tonumber(a.melee_attempts) or 0)
        local wst=Core.VP.ws_stats(a); totals.ws_damage=totals.ws_damage+ws; totals.ws_hits=totals.ws_hits+(tonumber(wst.hits) or 0); totals.ws_misses=totals.ws_misses+(tonumber(wst.misses) or 0); totals.ws_attempts=totals.ws_attempts+(tonumber(wst.attempts) or 0)
        totals.sc_count=totals.sc_count+(tonumber(a.skillchain_count) or 0); totals.sc_damage=totals.sc_damage+sc; totals.magic=totals.magic+magic; totals.ranged=totals.ranged+net(a.ranged,a.dheal_ranged); totals.pet=totals.pet+pet_net_damage(a); totals.mb=totals.mb+net(a.mb_damage,a.dheal_mb); totals.crit=totals.crit+(tonumber(a.melee_crit) or 0)
        local row={}; for _,k in ipairs(fields) do row[#row+1]=vals[k] or '-' end; return row
    end
    for i,a in ipairs(actors or {}) do rows[#rows+1]=values_for(a,i) end
    if #actors>0 then
        local _,active=elapsed_active(source,now); local represented_share=total~=0 and 100*totals.damage/total or 0
        local tv={rank='',player='TOTAL',job='',share=('%.1f%%'):format(represented_share),damage=n(totals.damage),dps=dash(hud_total_dps(totals.damage,source,now,'dynamic'),n),
            melee=n(totals.melee),acc=accuracy_pair_text(totals.melee_attempts,totals.melee_hits),ws_damage=n(totals.ws_damage),ws_share=share_text(totals.ws_damage,total),
            ws_hm=count_pair(totals.ws_hits,totals.ws_misses),ws_acc=accuracy_pair_text(totals.ws_attempts,totals.ws_hits),ws_avg=totals.ws_hits>0 and n(totals.ws_damage/totals.ws_hits) or '-',
            sc_count=tostring(totals.sc_count),sc_damage=n(totals.sc_damage),sc_share=share_text(totals.sc_damage,total),magic=n(totals.magic),ranged=n(totals.ranged),pet=n(totals.pet),mb=n(totals.mb),crit=totals.melee_hits>0 and pct(totals.crit,totals.melee_hits) or '-'}
        local row={}; for _,k in ipairs(fields) do row[#row+1]=tv[k] or '-' end; rows[#rows+1]=row
    end
    local mins={1,6}; if settings.job_column then mins[#mins+1]=Core.VP.show_subjob('dynamic') and 7 or 3 end; for _,v in ipairs({7,7,4}) do mins[#mins+1]=v end
    local cmap={rank='rank',player='player',job='job',share='general.share',damage='general.damage',dps='general.avg',melee='melee.damage',acc='melee.acc',ws_damage='ws.damage',ws_share='ws.share',ws_hm='ws.hm',ws_acc='ws.acc',ws_avg='ws.avg',sc_count='sc.count',sc_damage='sc.damage',sc_share='sc.share',magic='magic.damage',ranged='ranged.damage',pet='pet.damage',mb='magic.mb.damage',crit='melee.crit'}
    local control_keys={}; for _,k in ipairs(fields) do control_keys[#control_keys+1]=cmap[k] end
    return format_parse_dynamic(headers,rows,aligns,{gap=1,min_widths=mins,control_keys=control_keys})
end

local function hud_compact(source,actors,now)
    local total=Core.VP.hud_scope_total(source,actors)
    local headers={'#','Player'}; local aligns={'right','left'}; local fields={'rank','player'}
    if settings.job_column then headers[#headers+1]=Core.VP.job_header('compact'); aligns[#aligns+1]='left'; fields[#fields+1]='job' end
    local function add(key,label) fields[#fields+1]=key; headers[#headers+1]=label; aligns[#aligns+1]='right' end
    add('share','Tot Dmg%'); add('damage','Tot Dmg'); add('dps','DPS')
    if display_enabled('melee') and settings.columns.accuracy~=false then add('acc','Acc') end
    if display_enabled('ws') and settings.columns.ws_hm~=false then add('ws_hm','WS H/M') end
    if display_enabled('ws') and settings.columns.ws_avg~=false then add('ws_avg','WS Avg') end
    local rows={}; local t={dmg=0,hits=0,att=0,wsh=0,wsm=0,wsd=0}
    local function row_for(a,rank)
        local dmg=combined_damage(a); local share=total~=0 and 100*dmg/total or 0
        local vals={rank=tostring(a._vp_rank or rank or 0),player=hud_player_name(a),job=Core.VP.actor_job_text(a,'compact') or '-',share=('%.1f%%'):format(share),damage=n(dmg),dps=dash(hud_combined_dps(a,source,now),n),acc=accuracy_text(a,false),ws_hm=count_pair(Core.VP.ws_stats(a).hits,Core.VP.ws_stats(a).misses),ws_avg=dash(avg(Core.VP.ws_stats(a).mm),n)}
        local row={}; for _,k in ipairs(fields) do row[#row+1]=vals[k] or '-' end
        t.dmg=t.dmg+dmg; t.hits=t.hits+(tonumber(a.melee_hits) or 0); t.att=t.att+(tonumber(a.melee_attempts) or 0); t.wsh=t.wsh+(tonumber(Core.VP.ws_stats(a).hits) or 0); t.wsm=t.wsm+(tonumber(Core.VP.ws_stats(a).misses) or 0); t.wsd=t.wsd+Core.VP.ws_net(a)
        return row
    end
    for i,a in ipairs(actors or {}) do rows[#rows+1]=row_for(a,i) end
    if #actors>0 then
        local vals={rank='',player='TOTAL',job='',share=(total~=0 and ('%.1f%%'):format(100*t.dmg/total) or '0.0%'),damage=n(t.dmg),dps=dash(hud_total_dps(t.dmg,source,now,'compact'),n),acc=accuracy_pair_text(t.att,t.hits),ws_hm=count_pair(t.wsh,t.wsm),ws_avg=t.wsh>0 and n(t.wsd/t.wsh) or '-'}
        local row={}; for _,k in ipairs(fields) do row[#row+1]=vals[k] or '-' end; rows[#rows+1]=row
    end
    local minmap={rank=1,player=6,job=Core.VP.show_subjob('compact') and 7 or 3,share=9,damage=7,dps=4,acc=5,ws_hm=5,ws_avg=6}
    local cmap={rank='rank',player='player',job='job',share='general.share',damage='general.damage',dps='general.avg',acc='melee.acc',ws_hm='ws.hm',ws_avg='ws.avg'}
    local mins,control_keys={},{}; for _,k in ipairs(fields) do mins[#mins+1]=minmap[k] or 4; control_keys[#control_keys+1]=cmap[k] end
    return format_parse_dynamic(headers,rows,aligns,{gap=1,min_widths=mins,control_keys=control_keys})
end

local function hud_ws(source,actors,full)
    local headers={'Player'}; local aligns={'left'}; local fields={'player'}
    if settings.job_column then headers[#headers+1]=Core.VP.job_header(settings.view); aligns[#aligns+1]='left'; fields[#fields+1]='job' end
    local function add(key,label,align) fields[#fields+1]=key; headers[#headers+1]=label; aligns[#aligns+1]=align or 'right' end
    add('ws','WS','left'); add('att','Att'); add('hit','Hit'); add('miss','Miss')
    if settings.columns.ws_accuracy~=false then add('acc','Acc') end
    add('low','Low'); if settings.columns.ws_avg~=false then add('avg','Avg') end; add('peak','Peak'); add('total','Total')
    local rows={}
    local function emit(a,name,w,is_all)
        local st=is_all and Core.VP.ws_stats(a) or w
        local mm=st.mm or fresh_minmax(); local attempts=st.attempts or 0; local hits=st.hits or 0; local misses=st.misses or 0; local damage=st.damage or 0
        local vals={player=is_all and hud_player_name(a) or '',job=is_all and (Core.VP.actor_job_text(a,settings.view) or '-') or '',ws=name,att=attempts,hit=hits,miss=misses,acc=pct(hits,attempts),low=dash(mm.low,n),avg=dash(avg(mm),n),peak=dash(mm.peak,n),total=n(damage)}
        local r={}; for _,k in ipairs(fields) do r[#r+1]=vals[k] or '-' end; rows[#rows+1]=r
    end
    for _,a in ipairs(actors) do
        emit(a,'ALL',{},true)
        if full then
            local list={}; for name,w in pairs(a.ws) do if not Core.VP.action_hidden(name) and not Core.VP.action_excluded(name) then list[#list+1]={name=name,w=w} end end; table.sort(list,function(x,y) return x.w.damage>y.w.damage end)
            for _,x in ipairs(list) do emit(a,'  '..x.name,x.w,false) end
        end
    end
    return format_parse_dynamic(headers,rows,aligns,{gap=1,control_keys=Core.VP.control_keys_for_headers(headers,'ws')})
end

local function hud_magic(source,actors,full)
    local headers={'Player'}; local aligns={'left'}
    if settings.job_column then headers[#headers+1]=Core.VP.job_header(settings.view); aligns[#aligns+1]='left' end
    for _,h in ipairs({'Spell','Cast','Tgt','Land','Res','NoEf','Land%','Dmg','Low','Avg','Peak','MB#','MB Dmg','MBAvg','MBPk','N#','N Dmg','NAvg','NPk','Heal'}) do headers[#headers+1]=h; aligns[#aligns+1]=(h=='Spell' and 'left' or 'right') end
    local rows={}
    for _,a in ipairs(actors) do
        local ms=Core.VP.magic_stats(a); local aggregate={casts=ms.casts,targets=ms.targets,lands=ms.lands,resists=ms.resists,no_effect=ms.no_effect}
        local row={hud_player_name(a)}; if settings.job_column then row[#row+1]=Core.VP.actor_job_text(a,settings.view) or '-' end
        for _,v in ipairs({'ALL',ms.casts>0 and ms.casts or '-',ms.targets>0 and ms.targets or '-',ms.targets>0 and ms.lands or '-',ms.targets>0 and ms.resists or '-',ms.targets>0 and ms.no_effect or '-',spell_success_pct(aggregate),ms.damage>0 and n(ms.damage) or '-',dash(ms.mm.low,n),dash(avg(ms.mm),n),dash(ms.mm.peak,n),ms.mb_count>0 and ms.mb_count or '-',ms.mb_damage>0 and n(ms.mb_damage) or '-',dash(avg(ms.mb_mm),n),dash(ms.mb_mm.peak,n),ms.nonmb_count>0 and ms.nonmb_count or '-',ms.nonmb_damage>0 and n(ms.nonmb_damage) or '-',dash(avg(ms.nonmb_mm),n),dash(ms.nonmb_mm.peak,n),ms.healing>0 and n(ms.healing) or '-'}) do row[#row+1]=v end
        rows[#rows+1]=row
        if full then
            local list={}; for name,sp in pairs(a.spells or {}) do if not Core.VP.action_hidden(name) and not Core.VP.action_excluded(name) then list[#list+1]={name=name,sp=sp} end end
            table.sort(list,function(x,y) local xd=(x.sp.damage or 0)+(x.sp.healing or 0); local yd=(y.sp.damage or 0)+(y.sp.healing or 0); if xd==yd then return (x.sp.casts or 0)>(y.sp.casts or 0) end; return xd>yd end)
            for _,entry in ipairs(list) do local sp=entry.sp; local r={''}; if settings.job_column then r[#r+1]='' end; for _,v in ipairs({'  '..entry.name,sp.casts>0 and sp.casts or '-',sp.targets>0 and sp.targets or '-',sp.targets>0 and sp.lands or '-',sp.targets>0 and sp.resists or '-',sp.targets>0 and sp.no_effect or '-',spell_success_pct(sp),sp.damage>0 and n(sp.damage) or '-',dash(sp.damage_mm.low,n),dash(avg(sp.damage_mm),n),dash(sp.damage_mm.peak,n),sp.mb_hits>0 and sp.mb_hits or '-',sp.mb_damage>0 and n(sp.mb_damage) or '-',dash(avg(sp.mb_mm),n),dash(sp.mb_mm.peak,n),sp.nonmb_hits>0 and sp.nonmb_hits or '-',sp.nonmb_damage>0 and n(sp.nonmb_damage) or '-',dash(avg(sp.nonmb_mm),n),dash(sp.nonmb_mm.peak,n),sp.healing>0 and n(sp.healing) or '-'}) do r[#r+1]=v end; rows[#rows+1]=r end
        end
    end
    return format_parse_dynamic(headers,rows,aligns,{gap=1,control_keys=Core.VP.control_keys_for_headers(headers,'magic')})
end
local function hud_defense(source,actors)
    local headers={'Player'}; local aligns={'left'}
    if settings.job_column then headers[#headers+1]=Core.VP.job_header(settings.view); aligns[#aligns+1]='left' end
    for _,h in ipairs({'Taken','Phys','MagicT','Other','Hits','AvgHit','Low','Peak','Evd','Par','Blk','KO'}) do headers[#headers+1]=h; aligns[#aligns+1]='right' end
    local rows={}; for _,a in ipairs(actors) do local ds=Core.VP.defense_stats(a); local r={hud_player_name(a)}; if settings.job_column then r[#r+1]=Core.VP.actor_job_text(a,settings.view) or '-' end; for _,v in ipairs({n(ds.taken),n(ds.physical),n(ds.magic),n(ds.other),ds.hits,dash(avg(ds.mm),n),dash(ds.mm.low,n),dash(ds.mm.peak,n),a.evades,a.parries,a.blocks,a.deaths}) do r[#r+1]=v end; rows[#rows+1]=r end
    return format_parse_dynamic(headers,rows,aligns,{gap=1,control_keys=Core.VP.control_keys_for_headers(headers,'defense')})
end
local function hud_healing(source,actors,now)
    local total_taken,total_recv,total_mp=0,0,0; for _,a in ipairs(actors) do total_taken=total_taken+Core.VP.defense_stats(a).taken; total_recv=total_recv+a.received; total_mp=total_mp+a.cure_mp_received end
    local headers={'Player'}; local aligns={'left'}; if settings.job_column then headers[#headers+1]=Core.VP.job_header(settings.view); aligns[#aligns+1]='left' end
    for _,h in ipairs({'Taken','Dmg%','Cure R\'cvd','Recv%','MP Load','Burden','Cured','Self Cure','Cleanse','Dispel','Aspir','HPS','Cure#','CureAvg','Peak','HP/MP'}) do headers[#headers+1]=h; aligns[#aligns+1]='right' end
    local rows={}
    for _,a in ipairs(actors) do
        local ds=Core.VP.defense_stats(a); local hs=Core.VP.healing_stats(a,now); local rs=Core.VP.recovery_stats(a)
        local dmgload=total_taken>0 and ds.taken/total_taken or nil; local recvload=total_recv>0 and a.received/total_recv or nil; local mpload=total_mp>0 and a.cure_mp_received/total_mp or nil; local burden=dmgload and dmgload>0 and mpload and mpload/dmgload or nil; local hpmp=a.mp_spent>0 and hs.healing/a.mp_spent or nil
        local r={hud_player_name(a)}; if settings.job_column then r[#r+1]=Core.VP.actor_job_text(a,settings.view) or '-' end
        for _,v in ipairs({n(ds.taken),dmgload and ('%.1f%%'):format(dmgload*100) or '-',n(a.received),recvload and ('%.1f%%'):format(recvload*100) or '-',mpload and ('%.1f%%'):format(mpload*100) or '-',burden and ('%.2f'):format(burden) or '-',n(hs.healing),n(a.self_healing or 0),rs.cleanse or 0,rs.dispel or 0,n(rs.aspir or 0),dash(hps(a,source,now),n),hs.cures or 0,dash(avg(hs.mm),n),dash(hs.mm.peak,n),hpmp and ('%.1f'):format(hpmp) or '-'}) do r[#r+1]=v end; rows[#rows+1]=r
    end
    return format_parse_dynamic(headers,rows,aligns,{gap=1,control_keys=Core.VP.control_keys_for_headers(headers,'healing')})
end
function Core.VP.hud_healing_details(source,actors,now)
    local headers={'Player'}; local aligns={'left'}
    if settings.job_column then headers[#headers+1]=Core.VP.job_header(settings.view); aligns[#aligns+1]='left' end
    for _,h in ipairs({'Action','Use','Healed','Low','Avg','Peak'}) do headers[#headers+1]=h; aligns[#aligns+1]=(h=='Action' and 'left' or 'right') end
    local rows={}
    for _,a in ipairs(actors) do
        local r={hud_player_name(a)}; if settings.job_column then r[#r+1]=Core.VP.actor_job_text(a,settings.view) or '-' end
        local hs=Core.VP.healing_stats(a,now)
        for _,v in ipairs({'ALL',hs.cures>0 and hs.cures or '-',hs.healing>0 and n(hs.healing) or '-',dash(hs.mm.low,n),dash(avg(hs.mm),n),dash(hs.mm.peak,n)}) do r[#r+1]=v end
        rows[#rows+1]=r
        local list={}
        for name,h in pairs(a.healing_actions or {}) do if (tonumber(h.healing) or 0)>0 and not Core.VP.action_hidden(name) and not Core.VP.action_excluded(name) and (h.kind~='cure' or Core.VP.category_included('healing_cure')) then list[#list+1]={name=name,h=h} end end
        table.sort(list,function(x,y) local xd=tonumber(x.h.healing) or 0; local yd=tonumber(y.h.healing) or 0; if xd==yd then return tostring(x.name)<tostring(y.name) end; return xd>yd end)
        for _,entry in ipairs(list) do
            local h=entry.h; local rr={''}; if settings.job_column then rr[#rr+1]='' end
            for _,v in ipairs({'  '..entry.name,(h.uses or 0)>0 and h.uses or '-',n(h.healing or 0),dash(h.mm and h.mm.low,n),dash(h.mm and avg(h.mm),n),dash(h.mm and h.mm.peak,n)}) do rr[#rr+1]=v end
            rows[#rows+1]=rr
        end
    end
    return format_parse_dynamic(headers,rows,aligns,{gap=1,control_keys=Core.VP.control_keys_for_headers(headers,'healing cure')})
end

function Core.VP.hud_recovery_details(source,actors)
    local headers={'Player'}; local aligns={'left'}
    if settings.job_column then headers[#headers+1]=Core.VP.job_header(settings.view); aligns[#aligns+1]='left' end
    for _,h in ipairs({'Action','Type','Count'}) do headers[#headers+1]=h; aligns[#aligns+1]=(h=='Count' and 'right' or 'left') end
    local rows={}
    for _,a in ipairs(actors) do
        local rs=Core.VP.recovery_stats(a); local total=(tonumber(rs.cleanse) or 0)+(tonumber(rs.dispel) or 0)
        local r={hud_player_name(a)}; if settings.job_column then r[#r+1]=Core.VP.actor_job_text(a,settings.view) or '-' end
        for _,v in ipairs({'ALL','Recovery',total>0 and total or '-'}) do r[#r+1]=v end; rows[#rows+1]=r
        local list={}
        for name,count in pairs(a.cleanse_actions or {}) do if not Core.VP.action_hidden(name) and not Core.VP.action_excluded(name) then list[#list+1]={name=name,kind='Status',count=tonumber(count) or 0} end end
        for name,count in pairs(a.dispel_actions or {}) do if not Core.VP.action_hidden(name) and not Core.VP.action_excluded(name) then list[#list+1]={name=name,kind='Dispel',count=tonumber(count) or 0} end end
        if (tonumber(a.aspir_recovery) or 0)>0 and not Core.VP.action_hidden('Aspir') and not Core.VP.action_excluded('Aspir') then list[#list+1]={name='Aspir',kind='MP',count=tonumber(a.aspir_recovery) or 0} end
        table.sort(list,function(x,y) if x.count==y.count then return tostring(x.name)<tostring(y.name) end; return x.count>y.count end)
        for _,entry in ipairs(list) do local rr={''}; if settings.job_column then rr[#rr+1]='' end; rr[#rr+1]='  '..entry.name; rr[#rr+1]=entry.kind; rr[#rr+1]=entry.count; rows[#rows+1]=rr end
    end
    return format_parse_dynamic(headers,rows,aligns,{gap=1,control_keys=Core.VP.control_keys_for_headers(headers,'recovery')})
end

local function hud_pet(source,actors,now)
    local headers={'Player'}; local aligns={'left'}; local fields={'player'}
    if settings.job_column then headers[#headers+1]=Core.VP.job_header(settings.view); aligns[#aligns+1]='left'; fields[#fields+1]='job' end
    local function add(key,label) fields[#fields+1]=key; headers[#headers+1]=label; aligns[#aligns+1]='right' end
    add('master','Master'); add('pdmg','P.Dmg'); add('pshare','P.Dmg%'); add('combined','Combined'); add('melee','Melee')
    if settings.columns.accuracy~=false then add('acc','Acc') end
    add('ranged','Ranged'); if settings.columns.ranged_accuracy~=false then add('racc','R.Acc') end
    for _,x in ipairs({{'phys','Phys'},{'magic','Magic'},{'sc','SC'},{'mb','MB'},{'cured','Cured'},{'taken','Taken'}}) do add(x[1],x[2]) end
    local rows={}; local grand=0; for _,a in ipairs(actors) do grand=grand+combined_damage(a) end
    for _,a in ipairs(actors) do
        local p=a.pet; local master=player_net_damage(a); local pd=pet_net_damage(a); local combined=master+pd; local pphys=tonumber(p.physical) or 0; if pphys==0 then pphys=tonumber(p.ws) or 0 end
        local vals={player=hud_player_name(a),job=Core.VP.actor_job_text(a,settings.view) or '-',master=n(master),pdmg=n(pd),pshare=grand~=0 and ('%.1f%%'):format(100*pd/grand) or '-',combined=n(combined),melee=n(net(p.melee,p.dheal_melee)),acc=accuracy_pair_text(p.melee_attempts,p.melee_hits),ranged=n(net(p.ranged,p.dheal_ranged)),racc=accuracy_pair_text(p.ranged_attempts,p.ranged_hits),phys=n(net(pphys,p.dheal_physical)),magic=n((tonumber(p.magic) or 0)-(tonumber(p.dheal_magic) or 0)-(tonumber(p.dheal_enspell) or 0)),sc=n(net(p.skillchain,p.dheal_skillchain)),mb=n(net(p.mb_damage,p.dheal_mb)),cured=n(p.healing or 0),taken=n(p.taken or 0)}
        local r={}; for _,k in ipairs(fields) do r[#r+1]=vals[k] or '-' end; rows[#rows+1]=r
    end
    return format_parse_dynamic(headers,rows,aligns,{gap=1,control_keys=Core.VP.control_keys_for_headers(headers,'pet')})
end

local function hud_max(source,actors,now)
    local cols,widths,aligns,control_keys={'Player'},{6},{'left'},{'player'}
    if settings.job_column then cols[#cols+1]=Core.VP.job_header(settings.view); widths[#widths+1]=Core.VP.show_subjob(settings.view) and 7 or 3; aligns[#aligns+1]='left'; control_keys[#control_keys+1]='job' end
    local rows={}; for i,a in ipairs(actors) do rows[i]={hud_player_name(a)}; if settings.job_column then rows[i][#rows[i]+1]=Core.VP.actor_job_text(a,settings.view) or '-' end end
    local function section(context,names,ws,vals)
        for i,name in ipairs(names) do cols[#cols+1]=name; widths[#widths+1]=ws[i] or 8; aligns[#aligns+1]='right'; control_keys[#control_keys+1]=(Core.VP.control_keys_for_headers({name},context)[1]) end
        for r,a in ipairs(actors) do local v=vals(a); for _,x in ipairs(v) do rows[r][#rows[r]+1]=x end end
    end
    if section_on('general') then section('general',{'Dmg','D.Heal','Live','Avg','10m'},{9,8,8,8,8},function(a) return {n(combined_damage(a)),total_dheal(a)>0 and n(total_dheal(a)) or '-',dash(live_dps(a,now),n),dash(hud_combined_dps(a,source,now),n),dash(ten_dps(a,now),n)} end) end
    if section_on('melee') then
        if settings.columns.accuracy~=false then section('melee',{'Melee','Att','Hit','Miss','Acc','Low','Avg','Peak','Crit','C.Avg','C.Peak'},{9,6,6,6,7,8,8,8,7,8,8},function(a) return {a.melee>0 and n(a.melee) or '-',a.melee_attempts>0 and a.melee_attempts or '-',a.melee_attempts>0 and a.melee_hits or '-',a.melee_attempts>0 and a.melee_misses or '-',a.melee_attempts>0 and pct(a.melee_hits,a.melee_attempts) or '-',dash(a.melee_mm.low,n),dash(avg(a.melee_mm),n),dash(a.melee_mm.peak,n),a.melee_hits>0 and pct(a.melee_crit,a.melee_hits) or '-',dash(avg(a.crit_mm),n),dash(a.crit_mm.peak,n)} end)
        else section('melee',{'Melee','Att','Hit','Miss','Low','Avg','Peak','Crit','C.Avg','C.Peak'},{9,6,6,6,8,8,8,7,8,8},function(a) return {a.melee>0 and n(a.melee) or '-',a.melee_attempts>0 and a.melee_attempts or '-',a.melee_attempts>0 and a.melee_hits or '-',a.melee_attempts>0 and a.melee_misses or '-',dash(a.melee_mm.low,n),dash(avg(a.melee_mm),n),dash(a.melee_mm.peak,n),a.melee_hits>0 and pct(a.melee_crit,a.melee_hits) or '-',dash(avg(a.crit_mm),n),dash(a.crit_mm.peak,n)} end) end
    end
    if section_on('ws') then
        local show_acc=settings.columns.ws_accuracy~=false; local show_avg=settings.columns.ws_avg~=false
        if show_acc and show_avg then section('ws',{'WS','Att','Hit','Miss','WS%','Low','Avg','Peak'},{9,5,5,5,7,8,8,8},function(a) return {Core.VP.ws_stats(a).damage>0 and n(Core.VP.ws_stats(a).damage) or '-',Core.VP.ws_stats(a).attempts>0 and Core.VP.ws_stats(a).attempts or '-',Core.VP.ws_stats(a).attempts>0 and Core.VP.ws_stats(a).hits or '-',Core.VP.ws_stats(a).attempts>0 and Core.VP.ws_stats(a).misses or '-',Core.VP.ws_stats(a).attempts>0 and pct(Core.VP.ws_stats(a).hits,Core.VP.ws_stats(a).attempts) or '-',dash(Core.VP.ws_stats(a).mm.low,n),dash(avg(Core.VP.ws_stats(a).mm),n),dash(Core.VP.ws_stats(a).mm.peak,n)} end)
        elseif show_acc then section('ws',{'WS','Att','Hit','Miss','WS%','Low','Peak'},{9,5,5,5,7,8,8},function(a) return {Core.VP.ws_stats(a).damage>0 and n(Core.VP.ws_stats(a).damage) or '-',Core.VP.ws_stats(a).attempts>0 and Core.VP.ws_stats(a).attempts or '-',Core.VP.ws_stats(a).attempts>0 and Core.VP.ws_stats(a).hits or '-',Core.VP.ws_stats(a).attempts>0 and Core.VP.ws_stats(a).misses or '-',Core.VP.ws_stats(a).attempts>0 and pct(Core.VP.ws_stats(a).hits,Core.VP.ws_stats(a).attempts) or '-',dash(Core.VP.ws_stats(a).mm.low,n),dash(Core.VP.ws_stats(a).mm.peak,n)} end)
        elseif show_avg then section('ws',{'WS','Att','Hit','Miss','Low','Avg','Peak'},{9,5,5,5,8,8,8},function(a) return {Core.VP.ws_stats(a).damage>0 and n(Core.VP.ws_stats(a).damage) or '-',Core.VP.ws_stats(a).attempts>0 and Core.VP.ws_stats(a).attempts or '-',Core.VP.ws_stats(a).attempts>0 and Core.VP.ws_stats(a).hits or '-',Core.VP.ws_stats(a).attempts>0 and Core.VP.ws_stats(a).misses or '-',dash(Core.VP.ws_stats(a).mm.low,n),dash(avg(Core.VP.ws_stats(a).mm),n),dash(Core.VP.ws_stats(a).mm.peak,n)} end)
        else section('ws',{'WS','Att','Hit','Miss','Low','Peak'},{9,5,5,5,8,8},function(a) return {Core.VP.ws_stats(a).damage>0 and n(Core.VP.ws_stats(a).damage) or '-',Core.VP.ws_stats(a).attempts>0 and Core.VP.ws_stats(a).attempts or '-',Core.VP.ws_stats(a).attempts>0 and Core.VP.ws_stats(a).hits or '-',Core.VP.ws_stats(a).attempts>0 and Core.VP.ws_stats(a).misses or '-',dash(Core.VP.ws_stats(a).mm.low,n),dash(Core.VP.ws_stats(a).mm.peak,n)} end) end
    end
    if section_on('sc') then section('sc',{'SC'},{8},function(a) return {a.skillchain>0 and n(a.skillchain) or '-'} end) end
    if section_on('ranged') then
        if settings.columns.ranged_accuracy~=false then section('ranged',{'Rng','Shot','Hit','Miss','RAcc','Low','Avg','Peak','RCrit'},{9,6,6,6,7,8,8,8,7},function(a) return {a.ranged>0 and n(a.ranged) or '-',a.ranged_attempts>0 and a.ranged_attempts or '-',a.ranged_attempts>0 and a.ranged_hits or '-',a.ranged_attempts>0 and a.ranged_misses or '-',a.ranged_attempts>0 and pct(a.ranged_hits,a.ranged_attempts) or '-',dash(a.ranged_mm.low,n),dash(avg(a.ranged_mm),n),dash(a.ranged_mm.peak,n),a.ranged_hits>0 and pct(a.ranged_crit,a.ranged_hits) or '-'} end)
        else section('ranged',{'Rng','Shot','Hit','Miss','Low','Avg','Peak','RCrit'},{9,6,6,6,8,8,8,7},function(a) return {a.ranged>0 and n(a.ranged) or '-',a.ranged_attempts>0 and a.ranged_attempts or '-',a.ranged_attempts>0 and a.ranged_hits or '-',a.ranged_attempts>0 and a.ranged_misses or '-',dash(a.ranged_mm.low,n),dash(avg(a.ranged_mm),n),dash(a.ranged_mm.peak,n),a.ranged_hits>0 and pct(a.ranged_crit,a.ranged_hits) or '-'} end) end
    end
    if section_on('magic') then section('magic',{'Magic','Cast','Tgt','Land','Res','NoEf','Land%','Low','Avg','Peak','MB','MB#','MBAvg','MBPk','NMB','N#','NAvg','NPk','MHeal','Ensp'},{9,6,6,6,6,6,7,8,8,8,9,6,8,8,9,6,8,8,9,8},function(a) return {a.magic>0 and n(Core.VP.magic_net(a)) or '-',a.magic_casts>0 and a.magic_casts or '-',a.magic_targets>0 and a.magic_targets or '-',a.magic_targets>0 and a.magic_lands or '-',a.magic_targets>0 and a.magic_resists or '-',a.magic_targets>0 and a.magic_no_effect or '-',((a.magic_lands or 0)+(a.magic_resists or 0))>0 and pct(a.magic_lands,(a.magic_lands or 0)+(a.magic_resists or 0)) or '-',dash(a.magic_mm.low,n),dash(avg(ms.mm),n),dash(a.magic_mm.peak,n),a.mb_damage>0 and n(a.mb_damage) or '-',a.mb_count>0 and a.mb_count or '-',dash(avg(a.mb_mm),n),dash(a.mb_mm.peak,n),a.nonmb_damage>0 and n(a.nonmb_damage) or '-',a.nonmb_count>0 and a.nonmb_count or '-',dash(avg(a.nonmb_mm),n),dash(a.nonmb_mm.peak,n),a.magic_healing>0 and n(a.magic_healing) or '-',a.enspell>0 and n(a.enspell) or '-'} end) end
    if section_on('pet') then
        local ha=settings.columns.accuracy~=false; local hra=settings.columns.ranged_accuracy~=false
        if ha and hra then section('pet',{'P.Dmg','Melee','Acc','Ranged','R.Acc','Phys','Magic','SC','MB','Heal','Taken'},{9,9,7,9,7,9,9,8,8,9,9},function(a) local p=a.pet; local ph=tonumber(p.physical) or 0; if ph==0 then ph=tonumber(p.ws) or 0 end; return {n(pet_net_damage(a)),n(net(p.melee,p.dheal_melee)),accuracy_pair_text(p.melee_attempts,p.melee_hits),n(net(p.ranged,p.dheal_ranged)),accuracy_pair_text(p.ranged_attempts,p.ranged_hits),n(net(ph,p.dheal_physical)),n((tonumber(p.magic) or 0)-(tonumber(p.dheal_magic) or 0)-(tonumber(p.dheal_enspell) or 0)),n(net(p.skillchain,p.dheal_skillchain)),n(net(p.mb_damage,p.dheal_mb)),n(p.healing or 0),n(p.taken or 0)} end)
        elseif ha then section('pet',{'P.Dmg','Melee','Acc','Ranged','Phys','Magic','SC','MB','Heal','Taken'},{9,9,7,9,9,9,8,8,9,9},function(a) local p=a.pet; local ph=tonumber(p.physical) or 0; if ph==0 then ph=tonumber(p.ws) or 0 end; return {n(pet_net_damage(a)),n(net(p.melee,p.dheal_melee)),accuracy_pair_text(p.melee_attempts,p.melee_hits),n(net(p.ranged,p.dheal_ranged)),n(net(ph,p.dheal_physical)),n((tonumber(p.magic) or 0)-(tonumber(p.dheal_magic) or 0)-(tonumber(p.dheal_enspell) or 0)),n(net(p.skillchain,p.dheal_skillchain)),n(net(p.mb_damage,p.dheal_mb)),n(p.healing or 0),n(p.taken or 0)} end)
        elseif hra then section('pet',{'P.Dmg','Melee','Ranged','R.Acc','Phys','Magic','SC','MB','Heal','Taken'},{9,9,9,7,9,9,8,8,9,9},function(a) local p=a.pet; local ph=tonumber(p.physical) or 0; if ph==0 then ph=tonumber(p.ws) or 0 end; return {n(pet_net_damage(a)),n(net(p.melee,p.dheal_melee)),n(net(p.ranged,p.dheal_ranged)),accuracy_pair_text(p.ranged_attempts,p.ranged_hits),n(net(ph,p.dheal_physical)),n((tonumber(p.magic) or 0)-(tonumber(p.dheal_magic) or 0)-(tonumber(p.dheal_enspell) or 0)),n(net(p.skillchain,p.dheal_skillchain)),n(net(p.mb_damage,p.dheal_mb)),n(p.healing or 0),n(p.taken or 0)} end)
        else section('pet',{'P.Dmg','Melee','Ranged','Phys','Magic','SC','MB','Heal','Taken'},{9,9,9,9,9,8,8,9,9},function(a) local p=a.pet; local ph=tonumber(p.physical) or 0; if ph==0 then ph=tonumber(p.ws) or 0 end; return {n(pet_net_damage(a)),n(net(p.melee,p.dheal_melee)),n(net(p.ranged,p.dheal_ranged)),n(net(ph,p.dheal_physical)),n((tonumber(p.magic) or 0)-(tonumber(p.dheal_magic) or 0)-(tonumber(p.dheal_enspell) or 0)),n(net(p.skillchain,p.dheal_skillchain)),n(net(p.mb_damage,p.dheal_mb)),n(p.healing or 0),n(p.taken or 0)} end) end
    end
    if section_on('defense') then section('defense',{'Taken','Phys','MagicT','Other','Hits','LowHit','AvgHit','PeakHit','Evd','Par','Blk','KO'},{9,8,8,8,6,8,8,8,5,5,5,4},function(a) return {n(a.taken),a.taken_physical>0 and n(a.taken_physical) or '-',a.taken_magical>0 and n(a.taken_magical) or '-',(a.taken_other+a.taken_unknown)>0 and n(a.taken_other+a.taken_unknown) or '-',a.taken_hits>0 and a.taken_hits or '-',dash(a.taken_mm.low,n),dash(avg(a.taken_mm),n),dash(a.taken_mm.peak,n),a.evades,a.parries,a.blocks,a.deaths} end) end
    if section_on('healing') then section('healing',{'Cured','HPS','Cure#','Cure Rcvd','Self Cure','CureLow','CureAvg','CurePk','MP','HP/MP'},{9,8,6,9,9,8,8,8,8,8},function(a) return {a.healing>0 and n(a.healing) or '-',dash(hps(a,source,now),n),a.cures>0 and a.cures or '-',a.received>0 and n(a.received) or '-',a.self_healing>0 and n(a.self_healing) or '-',dash(a.cure_mm.low,n),dash(avg(a.cure_mm),n),dash(a.cure_mm.peak,n),a.mp_spent>0 and n(a.mp_spent) or '-',a.mp_spent>0 and ('%.1f'):format(a.healing/a.mp_spent) or '-'} end) end
    if section_on('recovery') then section('recovery',{'Status','Dispel','Aspir'},{7,7,8},function(a) return {Core.VP.recovery_stats(a).cleanse>0 and Core.VP.recovery_stats(a).cleanse or '-',Core.VP.recovery_stats(a).dispel>0 and Core.VP.recovery_stats(a).dispel or '-',Core.VP.recovery_stats(a).aspir>0 and n(Core.VP.recovery_stats(a).aspir) or '-'} end) end
    return format_parse_dynamic(cols,rows,aligns,{gap=1,control_keys=control_keys})
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

local function target_header(source,actors,max_width)
    if settings.target_hp=='off' or not source then return nil end
    local mob=windower.ffxi.get_mob_by_target and (windower.ffxi.get_mob_by_target('t') or windower.ffxi.get_mob_by_target('bt')) or nil
    if not mob or not mob.id or refresh_party(Core.now()).by_id[mob.id] then last_target_id=nil; return nil end
    local hpp=tonumber(mob.hpp); refresh_target_life(mob); observe_target_learning(mob); last_target_id=mob.id
    local zone=(windower.ffxi.get_info() or {}).zone; local known=enemy_registry:lookup(zone,mob.name); local hptext
    local learned_ok=known and known.max_hp_source=='learned' and (known.confidence=='medium' or known.confidence=='high' or known.confidence=='verified')
    local static_ok=known and known.max_hp_source and known.max_hp_source~='learned'
    if hpp and known and tonumber(known.max_hp) and (learned_ok or static_ok) then
        local maxhp=tonumber(known.max_hp); local currenthp=maxhp*Core.clamp(hpp,0,100)/100
        hptext=target_hp_color(('~%s/%s (%d%%)'):format(n(currenthp),n(maxhp),math.max(0,math.min(100,math.floor(hpp+0.5)))),hpp)
    else hptext=hpp and target_hp_color(('%d%%'):format(math.max(0,math.min(100,math.floor(hpp+0.5)))),hpp) or '?' end
    local incoming=Core.VP.incoming_display_for(mob.id,Core.now()); local name=tostring(mob.name or mob.id)
    local prefix='Target: '; local middle=' | HP: '..hptext..' | Incoming: '
    if max_width then
        local reserve=Core.visible_len(prefix)+Core.visible_len(middle)+Core.visible_len(incoming or '')
        local allowed=math.max(4,max_width-reserve)
        if #name>allowed then name=name:sub(1,math.max(1,allowed-1))..'~' end
    end
    local line=prefix..name..middle..(incoming or '')
    if max_width and Core.visible_len(line)>max_width then
        local plain=Core.visible_text(line); line=plain:sub(1,math.max(1,max_width-1))..'~'
    end
    return line
end

function Core.VP.report_destination_label()
    local d=Core.lower(settings.report_destination or 'party')
    local map={['local']='Self',self='Self',party='Party',alliance='Alliance',linkshell='Linkshell',linkshell2='Linkshell2',tell='Tell'}
    local label=map[d] or Core.display_word(d); if d=='tell' and settings.report_tell~='' then label=label..':'..settings.report_tell end; return label
end
function Core.VP.fit_plain(line,width)
    line=tostring(line or ''); if not width or #line<=width then return line end; if width<=1 then return line:sub(1,width) end; return line:sub(1,width-1)..'~'
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

function Core.VP.filter_display_text()
    local p=parsing_scope_text(); return p=='All' and 'None' or p
end

local function view_display_name(value)
    local names={
        compact='Compact', dynamic='Dynamic', full='Full', physical='Physical',
        ws='WS', ['ws-details']='WS Details', ranged='Ranged', magic='Magic', ['magic-details']='Magic Details',
        pet='Pet', healing='Healing', ['healing-details']='Healing Details', recovery='Recovery', ['recovery-details']='Recovery Details', defense='Defense',
    }
    return names[value] or Core.display_word(value)
end
function Core.VP.scope_label(value)
    local v=Core.lower(value or settings.scope or 'alliance')
    if v=='allparties' then return 'All Parties' end
    return Core.display_word(v)
end
function Core.VP.theme_label(value)
    local v=Core.lower(value or settings.theme or 'dark')
    if v=='contrastdark' then return 'ContrastDark' elseif v=='contrastlight' then return 'ContrastLight' end
    return Core.display_word(v)
end
function Core.VP.delta_duration(seconds)
    seconds=math.max(0,math.floor(tonumber(seconds) or 0)); if seconds<3600 then return ('%02d:%02d'):format(math.floor(seconds/60),seconds%60) end
    return Core.VP.duration_hms(seconds)
end


function Core.VP.short_zone_name()
    local info=windower.ffxi.get_info and windower.ffxi.get_info() or {}; local zr=res.zones and res.zones[tonumber(info.zone)] or nil
    local name=tostring((zr and (zr.en or zr.english or zr.name)) or 'Unknown')
    if Core.VP.ZONE_SHORT[name] then return Core.VP.ZONE_SHORT[name] end
    local swaps={{'^Southern ','S. '},{'^Northern ','N. '},{'^Eastern ','E. '},{'^Western ','W. '},{'^South ','S. '},{'^North ','N. '},{'^East ','E. '},{'^West ','W. '}}
    for _,r in ipairs(swaps) do local changed,n=name:gsub(r[1],r[2],1); if n>0 then return changed end end
    return name
end
function Core.VP.position_text()
    if not windower.ffxi.get_position then return nil end
    local ok,pos=pcall(windower.ffxi.get_position); if not ok or not pos then return nil end
    pos=tostring(pos); if pos:find('%?%-%?') then return nil end
    local grid=pos:match('([A-Z]+%-%d+)') or pos:match('([A-Z]+%-%d+)')
    if not grid or grid=='' then return nil end; return grid
end
function Core.VP.location_text()
    local z=Core.VP.short_zone_name(); local p=Core.VP.position_text(); return p and (z..' ('..p..')') or z
end
function Core.VP.duration_hms(seconds)
    seconds=math.max(0,math.floor(tonumber(seconds) or 0)); local h=math.floor(seconds/3600); local m=math.floor((seconds%3600)/60); local sec=seconds%60
    return ('%02d:%02d:%02d'):format(h,m,sec)
end
function Core.VP.table_for_view(source,actors,now,view)
    if not source then return hud_compact(nil,{},now) end
    if view=='ws' then return (display_enabled('ws') and enabled_filter('ws') and Core.VP.category_included('ws')) and hud_ws(source,actors,false) or format_parse_dynamic({'Player'},{},{'left'},{gap=1})
    elseif view=='ws-details' then return (display_enabled('ws') and enabled_filter('ws') and Core.VP.category_included('ws')) and hud_ws(source,actors,true) or format_parse_dynamic({'Player'},{},{'left'},{gap=1})
    elseif view=='magic' then return (display_enabled('magic') and enabled_filter('magic') and Core.VP.category_included('magic')) and hud_magic(source,actors,false) or format_parse_dynamic({'Player'},{},{'left'},{gap=1})
    elseif view=='magic-details' then return (display_enabled('magic') and enabled_filter('magic') and Core.VP.category_included('magic')) and hud_magic(source,actors,true) or format_parse_dynamic({'Player'},{},{'left'},{gap=1})
    elseif view=='defense' then return (display_enabled('defense') and Core.VP.category_included('defense')) and hud_defense(source,actors) or format_parse_dynamic({'Player'},{},{'left'},{gap=1})
    elseif view=='healing' then return (display_enabled('healing') and Core.VP.category_included('healing')) and hud_healing(source,actors,now) or format_parse_dynamic({'Player'},{},{'left'},{gap=1})
    elseif view=='healing-details' then return (display_enabled('healing') and Core.VP.category_included('healing')) and Core.VP.hud_healing_details(source,actors,now) or format_parse_dynamic({'Player'},{},{'left'},{gap=1})
    elseif view=='recovery' then local old_only=settings.max_only; settings.max_only={general=false,recovery=true}; local out=hud_max(source,actors,now); settings.max_only=old_only; return out
    elseif view=='recovery-details' then return (display_enabled('recovery') and Core.VP.category_included('recovery')) and Core.VP.hud_recovery_details(source,actors) or format_parse_dynamic({'Player'},{},{'left'},{gap=1})
    elseif view=='pet' then return (display_enabled('pet') and enabled_filter('pet') and Core.VP.category_included('pet')) and hud_pet(source,actors,now) or format_parse_dynamic({'Player'},{},{'left'},{gap=1})
    elseif view=='full' then
        local old_only=settings.max_only
        settings.max_only={general=true,melee=true,ws=true,sc=true,ranged=true}
        local p1=hud_max(source,actors,now)
        settings.max_only={magic=true,pet=true,healing=true,recovery=true,defense=true}
        local p2=hud_max(source,actors,now)
        settings.max_only=old_only
        local out={}
        for _,line in ipairs(p1 or {}) do out[#out+1]=line end
        out[#out+1]=''
        for _,line in ipairs(p2 or {}) do out[#out+1]=line end
        return out
    elseif view=='physical' then local old_only=settings.max_only; settings.max_only={general=true,melee=true,ws=true,sc=true}; local out=hud_max(source,actors,now); settings.max_only=old_only; return out
    elseif view=='ranged' then local old_only=settings.max_only; settings.max_only={general=true,ranged=true,ws=true,sc=true}; local out=hud_max(source,actors,now); settings.max_only=old_only; return out
    elseif view=='compact' then return hud_compact(source,actors,now)
    else return hud_overview(source,actors,now) end
end
-- Split one HUD line into a normal/base layer and a bold companion layer.
-- Both layers keep identical visible character positions and color-control
-- sequences. There is never a second full copy of the HUD text.
function Core.VP.bold_split_line(line,labels,full,tail_label)
    line=tostring(line or '')
    local plain=Core.visible_text(line)
    local mark={}
    if full then for i=1,#plain do mark[i]=true end end
    for _,label in ipairs(labels or {}) do
        local start=1
        while true do
            local a,b=plain:find(label,start,true); if not a then break end
            for i=a,b do mark[i]=true end
            start=b+1
        end
    end
    if tail_label then
        local a=plain:find(tail_label,1,true)
        if a then for i=a,#plain do mark[i]=true end end
    end
    local base,bold={},{}
    local i,visible=1,1
    while i<=#line do
        if line:sub(i,i+3)=='\\cs(' then
            local close=line:find(')',i+4,true)
            if close then local tok=line:sub(i,close); base[#base+1]=tok; bold[#bold+1]=tok; i=close+1
            else local ch=line:sub(i,i); base[#base+1]=ch; bold[#bold+1]=' '; i=i+1; visible=visible+1 end
        elseif line:sub(i,i+2)=='\\cr' then
            base[#base+1]='\\cr'; bold[#bold+1]='\\cr'; i=i+3
        else
            local ch=line:sub(i,i)
            if mark[visible] then base[#base+1]=' '; bold[#bold+1]=ch
            else base[#base+1]=ch; bold[#bold+1]=' ' end
            i=i+1; visible=visible+1
        end
    end
    return table.concat(base),table.concat(bold)
end

function Core.VP.sort_display_text()
    local target=tostring(settings.sort or 'dps')
    if target=='party' then return 'Party' end
    local kind,value=target:match('^(%a+)%:(.+)$')
    local label=value or target
    if kind=='action' then label=Core.VP.resolve_action_name(value) or Core.display_word(value)
    elseif kind=='category' then
        local cmap={ws='WS',sc='SC',mb='MB',magic_mb='Magic MB',magic_nonmb='Magic Non-MB',pet_sc='Pet SC',pet_mb='Pet MB'}
        label=cmap[value] or Core.display_word(tostring(value):gsub('_',' '))
    elseif kind=='field' then
        local fmap={
            ['general.avg']='DPS',['general.damage']='Damage',['general.share']='Tot Dmg%',['melee.acc']='Melee Acc',['melee.damage']='Melee',
            ['ws.damage']='WS Dmg',['ws.acc']='WS Acc',['ws.avg']='WS Avg',['ws.low']='WS Low',['ws.peak']='WS Peak',['sc.damage']='SC Dmg',
            ['ranged.damage']='Ranged Dmg',['ranged.acc']='R.Acc',['magic.damage']='Magic Dmg',['magic.mb.damage']='MB Dmg',['magic.mb.avg']='MB Avg',
            ['pet.damage']='Pet Dmg',['healing.cured']='Cured',['recovery.cleanse']='Cleanse',['recovery.dispel']='Dispel',['defense.taken']='Taken'
        }
        label=fmap[value] or Core.display_word(tostring(value):gsub('%.',' '))
    else
        local legacy={dps='DPS',damage='Damage',accuracy='Acc',racc='R.Acc',ws='WS',wsacc='WS Acc',wsavg='WS Avg',sc='SC',magic='Magic',pet='Pet',healing='Healing',cleanse='Cleanse',dispel='Dispel',taken='Taken'}
        label=legacy[target] or Core.display_word(target)
    end
    return tostring(label)..' '..((settings.sort_direction=='asc') and 'L-H' or 'H-L')
end

function Core.VP.compose_hud(source,scope,view,row_limit,now,label)
    now=now or Core.now(); local old_scope,old_view,old_rows=settings.scope,settings.view,settings.row_limit
    settings.scope=scope or old_scope; settings.view=view or old_view; settings.row_limit=row_limit==nil and old_rows or row_limit
    local ok,result,bold_result=pcall(function()
        local actors=display_actors(source); local elapsed=select(1,elapsed_active(source,now)); local table_lines=Core.VP.table_for_view(source,actors,now,settings.view) or {}
        local width=0; for _,line in ipairs(table_lines) do width=math.max(width,Core.visible_len(line)) end; width=math.max(width,settings.view=='compact' and 68 or 48)
        local base_lines,bold_lines={},{}
        local function add(line,labels,full,tail_label)
            local base,bold=Core.VP.bold_split_line(line,labels,full,tail_label)
            base_lines[#base_lines+1]=base; bold_lines[#bold_lines+1]=bold
        end
        local title=label and ('VanaParse '..label) or 'VanaParse'
        add(Core.VP.fit_plain(('%s | %s | Elapsed %s | Active %s'):format(title,Core.VP.location_text(),Core.VP.duration_hms(elapsed),Core.VP.active_display_text(source,now)),width),nil,true)
        local context=''; if split_view and scope~='allparties' then local sp=(split_view=='current') and active_split or find_split(tostring(split_view)); context=sp and ('/'..sp.name) or '/Split' end
        if settings.view=='compact' then
            add(Core.VP.fit_plain(('View: %s%s | Mode: %s | Filter: %s'):format(view_display_name(settings.view),context,Core.VP.scope_label(settings.scope),scope=='allparties' and 'Observed Encounter' or Core.VP.filter_display_text()),width),{'View:','Mode:','Filter:'})
        else
            add(Core.VP.fit_plain(('View: %s%s | Mode: %s | Filter: %s | Sort: %s | Report: %s'):format(view_display_name(settings.view),context,Core.VP.scope_label(settings.scope),scope=='allparties' and 'Observed Encounter' or Core.VP.filter_display_text(),Core.VP.sort_display_text(),Core.VP.report_destination_label()),width),{'View:','Mode:','Filter:','Sort:','Report:'})
        end
        if source and source.observer then
            add(Core.VP.fit_plain('Target: '..tostring(source.display_name or 'Observed Encounter'),width),{'Target:'})
        else
            local th=target_header(source,actors,width)
            if th then add(th,{'Target:','HP:'},false,'Incoming:') else add('') end
        end
        add('')
        for i,line in ipairs(table_lines) do
            local header=(i==1 or table_lines[i-1]=='')
            add(line,nil,header)
        end
        if settings.paused then add('PAUSED',nil,true) end
        return table.concat(base_lines,'\n'),table.concat(bold_lines,'\n')
    end)
    settings.scope,settings.view,settings.row_limit=old_scope,old_view,old_rows
    if not ok then error(result) end
    return result,bold_result
end

local function update_hud(force)
    local now=Core.now(); if Core.VP.transition_tick(now) or Core.VP.detect_micro_transition(now) then return end
    if not force and now-last_hud_update<0.20 then return end; last_hud_update=now
    if not current then start_from_engagement(now) end
    if current then
        local active=update_shared_clock(current,now); local live=encounter_has_live_enemy(current)
        if encounter_defeated(current) then finalize_encounter(now)
        elseif not live and not active and current.last_hostile and (now-current.last_hostile)>=settings.encounter_timeout then finalize_encounter(now) end
    end
    Core.VP.observer_cleanup(now)
    local function render_one(key,obj,source,scope,view,rows,label)
        if not obj then return end
        local ok,text,bold_text=pcall(Core.VP.compose_hud,source,scope,view,rows,now,label)
        if ok then
            obj:text(text)
            local bold=Core.VP.bold_huds and Core.VP.bold_huds[key]
            if bold then Core.VP.sync_bold_hud(key,obj); bold:text(bold_text or '') end
            local e=Core.VP.error_state['hud-'..key]; if e then e.count=0 end; return
        end
        on_error('hud-'..key,text)
        if key~='main' then
            local e=Core.VP.error_state['hud-'..key]
            if e and e.count>=3 then
                settings.secondary_huds[key].visible=false; obj:hide(); if Core.VP.bold_huds and Core.VP.bold_huds[key] then Core.VP.bold_huds[key]:hide() end; chat(167,Core.display_word(key)..' HUD disabled after repeated render errors. Main parser remains active.')
            end
        end
    end
    local main_source=selected_source(); render_one('main',hud,main_source,settings.scope,settings.view,settings.row_limit,nil)
    local acfg=settings.secondary_huds.all; if acfg and acfg.visible then
        local raw=split_view and session_source_for_split() or current_source(); local src=enemy_filtered_source(split_source(raw)); render_one('all',Core.VP.huds.all,src,'all',acfg.view,acfg.row_limit,'All')
    end
    local ocfg=settings.secondary_huds.allparties; if ocfg and ocfg.visible then
        render_one('allparties',Core.VP.huds.allparties,Core.VP.observer_selected_source(),'allparties',ocfg.view,ocfg.row_limit,'All Parties')
    end
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
    elseif destination=='t' or destination=='tell' then if tell_name and tell_name~='' then cmd='/t '..tell_name..' ' end end
    if cmd then report_queue[#report_queue+1]='input '..cmd..line; return true end
    return false
end

local function process_report_queue(now)
    now=now or Core.now(); if Core.VP.transition and Core.VP.transition.active then return end; if #report_queue==0 or now<report_next_at then return end
    local command=table.remove(report_queue,1); windower.send_command(command); report_next_at=now+(tonumber(settings.report_delay) or 1.05)
end

local Report={}
Report._scope_override=nil
Report._range_label=nil
Report.DESTINATIONS={
    p='party',party='party',a='alliance',alliance='alliance',
    l='linkshell',l1='linkshell',linkshell='linkshell',
    l2='linkshell2',linkshell2='linkshell2',
    t='tell',tell='tell',['local']='local',console='local',self='local',hud='local',
}
Report.PUBLIC_DESTINATIONS={say=true,s=true,yell=true,y=true,shout=true,sh=true,unity=true,assist=true,jp=true,en=true,eu=true}
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
    view='view',hud='view',full='full',dps='dps',damage='dps',dmg='dps',offense='dps',
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

Report.VIEW_SINGLE={
    compact='compact',dynamic='dynamic',full='full',physical='physical',ws='ws',['ws-details']='ws-details',ranged='ranged',magic='magic',['magic-details']='magic-details',pet='pet',healing='healing',['healing-details']='healing-details',recovery='recovery',['recovery-details']='recovery-details',defense='defense',
}
Report.VIEW_PHRASES={{'ws','details','ws-details'},{'weapon','skill','details','ws-details'},{'weaponskill','details','ws-details'},{'magic','details','magic-details'},{'healing','details','healing-details'},{'recovery','details','recovery-details'}}
Report.AMBIGUOUS_VIEWS={physical='physical',magic='magic',ranged='ranged',defense='defense',healing='healing',recovery='recovery',pet='pet',ws='ws',full='full'}
Report.METRIC_SINGLE={
    accuracy='accuracy',acc='accuracy',meleeacc='accuracy',['melee-acc']='accuracy',
    dps='dps',damage='damage',dmg='damage',totdmg='damage',['tot-dmg']='damage',
    percentage='share',percent='share',percentages='share',['%']='share',share='share',totdmgpercent='share',['tot-dmg%']='share',
    melee='melee',ranged='ranged',racc='racc',magic='magic',pet='pet',healing='healing',cured='healing',
    wsdamage='wsdamage',['ws-dmg']='wsdamage',wsavg='wsavg',wsaverage='wsavg',wsacc='wsacc',['ws-acc']='wsacc',wshm='wshm',['ws-hm']='wshm',
    sc='sc',skillchain='sc',mb='mb',recovery='recovery',cleanse='recovery',taken='taken',defense='taken',
}
Report.METRIC_PHRASES={
    {'total','damage','percent','share'},{'tot','dmg','%','share'},{'weapon','skill','average','wsavg'},{'weapon','skill','accuracy','wsacc'},
    {'weapon','skill','damage','wsdamage'},{'weapon','skill','hit/miss','wshm'},{'melee','accuracy','accuracy'},
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
    if Report._range_label then return Report._range_label end
    if split_view then local sp=(split_view=='current') and active_split or find_split(tostring(split_view)); return sp and ('Split '..sp.name) or 'Split' end
    if settings.period and settings.period~='session' then return Core.display_word(settings.period) end
    return 'Full Parse'
end
function Report.find_actor(source,name)
    if not source or not name or name=='' then return nil end
    local wanted=Core.lower(name); local exact=nil; local partial={}
    for _,a in ipairs(display_actors(source,true,false,Report._scope_override)) do
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
    local actors=display_actors(source,true,false,Report._scope_override); local limit=show_all and #actors or math.min(#actors,9)
    while #actors>limit do table.remove(actors) end; return actors
end
function Report.offense_values(a)
    local melee=enabled_filter('melee') and net(a.melee,a.dheal_melee) or 0
    local ranged=enabled_filter('ranged') and net(a.ranged,a.dheal_ranged) or 0
    local ws=enabled_filter('ws') and Core.VP.ws_net(a) or 0
    local sc=enabled_filter('sc') and net(a.skillchain,a.dheal_skillchain) or 0
    local magic=enabled_filter('magic') and (Core.VP.magic_net(a)) or 0
    local pet=enabled_filter('pet') and pet_net_damage(a) or 0
    return melee,ranged,ws,sc,magic,pet
end
function Report.report_denominator(source)
    local total=0; for _,a in ipairs(display_actors(source,true,false,Report._scope_override)) do total=total+combined_damage(a) end; return total
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
        report_emit(destination,tell_name,('WS Dmg %s | WS Dmg%% %.1f%% | WS H/M %s | WS Acc %s | WS Avg %s | SC# %s | SC Dmg %s | SC Dmg%% %.1f%%'):format(n(ws),denom~=0 and 100*ws/denom or 0,count_pair(Core.VP.ws_stats(a).hits,Core.VP.ws_stats(a).misses),pct(Core.VP.ws_stats(a).hits,Core.VP.ws_stats(a).attempts),dash(avg(Core.VP.ws_stats(a).mm),n),count_text(a.skillchain_count),n(sc),denom~=0 and 100*sc/denom or 0))
        if extra_mode then
            local extra={}
            if display_enabled('magic') and enabled_filter('magic') and magic~=0 then extra[#extra+1]='Magic '..n(magic) end
            if display_enabled('mb') and display_enabled('magic') and net(a.mb_damage,a.dheal_mb)~=0 then extra[#extra+1]='MB Dmg '..n(net(a.mb_damage,a.dheal_mb)) end
            if display_enabled('ranged') and ranged~=0 then extra[#extra+1]='Ranged '..n(ranged)..' | RAcc '..accuracy_text(a,true) end
            if display_enabled('pet') and pet~=0 then extra[#extra+1]='Pet '..n(pet) end
            if extra_mode=='full' and display_enabled('healing') and Core.VP.healing_stats(a).healing>0 then extra[#extra+1]='Cured '..n(Core.VP.healing_stats(a).healing) end
            if extra_mode=='full' and display_enabled('recovery') then local rs=Core.VP.recovery_stats(a); if rs.cleanse>0 or rs.dispel>0 then extra[#extra+1]=('Recovery %d | Dispel %d'):format(rs.cleanse,rs.dispel) end end
            if extra_mode=='full' and display_enabled('defense') and (tonumber(a.taken) or 0)>0 then extra[#extra+1]='Taken '..n(a.taken) end
            if #extra>0 then report_emit(destination,tell_name,table.concat(extra,' | ')) end
        end
        t.dmg=t.dmg+dmg; t.melee=t.melee+melee; t.hits=t.hits+(tonumber(a.melee_hits) or 0); t.att=t.att+(tonumber(a.melee_attempts) or 0); t.ws=t.ws+ws; t.wsh=t.wsh+(tonumber(Core.VP.ws_stats(a).hits) or 0); t.wsm=t.wsm+(tonumber(Core.VP.ws_stats(a).misses) or 0); t.wsa=t.wsa+(tonumber(Core.VP.ws_stats(a).attempts) or 0); t.sc=t.sc+sc; t.scc=t.scc+(tonumber(a.skillchain_count) or 0)
    end
    local _,active=elapsed_active(source,Core.now())
    report_emit(destination,tell_name,('TOTAL | Dmg %s | DPS %s | Acc %s | WS %s | WS Acc %s | WS Avg %s | SC# %d | SC %s'):format(n(t.dmg),active>0 and n(t.dmg/active) or '-',accuracy_pair_text(t.att,t.hits),n(t.ws),accuracy_pair_text(t.wsa,t.wsh),t.wsh>0 and n(t.ws/t.wsh) or '-',t.scc,n(t.sc)))
end
function Report.ws(destination,tell_name,actors,source,detailed)
    local denom=Report.report_denominator(source); local total_damage,total_hits,total_misses,total_attempts=0,0,0,0
    for i,a in ipairs(actors) do
        local ws=enabled_filter('ws') and Core.VP.ws_net(a) or 0
        local wst=Core.VP.ws_stats(a); local attempts=tonumber(wst.attempts) or 0; local hits=tonumber(wst.hits) or 0; local misses=tonumber(wst.misses) or 0
        if ws~=0 or attempts>0 then
            report_emit(destination,tell_name,('#%d %s | WS Dmg %s | WS Dmg%% %.1f%% | H/M %s | Acc %s | Avg %s'):format(i,a.name,n(ws),denom~=0 and 100*ws/denom or 0,count_pair(hits,misses),pct(hits,attempts),dash(avg(Core.VP.ws_stats(a).mm),n)))
            if detailed then
                local list={}; for name,w in pairs(a.ws or {}) do if (tonumber(w.attempts) or 0)>0 and not Core.VP.action_hidden(name) and not Core.VP.action_excluded(name) then list[#list+1]={name=name,w=w} end end
                table.sort(list,function(x,y) return (tonumber(x.w.damage) or 0)>(tonumber(y.w.damage) or 0) end)
                for _,e in ipairs(list) do local w=e.w; report_emit(destination,tell_name,('  %s | Use %s | Dmg %s | Avg %s | H/M %s | Acc %s'):format(e.name,count_text(w.attempts),n(w.damage or 0),dash(avg(w.mm),n),count_pair(w.hits,w.misses),pct(w.hits,w.attempts))) end
            end
        end
        total_damage=total_damage+ws; total_hits=total_hits+hits; total_misses=total_misses+misses; total_attempts=total_attempts+attempts
    end
    report_emit(destination,tell_name,('TOTAL WS | Dmg %s | Dmg%% %.1f%% | H/M %s | Acc %s | Avg %s'):format(n(total_damage),denom~=0 and 100*total_damage/denom or 0,count_pair(total_hits,total_misses),accuracy_pair_text(total_attempts,total_hits),total_hits>0 and n(total_damage/total_hits) or '-'))
end
function Report.sc(destination,tell_name,actors,source)
    local denom=Report.report_denominator(source); local total_damage,total_count=0,0
    for i,a in ipairs(actors) do
        local damage=enabled_filter('sc') and net(a.skillchain,a.dheal_skillchain) or 0; local count=tonumber(a.skillchain_count) or 0
        if damage~=0 or count>0 then report_emit(destination,tell_name,('#%d %s | SC# %s | SC Dmg %s | SC Dmg%% %.1f%% | Avg %s'):format(i,a.name,count_text(count),n(damage),denom~=0 and 100*damage/denom or 0,count>0 and n(damage/count) or '-')) end
        total_damage=total_damage+damage; total_count=total_count+count
    end
    report_emit(destination,tell_name,('TOTAL SC | SC# %d | Dmg %s | Dmg%% %.1f%% | Avg %s'):format(total_count,n(total_damage),denom~=0 and 100*total_damage/denom or 0,total_count>0 and n(total_damage/total_count) or '-'))
end

function Report.magic(destination,tell_name,actors,source,detailed)
    local total=0
    for i,a in ipairs(actors) do
        local _,_,_,_,magic=Report.offense_values(a); total=total+magic
        local ms=Core.VP.magic_stats(a); if magic~=0 or ms.casts>0 then
            report_emit(destination,tell_name,('#%d %s | Magic %s | Cast %d | Land/Res %d/%d | MB Cast %d | MB Dmg %s | Avg %s'):format(i,a.name,n(magic),ms.casts,ms.lands,ms.resists,ms.mb_count,n(ms.mb_damage or 0),dash(avg(a.magic_mm),n)))
            if detailed then
                local list={}; for name,sp in pairs(a.spells or {}) do if (tonumber(sp.casts) or 0)>0 and not Core.VP.action_hidden(name) and not Core.VP.action_excluded(name) then list[#list+1]={name=name,sp=sp} end end
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
        local ms=Core.VP.magic_stats(a)
        if ms.mb_count>0 or ms.mb_damage>0 then
            report_emit(destination,tell_name,('%s | MB Hits %d | MB Dmg %s | Avg %s'):format(a.name,ms.mb_count,n(ms.mb_damage),dash(avg(ms.mb_mm),n)))
            local list={}; for name,sp in pairs(a.spells or {}) do if (tonumber(sp.mb_hits) or 0)>0 and not Core.VP.action_hidden(name) and not Core.VP.action_excluded(name) then list[#list+1]={name=name,sp=sp} end end
            table.sort(list,function(x,y) return (tonumber(x.sp.mb_damage) or 0)>(tonumber(y.sp.mb_damage) or 0) end)
            for _,e in ipairs(list) do local sp=e.sp; local meta=spell_meta_text(sp); report_emit(destination,tell_name,('  %s (%d) Avg %s | Dmg %s%s'):format(e.name,tonumber(sp.mb_hits) or 0,dash(avg(sp.mb_mm),n),n(sp.mb_damage or 0),meta and (' | '..meta) or '')) end
            total_hits=total_hits+ms.mb_count; total_damage=total_damage+ms.mb_damage
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
    for i,a in ipairs(actors) do local hs=Core.VP.healing_stats(a); if hs.healing>0 or (tonumber(a.received) or 0)>0 then report_emit(destination,tell_name,('#%d %s | Cured %s | Cure Rcvd %s | Self %s | Cure# %d | Avg %s'):format(i,a.name,n(hs.healing),n(a.received),n(a.self_healing),hs.cures,dash(avg(a.cure_mm),n))) end; cured=cured+hs.healing; received=received+(tonumber(a.received) or 0) end
    report_emit(destination,tell_name,('TOTAL Healing | Cured %s | Cure Rcvd %s'):format(n(cured),n(received)))
end
function Report.recovery(destination,tell_name,actors,source)
    local cleanses,dispels=0,0
    for i,a in ipairs(actors) do
        local rs=Core.VP.recovery_stats(a)
        if rs.cleanse>0 or rs.dispel>0 or rs.aspir>0 then
            local actions={}; for name,count in pairs(a.cleanse_actions or {}) do if not Core.VP.action_hidden(name) and not Core.VP.action_excluded(name) then actions[#actions+1]=name..' '..tostring(count) end end; for name,count in pairs(a.dispel_actions or {}) do if not Core.VP.action_hidden(name) and not Core.VP.action_excluded(name) then actions[#actions+1]=name..' '..tostring(count) end end; table.sort(actions)
            report_emit(destination,tell_name,('#%d %s | Recovery %d | Dispel %d | Aspir %s%s'):format(i,a.name,rs.cleanse,rs.dispel,n(rs.aspir),#actions>0 and (' | '..table.concat(actions,', ')) or ''))
        end
        cleanses=cleanses+rs.cleanse; dispels=dispels+rs.dispel
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
    if report_significant(ws,dmg,exhaustive) or (tonumber(Core.VP.ws_stats(a).attempts) or 0)>0 then report_emit(destination,tell_name,('WS | Dmg %s | H/M %s | Acc %s | Avg %s | SC %s/%s'):format(n(ws),count_pair(Core.VP.ws_stats(a).hits,Core.VP.ws_stats(a).misses),pct(Core.VP.ws_stats(a).hits,Core.VP.ws_stats(a).attempts),dash(avg(Core.VP.ws_stats(a).mm),n),count_text(a.skillchain_count),n(sc))) end
    if report_significant(ranged,dmg,exhaustive) then report_emit(destination,tell_name,('Ranged | Dmg %s | Acc %s | Avg %s'):format(n(ranged),accuracy_text(a,true),dash(avg(a.ranged_mm),n))) end
    if report_significant(magic,dmg,exhaustive) or (tonumber(a.magic_casts) or 0)>0 then report_emit(destination,tell_name,('Magic | Dmg %s | Cast %d | MB %d/%s | Avg %s'):format(n(magic),tonumber(a.magic_casts) or 0,tonumber(a.mb_count) or 0,n(a.mb_damage or 0),dash(avg(a.magic_mm),n))) end
    if report_significant(pet,dmg,exhaustive) then report_emit(destination,tell_name,('Pet | Dmg %s | Melee %s | Ranged %s | Magic %s | Heal %s'):format(n(pet),n(net(a.pet.melee,a.pet.dheal_melee)),n(net(a.pet.ranged,a.pet.dheal_ranged)),n((tonumber(a.pet.magic) or 0)-(tonumber(a.pet.dheal_magic) or 0)-(tonumber(a.pet.dheal_enspell) or 0)),n(a.pet.healing or 0))) end
    if (tonumber(a.healing) or 0)>0 then report_emit(destination,tell_name,('Healing | Cured %s | Cure Rcvd %s | Self %s | Cure# %d | Avg %s'):format(n(a.healing),n(a.received),n(a.self_healing),tonumber(a.cures) or 0,dash(avg(a.cure_mm),n))) end
    if (tonumber(a.cleanses) or 0)>0 or (tonumber(a.dispels) or 0)>0 then report_emit(destination,tell_name,('Recovery | Status %d | Dispel %d'):format(tonumber(a.cleanses) or 0,tonumber(a.dispels) or 0)) end
    if (tonumber(a.taken) or 0)>0 or (tonumber(a.evades) or 0)>0 or (tonumber(a.parries) or 0)>0 or (tonumber(a.blocks) or 0)>0 then report_emit(destination,tell_name,('Defense | Taken %s | AvgHit %s | Evd %d | Par %d | Blk %d | KO %d'):format(n(a.taken),dash(avg(a.taken_mm),n),tonumber(a.evades) or 0,tonumber(a.parries) or 0,tonumber(a.blocks) or 0,tonumber(a.deaths) or 0)) end
    if exhaustive then
        local wslist={}; for name,w in pairs(a.ws or {}) do if (tonumber(w.attempts) or 0)>0 then wslist[#wslist+1]={name=name,w=w} end end; table.sort(wslist,function(x,y) return (tonumber(x.w.damage) or 0)>(tonumber(y.w.damage) or 0) end)
        for _,e in ipairs(wslist) do report_emit(destination,tell_name,('  WS %s | %d use | Dmg %s | Avg %s | Acc %s'):format(e.name,tonumber(e.w.attempts) or 0,n(e.w.damage or 0),dash(avg(e.w.mm),n),pct(e.w.hits,e.w.attempts))) end
        local splist={}; for name,sp in pairs(a.spells or {}) do if (tonumber(sp.casts) or 0)>0 and not Core.VP.action_hidden(name) and not Core.VP.action_excluded(name) then splist[#splist+1]={name=name,sp=sp} end end; table.sort(splist,function(x,y) return (tonumber(x.sp.damage) or 0)>(tonumber(y.sp.damage) or 0) end)
        for _,e in ipairs(splist) do local sp=e.sp; local meta=spell_meta_text(sp); report_emit(destination,tell_name,('  Spell %s | Cast %d | Dmg %s | Avg %s | MB %d/%s%s'):format(e.name,tonumber(sp.casts) or 0,n(sp.damage or 0),dash(avg(sp.damage_mm),n),tonumber(sp.mb_hits) or 0,n(sp.mb_damage or 0),meta and (' | '..meta) or '')) end
        local acts={}; for name,count in pairs(a.cleanse_actions or {}) do if not Core.VP.action_hidden(name) and not Core.VP.action_excluded(name) then acts[#acts+1]='Recovery '..name..' '..count end end; for name,count in pairs(a.dispel_actions or {}) do if not Core.VP.action_hidden(name) and not Core.VP.action_excluded(name) then acts[#acts+1]='Dispel '..name..' '..count end end; table.sort(acts); for _,line in ipairs(acts) do report_emit(destination,tell_name,'  '..line) end
    end
end
function Core.VP.report_range_source(req)
    local raw=session_source_for_split(); if not raw then return nil end
    if not req or not req.split_start then return enemy_filtered_source(raw) end
    local a=find_split(tostring(req.split_start)); if not a then return nil end
    local start_snap=a.baseline; local end_snap=nil
    if req.split_end then local b=find_split(tostring(req.split_end)); end_snap=b and b.baseline or nil; if not end_snap then return nil end
    else end_snap=snapshot_source(raw,Core.now()) end
    return delta_source_from_snapshots(end_snap,start_snap)
end
function Core.VP.filter_source_by_terms(source,terms)
    if not source or not terms or #terms==0 then return source end
    local out={started=source.started,last=source.last,ended=source.ended,active_committed=source.active_committed,actors={},enemy_names={}}
    for key,a in pairs(source.actors or {}) do
        local d=new_actor(a.id,a.name); d.actor_type=a.actor_type; d.session_scope=a.session_scope; d.session_order=a.session_order; d.weapon_class=a.weapon_class; d.main_job=a.main_job; d.sub_job=a.sub_job
        local used=false
        if type(a.enemy_ids)=='table' and next(a.enemy_ids)~=nil then for _,b in pairs(a.enemy_ids) do if enemy_name_matches(b.name,terms) then add_bucket_to_filtered(d,b); used=true end end
        else for name,b in pairs(a.enemy or {}) do if enemy_name_matches(name,terms) then add_bucket_to_filtered(d,b); used=true end end end
        if used then out.actors[key]=d end
    end
    return out
end
function Core.VP.split_token_value(token)
    local a,b=tostring(token or ''):match('^(%d+)%-(%d+)$'); if a then return tonumber(a),tonumber(b) end
    local n=tonumber(token); if n then return n,nil end; return nil,nil
end

function Report.parse_args(args)
    local tokens={}; for i=2,#args do if Core.lower(args[i])~='report' and Core.lower(args[i])~='rep' then tokens[#tokens+1]=args[i] end end
    local req={destination=settings.report_destination or 'party',tell_name=settings.report_tell~='' and settings.report_tell or nil,scope=nil,view_name=nil,metric=nil,show_all=false,exhaustive=false,split_start=nil,split_end=nil,scope_override=nil,subject=nil}
    -- Resolve multiword metrics first so they cannot be mistaken for a player/enemy name.
    local consumed={}
    for _,phrase in ipairs(Report.METRIC_PHRASES) do
        local words=#phrase-1
        for i=1,#tokens-words+1 do
            local ok=true; for j=1,words do if Core.lower(tokens[i+j-1])~=phrase[j] then ok=false break end end
            if ok then req.metric=phrase[#phrase]; for j=0,words-1 do consumed[i+j]=true end; break end
        end
        if req.metric then break end
    end
    local clean_tokens={}; for i,t in ipairs(tokens) do if not consumed[i] then clean_tokens[#clean_tokens+1]=t end end; tokens=clean_tokens
    -- Resolve multiword View names before single-token selectors.
    for _,phrase in ipairs(Report.VIEW_PHRASES or {}) do
        local words=#phrase-1
        for i=1,#tokens-words+1 do
            local ok=true; for j=1,words do if Core.lower(tokens[i+j-1])~=phrase[j] then ok=false break end end
            if ok then req.view_name=phrase[#phrase]; for j=0,words-1 do tokens[i+j]=false end; break end
        end
        if req.view_name then break end
    end
    -- A View token is authoritative. Metrics can subsequently narrow it.
    if not req.view_name then for i,t in ipairs(tokens) do if t then local low=Core.lower(t); if Report.VIEW_SINGLE[low] then req.view_name=Report.VIEW_SINGLE[low]; tokens[i]=false; break end end end end
    if not req.metric then
        for _,t in ipairs(tokens) do if t and Report.METRIC_SINGLE[Core.lower(t)] and not Report.SCOPE_SINGLE[Core.lower(t)] then req.metric=Report.METRIC_SINGLE[Core.lower(t)]; break end end
    end
    -- Accuracy, WS Avg and similarly metric-only words are never report categories.
    for i,t in ipairs(tokens) do if t then local low=Core.lower(t); local m=Report.METRIC_SINGLE[low]; if m and (low=='accuracy' or low=='acc' or low=='meleeacc' or low=='racc' or low=='wsavg' or low=='wsaverage' or low=='wsacc' or low=='wshm' or low=='totdmg' or low=='tot-dmg' or low=='share') then req.metric=req.metric or m; tokens[i]=false end end end
    if req.metric and not req.view_name then
        for i,t in ipairs(tokens) do if t then local v=Report.AMBIGUOUS_VIEWS[Core.lower(t)]; if v then req.view_name=v; tokens[i]=false; break end end end
    end
    local compacted={}; for _,t in ipairs(tokens) do if t then compacted[#compacted+1]=t end end; tokens=compacted
    local leftovers={}; local i=1
    while i<=#tokens do
        local low=Core.lower(tokens[i] or '')
        if low=='to' or low=='send' or low=='destination' or low=='channel' then
            local d=Core.lower(tokens[i+1] or ''); if Report.PUBLIC_DESTINATIONS[d] then return nil,'Public report channels are not supported. Allowed: HUD, Self, Tell, Party, Alliance, Linkshell, Linkshell2.' end; if not Report.DESTINATIONS[d] then return nil,'Unknown report destination.' end
            req.destination=Report.DESTINATIONS[d]; i=i+2; if req.destination=='tell' then req.tell_name=tokens[i]; if not req.tell_name then return nil,'Tell requires a player name.' end; i=i+1 end
        elseif low=='scope' or low=='mode' or low=='actors' or low=='from' then
            local v=Core.lower(tokens[i+1] or ''):gsub('%s+',''); local consume=2
            if v=='all' and Core.lower(tokens[i+2] or '')=='parties' then v='allparties'; consume=3 elseif v=='allparty' or v=='allpartys' then v='allparties' end
            if v=='self' or v=='local' or v=='party' or v=='alliance' or v=='all' or v=='allparties' then req.scope_override=v; i=i+consume else return nil,'Scope must be self, local, party, alliance, all, or allparties.' end
        elseif low=='split' or low=='splits' then
            local a,b=Core.VP.split_token_value(tokens[i+1]); if not a then return nil,'Split report requires a split number or range such as 1 or 1-2.' end; req.split_start,req.split_end=a,b; i=i+2
        elseif Report.PUBLIC_DESTINATIONS[low] then
            return nil,'Public report channels are not supported. Allowed: HUD, Self, Tell, Party, Alliance, Linkshell, Linkshell2.'
        elseif Report.DESTINATIONS[low] and low~='self' and low~='local' and low~='hud' then
            req.destination=Report.DESTINATIONS[low]; i=i+1; if req.destination=='tell' then req.tell_name=tokens[i]; if not req.tell_name then return nil,'Tell requires a player name.' end; i=i+1 end
        elseif low=='self' or low=='local' or low=='hud' then
            req.destination='local'; i=i+1
        elseif low=='all' then
            -- "report all" means every actor and every metric in the selected/current View.
            req.show_all=true; req.scope=req.scope or 'view'; req.view_name=req.view_name or settings.view; i=i+1
        elseif low=='view' then req.scope='view'; req.view_name=req.view_name or settings.view; req.show_all=true; i=i+1
        else
            local matched=false
            for _,p in ipairs(Report.SCOPE_PHRASES) do
                local count=#p-1; local ok=true; if i+count-1>#tokens then ok=false end
                if ok then for j=1,count do if Core.lower(tokens[i+j-1])~=p[j] then ok=false break end end end
                if ok then req.scope=p[#p]; i=i+count; matched=true; break end
            end
            if not matched and Report.SCOPE_SINGLE[low] then req.scope=Report.SCOPE_SINGLE[low]; i=i+1; matched=true end
            if not matched and Report.METRIC_SINGLE[low] then req.metric=req.metric or Report.METRIC_SINGLE[low]; i=i+1; matched=true end
            if not matched then leftovers[#leftovers+1]=tokens[i]; i=i+1 end
        end
    end
    if req.view_name then req.scope='view'; req.show_all=true end
    if req.metric then req.scope='view'; req.view_name=req.view_name or settings.view; req.show_all=true end
    req.scope=req.scope or settings.report_content or 'view'; if req.scope=='view' then req.view_name=req.view_name or settings.view end
    req.subject=#leftovers>0 and table.concat(leftovers,' ') or nil
    if req.scope=='performance' and req.show_all then req.exhaustive=true; req.show_all=false end
    return req,nil
end

function Report.view(destination,tell_name,source,view_name,actors,actor_only)
    view_name=view_name or settings.view
    actors=actors or display_actors(source,true,false,Report._scope_override)
    local old_view=settings.view; settings.view=view_name; Core.VP.report_render_exact=true; Core.VP.report_scope_total_override=Report.report_denominator(source)
    local ok,lines=pcall(Core.VP.table_for_view,source,actors,Core.now(),view_name)
    Core.VP.report_render_exact=false; Core.VP.report_scope_total_override=nil; settings.view=old_view
    if not ok then report_emit(destination,tell_name,'View report failed safely: '..tostring(lines)); return end
    report_emit(destination,tell_name,('VP View | %s | Mode %s'):format(view_display_name(view_name),Core.VP.scope_label(Report._scope_override or settings.scope)))
    for _,line in ipairs(lines or {}) do local plain=plain_text(line); if not (actor_only and plain:find('TOTAL',1,true)) then report_emit(destination,tell_name,plain) end end
end
function Report.metric_label(metric)
    return ({accuracy='Acc',dps='DPS',damage='Tot Dmg',share='Tot Dmg%',melee='Melee',ranged='Ranged',racc='RAcc',magic='Magic',pet='Pet',healing='Healing',wsdamage='WS Dmg',wsavg='WS Avg',wsacc='WS Acc',wshm='WS H/M',sc='SC Dmg',mb='MB Dmg',recovery='Recovery',taken='Taken'})[metric] or Core.display_word(metric)
end
function Report.metric_value(metric,a,source,total)
    if metric=='accuracy' then return accuracy_text(a,false)
    elseif metric=='dps' then return dash(combined_dps(a,source,Core.now()),n)
    elseif metric=='damage' then return n(combined_damage(a))
    elseif metric=='share' then return total~=0 and ('%.1f%%'):format(100*combined_damage(a)/total) or '0.0%'
    elseif metric=='melee' then return n(net(a.melee,a.dheal_melee))
    elseif metric=='ranged' then return n(net(a.ranged,a.dheal_ranged))
    elseif metric=='racc' then return accuracy_text(a,true)
    elseif metric=='magic' then return n(Core.VP.magic_net(a))
    elseif metric=='pet' then return n(pet_net_damage(a))
    elseif metric=='healing' then return n(Core.VP.healing_stats(a).healing)
    elseif metric=='wsdamage' then return n(Core.VP.ws_net(a))
    elseif metric=='wsavg' then return dash(avg(Core.VP.ws_stats(a).mm),n)
    elseif metric=='wsacc' then return accuracy_pair_text(Core.VP.ws_stats(a).attempts,Core.VP.ws_stats(a).hits)
    elseif metric=='wshm' then return count_pair(Core.VP.ws_stats(a).hits,Core.VP.ws_stats(a).misses)
    elseif metric=='sc' then return n(net(a.skillchain,a.dheal_skillchain))
    elseif metric=='mb' then return n(net(a.mb_damage,a.dheal_mb))
    elseif metric=='recovery' then local rs=Core.VP.recovery_stats(a); return tostring((tonumber(rs.cleanse) or 0)+(tonumber(rs.dispel) or 0))
    elseif metric=='taken' then return n(tonumber(a.taken) or 0) end
    return '-'
end
function Report.metric(destination,tell_name,metric,view_name,actors,source)
    local total=Report.report_denominator(source); report_emit(destination,tell_name,('VP %s | %s | Mode %s'):format(Report.metric_label(metric),view_display_name(view_name or settings.view),Core.VP.scope_label(Report._scope_override or settings.scope)))
    for _,a in ipairs(actors or {}) do report_emit(destination,tell_name,('#%d %s | %s %s'):format(tonumber(a._vp_rank) or 0,a.name or 'Unknown',Report.metric_label(metric),Report.metric_value(metric,a,source,total))) end
end

function Report.send(args)
    local req,err=Report.parse_args(args); if err then chat(167,err); return end
    Report._scope_override=req.scope_override; Report._range_label=nil
    local source
    if req.split_start then
        source=Core.VP.report_range_source(req); if not source then chat(167,'Requested split range was not found.'); Report._scope_override=nil; return end
        Report._range_label='Split '..tostring(req.split_start)..(req.split_end and ('-'..tostring(req.split_end)) or '-End')
    else source=selected_source() end
    if not source then chat(167,'No report data available.'); Report._scope_override=nil; Report._range_label=nil; return end
    local actor_name=nil
    if req.subject then
        local a=Report.find_actor(source,req.subject)
        if a then actor_name=a.name else source=Core.VP.filter_source_by_terms(source,{req.subject}) end
    end
    local actors=Report.report_actors(source,(req.show_all or req.scope=='view' or req.metric~=nil),actor_name)
    if #actors==0 then chat(167,req.subject and ('No matching report data: '..req.subject) or 'No actors to report.'); Report._scope_override=nil; Report._range_label=nil; return end
    if req.scope=='view' then
        if req.metric then Report.metric(req.destination,req.tell_name,req.metric,req.view_name,actors,source) else Report.view(req.destination,req.tell_name,source,req.view_name,actors,actor_name~=nil) end
        if req.destination~='local' then chat(207,('Queued %s report to %s%s (%d actor%s, %.2fs delay).'):format(req.metric and Report.metric_label(req.metric) or view_display_name(req.view_name or settings.view),req.destination,req.tell_name and (' '..req.tell_name) or '',#actors,#actors==1 and '' or 's',tonumber(settings.report_delay) or 1.05)) end
        Report._scope_override=nil; Report._range_label=nil; return
    end
    Report.header(req.destination,req.tell_name,req.scope,source,#actors,actor_name)
    if req.scope=='percent' then Report.percent(req.destination,req.tell_name,actors,source)
    elseif req.scope=='full' then Report.physical(req.destination,req.tell_name,actors,source,'full')
    elseif req.scope=='dps' then Report.physical(req.destination,req.tell_name,actors,source,'dps')
    elseif req.scope=='physical' then Report.physical(req.destination,req.tell_name,actors,source,false)
    elseif req.scope=='ws' then Report.ws(req.destination,req.tell_name,actors,source,actor_name~=nil)
    elseif req.scope=='sc' then Report.sc(req.destination,req.tell_name,actors,source)
    elseif req.scope=='magic' then Report.magic(req.destination,req.tell_name,actors,source,actor_name~=nil)
    elseif req.scope=='mb' then Report.mb(req.destination,req.tell_name,actors,source)
    elseif req.scope=='ranged' then Report.ranged(req.destination,req.tell_name,actors,source)
    elseif req.scope=='healing' then Report.healing(req.destination,req.tell_name,actors,source)
    elseif req.scope=='recovery' then Report.recovery(req.destination,req.tell_name,actors,source)
    elseif req.scope=='defense' then Report.defense(req.destination,req.tell_name,actors,source)
    elseif req.scope=='pet' or req.scope=='pet_physical' or req.scope=='pet_magic' or req.scope=='pet_ranged' or req.scope=='pet_healing' then Report.pet(req.destination,req.tell_name,actors,source,req.scope)
    elseif req.scope=='performance' then for _,a in ipairs(actors) do Report.performance(req.destination,req.tell_name,a,source,req.exhaustive) end
    else Report.physical(req.destination,req.tell_name,actors,source,true) end
    if req.destination~='local' then chat(207,('Queued %s report to %s%s (%d actor%s, %.2fs delay).'):format(req.scope,req.destination,req.tell_name and (' '..req.tell_name) or '',#actors,#actors==1 and '' or 's',tonumber(settings.report_delay) or 1.05)) end
    Report._scope_override=nil; Report._range_label=nil
end

local function set_column(option,value)
    settings.columns=settings.columns or {}
    if option=='ranged' then settings.columns.ranged=value
    elseif option=='pet' then settings.columns.pet=value
    elseif option=='healing' then settings.columns.healing=value
    elseif option=='crits' then settings.columns.crits=value==true
    elseif option=='pet_types' then settings.columns.pet_types=value==true
    elseif option=='wsavg' or option=='ws_avg' then settings.columns.ws_avg=value~=false end
end

local FILTER_ALIASES={
    melee='melee',ranged='ranged',range='ranged',ws='ws',sc='sc',skillchain='sc',magic='magic',other='other',pet='pet',
    petmelee='pet_melee',['pet-melee']='pet_melee',pmelee='pet_melee',petranged='pet_ranged',['pet-ranged']='pet_ranged',pranged='pet_ranged',
    petphysical='pet_physical',['pet-physical']='pet_physical',pphys='pet_physical',petmagic='pet_magic',['pet-magic']='pet_magic',pmagic='pet_magic',
    petsc='pet_sc',['pet-sc']='pet_sc',psc='pet_sc',
}

local function set_view(value)
    value=Core.lower(value or ''):gsub('^%s+',''):gsub('%s+$',''):gsub('%s+',' ')
    local aliases={
        compact='compact',dynamic='dynamic',full='full',physical='physical',melee='physical',
        ws='ws',weaponskill='ws',['weapon skill']='ws',wsdetails='ws-details',wsdetail='ws-details',['ws details']='ws-details',['ws detail']='ws-details',weaponskilldetails='ws-details',weaponskilldetail='ws-details',['weaponskill details']='ws-details',['weaponskill detail']='ws-details',['weapon skill details']='ws-details',['weapon skill detail']='ws-details',
        ranged='ranged',range='ranged',magic='magic',magicdetails='magic-details',magicdetail='magic-details',['magic details']='magic-details',['magic detail']='magic-details',pet='pet',
        healing='healing',cure='healing',healingdetails='healing-details',healingdetail='healing-details',['healing details']='healing-details',['healing detail']='healing-details',
        recovery='recovery',recoverydetails='recovery-details',recoverydetail='recovery-details',['recovery details']='recovery-details',['recovery detail']='recovery-details',defense='defense'
    }
    if aliases[value] then settings.view=aliases[value]; return true end; return false
end
local function set_scope(value)
    value=Core.lower(value):gsub('%s+',''); if value=='allparty' or value=='allpartys' then value='allparties' end; if value=='self' or value=='local' or value=='party' or value=='alliance' or value=='all' or value=='allparties' or value=='custom' then settings.scope=value; return true end; return false
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
    if value=='' or token=='list' or token=='status' then chat(207,Core.VP.filter_status_text()); return end
    if undo and (token=='all' or token=='clear' or token=='reset') then settings.enemy_filter_text=''; settings.enemy_filter_ids=''; Core.VP.all_damage_filters(true); chat(207,'All filters cleared.'); return end
    if not undo and (token=='all' or token=='clear' or token=='reset') then settings.enemy_filter_text=''; settings.enemy_filter_ids=''; Core.VP.all_damage_filters(true); chat(207,'All filters cleared.'); return end
    local canonical=FILTER_ALIASES[token] or FILTER_ALIASES[token:gsub('%s+','')]
    if not canonical then
        local cat=normalize_category(value)
        canonical=FILTER_ALIASES[cat] or FILTER_ALIASES[cat:gsub('_','')]
        if cat=='physical' then canonical='melee' elseif cat=='pet_physical' then canonical='pet_physical' elseif cat=='pet_magic' then canonical='pet_magic' elseif cat=='pet_ranged' then canonical='pet_ranged' end
    end
    if canonical or normalize_category(value)=='physical' then
        local cat=normalize_category(value)
        if undo then Core.VP.all_damage_filters(true); chat(207,'Damage filter removed: '..Core.display_word(cat=='physical' and 'physical' or canonical))
        else
            Core.VP.all_damage_filters(false)
            if cat=='physical' then settings.filters.melee=true; settings.filters.ws=true; settings.filters.sc=true
            else settings.filters[canonical]=true; if canonical:find('^pet_') then settings.filters.pet=true end end
            chat(207,'Filtering damage: '..Core.display_word(cat=='physical' and 'physical' or canonical))
        end
        return
    end
    if token=='current' or token=='target' then
        if undo then settings.enemy_filter_ids=''; chat(207,'Current-target filter removed.') else add_current_target_filter() end
        return
    end
    if undo then
        if Core.VP.remove_enemy_filter_text(value) then chat(207,'Enemy filter removed: '..value) else chat(167,'Enemy filter not found: '..value) end
    else Core.VP.add_enemy_filter_text(value); chat(207,'Enemy filter added: '..value) end
end

Core.VP.menu_colors={base=160,green=204,blue=207}
function Core.VP.menu_piece(text,color)
    return string.color(Core.humanize_command_text(tostring(text or '')),color or Core.VP.menu_colors.base,Core.VP.menu_colors.base)
end
function Core.VP.menu_print(parts)
    local out=Core.VP.menu_piece('[VanaParse] ',Core.VP.menu_colors.green)
    for _,part in ipairs(parts or {}) do
        if type(part)=='table' then out=out..Core.VP.menu_piece(part[1],part[2])
        else out=out..Core.VP.menu_piece(part,Core.VP.menu_colors.base) end
    end
    windower.add_to_chat(Core.VP.menu_colors.base,out)
end
function Core.VP.help_line(text) Core.VP.menu_print({{text,Core.VP.menu_colors.base}}) end
function Core.VP.help_title(text) Core.VP.menu_print({{text,Core.VP.menu_colors.green}}) end
function Core.VP.append_blue_values(parts,current)
    local values={}
    for value in tostring(current or ''):gmatch('[^|]+') do values[#values+1]=(value:gsub('^%s+',''):gsub('%s+$','')) end
    for i,value in ipairs(values) do
        if i>1 then parts[#parts+1]={' | ',Core.VP.menu_colors.base} end
        parts[#parts+1]={value,Core.VP.menu_colors.blue}
    end
end
function Core.VP.help_heading(text,current)
    local parts={{text,Core.VP.menu_colors.green}}
    if current and tostring(current)~='' then
        parts[#parts+1]={' [',Core.VP.menu_colors.base}
        Core.VP.append_blue_values(parts,current)
        parts[#parts+1]={']',Core.VP.menu_colors.base}
    end
    Core.VP.menu_print(parts)
end
function Core.VP.help_topic(label,current,description,command)
    local parts={{label,Core.VP.menu_colors.green}}
    if current and tostring(current)~='' then
        parts[#parts+1]={' [',Core.VP.menu_colors.base}
        Core.VP.append_blue_values(parts,current)
        parts[#parts+1]={']',Core.VP.menu_colors.base}
    end
    if description and description~='' then parts[#parts+1]={': '..description,Core.VP.menu_colors.base} end
    if command and command~='' then
        parts[#parts+1]={' ',Core.VP.menu_colors.base}
        parts[#parts+1]={command,Core.VP.menu_colors.green}
    end
    Core.VP.menu_print(parts)
end
function Core.VP.help_options(label,values)
    local parts={{label..': ',Core.VP.menu_colors.green}}
    if type(values)=='string' then
        local parsed={}
        for value in tostring(values):gmatch('[^|]+') do parsed[#parsed+1]=(value:gsub('^%s+',''):gsub('%s+$','')) end
        values=parsed
    end
    for i,value in ipairs(values or {}) do
        if i>1 then parts[#parts+1]={' | ',Core.VP.menu_colors.base} end
        parts[#parts+1]={tostring(value),Core.VP.menu_colors.blue}
    end
    Core.VP.menu_print(parts)
end
function Core.VP.help_commands(label,commands,description)
    local parts={{label..': ',Core.VP.menu_colors.green}}
    if type(commands)=='string' then commands={commands} end
    for i,command in ipairs(commands or {}) do
        if i>1 then parts[#parts+1]={' | ',Core.VP.menu_colors.base} end
        parts[#parts+1]={tostring(command),Core.VP.menu_colors.green}
    end
    if description and description~='' then parts[#parts+1]={' - '..description,Core.VP.menu_colors.base} end
    Core.VP.menu_print(parts)
end
function Core.VP.copy_table(value)
    if type(value)~='table' then return value end
    local out={}; for k,v in pairs(value) do out[Core.VP.copy_table(k)]=Core.VP.copy_table(v) end; return out
end
function Core.VP.profile_snapshot()
    local keys={'visible','view','scope','sort','period','custom_players','local_players','alliance_limit','row_limit','report_delay','report_destination','report_tell','report_content','include_trusts','include_allied_npcs','job_column','job_sub_mode','theme','bg_opacity','contrast_bg_opacity','dps_refresh_seconds','columns','display','controls','pins','self_pin','pin_local','pin_party','pin_alliance','target_hp','highlights','filters','enemy_filter_text','enemy_filter_ids'}
    local out={}; for _,k in ipairs(keys) do out[k]=Core.VP.copy_table(settings[k]) end
    out.secondary_huds={}
    for key,cfg in pairs(settings.secondary_huds or {}) do out.secondary_huds[key]={visible=cfg.visible==true,view=cfg.view,row_limit=cfg.row_limit} end
    return out
end
function Core.VP.apply_profile(profile,name)
    if type(profile)~='table' then return false end
    for k,v in pairs(profile) do
        if k~='secondary_huds' then settings[k]=Core.VP.copy_table(v) end
    end
    if type(profile.secondary_huds)=='table' then
        for key,v in pairs(profile.secondary_huds) do
            if settings.secondary_huds[key] then
                settings.secondary_huds[key].visible=v.visible==true
                settings.secondary_huds[key].view=v.view or settings.secondary_huds[key].view
                settings.secondary_huds[key].row_limit=tonumber(v.row_limit) or settings.secondary_huds[key].row_limit
                local obj=Core.VP.huds[key]; if obj then if settings.secondary_huds[key].visible then obj:show(); if Core.VP.bold_huds[key] then Core.VP.bold_huds[key]:show() end else obj:hide(); if Core.VP.bold_huds[key] then Core.VP.bold_huds[key]:hide() end end end
            end
        end
    end
    settings.job_sub_mode=Core.lower(settings.job_sub_mode or 'auto'); settings.subjob=(settings.job_sub_mode=='on')
    settings.active_profile=name or ''
    Core.VP.apply_theme_runtime()
    if settings.visible then hud:show() else hud:hide() end
    return true
end
function Core.VP.persist_settings(save_registry)
    Core.VP.capture_hud_settings(); config.save(settings)
    if save_registry then enemy_registry:save(); Core.VP.registry_dirty=false; Core.VP.registry_next_save=Core.now()+(tonumber(settings.registry_save_seconds) or 120) end
end
function Core.VP.profile_name(args,first)
    local parts={}; for i=first,#args do if args[i] and tostring(args[i])~='' then parts[#parts+1]=tostring(args[i]) end end
    return table.concat(parts,' '):gsub('^%s+',''):gsub('%s+$','')
end
function Core.VP.saved_profile_names()
    local out={}; for name in pairs(settings.profiles or {}) do out[#out+1]=name end; table.sort(out,function(a,b) return Core.lower(a)<Core.lower(b) end); return out
end
function Core.VP.save_named_profile(name)
    name=tostring(name or ''):gsub('^%s+',''):gsub('%s+$',''); if name=='' then return false,'A settings name is required.' end
    settings.profiles=settings.profiles or {}; settings.profiles[name]=Core.VP.profile_snapshot(); settings.active_profile=name; Core.VP.persist_settings(false); return true,'Settings saved as ['..name..'].'
end
function Core.VP.find_profile(name)
    local wanted=Core.lower(name or ''); for k,v in pairs(settings.profiles or {}) do if Core.lower(k)==wanted then return k,v end end; return nil,nil
end
function Core.VP.restore_named_profile(name)
    local key,profile=Core.VP.find_profile(name); if not profile then return false,'Saved settings not found: '..tostring(name) end
    Core.VP.previous_settings_profile=Core.VP.profile_snapshot(); Core.VP.previous_profile_name=settings.active_profile
    Core.VP.apply_profile(profile,key); Core.VP.persist_settings(false); return true,'Restored ['..key..'].'
end
function Core.VP.restore_defaults()
    Core.VP.previous_settings_profile=Core.VP.profile_snapshot(); Core.VP.previous_profile_name=settings.active_profile
    local profiles=settings.profiles or {}

    -- A true default reset owns the complete render lifecycle. Destroy every
    -- current text primitive first, then reset the live Settings object in
    -- place so Windower config metadata remains valid, and finally create
    -- brand-new HUD primitives from canonical defaults.
    Core.VP.destroy_huds()
    for k in pairs(settings) do if k~='profiles' then settings[k]=nil end end
    local d=Core.VP.copy_table(defaults)
    for k,v in pairs(d) do if k~='profiles' then settings[k]=v end end
    settings.profiles=profiles
    settings.active_profile=''
    settings.job_sub_mode='auto'
    settings.subjob=false

    Core.VP.create_huds_from_settings()
    Core.VP.persist_settings(false)
end
function Core.VP.return_previous_profile()
    if not Core.VP.previous_settings_profile then return false,'No previous settings snapshot is available in this addon session.' end
    local current_snap=Core.VP.profile_snapshot(); local current_name=settings.active_profile
    Core.VP.apply_profile(Core.VP.previous_settings_profile,Core.VP.previous_profile_name or '')
    Core.VP.previous_settings_profile=current_snap; Core.VP.previous_profile_name=current_name; Core.VP.persist_settings(false); return true,'Returned to previous settings.'
end

function Core.VP.pins_state()
    local list={}; if settings.self_pin then list[#list+1]='Self' end; if settings.pin_local then list[#list+1]='Local' end; if settings.pin_party then list[#list+1]='Party' end; if settings.pin_alliance then list[#list+1]='Alliance' end
    for name in pairs(settings.pins or {}) do list[#list+1]=name end; table.sort(list); return #list>0 and table.concat(list,', ') or 'None'
end
function Core.VP.current_profile_label() return settings.active_profile~='' and settings.active_profile or 'Custom' end
function Core.VP.job_state()
    if not settings.job_column then return 'Hidden' end
    if settings.job_sub_mode=='auto' then return 'Auto: Job / Job/Sub' end
    return settings.job_sub_mode=='on' and 'Job/Sub' or 'Job'
end
function Core.VP.transition_state()
    if Core.VP.transition and Core.VP.transition.active then return 'Settling' end
    if settings.paused then return 'Paused' end
    return 'Ready'
end
function Core.VP.observer_state()
    local src=Core.VP.observer_selected_source(); return src and tostring(src.display_name or 'Observed Encounter') or 'None'
end


function Core.VP.print_status()
    local src=selected_source(); local now=Core.now(); local elapsed=elapsed_active(src,now); local actors=src and display_actors(src,true,false) or {}
    Core.VP.help_line('VanaParse Status ['..Core.VP.transition_state()..' | '..Core.VP.current_profile_label()..']')
    Core.VP.help_line('Location: '..Core.VP.location_text()..' | Encounter: '..(current and 'Open' or 'None'))
    Core.VP.help_line(('View: %s | Mode: %s | Sort: %s | Filter: %s'):format(view_display_name(settings.view),Core.VP.scope_label(settings.scope),Core.display_word(settings.sort),Core.VP.filter_display_text()))
    Core.VP.help_line(('Elapsed: %s | Active: %s'):format(Core.VP.duration_hms(elapsed),Core.VP.active_display_text(src,now)))
    Core.VP.help_line(('Actors: %d | WS Avg: %s | DPS Refresh: %.1fs'):format(#actors,Core.VP.wsavg_state(),tonumber(settings.dps_refresh_seconds) or 5))
    Core.VP.help_line(('Pins: %s'):format(Core.VP.pins_state()))
    Core.VP.help_line(('All HUD: %s | All Parties HUD: %s | Observing: %s'):format(settings.secondary_huds.all.visible and 'On' or 'Off',settings.secondary_huds.allparties.visible and 'On' or 'Off',Core.VP.observer_state()))
    Core.VP.help_line(('Report: %s | Content: %s | Delay: %.2fs'):format(Core.VP.report_destination_label(),Core.display_word(settings.report_content),tonumber(settings.report_delay) or 1.05))
    Core.VP.help_line(('Theme: %s | BG: %.1f%% | Font: %s %spt'):format(Core.VP.theme_label(settings.theme),Core.VP.effective_bg_opacity(),Core.VP.font_name(),Core.VP.font_size_label()))
end
function Core.VP.print_settings(section)
    section=Core.lower(section or '')
    if section=='' or section=='all' then
        Core.VP.help_line('VanaParse Settings ['..Core.VP.current_profile_label()..']')
        Core.VP.help_line(('View: %s | Mode: %s | Sort: %s | Filter: %s'):format(view_display_name(settings.view),Core.VP.scope_label(settings.scope),Core.display_word(settings.sort),Core.VP.filter_display_text()))
        Core.VP.help_line(('Job: %s | WS Avg: %s'):format(Core.VP.job_state(),Core.VP.wsavg_state()))
        Core.VP.help_line(('Rows: %s | Pins: %s'):format(settings.row_limit==0 and 'All' or tostring(settings.row_limit),Core.VP.pins_state()))
        Core.VP.help_line(('Report: %s | Content: %s | Delay: %.2fs'):format(Core.VP.report_destination_label(),Core.display_word(settings.report_content),tonumber(settings.report_delay) or 1.05))
        Core.VP.help_line(('Theme: %s | BG: %.1f%% | Normal BG: %.1f%% | Contrast BG: %.1f%%'):format(Core.VP.theme_label(settings.theme),Core.VP.effective_bg_opacity(),settings.bg_opacity,settings.contrast_bg_opacity))
        Core.VP.help_line(('Font: %s %spt | DPS Refresh: %.1fs'):format(Core.VP.font_name(),Core.VP.font_size_label(),tonumber(settings.dps_refresh_seconds) or 5))
        Core.VP.help_line(('Idle: Detect %ds | Timeout %ds | Notice %ds'):format(settings.idle_detect_seconds,settings.idle_timeout_seconds,settings.notice_seconds))
        Core.VP.help_line(('All HUD: %s/%s | All Parties HUD: %s/%s'):format(settings.secondary_huds.all.visible and 'On' or 'Off',view_display_name(settings.secondary_huds.all.view),settings.secondary_huds.allparties.visible and 'On' or 'Off',view_display_name(settings.secondary_huds.allparties.view)))
        return
    end
    if section=='view' or section=='hud' then Core.VP.help_line(('Settings - View [%s]'):format(view_display_name(settings.view))); Core.VP.help_line(('Rows: %s | Job: %s'):format(settings.row_limit==0 and 'All' or settings.row_limit,Core.VP.job_state()))
    elseif section=='mode' then Core.VP.help_line(('Settings - Mode [%s]'):format(Core.VP.scope_label(settings.scope)))
    elseif section=='sort' then Core.VP.help_line(('Settings - Sort [%s]'):format(Core.display_word(settings.sort)))
    elseif section=='filter' or section=='filters' then Core.VP.help_line('Settings - Filter ['..Core.VP.filter_display_text()..']'); Core.VP.help_line(Core.VP.filter_status_text())
    elseif section=='reports' or section=='report' then Core.VP.help_line('Settings - Reports ['..Core.VP.report_destination_label()..' | '..Core.display_word(settings.report_content)..']'); Core.VP.help_line(('Delay: %.2fs'):format(settings.report_delay))
    elseif section=='theme' then Core.VP.help_line(('Settings - Theme [%s | BG %.1f%%]'):format(Core.VP.theme_label(settings.theme),Core.VP.effective_bg_opacity())); Core.VP.help_line(('Normal BG: %.1f%% | Contrast BG: %.1f%%'):format(settings.bg_opacity,settings.contrast_bg_opacity))
    elseif section=='font' or section=='size' then Core.VP.help_line(('Settings - Font [%s | %spt]'):format(Core.VP.font_name(),Core.VP.font_size_label()))
    elseif section=='local' then Core.VP.help_line(('Settings - Local [%d]'):format(#settings.local_players)); Core.VP.help_line(#settings.local_players>0 and table.concat(settings.local_players,', ') or 'Self only')
    elseif section=='pins' or section=='pin' then Core.VP.help_line('Settings - Pins ['..Core.VP.pins_state()..']')
    elseif section=='save' or section=='saved' or section=='profiles' then local names=Core.VP.saved_profile_names(); Core.VP.help_line('Settings - Saved ['..Core.VP.current_profile_label()..']'); Core.VP.help_line(#names>0 and table.concat(names,', ') or 'None')
    elseif section=='idle' or section=='session' then Core.VP.help_line(('Settings - Idle [Detect %ds | Timeout %ds]'):format(settings.idle_detect_seconds,settings.idle_timeout_seconds)); Core.VP.help_line(('Notice: %ds | DPS HUD refresh: %.1fs'):format(settings.notice_seconds,tonumber(settings.dps_refresh_seconds) or 5))
    else Core.VP.help_line('Unknown settings section. Use //vp settings.') end
end

function Core.VP.print_help(section)
    section=Core.lower(section or '')
    local ver=tostring(_addon.version or 'Unknown')
    if section=='' or section=='all' then
        Core.VP.help_title('VanaParse (Ver. '..ver..') Help')
        Core.VP.help_topic('View',view_display_name(settings.view),'What statistics are displayed.','//vp view [view]')
        Core.VP.help_options('Options',{'Compact','Dynamic','Full','Physical','WS','WS Details','Ranged','Magic','Magic Details','Pet','Healing','Healing Details','Recovery','Recovery Details','Defense'})
        Core.VP.help_topic('Mode',Core.VP.scope_label(settings.scope),'WHO is included.','//vp mode [mode]')
        Core.VP.help_options('Options',{'Self','Local (Multibox)','Party','Alliance','All','All Parties','Custom'})
        Core.VP.help_topic('Sort',Core.display_word(settings.sort),'How player rows are ordered.','//vp sort [sort]')
        Core.VP.help_options('Options',{'DPS','Damage','Melee','Accuracy','Ranged','R.Acc','WS','WS Acc','WS Avg','SC','Magic','Pet','Healing','Recovery','Taken','Party'})
        Core.VP.help_topic('Display',display_status_text(),'Show or hide parser categories/columns regardless of current View.','//vp show <category>')
        Core.VP.help_topic('Filter',Core.VP.filter_display_text(),'Enemy and damage filtering.','//vp filter')
        Core.VP.help_topic('Reports',Core.VP.report_destination_label()..' | '..Core.display_word(settings.report_content),'View, metric and player reports.','//vp report')
        Core.VP.help_topic('Session',current and 'Open' or 'None','Active timing, pause, reset and splits.','//vp help session')
        Core.VP.help_topic('Theme',Core.VP.theme_label(settings.theme)..' | BG '..('%.1f%%'):format(Core.VP.effective_bg_opacity()),'HUD appearance.','//vp theme')
        Core.VP.help_topic('Font',Core.VP.font_name()..' '..Core.VP.font_size_label()..'pt','Font family and size.','//vp help font')
        Core.VP.help_topic('Saved Settings',Core.VP.current_profile_label(),'Named configurations.','//vp help save')
        Core.VP.help_options('More',{'sort','split','local','pins','setup','commands'})
        Core.VP.help_commands('Details',{'//vp help <command>'},'Use a command name for specific options. Example: //vp help mode')
        Core.VP.help_line('Complete command reference: COMMAND_DIRECTORY.md')
        return
    end
    if section=='view' or section=='hud' then
        Core.VP.help_heading('VanaParse (Ver. '..ver..') Help - HUD / View',view_display_name(settings.view))
        Core.VP.help_line('WHAT statistics are displayed. Bare //vp view cycles Compact > Dynamic > Full > Physical > WS, then lists all Views.')
        Core.VP.help_options('Options',{'Compact','Dynamic','Full','Physical','WS','WS Details','Ranged','Magic','Magic Details','Pet','Healing','Healing Details','Recovery','Recovery Details','Defense'})
        Core.VP.help_line('Compact Auto = Job. Other views Auto = Job/Sub. Joined/reversed forms such as //vp wsdetails and //vp wsdetails view are accepted.')
        Core.VP.help_commands('Secondary',{'//vp hud all view [<view>]','//vp hud allparties view [<view>]'},'Bare secondary view cycles.')
        Core.VP.help_commands('Display',{'//vp show <field|category|action>','//vp hide <field|category|action>','//vp <subject> show','//vp <subject> hide'},'Every visible field/category can be shown or hidden regardless of View. Named detail actions can also be controlled, e.g. //vp hide low or //vp hide Savage Blade.')
        Core.VP.help_commands('Calculate',{'//vp include <field|category|action>','//vp exclude <field|category|action>','//vp <subject> include','//vp <subject> exclude'},'Exclude changes calculated results without deleting raw captured data.'); Core.VP.help_commands('Example',{'//vp view physical','//vp view wsdetails','//vp low hide','//vp exclude Savage Blade'})
    elseif section=='mode' then
        Core.VP.help_heading('VanaParse (Ver. '..ver..') Help - Mode',Core.VP.scope_label(settings.scope))
        Core.VP.help_line('WHO is included. Bare //vp mode cycles.')
        Core.VP.help_options('Options',{'self','local (multibox)','party','alliance','all','allparties','custom'})
        Core.VP.help_line('All = observed contributors to the current encounter. All Parties = nearby observed encounters regardless of claim.')
        Core.VP.help_commands('Example',{'//vp mode allparties'})
    elseif section=='sort' then
        Core.VP.help_heading('VanaParse (Ver. '..ver..') Help - Sort',Core.display_word(settings.sort))
        Core.VP.help_line('HOW player rows are ordered. Bare //vp sort cycles.')
        Core.VP.help_options('Options',{'dps','damage','melee','accuracy','ranged','racc','ws','wsacc','wsavg','sc','magic','pet','healing','recovery','taken','party'})
        Core.VP.help_commands('Example',{'//vp sort dps'})
    elseif section=='filter' or section=='filters' then
        Core.VP.help_heading('VanaParse (Ver. '..ver..') Help - Filter',Core.VP.filter_display_text())
        Core.VP.help_commands('Enemy',{'//vp filter target','//vp filter <enemy name>','//vp unfilter <enemy name>','//vp filter clear'})
        Core.VP.help_line('Damage categories can also be included/excluded or filtered. Bare //vp filter reports current state.')
        Core.VP.help_commands('Example',{'//vp filter target'})
    elseif section=='session' then
        Core.VP.help_heading('VanaParse (Ver. '..ver..') Help - Session',current and 'Open' or 'None')
        Core.VP.help_line('Active measures battle participation. 30s quiet enters Idle; 60s Idle is omitted and Active pauses.')
        Core.VP.help_line('HUD DPS refreshes every '..tostring(settings.dps_refresh_seconds)..'s; reports always use exact current DPS.')
        Core.VP.help_commands('Commands',{'//vp pause','//vp resume','//vp reset','//vp status','//vp save'})
        Core.VP.help_commands('Example',{'//vp status'})
    elseif section=='reports' or section=='report' then
        Core.VP.help_heading('VanaParse (Ver. '..ver..') Help - Reports',Core.VP.report_destination_label()..' | '..Core.display_word(settings.report_content))
        Core.VP.help_options('Views',{'compact','dynamic','physical','magic','ranged','healing','pet','ws','etc.'})
        Core.VP.help_options('Metrics',{'accuracy','dps','damage','share','wsavg','wsacc','wshm','melee','ranged','magic','pet','healing','sc','mb','recovery','taken'})
        Core.VP.help_line('A player name narrows to that actor even when not currently visible in the HUD rows.')
        Core.VP.help_options('Actor scope',{'self','local','party','alliance','all','allparties'})
        Core.VP.help_options('Destinations',{'hud/self','tell','party','alliance','linkshell','linkshell2'})
        Core.VP.help_line('Public channels are blocked: say, yell, shout, unity, assist, jp, en, eu.')
        Core.VP.help_commands('Example',{'//vp report accuracy compact party'})
    elseif section=='split' then
        Core.VP.help_heading('VanaParse (Ver. '..ver..') Help - Split',tostring(#splits))
        Core.VP.help_commands('Commands',{'//vp split [name]','//vp split list','//vp split show <n|name>','//vp split delete <n|name>','//vp split clear','//vp split current','//vp unsplit'})
        Core.VP.help_commands('Reports',{'//vp report split 1','//vp report split 1-2 magic'})
        Core.VP.help_commands('Example',{'//vp report split 1-2 physical'})
    elseif section=='local' then
        Core.VP.help_heading('VanaParse (Ver. '..ver..') Help - Local',tostring(#settings.local_players))
        Core.VP.help_line('Local is a saved list of characters you control, independent of Party/Alliance placement.')
        Core.VP.help_commands('Commands',{'//vp local show','//vp local add <name...>','//vp local remove <name>','//vp local clear'})
        Core.VP.help_commands('Example',{'//vp local add PlayerA PlayerB'})
    elseif section=='pins' or section=='pin' then
        Core.VP.help_heading('VanaParse (Ver. '..ver..') Help - Pins',Core.VP.pins_state())
        Core.VP.help_line('Pins move actors visually without changing true # rank.')
        Core.VP.help_options('Targets',{'self','local','party','alliance','<player>','all','default'})
        Core.VP.help_commands('Example',{'//vp pin local'})
    elseif section=='setup' then
        Core.VP.help_heading('VanaParse (Ver. '..ver..') Help - Setup',Core.VP.job_state())
        Core.VP.help_options('Options',{'job','sub','wsavg','highlights','crits','rows','target','include/exclude','filter/unfilter'})
        Core.VP.help_options('Boolean words',{'on/show/enable','off/hide/disable','toggle','status/state/settings','default/reset'})
        Core.VP.help_commands('Example',{'//vp sub auto'})
    elseif section=='theme' then
        Core.VP.help_heading('VanaParse (Ver. '..ver..') Help - Theme',Core.VP.theme_label(settings.theme)..' | BG '..('%.1f%%'):format(Core.VP.effective_bg_opacity()))
        Core.VP.help_options('Cycle',{'dark','light','contrastdark','contrastlight'})
        Core.VP.help_line('Contrast themes default to 80% opacity (20% transparency) and remember a separate contrast BG value.')
        Core.VP.help_commands('Background',{'//vp bg <0-100 or 0-100%>'},'Theme changes color/text/background palette.')
        Core.VP.help_commands('Shortcuts',{'//vp dark','//vp light','//vp contrast dark','//vp contrast light'})
        Core.VP.help_commands('Example',{'//vp bg 76%'})
    elseif section=='font' or section=='size' then
        Core.VP.help_heading('VanaParse (Ver. '..ver..') Help - Font',Core.VP.font_name()..' | '..Core.VP.font_size_label()..'pt')
        Core.VP.help_commands('Commands',{'//vp font <name>','//vp font list','//vp font size <5-36>','//vp fontsize <size>','//vp size <size>','//vp set size <size>'})
        Core.VP.help_options('Approved Fonts',Core.VP.APPROVED_FONTS)
        Core.VP.help_line('Only fonts confirmed in-game to preserve parser columns are accepted. Sizes round to the nearest 0.25 point.')
        Core.VP.help_commands('Examples',{'//vp font Courier New','//vp size 6.25','//vp size 6.5'})
    elseif section=='save' or section=='saved' or section=='profiles' then
        local names=Core.VP.saved_profile_names()
        Core.VP.help_heading('VanaParse (Ver. '..ver..') Help - Saved Settings',Core.VP.current_profile_label())
        Core.VP.help_commands('Commands',{'//vp save <name>','//vp restore <name>','//vp saves','//vp delete setting <name>','//vp default','//vp return'})
        Core.VP.help_line('Combat totals and temporary encounter data are not stored in profiles. Saved: '..(#names>0 and table.concat(names,', ') or 'None'))
        Core.VP.help_commands('Example',{'//vp save multibox'})
    elseif section=='commands' or section=='command' then
        Core.VP.help_title('VanaParse (Ver. '..ver..') Help - Commands')
        Core.VP.help_line('Boolean feature: bare command toggles. Selectors such as View/Mode/Theme/Sort cycle when bare.')
        Core.VP.help_options('Shared words',{'on/show/enable','off/hide/disable','toggle','status/state/settings','default/reset'})
        Core.VP.help_commands('Details',{'//vp help <command>'},'Use COMMAND_DIRECTORY.md for the complete reference.')
        Core.VP.help_commands('Example',{'//vp help mode'})
    else Core.VP.help_line('Unknown help section: '..tostring(section)..'. Use //vp help.') end
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
    if value=='' or token=='list' or token=='status' then chat(207,Core.VP.filter_status_text()); return end
    if undo and (token=='all' or token=='clear' or token=='reset') then settings.enemy_filter_text=''; settings.enemy_filter_ids=''; Core.VP.all_damage_filters(true); chat(207,'All filters cleared.'); return end
    if not undo and (token=='all' or token=='clear' or token=='reset') then settings.enemy_filter_text=''; settings.enemy_filter_ids=''; Core.VP.all_damage_filters(true); chat(207,'All filters cleared.'); return end
    local canonical=FILTER_ALIASES[token] or FILTER_ALIASES[token:gsub('%s+','')]
    if not canonical then
        local cat=normalize_category(value)
        canonical=FILTER_ALIASES[cat] or FILTER_ALIASES[cat:gsub('_','')]
        if cat=='physical' then canonical='melee' elseif cat=='pet_physical' then canonical='pet_physical' elseif cat=='pet_magic' then canonical='pet_magic' elseif cat=='pet_ranged' then canonical='pet_ranged' end
    end
    if canonical or normalize_category(value)=='physical' then
        local cat=normalize_category(value)
        if undo then Core.VP.all_damage_filters(true); chat(207,'Damage filter removed: '..Core.display_word(cat=='physical' and 'physical' or canonical))
        else
            Core.VP.all_damage_filters(false)
            if cat=='physical' then settings.filters.melee=true; settings.filters.ws=true; settings.filters.sc=true
            else settings.filters[canonical]=true; if canonical:find('^pet_') then settings.filters.pet=true end end
            chat(207,'Filtering damage: '..Core.display_word(cat=='physical' and 'physical' or canonical))
        end
        return
    end
    if token=='current' or token=='target' then
        if undo then settings.enemy_filter_ids=''; chat(207,'Current-target filter removed.') else add_current_target_filter() end
        return
    end
    if undo then
        if Core.VP.remove_enemy_filter_text(value) then chat(207,'Enemy filter removed: '..value) else chat(167,'Enemy filter not found: '..value) end
    else Core.VP.add_enemy_filter_text(value); chat(207,'Enemy filter added: '..value) end
end

local function full_reset(reason)
    local snap=current_source(); if snap then log_source('SESSION',snap,Core.now(),reason or 'manual-reset') end
    current=nil; last_fight=nil; history={}; session_actors={}; session_activity=Core.Activity.new(settings.active_timeout); session_active_committed=0; session_last_event=nil; session_started=Core.now(); forced_miss_windows={}; target_learning={}; target_lives={}; last_target_id=nil; splits={}; active_split=nil; split_counter=0; split_view=nil; Core.VP.observer={encounters={},order={},focus=nil,actor_to_encounter={},last_cleanup=0}
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

function Core.VP.set_report_destination(dest,tell_name)
    dest=Core.lower(dest or '')
    if Report.PUBLIC_DESTINATIONS[dest] then return false,'public' end
    local mapped=Report.DESTINATIONS[dest]; if not mapped then return false,'unknown' end
    if mapped=='tell' and (not tell_name or tell_name=='') then return false,'tell' end
    settings.report_destination=mapped; if mapped=='tell' then settings.report_tell=tell_name else settings.report_tell='' end
    return true
end
function Core.VP.pin_group(action,target)
    action=Core.lower(action or ''); target=Core.lower(target or '')
    local on=action=='pin'
    if target=='me' then target='self' end
    if target=='self' then settings.self_pin=on; return true
    elseif target=='local' then settings.pin_local=on; return true
    elseif target=='party' then settings.pin_party=on; return true
    elseif target=='alliance' then settings.pin_alliance=on; return true
    elseif target=='all' and not on then settings.pins={}; settings.self_pin=false; settings.pin_local=false; settings.pin_party=false; settings.pin_alliance=false; return true
    elseif target=='default' then settings.pins={}; settings.self_pin=true; settings.pin_local=false; settings.pin_party=false; settings.pin_alliance=false; return true end
    return false
end
function Core.VP.local_group_command(args)
    local sub=Core.lower(args[2] or 'show')
    if sub=='show' or sub=='list' then chat(207,'Local players: '..(#settings.local_players>0 and table.concat(settings.local_players,', ') or 'Self only')); return true end
    if sub=='clear' then settings.local_players={}; chat(207,'Local player list cleared.'); return true end
    if sub=='add' then
        local seen={}; for _,n in ipairs(settings.local_players) do seen[Core.lower(n)]=true end
        for i=3,#args do local n=tostring(args[i]); if n~='' and not seen[Core.lower(n)] then settings.local_players[#settings.local_players+1]=n; seen[Core.lower(n)]=true end end
        chat(207,'Local players updated.'); return true
    end
    if sub=='remove' and args[3] then local wanted=Core.lower(args[3]); local out={}; for _,n in ipairs(settings.local_players) do if Core.lower(n)~=wanted then out[#out+1]=n end end; settings.local_players=out; chat(207,'Local player removed: '..tostring(args[3])); return true end
    return false
end

windower.register_event('action',function(act) Core.safe_call('action',process_action,on_error,act) end)
windower.register_event('incoming chunk',function(id,original,modified,injected,blocked)
    if injected or blocked then return end
    if Core.VP.transition and Core.VP.transition.active then return end
    if id==0x0C9 then Core.safe_call('check-metadata',Core.VP.process_check_chunk,on_error,original) end
end)
windower.register_event('prerender',function()
    local now=Core.now(); Core.safe_call('transition',Core.VP.transition_tick,on_error,now); Core.safe_call('teleport-detect',Core.VP.detect_micro_transition,on_error,now)
    if not Core.VP.transition.active then
        Core.safe_call('report-queue',process_report_queue,on_error,now); Core.safe_call('prerender',update_hud,on_error,false)
        if Core.VP.registry_dirty and now>=Core.VP.registry_next_save then Core.safe_call('registry-save',function() enemy_registry:save(); Core.VP.registry_dirty=false; Core.VP.registry_next_save=now+(tonumber(settings.registry_save_seconds) or 120) end,on_error) end
    end
end)
windower.register_event('zone change',function()
    Core.safe_call('zone-change',function()
        Core.VP.transition.pending_finalize=current~=nil; Core.VP.transition_begin('zone',settings.transition_full_min,settings.transition_full_max)
        party_cache={by_id={},order={},self_id=nil}; party_cache_at=0
    end,on_error)
end)
windower.register_event('load','login',function() Core.safe_call('load-login',function() party_cache=Core.party_snapshot(windower); party_cache_at=Core.now(); Core.VP.transition_begin('login',2,10) end,on_error) end)
Core.VP.detect_micro_transition(Core.now())

function Core.VP.toggle_word(value)
    value=Core.lower(value or '')
    if value=='' or value=='toggle' then return 'toggle' end
    if value=='on' or value=='show' or value=='true' or value=='1' or value=='add' or value=='enable' or value=='enabled' then return 'on' end
    if value=='off' or value=='hide' or value=='false' or value=='0' or value=='remove' or value=='disable' or value=='disabled' then return 'off' end
    if value=='default' or value=='reset' then return 'default' end
    if value=='status' or value=='state' or value=='setting' or value=='settings' then return 'status' end
    return nil
end
function Core.VP.boolean_toggle(current,default_value,word)
    local op=Core.VP.toggle_word(word)
    if op=='toggle' then return not current,'set'
    elseif op=='on' then return true,'set'
    elseif op=='off' then return false,'set'
    elseif op=='default' then return default_value==true,'set'
    elseif op=='status' then return current,'status' end
    return current,'invalid'
end
function Core.VP.wsavg_state() return settings.columns.ws_avg~=false and 'On' or 'Off' end
function Core.VP.handle_display_toggle(command,arg)
    local current,item=Core.VP.display_item_enabled(command)
    if current==nil then return false end
    local op=Core.VP.toggle_word(arg); if not op then return false,'invalid' end
    local def=true
    if item=='accuracy' or item=='ranged_accuracy' or item=='ws_accuracy' or item=='ws_hm' or item=='ws_avg' then def=defaults.columns[item]~=false
    elseif item=='crits' then def=defaults.columns.crits==true
    elseif defaults.display[item]~=nil then def=defaults.display[item]~=false end
    local value,state=Core.VP.boolean_toggle(current,def,arg)
    if state=='status' then chat(207,Core.display_word(item:gsub('_',' '))..' display '..(current and 'On' or 'Off')..'.'); return true end
    if state=='invalid' then return false,'invalid' end
    Core.VP.set_display_item(item,value); chat(207,Core.display_word(item:gsub('_',' '))..' display '..(value and 'On' or 'Off')..'.'); return true
end

Core.VP.VIEW_CYCLE={'compact','dynamic','full','physical','ws','ws-details','ranged','magic','magic-details','pet','healing','healing-details','recovery','recovery-details','defense'}
Core.VP.PRIMARY_VIEW_CYCLE={'compact','dynamic','full','physical','ws'}
Core.VP.MODE_CYCLE={'self','local','party','alliance','all','allparties','custom'}
Core.VP.THEME_CYCLE={'dark','light','contrastdark','contrastlight'}
Core.VP.SORT_CYCLE={'dps','damage','melee','accuracy','ranged','racc','ws','wsacc','wsavg','sc','magic','pet','healing','cleanse','dispel','taken','party'}
function Core.VP.cycle_value(current,values)
    current=Core.lower(current or '')
    for i,v in ipairs(values or {}) do if Core.lower(v)==current then return values[(i % #values)+1] end end
    return values and values[1] or current
end
function Core.VP.set_theme(value)
    value=Core.lower(value or ''):gsub('%s+','')
    local aliases={inverse='light',hc='contrastdark',highcontrast='contrastdark',contrast='contrastdark',['contrast-dark']='contrastdark',['contrast-light']='contrastlight'}
    value=aliases[value] or value
    if value~='dark' and value~='light' and value~='contrastdark' and value~='contrastlight' then return false end
    settings.theme=value; Core.VP.apply_theme_runtime(); return true
end
function Core.VP.percent_number(value)
    local text=tostring(value or ''):gsub('%%$',''); return tonumber(text)
end
function Core.VP.unique_shorthand(args)
    local cmd=Core.lower(args[1] or '')
    local view_unique={compact=true,dynamic=true,full=true,physical=true,ranged=true,pet=true,healing=true,recovery=true,defense=true,wsdetails=true,wsdetail=true,magicdetails=true,magicdetail=true,healingdetails=true,healingdetail=true,recoverydetails=true,recoverydetail=true}
    if view_unique[cmd] then return {'view',args[1]} end
    local second=Core.lower(args[2] or '')
    if (cmd=='ws' or cmd=='weaponskill' or (cmd=='weapon' and second=='skill')) then
        local detail=(cmd=='weapon') and Core.lower(args[3] or '') or second
        if detail=='detail' or detail=='details' then return {'view','ws details'} end
    end
    if (cmd=='magic' or cmd=='healing' or cmd=='recovery') and (second=='detail' or second=='details') then return {'view',cmd..' details'} end
    if cmd=='dark' or cmd=='light' or cmd=='contrastdark' or cmd=='contrastlight' or cmd=='hc' or cmd=='highcontrast' then return {'theme',args[1]} end
    if cmd=='contrast' and (Core.lower(args[2] or '')=='dark' or Core.lower(args[2] or '')=='light') then return {'theme','contrast'..Core.lower(args[2])} end
    if cmd=='self' or cmd=='party' or cmd=='alliance' or cmd=='allparties' or cmd=='allparty' or cmd=='allpartys' or cmd=='custom' then return {'mode',args[1]} end
    return nil
end

function Core.VP.normalize_command_order(args)
    local out={}; for i,v in ipairs(args or {}) do out[i]=v end
    local first=Core.lower(out[1] or ''); local last=Core.lower(out[#out] or '')
    -- Reversed View syntax: //vp wsdetails view, //vp magicdetails view.
    if #out>=2 and last=='view' then
        local subject=Core.join({unpack(out,1,#out-1)},' ')
        local keep=settings.view; local ok=set_view(subject); settings.view=keep
        if ok then return {'view',subject} end
    end
    -- Reversed control syntax: //vp acc hide, //vp Savage Blade exclude.
    if #out>=2 and (last=='show' or last=='hide' or last=='add' or last=='remove' or last=='on' or last=='off' or last=='enable' or last=='disable' or last=='include' or last=='exclude') then
        local subject=Core.join({unpack(out,1,#out-1)},' ')
        local action=Core.VP.resolve_action_name(subject); local state=Core.VP.display_item_enabled(subject); local field=Core.VP.resolve_field_key(subject)
        if action or state~=nil or field then
            if last=='include' or last=='exclude' then return {last,subject} end
            local verb=(last=='show' or last=='add' or last=='on' or last=='enable') and 'show' or 'hide'
            return {verb,subject}
        end
    end
    return out
end

function Core.VP.handle_command(...)
    local args=Core.VP.normalize_command_order({...}); local cmd=Core.lower(args[1] or 'help')
    if cmd=='rep' then args[1]='report'; cmd='report' end
    -- Natural report order: //vp PlayerA report full party and similar forms.
    if cmd~='set' then
        local report_at=nil; for i,v in ipairs(args) do local l=Core.lower(v); if l=='report' or l=='rep' then report_at=i break end end
        if report_at and report_at~=1 then local normalized={'report'}; for i,v in ipairs(args) do if i~=report_at then normalized[#normalized+1]=v end end; args=normalized; cmd='report' end
    end
    -- Natural pin order: //vp self pin, //vp local unpin.
    if (cmd=='self' or cmd=='local' or cmd=='party' or cmd=='alliance') and (Core.lower(args[2])=='pin' or Core.lower(args[2])=='unpin') then args={args[2],args[1]}; cmd=Core.lower(args[1]) end
    -- Hierarchical help may also be reversed: //vp mode help, //vp theme help.
    if Core.lower(args[2] or '')=='help' and cmd~='report' then Core.VP.print_help(cmd); return end
    local short=Core.VP.unique_shorthand(args); if short then args=short; cmd=Core.lower(args[1]) end
    if cmd=='help' or cmd=='?' then Core.VP.print_help(args[2]); return
    elseif cmd=='version' then windower.add_to_chat(207,'VanaParse: Version '..tostring(_addon.version)); return
    elseif cmd=='status' then Core.VP.print_status(); return
    elseif cmd=='health' then
        local total=0; local parts={}; for label,e in pairs(Core.VP.error_state or {}) do local c=tonumber(e.count) or 0; if c>0 then total=total+c; parts[#parts+1]=label..':'..c end end; table.sort(parts)
        Core.VP.help_line(('VanaParse Health [%s] | Errors %d | Transition %s'):format(total==0 and 'Good' or 'Degraded',total,Core.VP.transition_state()))
        Core.VP.help_line(('Main HUD: %s | All HUD: %s | All Parties HUD: %s'):format(settings.visible and 'On' or 'Off',settings.secondary_huds.all.visible and 'On' or 'Off',settings.secondary_huds.allparties.visible and 'On' or 'Off'))
        if #parts>0 then Core.VP.help_line('Active error counters: '..table.concat(parts,', ')) else Core.VP.help_line('No active VanaParse error counters.') end
        return
    elseif cmd=='settings' or cmd=='setting' or cmd=='config' or cmd=='configuration' then Core.VP.print_settings(args[2]); return
    elseif cmd=='saves' or cmd=='saved' then local names=Core.VP.saved_profile_names(); Core.VP.help_line('Saved Settings ['..Core.VP.current_profile_label()..']: '..(#names>0 and table.concat(names,', ') or 'None')); return
    elseif cmd=='restore' then local name=Core.VP.profile_name(args,2); local ok,msg=Core.VP.restore_named_profile(name); chat(ok and 207 or 167,msg); update_hud(true); return
    elseif cmd=='default' then Core.VP.restore_defaults(); chat(207,'VanaParse defaults restored and HUD render rebuilt. Named settings were preserved.'); update_hud(true); return
    elseif cmd=='return' then local ok,msg=Core.VP.return_previous_profile(); chat(ok and 207 or 167,msg); update_hud(true); return
    elseif cmd=='delete' and (Core.lower(args[2] or '')=='setting' or Core.lower(args[2] or '')=='settings' or Core.lower(args[2] or '')=='profile') then local name=Core.VP.profile_name(args,3); local key=Core.VP.find_profile(name); if key then settings.profiles[key]=nil; if settings.active_profile==key then settings.active_profile='' end; Core.VP.persist_settings(false); chat(207,'Deleted saved settings ['..key..'].') else chat(167,'Saved settings not found: '..name) end; return
    elseif cmd=='save' then
        local first=2; if Core.lower(args[2] or '')=='setting' or Core.lower(args[2] or '')=='settings' then first=3 end
        local name=Core.VP.profile_name(args,first)
        if name=='' then Core.VP.persist_settings(true); chat(207,'Settings and learned registry saved.') else local ok,msg=Core.VP.save_named_profile(name); chat(ok and 207 or 167,msg) end; return
    elseif cmd=='observe' then local name=Core.VP.profile_name(args,2); local ok,msg=Core.VP.observer_focus(name); chat(ok and 207 or 167,msg); update_hud(true); return
    elseif cmd=='hud' then
        local which=Core.lower(args[2] or 'main'):gsub('%s+',''); if which=='allparty' or which=='allpartys' or which=='allparties' then which='allparties' end
        if which=='main' then local op=Core.lower(args[3] or 'toggle'); if op=='on' or op=='show' then settings.visible=true; hud:show(); if Core.VP.bold_huds.main then Core.VP.bold_huds.main:show() end elseif op=='off' or op=='hide' then settings.visible=false; hud:hide(); if Core.VP.bold_huds.main then Core.VP.bold_huds.main:hide() end elseif op=='toggle' or op=='' then settings.visible=not settings.visible; if settings.visible then hud:show(); if Core.VP.bold_huds.main then Core.VP.bold_huds.main:show() end else hud:hide(); if Core.VP.bold_huds.main then Core.VP.bold_huds.main:hide() end end elseif op=='status' then chat(207,'Main HUD '..(settings.visible and 'On' or 'Off')..'.'); return else chat(167,'Main HUD: on | off | toggle | status'); return end; Core.VP.persist_settings(false); chat(207,'Main HUD '..(settings.visible and 'On' or 'Off')..'.'); return end
        local cfg=settings.secondary_huds[which]; local obj=Core.VP.huds[which]; if not cfg or not obj then chat(167,'HUD: main | all | allparties'); return end
        local op=Core.lower(args[3] or 'toggle')
        if op=='on' or op=='show' then cfg.visible=true; obj:show(); if Core.VP.bold_huds[which] then Core.VP.bold_huds[which]:show() end
        elseif op=='off' or op=='hide' then cfg.visible=false; obj:hide(); if Core.VP.bold_huds[which] then Core.VP.bold_huds[which]:hide() end
        elseif op=='toggle' then cfg.visible=not cfg.visible; if cfg.visible then obj:show(); if Core.VP.bold_huds[which] then Core.VP.bold_huds[which]:show() end else obj:hide(); if Core.VP.bold_huds[which] then Core.VP.bold_huds[which]:hide() end end
        elseif op=='view' then
            local keep=settings.view; local requested=Core.join({select(4,unpack(args))},' ')
            if not requested or tostring(requested)=='' then requested=Core.VP.cycle_value(cfg.view,Core.VP.VIEW_CYCLE) end
            if not set_view(requested) then settings.view=keep; chat(167,'Unknown view.'); return else cfg.view=settings.view; settings.view=keep end
        elseif op=='rows' then local v=Core.lower(args[4] or 'default'); if v=='all' then cfg.row_limit=0 elseif v=='default' then cfg.row_limit=8 else local n=tonumber(v); if not n then chat(167,'Use rows <1-99 | all | default>.'); return end; cfg.row_limit=Core.clamp(math.floor(n),1,99) end
        elseif op=='status' then chat(207,Core.display_word(which)..' HUD ['..(cfg.visible and 'On' or 'Off')..' | '..view_display_name(cfg.view)..' | Rows '..(cfg.row_limit==0 and 'All' or cfg.row_limit)..']'); return
        else chat(167,'HUD '..which..': on | off | toggle | view <view> | rows <n|all|default>'); return end
        Core.VP.persist_settings(false); update_hud(true); chat(207,Core.VP.scope_label(which)..' HUD ['..(cfg.visible and 'On' or 'Off')..' | '..view_display_name(cfg.view)..' | Rows '..(cfg.row_limit==0 and 'All' or cfg.row_limit)..'].'); return
    elseif cmd=='show' or cmd=='hide' or cmd=='add' or cmd=='remove' then
        local visible=(cmd=='show' or cmd=='add'); local subject=Core.join({select(2,unpack(args))},' '); local token=Core.lower(subject)
        if subject=='' or token=='hud' then settings.visible=visible; if visible then hud:show(); if Core.VP.bold_huds.main then Core.VP.bold_huds.main:show() end else hud:hide(); if Core.VP.bold_huds.main then Core.VP.bold_huds.main:hide() end end; chat(207,'Main HUD '..(visible and 'On' or 'Off')..'.')
        elseif token=='highlights' then settings.highlights=visible; chat(207,'Highlights '..(visible and 'On' or 'Off')..'.')
        else
            local action=Core.VP.resolve_action_name(subject)
            if action then Core.VP.set_action_hidden(action,not visible); chat(207,(visible and 'Shown: ' or 'Hidden: ')..action)
            else
                local state=Core.VP.display_item_enabled(subject)
                if state~=nil then local ok,item=Core.VP.set_display_item(subject,visible); chat(207,(visible and 'Shown: ' or 'Hidden: ')..Core.display_word((item or subject):gsub('_',' ')))
                else
                    local field=Core.VP.resolve_field_key(subject)
                    if field then Core.VP.set_field_hidden(field,not visible); chat(207,(visible and 'Shown: ' or 'Hidden: ')..subject)
                    else chat(167,'Unknown Show/Hide subject: '..subject..'. Use a visible column/category/action name.'); return end
                end
            end
        end
        Core.VP.persist_settings(false); update_hud(true); return
    elseif cmd=='include' or cmd=='exclude' then
        local include=cmd=='include'; local subject=Core.join({select(2,unpack(args))},' '); local token=Core.lower(subject)
        if token=='trust' or token=='trusts' then settings.include_trusts=include; chat(207,(include and 'Included' or 'Excluded')..' Trust rows.')
        elseif token=='ally' or token=='allies' or token=='allied' or token=='allied npc' or token=='allied npcs' then settings.include_allied_npcs=include; chat(207,(include and 'Included' or 'Excluded')..' allied NPC rows.')
        elseif token=='all' then Core.VP.all_damage_filters(include); settings.controls.excluded_fields={}; settings.controls.excluded_actions={}; settings.controls.excluded_categories={}; chat(207,(include and 'Included: ' or 'Excluded: ')..'all damage categories')
        else
            local action=Core.VP.resolve_action_name(subject)
            if action then Core.VP.set_action_excluded(action,not include); chat(207,(include and 'Included: ' or 'Excluded: ')..action)
            else
                local cat=normalize_category(subject); local canonical=nil
                local category_set={physical=true,melee=true,ws=true,sc=true,magic=true,mb=true,ranged=true,pet=true,healing=true,recovery=true,defense=true}
                for k in pairs(Core.VP.CATEGORY_PARENT or {}) do category_set[k]=true end
                if category_set[cat] then
                    canonical=cat
                    if cat=='physical' then
                        for _,k in ipairs({'physical','melee','ws','sc'}) do Core.VP.set_category_excluded(k,not include) end
                        settings.filters.melee=include; settings.filters.ws=include; settings.filters.sc=include
                    else
                        Core.VP.set_category_excluded(cat,not include)
                        if settings.filters[cat]~=nil then settings.filters[cat]=include end
                        if include and cat:find('^pet_') then settings.filters.pet=true; Core.VP.set_category_excluded('pet',false) end
                    end
                end
                if canonical then chat(207,(include and 'Included: ' or 'Excluded: ')..subject)
                else
                    local field=Core.VP.resolve_field_key(subject)
                    if field then Core.VP.set_field_excluded(field,not include); chat(207,(include and 'Included metric: ' or 'Excluded metric: ')..subject)
                    else chat(167,'Unknown Include/Exclude subject: '..subject..'. Use a visible column/category/action name.'); return end
                end
            end
        end
        Core.VP.persist_settings(false); update_hud(true); return
    elseif cmd=='filter' then handle_filter_command(args,false)
    elseif cmd=='unfilter' then handle_filter_command(args,true)
    elseif cmd=='set' then
        local item=Core.lower(args[2] or '')
        if item=='rows' or item=='row' then
            local value=Core.lower(args[3] or 'default')
            if value=='all' or value=='off' then settings.row_limit=0
            elseif value=='default' or value=='reset' then settings.row_limit=8
            else local nrows=tonumber(args[3]); if nrows then settings.row_limit=Core.clamp(math.floor(nrows),1,99) else chat(167,'Use //vp set rows <1-99 | all | default>.'); return end end
            chat(207,'Visible actor rows: '..(settings.row_limit==0 and 'All' or tostring(settings.row_limit)))
        elseif item=='delay' or (item=='report' and Core.lower(args[3] or '')=='delay') then
            local idx=(item=='report') and 4 or 3; settings.report_delay=Core.clamp(tonumber(args[idx]) or 1.05,0.10,3.00); chat(207,('Report delay %.2fs.'):format(settings.report_delay))
        elseif item=='scope' then local sv=args[3]; if Core.lower(args[3] or '')=='all' and Core.lower(args[4] or '')=='parties' then sv='allparties' end; if not set_scope(sv) then chat(167,'Use //vp set scope <self | local | party | alliance | all | allparties | custom>.'); return end
        elseif item=='report' then
            if Core.lower(args[3] or '')=='content' then local c=Core.lower(args[4] or 'view'); if not Report.SCOPE_SINGLE[c] then chat(167,'Unknown report content. Use view, full, physical, ws, magic, ranged, pet, healing, recovery, defense or percent.'); return end; settings.report_content=Report.SCOPE_SINGLE[c]; chat(207,'Default report content: '..Core.display_word(settings.report_content)..'.')
            else local ok,why=Core.VP.set_report_destination(args[3],args[4]); if not ok then if why=='public' then chat(167,'Public report channels are not supported. Allowed: HUD, Self, Tell, Party, Alliance, Linkshell, Linkshell2.') else chat(167,'Use //vp set report <hud | self | tell <name> | party | alliance | linkshell | linkshell2>.') end; return end; chat(207,'Report destination: '..Core.VP.report_destination_label()) end
        elseif item=='size' or item=='fontsize' then local size=Core.VP.parse_font_size(args[3]); if not size then chat(167,'Use //vp set size <5-36> in 0.25pt increments.'); return end; Core.VP.apply_font_runtime(nil,size); chat(207,('Font size %spt.'):format(Core.VP.font_size_label(size)))
        elseif item=='font' then local name=Core.join({select(3,unpack(args))},' '); if name=='' then chat(207,('Font: %s | Size %spt | Approved: %s'):format(Core.VP.font_name(),Core.VP.font_size_label(),Core.VP.approved_fonts_text())) else local applied,_,ok,msg=Core.VP.apply_font_runtime(name,nil); if ok then chat(207,'Font '..applied..'.') else chat(167,msg) end end
        elseif item=='position' or item=='pos' then local x,y=tonumber(args[3]),tonumber(args[4]); if x and y then hud:pos(x,y); chat(207,('HUD position %d %d.'):format(x,y)) else chat(167,'Use //vp set position <x> <y>.'); return end
        elseif item=='bg' or item=='background' or item=='opacity' then local v=Core.VP.percent_number(args[3]); if not v then chat(167,'Use //vp set bg <0-100 or 0-100%>.'); return end; v=Core.VP.set_active_bg_opacity(v); Core.VP.apply_theme_runtime(); chat(207,('Background opacity %.1f%%.'):format(v))
        elseif item=='theme' then local v=args[3]; if Core.lower(v or '')=='contrast' and (Core.lower(args[4] or '')=='dark' or Core.lower(args[4] or '')=='light') then v='contrast'..Core.lower(args[4]) end; if not Core.VP.set_theme(v) then chat(167,'Theme: dark | light | contrastdark | contrastlight'); return end; chat(207,'Theme '..Core.VP.theme_label(settings.theme)..' | BG '..string.format('%.1f%%',Core.VP.effective_bg_opacity())..'.')
        elseif item=='target' then local mode=Core.lower(args[3] or 'auto'); if mode=='on' or mode=='off' or mode=='auto' then settings.target_hp=mode; chat(207,'Target line '..Core.display_word(mode)..'.') else chat(167,'Use //vp set target <on | off | auto>.'); return end
        elseif item=='wsavg' or item=='wsaverage' then local v=Core.lower(args[3] or 'on'); settings.columns.ws_avg=not (v=='off' or v=='hide' or v=='false' or v=='0'); chat(207,'WS Avg '..Core.VP.wsavg_state()..'.')
        else chat(167,'Set: rows | delay | report | scope | font | size | position | bg | theme | target | wsavg'); return end
    elseif cmd=='view' then
        local value=Core.join({select(2,unpack(args))},' ')
        if not value or value=='' then
            local next_value=nil
            for i,v in ipairs(Core.VP.PRIMARY_VIEW_CYCLE) do if settings.view==v and i<#Core.VP.PRIMARY_VIEW_CYCLE then next_value=Core.VP.PRIMARY_VIEW_CYCLE[i+1]; break end end
            if next_value then value=next_value
            else
                chat(207,'View: Compact | Dynamic | Full | Physical | WS | WS Details | Ranged | Magic | Magic Details | Pet | Healing | Healing Details | Recovery | Recovery Details | Defense')
                return
            end
        end
        if not set_view(value) then chat(167,'View: Compact | Dynamic | Full | Physical | WS | WS Details | Ranged | Magic | Magic Details | Pet | Healing | Healing Details | Recovery | Recovery Details | Defense') else chat(207,'View '..view_display_name(settings.view)..'.') end
    elseif cmd=='mode' or cmd=='scope' then
        local value=args[2]; if not value or value=='' then value=Core.VP.cycle_value(settings.scope,Core.VP.MODE_CYCLE) end; if Core.lower(args[2] or '')=='all' and Core.lower(args[3] or '')=='parties' then value='allparties' end
        if not set_scope(value) then chat(167,'Mode: self | local | party | alliance | all | allparties | custom') else chat(207,'Mode '..Core.VP.scope_label(settings.scope)..'.') end
    elseif cmd=='performance' or cmd=='stat' or cmd=='stats' then
        local source=selected_source(); if not source then chat(167,'No performance data available.'); return end
        local exhaustive=false; local parts={}; for i=2,#args do if Core.lower(args[i])=='all' then exhaustive=true else parts[#parts+1]=args[i] end end
        local name=table.concat(parts,' '); if name=='' then local p=windower.ffxi.get_player(); name=p and p.name or '' end
        local a=Report.find_actor(source,name); if not a then chat(167,'Player not found in selected parse: '..tostring(name)); return end
        Report.performance('local',nil,a,source,exhaustive)
    elseif cmd=='report' then
        local t2=Core.lower(args[2] or ''); if t2=='set' or t2=='mode' or t2=='destination' or t2=='channel' then local ok,why=Core.VP.set_report_destination(args[3],args[4]); if ok then chat(207,'Report destination: '..Core.VP.report_destination_label()) elseif why=='public' then chat(167,'Public report channels are not supported. Allowed: HUD, Self, Tell, Party, Alliance, Linkshell, Linkshell2.') else chat(167,'Use //vp report set <hud | self | tell <name> | party | alliance | linkshell | linkshell2>.') end else Report.send(args) end
    elseif cmd=='job' or cmd=='jobs' then
        local v=Core.lower(args[2] or ''); local op=Core.VP.toggle_word(v)
        if v=='auto' then settings.job_column=true; settings.job_sub_mode='auto'; chat(207,'Job display: '..Core.VP.job_state())
        elseif not op then chat(167,'Job: on | off | toggle | auto | default | status')
        elseif op=='status' then chat(207,'Job display: '..Core.VP.job_state())
        elseif op=='default' then settings.job_column=defaults.job_column; settings.job_sub_mode=defaults.job_sub_mode; chat(207,'Job display: '..Core.VP.job_state())
        else settings.job_column=(op=='toggle') and not settings.job_column or (op=='on'); chat(207,'Job column '..(settings.job_column and 'On' or 'Off')..'.') end
    elseif cmd=='sub' or cmd=='subjob' or cmd=='subjobs' then
        local v=Core.lower(args[2] or ''); local op=Core.VP.toggle_word(v)
        if v=='auto' or op=='default' then settings.job_sub_mode='auto'; settings.subjob=false; settings.job_column=true; chat(207,'Subjob display Auto: Compact Job, other views Job/Sub.')
        elseif not op then chat(167,'Subjob: on | off | toggle | auto | default | status')
        elseif op=='status' then chat(207,'Job display: '..Core.VP.job_state())
        else local on=(op=='toggle') and (settings.job_sub_mode~='on') or (op=='on'); settings.job_sub_mode=on and 'on' or 'off'; settings.subjob=on; settings.job_column=true; chat(207,'Subjob display '..(on and 'On' or 'Off')..'.') end
    elseif cmd=='wsavg' or cmd=='wsaverage' or cmd=='weaponskillavg' then
        local current=settings.columns.ws_avg~=false; local value,state=Core.VP.boolean_toggle(current,defaults.columns.ws_avg,args[2]); if state=='invalid' then chat(167,'WS Avg: on | off | toggle | default | status') elseif state=='status' then chat(207,'WS Avg '..Core.VP.wsavg_state()..'.') else settings.columns.ws_avg=value; chat(207,'WS Avg '..Core.VP.wsavg_state()..'.') end
    elseif cmd=='highlights' or cmd=='highlight' then
        local value,state=Core.VP.boolean_toggle(settings.highlights==true,defaults.highlights,args[2]); if state=='invalid' then chat(167,'Highlights: on | off | toggle | default | status') elseif state=='status' then chat(207,'Highlights '..(settings.highlights and 'On' or 'Off')..'.') else settings.highlights=value; chat(207,'Highlights '..(settings.highlights and 'On' or 'Off')..'.') end
    elseif cmd=='crits' or cmd=='crit' or cmd=='critical' then
        local current=settings.columns.crits==true; local value,state=Core.VP.boolean_toggle(current,defaults.columns.crits,args[2]); if state=='invalid' then chat(167,'Crits: on | off | toggle | default | status') elseif state=='status' then chat(207,'Crits '..(current and 'On' or 'Off')..'.') else settings.columns.crits=value; chat(207,'Crits '..(value and 'On' or 'Off')..'.') end
    elseif Core.VP.display_item_enabled(cmd)~=nil then
        local handled,why=Core.VP.handle_display_toggle(cmd,args[2]); if not handled and why=='invalid' then chat(167,Core.display_word(Core.VP.normalize_display_item(cmd):gsub('_',' '))..': on | off | toggle | default | status') end
    elseif cmd=='font' then
        local sub=Core.lower(args[2] or ''); if sub=='' or sub=='status' then chat(207,('Font: %s | Size %spt | Approved: %s'):format(Core.VP.font_name(),Core.VP.font_size_label(),Core.VP.approved_fonts_text()))
        elseif sub=='list' or sub=='options' then Core.VP.help_options('Approved Fonts',Core.VP.APPROVED_FONTS)
        elseif sub=='size' then local size=Core.VP.parse_font_size(args[3]); if not size then chat(167,'Use //vp font size <5-36> in 0.25pt increments.') else Core.VP.apply_font_runtime(nil,size); chat(207,('Font size %spt.'):format(Core.VP.font_size_label(size))) end
        else local name=Core.join({select(2,unpack(args))},' '); local applied,_,ok,msg=Core.VP.apply_font_runtime(name,nil); if ok then chat(207,'Font '..applied..'.') else chat(167,msg) end end
    elseif cmd=='fontsize' or cmd=='size' then local size=Core.VP.parse_font_size(args[2]); if not size then chat(207,('Font size %spt.'):format(Core.VP.font_size_label())) else Core.VP.apply_font_runtime(nil,size); chat(207,('Font size %spt.'):format(Core.VP.font_size_label(size))) end
    elseif cmd=='bg' or cmd=='background' or cmd=='opacity' then local v=Core.VP.percent_number(args[2]); if not v then chat(207,('Background opacity %.1f%%.'):format(Core.VP.effective_bg_opacity())) else v=Core.VP.set_active_bg_opacity(v); Core.VP.apply_theme_runtime(); chat(207,('Background opacity %.1f%%.'):format(v)) end
    elseif cmd=='theme' then
        local v=args[2]; if Core.lower(v or '')=='contrast' and (Core.lower(args[3] or '')=='dark' or Core.lower(args[3] or '')=='light') then v='contrast'..Core.lower(args[3]) end
        if not v or v=='' then v=Core.VP.cycle_value(settings.theme,Core.VP.THEME_CYCLE) end
        if Core.VP.set_theme(v) then chat(207,'Theme '..Core.VP.theme_label(settings.theme)..' | BG '..string.format('%.1f%%',Core.VP.effective_bg_opacity())..'.') else chat(167,'Theme: dark | light | contrastdark | contrastlight') end
    elseif cmd=='inverse' then settings.theme=(settings.theme=='light') and 'dark' or 'light'; Core.VP.apply_theme_runtime(); chat(207,'Theme '..Core.VP.theme_label(settings.theme)..'.')
    elseif cmd=='local' then if not Core.VP.local_group_command(args) then chat(167,'Local: add <name...> | remove <name> | clear | show') end
    elseif cmd=='split' then handle_split_command(args)
    elseif cmd=='unsplit' then split_view=nil; chat(207,'Showing full session.')
    elseif cmd=='pause' or cmd=='stop' then settings.paused=true; chat(207,'Paused.')
    elseif cmd=='continue' or cmd=='resume' or cmd=='start' then settings.paused=false; chat(207,'Active.')
    elseif cmd=='reset' or cmd=='clear' then full_reset('manual-reset'); chat(207,'Full parse session cleared.')
    elseif cmd=='sort' then
        local raw={}; for i=2,#args do raw[#raw+1]=args[i] end
        local explicit=nil; local tail=Core.lower(raw[#raw] or '')
        if tail=='asc' or tail=='ascending' or tail=='low' or tail=='lowtohigh' then explicit='asc'; table.remove(raw)
        elseif tail=='desc' or tail=='descending' or tail=='high' or tail=='hightolow' then explicit='desc'; table.remove(raw) end
        local subject=Core.join(raw,' ')
        if subject=='' then
            local legacy=settings.sort; if tostring(legacy):find(':',1,true) then legacy='dps' end
            subject=Core.VP.cycle_value(legacy,Core.VP.SORT_CYCLE)
        end
        local token=Core.lower(subject); local target=nil; local label=subject
        if token=='party' then target='party'
        else
            local action=Core.VP.resolve_action_name(subject)
            local cat=normalize_category(subject); local category_set={physical=true,melee=true,ws=true,sc=true,magic=true,mb=true,ranged=true,pet=true,healing=true,recovery=true,defense=true}
            for k in pairs(Core.VP.CATEGORY_PARENT or {}) do category_set[k]=true end
            local field=Core.VP.resolve_field_key(subject)
            local legacy={damage='general.damage',dps='general.avg',accuracy='melee.acc',acc='melee.acc',racc='ranged.acc',wsacc='ws.acc',wsavg='ws.avg',taken='defense.taken',cleanse='recovery.cleanse',cleanses='recovery.cleanse',dispel='recovery.dispel',dispels='recovery.dispel'}
            if legacy[token] then target='field:'..legacy[token]
            elseif field then target='field:'..field
            elseif category_set[cat] then target='category:'..cat
            elseif action then target='action:'..Core.VP.action_key(action); label=action end
        end
        if not target then chat(167,'Unknown Sort target: '..subject..'. Use any category, subcategory, visible metric or known action.'); return end
        if explicit then settings.sort_direction=explicit
        elseif settings.sort==target then settings.sort_direction=(settings.sort_direction=='asc') and 'desc' or 'asc'
        else settings.sort_direction='desc' end
        settings.sort=target
        -- Explicit sort is authoritative: pins are cleared so visible row order matches the selected metric.
        settings.pins={}; settings.self_pin=false; settings.pin_local=false; settings.pin_party=false; settings.pin_alliance=false
        chat(207,'Sort '..tostring(label)..' | '..(settings.sort_direction=='asc' and 'Low to High' or 'High to Low')..'.')
    elseif cmd=='pin' or cmd=='unpin' then
        local target=Core.lower(args[2] or ''); if target=='' then chat(167,'Use //vp '..cmd..' <self | local | party | alliance | player | all | default>.')
        elseif Core.VP.pin_group(cmd,target) then chat(207,Core.display_word(cmd)..' '..Core.display_word(target)..'.')
        else local name=args[2]; if target=='me' then local p=windower.ffxi.get_player(); name=p and p.name or name end; if cmd=='pin' then settings.pins[Core.lower(name)]=tonumber(args[3]) or true; chat(207,'Pinned '..name..'.') else settings.pins[Core.lower(name)]=nil; chat(207,'Unpinned '..name..'.') end end
    elseif cmd=='lock' then settings.hud.flags.draggable=false; hud:draggable(false)
    elseif cmd=='unlock' then settings.hud.flags.draggable=true; hud:draggable(true)
    elseif cmd=='save' then Core.VP.persist_settings(true); chat(207,'Settings saved.')
    elseif cmd=='reload' then Core.VP.persist_settings(true); windower.send_command('lua reload VanaParse'); return
    elseif cmd=='unload' then Core.VP.persist_settings(true); windower.send_command('lua unload VanaParse'); return
    else chat(167,'Unknown command. Use //vp help.') end
    Core.VP.persist_settings(false); update_hud(true)
end
windower.register_event('addon command',function(...) Core.safe_call('addon-command',Core.VP.handle_command,on_error,...) end)

windower.register_event('unload',function() Core.safe_call('unload-save',function() log_source('SESSION',current_source(),Core.now(),'unload'); Core.VP.persist_settings(true) end,on_error) end)
