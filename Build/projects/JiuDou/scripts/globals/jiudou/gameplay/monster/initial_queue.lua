--- 首波怪物队列。
--- 仅决定初始槽位的创建顺序：优先玩家所在区域，其余槽位随后补齐。
--- 槽位本身持有独立随机流，改变队列调度实现不会改变生成结果。
local module = {}

---@param slots MonsterSlot[]
---@param hero_results HeroSelectionResult[]
---@param initial_slot_count integer 仅普通与精英的槽位数量，Boss 不参与首波生成
---@return MonsterSlot[] queue
function module.build(slots, hero_results, initial_slot_count)
    local priority_blocks = {}
    for _, result in ipairs(hero_results or {}) do
        priority_blocks[result.blockId] = true
    end

    local queue = {}
    local last_index = math.min(#(slots or {}), math.max(0, math.floor(tonumber(initial_slot_count) or 0)))
    for priority_pass = 1, 2 do
        local want_priority = priority_pass == 1
        for index = 1, last_index do
            local slot = slots[index]
            local is_priority = priority_blocks[slot.blockId] == true
            if is_priority == want_priority then
                table.insert(queue, slot)
            end
        end
    end
    return queue
end

return module
