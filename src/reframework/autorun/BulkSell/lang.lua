-- Every text Bulk Sell shows, by key, so the UI can be translated (v0.5.0 adds more
-- languages). T(key, ...) formats the text with string.format; an unknown key is shown
-- as the key itself rather than failing.

local lang = {}

local EN = {
    window_title = "Bulk Sell Equipment",
    version = "Version %s",
    show_window = "Show window",
    hide_window = "Hide window",
    debug_files = "Write debug files (for bug reports)",
    debug_perf = "Last job: %s, %d frames, longest step %.1f ms",
    error = "Error: %s",
    ui_error = "UI error: %s",
    working = "Working...",
    scan = "Scan Equipment Box",
    intro = "Scan reads your talismans. Nothing is sold until you confirm.",
    scanned = "Scanned %s · %d appraised (%d protected) · Box %d / %d (%d free)",
    ok = "OK",
    skill_id = "Skill #%s",
    no_skills = "(no skills)",
    and_more = "... and %d more",

    -- Keep option
    keep = "Keep",
    keep_manual = "Keep everything (sell only what I tick)",
    keep_covered = "Keep every unique talisman (sell duplicates and covered ones)",
    keep_best_n = "Keep the best %d per skill",
    keep_count = "%d to sell (%s z)",
    keep_help = "Bulk Sell asks of every appraised talisman: do you still need it?\n"
        .. "Never sold: equipped, in a loadout, favorite, with decorations, or with an RNG Charm Crafting bonus.\n"
        .. "Keep every unique talisman: only duplicates and talismans that a kept talisman matches or beats\n"
        .. "on every skill and slot are sold.\n"
        .. "Keep the best N per skill: for every skill and every slot shape your N best talismans stay;\n"
        .. "every other unique talisman up to your rarity limit is sold.\n"
        .. "Your ticks beat the rules, and nothing is sold until you confirm.",
    rarity_limit = "Sell unique talismans only up to rarity",
    rarity_hint = "Limited to R%d. Up to R8, best %d would sell %d (%s z).",
    always_keep_title = "Always keep (never sold as unique) talismans with:",
    always_keep_add = "Add Always keep",
    skill = "Skill",
    min_level = "Min level",
    remove = "Remove",

    -- Summary
    summary_line = "Sell %d · keep %d · about %s z · box after the sale %s / %s",
    summary_detail = "Duplicates %d · covered %d · unique %d · your picks %d (sell %d / keep %d) · protected %d · "
        .. "R5 %d  R6 %d  R7 %d  R8 %d",
    promise_best = "Your best %d for every skill and slot shape stay. No skill level leaves your box.",
    promise_covered = "Only duplicates and covered talismans are sold. No skill level leaves your box.",
    warn_losses = "%d planned sales lower a skill or remove a slot shape (listed when you press Sell).",

    -- Selling
    sell_all = "Sell %d talismans",
    sell_shown = "Sell the %d shown",
    sell_one = "Sell just 1 (test)",
    empty_covered = "Nothing more to sell: every talisman is unique. To free space, choose \"Keep the best N per skill\" above.",
    empty_manual = "Nothing is ticked. Tick talismans in the list, or choose another Keep option above.",
    empty_best = "Nothing to sell with these settings.",
    updating = "Updating the list...",
    rescanning = "The box may have changed. Rescanning...",
    continue_without_picks = "Continue without my picks",
    notice_list_changed = "The list changed; review and press Sell again.",
    notice_picks_not_saved = "Your picks could not be saved; see the REFramework log.",
    notice_picks_removed = "%d picks removed: %s",
    confirm_question = "Sell %s for %s z? This cannot be undone.",
    confirm_one = "1 talisman (%s)",
    confirm_many = "%d talismans",
    confirm_unique = "%d are unique: no identical or better talisman stays. For each of their skills and slot shapes "
        .. "you keep at least %d that rank higher.",
    confirm_picks = "%d of them are your Sell picks.",
    confirm_share = "That is %d%% of your appraised talismans.",
    ack_unique = "I understand that unique talismans are sold.",
    loss_title = "This sale removes:",
    loss_skill_lower = "%s %d (best left %d) %s",
    loss_skill_gone = "%s %d (none left) %s",
    loss_shape = "slot shape %s (none left) #%d",
    ack_loss = "I accept losing these.",
    yes_sell = "Yes, sell",
    cancel = "Cancel",
    selling_progress = "Selling... %d / %d  (%s z)",
    stop = "Stop",
    sold_result = "Sold %d talismans for %s z.",
    sold_skipped = "%d were kept after a last check (changed, equipped, favorite...).",
    stopped = "Stopped: %s",
    receipt = "Receipt: reframework/data/%s",
    stop_by_you = "you pressed Stop.",
    stop_menu_closed = "the REFramework menu was closed.",
    stop_error = "Error: %s",
    stop_plan_mismatch = "The sale list does not match the plan; nothing more was sold.",
    skip_kept_instead_gone = "the talisman kept instead is gone",
    skip_kept_for_changed = "a talisman kept for its skills changed (#%d)",

    -- Table
    show = "Show",
    filter_to_sell = "To sell",
    filter_to_keep = "To keep",
    filter_all = "All",
    filter_picks = "Your picks",
    filter_unique = "Unique sales",
    find = "Find",
    shown_line = "%d shown (%d to sell, %s z) ·",
    mark_shown = "Mark shown:",
    mark_sell = "Sell",
    mark_keep = "Keep",
    mark_auto = "Auto",
    undo = "Undo",
    page = "Page %d / %d",
    col_sell = "Sell",
    col_box = "Box",
    col_talisman = "Talisman",
    col_slots = "Slots",
    col_price = "Price",
    col_verdict = "Verdict",
    col_why = "Why",

    -- Verdicts
    v_keep = "Keep",
    v_keep_protected = "Keep · protected",
    v_keep_pick = "Keep · your pick",
    v_keep_best_n = "Keep · best %d",
    v_keep_always = "Keep · Always keep",
    v_keep_rarity = "Keep · above R%d",
    v_keep_not_ticked = "Keep · not ticked",
    v_keep_held_back = "Keep · held back",
    v_sell_pick = "Sell · your pick",
    v_sell_unique = "Sell · unique",
    v_sell_duplicate = "Sell · duplicate",
    v_sell_covered = "Sell · covered",

    -- Why
    why_same_as = "Same as #%d (kept)",
    why_covered_by = "Covered by #%d %s",
    why_ignoring = " (ignoring %s)",
    why_not_in_best = "Not in your best %d",
    why_closest = "closest %s",
    why_beaten_by_sold = "beaten by a talisman that is also sold",
    why_rank_skill = "%s #%d of %d",
    why_rank_shape = "Slot shape %s #%d of %d",
    why_pick = "Your pick",
    why_pick_covered = "Your pick (covered by #%d)",
    why_pick_unique = "Your pick (unique)",
    why_last_skill = "LAST %s %d",
    why_last_shape = "LAST %s talisman",
    why_always_keep = "Always keep %s %d+",
    why_rarity = "Unique; you sell up to R%d",
    why_auto_off = "You keep everything; tick it to sell",
    why_safety_check = "Held back by a safety check - please report",
    why_best = "Nothing kept matches or beats it",
    why_protected_equipped = "Equipped",
    why_protected_loadout = "In a loadout",
    why_protected_favorite = "Favorite: remove the star in game to sell it",
    why_protected_decorations = "Has decorations: remove them in game to sell it",
    why_protected_bonus = "RNG Charm Crafting bonus",
}

lang.EN = EN
local current = EN

function lang.T(key, ...)
    local text = current[key] or EN[key]
    if not text then return key end
    if select("#", ...) == 0 then return text end
    local ok, result = pcall(string.format, text, ...)
    return ok and result or text
end

return lang
