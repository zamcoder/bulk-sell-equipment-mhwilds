-- Exports (BulkSell/export.lua): the mhwilds.wiki-db.com line format, CSV, scopes, points.

local export = require("BulkSell.export")
local support = require("analysis_support")
local charm, eq = support.charm, support.eq
local runner = support.runner()
local test = runner.test

local NAMES = { [1] = "Slugger", [2] = "Foray", [3] = "Power Prolonger", [4] = "Water Resistance", [5] = "Attack Boost",
    [6] = "Ambush", [7] = "Dragon Attack", [8] = "Guard", [9] = "Maximum Might" }

test("wiki-db lines match the site's import format (real talismans)", function()
    eq(export.wikidb_line(charm(1, 8, "1:3,2:1", "W1,A1,A1"), NAMES), "Slugger,3,Foray,1,,0,1,1,0,1,0,0")
    eq(export.wikidb_line(charm(2, 8, "3:3,4:3", "W1"), NAMES), "Power Prolonger,3,Water Resistance,3,,0,0,0,0,1,0,0")
    eq(export.wikidb_line(charm(3, 6, "5:2,6:2", "A2,A1"), NAMES), "Attack Boost,2,Ambush,2,,0,2,1,0,0,0,0")
    eq(export.wikidb_line(charm(4, 7, "7:2,8:1,9:1", "A3"), NAMES), "Dragon Attack,2,Guard,1,Maximum Might,1,3,0,0,0,0,0")
end)

test("every slot layout of appraised talismans", function()
    local cases = {
        { "", "0,0,0,0,0,0" }, { "A1", "1,0,0,0,0,0" }, { "A1,A1", "1,1,0,0,0,0" }, { "A1,A1,A1", "1,1,1,0,0,0" },
        { "A2", "2,0,0,0,0,0" }, { "A1,A2", "2,1,0,0,0,0" }, { "A3", "3,0,0,0,0,0" }, { "W1", "0,0,0,1,0,0" },
        { "W1,A1", "1,0,0,1,0,0" }, { "W1,A1,A1", "1,1,0,1,0,0" },
    }
    for _, case in ipairs(cases) do
        local line = export.wikidb_line(charm(1, 5, "5:1", case[1]), NAMES)
        eq(line, "Attack Boost,1,,0,,0," .. case[2], "slots " .. case[1])
    end
end)

test("names never break a line", function()
    eq(export.wikidb_line(charm(1, 5, "1:1"), { [1] = "Odd, Name" }), "Odd  Name,1,,0,,0,0,0,0,0,0,0")
    eq(export.wikidb_line(charm(1, 5, "77:2"), {}), "Skill #77,2,,0,,0,0,0,0,0,0,0", "unknown name")
    eq(export.wikidb({ charm(1, 5, "1:1"), charm(2, 5, "2:1") }, NAMES), "Slugger,1,,0,,0,0,0,0,0,0,0\nForay,1,,0,,0,0,0,0,0,0,0\n")
    eq(export.wikidb({}, NAMES), "", "empty list")
end)

test("scopes", function()
    local charms = { charm(1, 5, "1:1"), charm(2, 5, "2:1"), charm(3, 5, "3:1") }
    local verdicts = { [1] = { action = "keep" }, [2] = { action = "sell" }, [3] = { action = "keep" } }
    eq(#export.select(charms, verdicts, "all"), 3, "all")
    eq(#export.select(charms, verdicts, "stays"), 2, "stays")
    eq(export.select(charms, verdicts, "sell")[1].key, 2, "sell")
end)

test("CSV has a BOM, a header and quoted fields", function()
    local c = charm(9, 7, "5:2,6:1", "W1,A1")
    c.price, c.protected = 4500, nil
    local text = export.csv({ c }, { [9] = { action = "sell", reason = "dominated", ref = 3 } }, NAMES,
        function() return "Sell · covered" end, function() return "Covered by #3 R8 Attack Boost 3, Ambush 2" end)
    eq(text:sub(1, 3), "\239\187\191", "BOM")
    local lines = {}
    for line in text:gmatch("([^\r\n]+)") do lines[#lines + 1] = line end
    eq(lines[1]:sub(4), "box,rarity,skill1,level1,skill2,level2,skill3,level3,slots,armor1,armor2,armor3,weapon1,price,"
        .. "verdict,reason,kept_instead,protected", "header")
    eq(lines[2], '9,7,Attack Boost,2,Ambush,1,,,W1 A1,1,0,0,1,4500,Sell · covered,"Covered by #3 R8 Attack Boost 3, Ambush 2",3,',
        "row")
    eq(text:sub(-2), "\r\n", "CRLF line ends")
end)

test("Melding Pot points", function()
    eq(export.meld_points({ charm(1, 5), charm(2, 6), charm(3, 7), charm(4, 8) }), 20)
end)

runner.run()
