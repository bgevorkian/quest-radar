local _, ns = ...
ns.ByID, ns.ByMap = {}, {}
for _, q in ipairs(ns.Quests) do
    ns.ByID[q.id] = ns.ByID[q.id] or {}
    table.insert(ns.ByID[q.id], q)
    for _, point in ipairs(q.points) do
        ns.ByMap[point[1]] = ns.ByMap[point[1]] or {}
        table.insert(ns.ByMap[point[1]], {quest=q, point=point})
    end
end
local function contains(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end
function ns.CharacterFits(q, ctx)
    for _, c in ipairs(q.constraints) do
        if c.r and c.r ~= ctx.faction then return false end
        if c.c and not contains(c.c, ctx.class) then return false end
        if c.races and not contains(c.races, ctx.race) then return false end
    end
    return true
end
local function dependencyFits(id, ctx)
    local variants = ns.ByID[math.abs(id)]
    if not variants then return nil end
    for _, q in ipairs(variants) do if ns.CharacterFits(q, ctx) then return true end end
    return false
end
local function breadcrumb(id, ctx)
    for _, q in ipairs(ns.ByID[math.abs(id)] or {}) do
        if ns.CharacterFits(q,ctx) then
            for _, c in ipairs(q.constraints) do if c.isBreadcrumb then return true end end
        end
    end
    return false
end
-- Result: hidden, calculated, uncertain. Only live dialogue can confirm an offer.
function ns.Evaluate(q, ctx)
    if not ns.CharacterFits(q, ctx) then return "hidden", "Другой класс, раса или фракция" end
    local active=ctx.onQuest(q.id)
    if active then return "hidden", "Уже в журнале" end
    local uncertain = #q.uncertain > 0
    local reasons = {}
    for _, reason in ipairs(q.uncertain) do reasons[#reasons+1] = reason end
    local function unknown(reason) uncertain=true; reasons[#reasons+1]=reason end
    if active==nil then unknown("Журнал заданий недоступен") end
    local recurring = false
    for _, c in ipairs(q.constraints) do
        recurring = recurring or c.repeatable or c.isDaily or c.isWeekly or c.isYearly or c.isMonthly
    end
    local done = ctx.completed(q.id)
    if done and not recurring then return "hidden", "Уже выполнено" end
    if done == nil then unknown("История выполненных заданий недоступна") end
    if recurring then unknown("Повторяемое задание: готовность нужно проверить") end
    for _, c in ipairs(q.constraints) do
        if c.u then return "hidden", "Помечено в ATT как недоступное" end
        local level = type(c.lvl)=="table" and c.lvl[1] or c.lvl
        if level and ctx.level < level then return "hidden", "Нужен уровень "..level end
        if c.requireSkill then
            local rank = ctx.skill(c.requireSkill)
            if rank == nil then unknown("Не удалось проверить профессию")
            elseif rank < (tonumber(c.learnedAt) or 1) then return "hidden", "Не подходит профессия или её уровень" end
        end
        for _, field in ipairs({"minReputation", "maxReputation"}) do
            local rep = c[field]
            if rep then
                local value = ctx.reputation(rep[1])
                if value == nil then unknown("Не удалось проверить репутацию")
                elseif field == "minReputation" and value < rep[2] then return "hidden", "Недостаточная репутация"
                elseif field == "maxReputation" and value >= rep[2] then return "hidden", "Превышено ограничение репутации" end
            end
        end
        for _, id in ipairs(c.altQuests or {}) do
            if ctx.completed(id) then return "hidden", "Выполнено альтернативное задание" end
        end
        if c.sourceQuests then
            local eligible, complete, unknownCount = 0, 0, 0
            for _, id in ipairs(c.sourceQuests) do
                local fits = dependencyFits(id, ctx)
                if fits ~= false then
                    eligible = eligible + 1
                    local state
                    if id < 0 then state = ctx.onQuest(-id) else state = ctx.completed(id) end
                    if state then complete=complete+1
                    elseif state == nil or fits == nil or breadcrumb(id,ctx) then unknownCount=unknownCount+1 end
                end
            end
            local required = c.sqreq or eligible
            if eligible == 0 then unknown("Нет подходящей ветки предшественников")
            elseif complete < required then
                if complete + unknownCount < required then return "hidden", "Не выполнены предыдущие задания" end
                unknown("Не удалось проверить часть предшественников")
            end
        end
    end
    return uncertain and "uncertain" or "calculated", table.concat(reasons, "; ")
end
