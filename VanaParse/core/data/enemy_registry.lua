-- VanaCore enemy registry baseline
-- English is the authoritative documentation language. Runtime identity/HPP
-- comes from FFXI; this file supplies only verified optional metadata.
return {
    schema = 1,
    version = '2026.08.20.1',
    records = {
        -- Key format: '<zone id>|<lowercase enemy name>'
        -- Example user/external record:
        -- ['999|example nm'] = {name='Example NM', zone_id=999, max_hp=1000000, confidence='verified'},
    },
}
