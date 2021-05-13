-- ========================================================================= --
-- -- CONSTANTS ------------------------------------------------------------ --
-- ========================================================================= --

-- ========================================================================= --
-- -- CLASSES -------------------------------------------------------------- --
-- ========================================================================= --

--[[ RECOMMENDATION ENGINES ]]-------------------------------------------------

--fpp:include "engine/cb_engine.lua"
--fpp:include "engine/tcr_engine.lua"

--[[ RE-RANKING ALGORITHMS ]]--------------------------------------------------

--fpp:include "reranker/epsilon_dithering_reranker.lua"

--[[ UTILITIES ]]--------------------------------------------------------------

--fpp:include "common/interner.lua"

local Logger = {};
Logger.new = function (config)
  local self = {};

  local function tostring(value)
    local str = ''

    if (type(value) ~= 'table') then
      if (type(value) == 'string') then
        str = string.format("%q", value)
      else
        str = _tostring(value)
      end
    else
      local auxTable = {}
      for key in pairs(value) do
        if (tonumber(key) ~= key) then
          table.insert(auxTable, key)
        else
          table.insert(auxTable, tostring(key))
        end
      end
      table.sort(auxTable)
    
      str = str..'{'
      local separator = ""
      local entry = ""
      for _, fieldName in ipairs(auxTable) do
        if ((tonumber(fieldName)) and (tonumber(fieldName) > 0)) then
          entry = tostring(value[tonumber(fieldName)])
        else
          entry = fieldName.." = "..tostring(value[fieldName])
        end
        str = str..separator..entry
        separator = ", "
      end
      str = str..'}'
    end
    return str
  end

  self.debug = function (fmt, ...)
    if (type(fmt) == 'table') then
      print(tostring(fmt));
    else
      print(string.format(fmt, ...));
    end
  end
  return self;
end

-- ========================================================================= --
-- -- FUNCTIONS ------------------------------------------------------------ --
-- ========================================================================= --

-- A polymorphic function to record interactions with multiple engines at once.
local function recordInteractionPolymorphic (engines, interaction)
  local user_token_pool = Interner.new({
    prefix = 'utp:',
    logger = redis,
    store = redis
  });
  local item_token_pool = Interner.new({
    prefix = 'itp:',
    logger = redis,
    store = redis
  });

  interaction.userId = tostring(user_token_pool.idOf(interaction.userId));
  interaction.itemId = tostring(item_token_pool.idOf(interaction.itemId));

  for k, v in pairs(engines)
  do
    v.recordInteraction(interaction);
  end
end -- recordInteractionPolymorphic()

-------------------------------------------------------------------------------

-- A polymorphic function to recommend from multiple engines at once.
local function getRecommendationsPolymorphic (engines, user_id)
  local user_token_pool = Interner.new({
    prefix = 'utp:',
    logger = redis,
    store = redis
  });

  local recs = {};
  for k, v in pairs(engines)
  do
    recs[k] = v.getRecommendations(tostring(user_token_pool.idOf(user_id,
      type(user_id), false)));
  end

  return recs;
end -- getRecommendationsPolymorphic()

-- ========================================================================= --
-- -- ACCESSOR ------------------------------------------------------------- --
-- ========================================================================= --

--[[
-- The bread and butter of our script.
--]]
local function main (
  -- luacheck: no unused args
  argc,
  argv
)

  if _G.redis then
    redis.log(redis.LOG_DEBUG, "we're running real redis");
  else
    redis.log(redis.LOG_DEBUG, "we're running fake redis");
  end

  if (2 ~= argc) then
    return redis.error_reply('Invalid number of arguments.')
  end

  local time = tonumber(argv[1]);
  math.randomseed(time);

  local svc_user_id = argv[2];

  -- Instantiate multiple engines
  local engines = {
    cbe = CBEngine.new('cbe'),
    tcre = TCREngine.new({
      prefix = 'tcre:',
      logger = Logger.new(),
      store = redis
    });
  };

  -- Instantiate our re-ranker
  local edr = EpsilonDitheringReranker.new({ epsilon = 1.25 });

  if (math.random() < 0.5) then
    recordInteractionPolymorphic(engines, {
      userId = svc_user_id,
      itemId = 'item-001',
      event_type = 'impression',
      weight = 0
    });
  end
  if (math.random() < 0.5) then
    recordInteractionPolymorphic(engines, {
      userId = svc_user_id,
      itemId = 'item-001',
      event_type = 'click',
      weight = 2
    });
  end
  if (math.random() < 0.5) then
    recordInteractionPolymorphic(engines, {
      userId = svc_user_id,
      itemId = 'item-002',
      event_type = 'click',
      weight = 2
    });
  end
  if (math.random() < 0.5) then
    recordInteractionPolymorphic(engines, {
      userId = svc_user_id,
      itemId = 'item-003',
      event_type = 'click',
      weight = 2
    });
  end
  if (math.random() < 0.5) then
    recordInteractionPolymorphic(engines, {
      userId = svc_user_id,
      itemId = 'item-004',
      event_type = 'add-to-cart',
      weight = 4
    });
  end
  if (math.random() < 0.5) then
    recordInteractionPolymorphic(engines, {
      userId = svc_user_id,
      itemId = 'item-002',
      event_type = 'buy',
      weight = 5
    });
  end

  -- Get recommendations for this user.
  local all_engine_recommendations = getRecommendationsPolymorphic(engines,
    svc_user_id);
  redis.debug(all_engine_recommendations);

  -- Rerank the results to shuffle them a little.
  local tcre_recommendations = all_engine_recommendations.tcre;
  local recommendations = edr.rerank(svc_user_id, tcre_recommendations);
  redis.debug(recommendations);

  -- Convert to a format Redis can return.
  local item_token_pool = Interner.new({
    prefix = 'itp:',
    logger = redis,
    store = redis
  });
  local retval = {};
  for ii = 1, #recommendations
  do
    retval[#retval + 1] = item_token_pool.valueOf(recommendations[ii].id);
    retval[#retval + 1] = tostring(recommendations[ii].score);
  end

  return retval;
end -- main()

-- ========================================================================= --
-- -- ENTRYPOINT ----------------------------------------------------------- --
-- ========================================================================= --

-- Call accessor
-- luacheck: globals KEYS
if not KEYS then
  KEYS = {};
end
return main(#KEYS, KEYS);
