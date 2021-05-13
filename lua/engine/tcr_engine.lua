--fpp:ifndef TCR_ENGINE_LUA              /* Guard against multiple inclusion */
--fpp:define TCR_ENGINE_LUA
--[[                                                   :vi set ts=2 et sw=2: **
** ========================================================================= **
**                ____                            __    _ __                 **
**               / __ \___  _________  ____ ___  / /   (_) /____             **
**              / /_/ / _ \/ ___/ __ \/ __ `__ \/ /   / / __/ _ \            **
**             / _, _/  __/ /__/ /_/ / / / / / / /___/ / /_/  __/            **
**            /_/ |_|\___/\___/\____/_/ /_/ /_/_____/_/\__/\___/             **
**                                                                           **
** ========================================================================= **
**           TENCENTREC ITEM-BASED COLLABORATIVE FILTERING ENGINE            **
** ========================================================================= **
** RecomLite Recommender System                                              **
** Copyright (C) Jonah H. Harris <jonah.harris@gmail.com>                    **
** All Rights Reserved.                                                      **
**                                                                           **
** Permission to use, copy, modify, and/or distribute this software for any  **
** purpose is subject to the terms specified in the License Agreement.       **
** ========================================================================= **
**                                                                           **
** Calculate Member-to-Member Jaccard Scores (Distributed Variant)           **
** ---------------------------------------------------------------           **
**                                                                           **
** DESCRIPTION                                                               **
**  This script handles all REDIS actions necessary to perform a Maidenpool  **
**  Jaccard score calculation between members and return the results to the  **
**  caller.                                                                  **
**                                                                           **
**  For performance reasons, scores computed by this process are cached      **
**  locally for a period of time.                                            **
**                                                                           **
**  NOTE:                                                                    **
**    This variant of the code has been designed to run in a distributed     **
**    fashion, where the interaction data for the primary member the         **
**    comparisons are being performed for ARE NOT on this shard and,         **
**    accordingly, has been passed-in by the caller. It is the caller's      **
**    responsiblity to the member-to-shard mapping.                          **
**                                                                           **
**  SEE ALSO:                                                                **
**    - C-based Aphrodite Interaction Store                                  **
**      - Performs Jaccard score calculation using optimized trees.          **
**    - C-based Aphrodite Sketch Store                                       **
**      - Performs Jaccard score approximation using HyperMinHash.           **
**                                                                           **
** USAGE                                                                     **
**  EVALSHA <SHA>                                                            **
**    #                                                                      **
**    member_id                                                              **
**    #                                                                      **
**    [member_set ...]                                                       **
**    interaction_type                                                       **
**    direction                                                              **
**    [local_ids_to_intersect ...]                                           **
**                                                                           **
** EXAMPLE                                                                   **
**  EVALSHA <SHA> 7 179 2 166 2205 pv in 179                                 **
** ======================================================================= --]]

-- ========================================================================= --
-- -- INCLUSIONS ----------------------------------------------------------- --
-- ========================================================================= --

--fpp:include "abstract_engine.lua"
--fpp:include "../common/types.lua"

-- ========================================================================= --
-- -- GLOBALS -------------------------------------------------------------- --
-- ========================================================================= --

-- luacheck: globals table, globals redis, ignore unpack
local unpack = table.unpack;

-- luacheck: push ignore TCREngine
local TCREngine = {};
-- luacheck: pop

-- ========================================================================= --
-- -- CLASS DEFINITIONS ---------------------------------------------------- --
-- ========================================================================= --

--[[
-- A Redis+Lua-based implementation of the TencentRec Engine.
--]]
TCREngine.new = function (config)

  -----------------------------------------------------------------------------
  --[[ PROPERTIES ]]-----------------------------------------------------------
  -----------------------------------------------------------------------------

  -- Validate passed-in configuration.
  if (type(config) ~= 'table'
    or type(config.prefix) ~= 'string'
    or type(config.logger) ~= 'table'
    or type(config.logger.debug) ~= 'function'
    or type(config.store) ~= 'table'
    or type(config.store.call) ~= 'function')
  then
    error('invalid configuration.');
  end

  -- luacheck: globals AbstractEngine
  local self = AbstractEngine.new()

  --[[
  -- The full (descriptive) name of this engine.
  --]]
  self._name = 'TencentRec Item-based Collaborative Filtering Engine';

  --[[
  -- The prefix this engine uses to distinguish its keys.
  --]]
  self._short_name = 'tcre';

  --[[
  -- This is the configuration for our instance.
  --]]
  self._config = config;

  --[[
  -- The passed-in prefix used for all keys accessed by this interner.
  --]]
  self._prefix = config.prefix;

  --[[
  -- The passed-in logger to use.
  --]]
  self._logger = config.logger;

  --[[
  -- The passed-in store to use.
  --]]
  self._store = config.store;

  --[[
  -- keys
  --]]
  self._keys = {
    --[[
    -- This sequence key represents the primary key for interned tokens. It
    -- should *always* contain the highest sequence value and be incremented
    -- atomically.
    --]]
    sequence = (self._prefix .. ':id'),

    --[[
    -- This key, a hashmap, stores one entry for each distinct token value
    -- interned by token (field) to token id (value). This is used for
    -- forward lookups.
    --]]
    forward_hash = (self._prefix .. ':fh'),

    --[[
    -- This key, a hashmap, stores one entry for each distinct token value
    -- interned by token id (field) to token (value). This is used for
    -- reverse lookups.
    --]]
    reverse_hash = (self._prefix .. ':rh'),

    --[[
    -- This key, a hashmap, stores one entry for each distinct token value
    -- interned by token id (field) to type (value).
    --]]
    type_hash = (self._prefix .. ':th'),

    --[[
    -- This key, a hashmap, stores one entry for each distinct item-to-item
    -- pair keyed by least_item_id:greatest_item_id (field) with score (value).
    --]]
    item_sims_hash = table.concat({ self._prefix, 'h:i:s' }, ''),

    --[[
    -- This key, a sorted set, stores one entry for each item keyed by item_id
    -- (field) with count (value).
    --]]
    item_counts_zset = table.concat({ self._prefix, 'z:i:c' }, ''),

    --[[
    -- This key, a sorted set, stores one entry for each distinct item-to-item
    -- pair keyed by least_item_id:greatest_item_id (field) with count (value).
    --]]
    item_pair_count_zset = table.concat({ self._prefix, 'z:i:pc' }, '')
  };

  -----------------------------------------------------------------------------
  --[[ PRIVATE METHODS ]]------------------------------------------------------
  -----------------------------------------------------------------------------

  --[[
  -- Composes two ids into a pair.
  --]]
  local function composeItemPairHashFieldKey (
    firstItemId,
    secondItemId
  )
    assert(firstItemId);
    assert(secondItemId);
    local ids = { tostring(firstItemId), tostring(secondItemId) };
    table.sort(ids);
    return table.concat(ids, ':');
  end -- composeItemPairHashFieldKey()

  -----------------------------------------------------------------------------

  local function composeItemSimilarityZSetKey (item_id)
    assert(item_id);
    return string.format('%sz:i:%s:s', self._prefix, item_id);
  end -- TCREngine::private composeItemSimilarityZSetKey()

  -----------------------------------------------------------------------------

  local function composeMethodName (
    method_name
  )
    return table.concat({ self._short_name, method_name }, '::');
  end -- TCREngine::private composeItemPairHashFieldKey()

  -----------------------------------------------------------------------------

  local function composeUserInterestHashKey (user_id)
    assert(user_id);
    return string.format('%sh:u:%s:i', self._prefix, user_id);
  end -- TCREngine::private composeUserInterestHashKey()

  -----------------------------------------------------------------------------

  local function getItemCount (
    itemId
  )
    local logger = self._logger;
    local store = self._store;

    logger.debug('getting item (%s) count', itemId);
    return store.call('zscore', self._keys.item_counts_zset, itemId);
  end -- TCREngine::private getItemCount()

  -----------------------------------------------------------------------------

  local function getPairCount (
    itemPairKey
  )
    local logger = self._logger;
    local store = self._store;

    logger.debug('getting pair (%s) count', itemPairKey);
    return tonumber(store.call('zscore', self._keys.item_pair_count_zset,
      itemPairKey));
  end -- TCREngine::private getPairCount()

  -----------------------------------------------------------------------------

  --[[
  -- Retrieves the user's items.
  --]]
  local function getUserItems (
    userId
  )
    local logger = self._logger;
    local store = self._store;
    logger.debug('getting user (%s) items', userId);
    local items = store.call('hgetall', composeUserInterestHashKey(userId));
    if (0 == #items) then
      return nil;
    end

    -- Convert Redis hash result to table
    local user = {};
    for ii = 1, #items, 2
    do
      user[items[ii]] = tonumber(items[(ii + 1)]);
    end

    return user;
  end -- TCREngine::private getUserItems()

  -----------------------------------------------------------------------------

  --[[
  -- Updates the count (i.e. the sum of all event weights) for a given item.
  --]]
  local function incrementItemCount (
    itemId,
    deltaWeight
  )
    local logger = self._logger;
    local store = self._store;

    logger.debug('incrementing item (%s) count by weight (%f)', itemId,
      deltaWeight);

    return store.call('zincrby', self._keys.item_counts_zset, deltaWeight,
      itemId);
  end -- TCREngine::private incrementItemCount()

  -----------------------------------------------------------------------------

  local function incrementPairCount (
    itemPairKey,
    deltaCoRating
  )
    local logger = self._logger;
    local store = self._store;

    logger.debug('incrementing pair (%s) count (%f)', itemPairKey,
      deltaCoRating);
    store.call('zincrby', self._keys.item_pair_count_zset, deltaCoRating,
      itemPairKey);
  end -- TCREngine::private incrementPairCount()

  -----------------------------------------------------------------------------

  --[[
  -- Composes two ids into a pair.
  --]]
  local function setItemSimilarity (
    firstItemId,
    secondItemId,
    similarityScore
  )
    local logger = self._logger;
    local store = self._store;

    logger.debug('saving similarity (%f) between items (%s and %s)',
      similarityScore, firstItemId, secondItemId);

    store.call('zadd', composeItemSimilarityZSetKey(firstItemId),
      similarityScore, secondItemId);

    store.call('zadd', composeItemSimilarityZSetKey(secondItemId),
      similarityScore, firstItemId);

    store.call('hset', self._keys.item_sims_hash, composeItemPairHashFieldKey(
      firstItemId, secondItemId), similarityScore);
  end -- TCREngine::_saveSimilarity()

  -----------------------------------------------------------------------------

  --[[
  -- Composes two ids into a pair.
  --]]
  local function updateItemSimilarity (
    firstItem,
    newItemCount,
    secondItem,
    pairCount
  )
    local __FUNC__ = 'updateItemSimilarity';
    local logger = self._logger;

    local secondItemCount = getItemCount(secondItem);
    if (nil == secondItemCount) then
      local err = (composeMethodName(__FUNC__) .. ': ' ..
        'a count for item (' .. secondItem .. ') does not exist.');
      logger.debug(err);
      return redis.error_reply(err);
    end

    secondItemCount = tonumber(secondItemCount);
    if (not is_integer(secondItemCount) and secondItemCount > 0) then
      local err = (composeMethodName(__FUNC__) .. ': ' ..
        'secondItemCount (' .. secondItemCount .. ') is not a number.');
      logger.debug(err);
      return redis.error_reply(err);
    end

    setItemSimilarity(firstItem, secondItem,
      (pairCount / (math.sqrt(newItemCount) * math.sqrt(secondItemCount))));
  end -- TCREngine::_updateItemSimilarity()

  -----------------------------------------------------------------------------

  --[[
  -- Composes two ids into a pair.
  --]]
  local function updatePairCount (
    eventItemId,
    currentItemWeight,
    newItemWeight,
    newItemCount,
    anotherItemId,
    anotherItemWeight
  )
    local deltaCoRating = 0;
    if (0 == currentItemWeight) then
      deltaCoRating = math.min(newItemWeight, anotherItemWeight);
    elseif (currentItemWeight < anotherItemWeight) then
      if (newItemWeight < anotherItemWeight) then
        deltaCoRating = (newItemWeight - currentItemWeight);
      else
        deltaCoRating = (anotherItemWeight - currentItemWeight);
      end
    end

    local itemPairKey = composeItemPairHashFieldKey(eventItemId,
      anotherItemId);
    local currentPairCount = getPairCount(itemPairKey);

    --if (nil == currentPairCount) then
    if (type(currentPairCount) ~= 'number') then
      currentPairCount = 0;
    end

    if (0 ~= deltaCoRating) then
      incrementPairCount(itemPairKey, deltaCoRating);
    end

    updateItemSimilarity(eventItemId, newItemCount, anotherItemId,
      (currentPairCount + deltaCoRating));
  end -- TCREngine::_updatePairCount()

  -----------------------------------------------------------------------------

  --[[
  -- Composes two ids into a pair.
  --]]
  local function updatePair (
    eventItemId,
    currentItemWeight,
    newItemWeight,
    newItemCount,
    anotherItem
  )
    local logger = self._logger;
    logger.debug('update pair %s:%s', eventItemId, anotherItem.item_id);
    local anotherItemId = anotherItem.item_id;
    local anotherItemWeight = anotherItem.weight;
    updatePairCount(eventItemId, currentItemWeight, newItemWeight,
      newItemCount, anotherItemId, anotherItemWeight);
  end -- TCREngine::_updatePair()

  -----------------------------------------------------------------------------

  --[[
  -- Composes two ids into a pair.
  --]]
  local function recalculateSimilarity (
    user,
    item_id,
    current_weight,
    new_weight
  )
    local __FUNC__ = 'recalculateSimilarity';
    local logger = self._logger;

    local currentItemCount = getItemCount(item_id);
    if (false == currentItemCount) then
      local err = (composeMethodName(__FUNC__) .. ': ' ..
        'a count for item (' .. item_id .. ') does not exist.');
      logger.debug(err);
      currentItemCount = 0;
    end

    local itemCountDelta = (new_weight - current_weight);
    incrementItemCount(item_id, itemCountDelta);
    local newItemCount = (currentItemCount + itemCountDelta);
    for another_item_id, another_item_value in pairs(user)
    do
      if (another_item_id ~= item_id) then
        updatePair(item_id, current_weight, new_weight, newItemCount,
          { item_id = another_item_id, weight = another_item_value });
      end
    end

    return (true);
  end -- TCREngine::_recalculateSimilarity()

  -----------------------------------------------------------------------------

  --[[
  -- Composes two ids into a pair.
  --]]
  self._track_event = function (
    user_id,
    item_id,
    event_type,
    weight
  )
    local logger = self._logger;
    local store = self._store;
    local user_key = composeUserInterestHashKey(user_id);

    logger.debug("track_event");
    --[[
    -- If this event is an impression, we only need to record it for
    -- statistics, not for recommendation.
    --]]
    if ('impression' == event_type) then
      return false;
    end

    -- Fetch user
    local user = getUserItems(user_id);
    if (nil == user) then
      logger.debug('saving new user (%s) for item (%s) by weight (%f)',
        user_id, item_id, weight);
      --self._saveNewUser(user_id, item_id, weight);
      store.call('hset', user_key, item_id, weight);
      incrementItemCount(item_id, weight);
      return;
    end

    local newWeight = weight;
    local currentWeight = 0.0;
    if (nil ~= user[item_id]) then
      currentWeight = user[item_id];
    end

    if (currentWeight >= newWeight) then
      return;
    end

    store.call('hset', user_key, item_id, newWeight);
    return recalculateSimilarity(user, item_id, currentWeight, newWeight);
  end -- TCREngine::_track_event()

  -----------------------------------------------------------------------------

  --[[
  -- Composes two ids into a pair.
  --]]
  self.getRecommendations = function (
    user_id,
    limit
  )
    local logger = self._logger;
    local store = self._store;

    limit = limit or 10;
    local userItems = getUserItems(user_id);

    redis.debug(userItems);
    if (nil == userItems) then
      return {};
    end

    --[[
     * For each item the user has interacted with, fetch the top N similar
     * items.
     *
     * NOTE: This should be done in parallel.
     *  1. Fetch all items the user has interacted with.
     *  2. Batch all (item_id, weight) tuples such that they can be sent as a
     *     single request to each item server.
     *  3. Return the results.
    ]]--
    local itemSimilarities = {};
    for item_id, item_value in pairs(userItems)
    do
      local counter = 0;
      local similarities = {};
      local similarItems = store.call('zrevrangebyscore',
        composeItemSimilarityZSetKey(item_id),
        '+inf', '-inf', 'withscores', 'limit', 0, 100);
      --logger.debug("similarItems for " .. item_id);
      logger.debug('similarItems...');
      redis.debug(similarItems);
      --local sims = similarItems;

      local sims = {};
      for ii = 1, #similarItems, 2
      do
        sims[similarItems[ii]] = tonumber(similarItems[ii + 1]);
      end
      logger.debug('sims...');
      redis.debug(sims);

      for similar_item_id, similar_item_value in pairs(sims)
      do
        redis.debug(similar_item_id);
        redis.debug(similar_item_value);
        -- Prune recommended items by those already purchased.
        if (nil == userItems[similar_item_id]
          or 5 ~= userItems[similar_item_id])
        then
          table.insert(similarities, {
            item_id,
            similar_item_id,
            similar_item_value
          });

          -- Top-N
          counter = (counter + 1);
          if (limit == counter) then
            break;
          end
        end
      end
      --logger.debug("-- SIMILARITIES");
      --redis.debug(similarities);

      if (0 < #similarities) then
        table.insert(itemSimilarities, {
          {
            item_id,
            item_value
          },
          similarities
        });
      end
    end
    logger.debug("-- ITEM SIMILARITIES");
    redis.debug(itemSimilarities);

    -- Predict the user's weight for each recommended item
    local scores = {};
    for ii = 1, #itemSimilarities
    do
      local item = itemSimilarities[ii][1];
      local sims = itemSimilarities[ii][2];
      logger.debug("-- item " .. ii);
      redis.debug(item);
      logger.debug("-- sims " .. ii);
      redis.debug(sims);
      for jj = 1, #sims
      do
        local sim = sims[jj];
        table.insert(scores, { sim[2], sim[3] * item[2], sim[3] });
      end
    end

    logger.debug("-- SCORES");
    redis.debug(scores);

    local final_scores = {};
    for ii = 1, #scores
    do
      local score = scores[ii];
      if (nil == final_scores[score[1]]) then
        final_scores[score[1]] = { 0, 0 };
      end

      logger.debug('final[' .. score[1] .. '][1] = '
        .. final_scores[score[1]][1] .. ' + ' .. score[2]);
      logger.debug('final[' .. score[1] .. '][2] = '
        .. final_scores[score[1]][2] .. ' + ' .. score[3]);
      final_scores[score[1]][1] = (final_scores[score[1]][1] + score[2]);
      final_scores[score[1]][2] = (final_scores[score[1]][2] + score[3]);
    end

    --logger.debug("-- FINAL SCORES");
    --redis.debug(final_scores);

    local sum = 0;
    for item_id, item_score in pairs(final_scores)
    do
      logger.debug('> final[' .. item_id .. '] = '
        .. item_score[1] .. ' / ' .. item_score[2]);
      final_scores[item_id] = (item_score[1] / item_score[2]);
      sum = (sum + final_scores[item_id]);
    end

    --logger.debug("-- FINAL SCORES 2");
    --redis.debug(final_scores);

    local result = {};
    for item_id, item_score in pairs(final_scores)
    do
      --logger.debug("> " .. item_id)
      table.insert(result, { id = item_id, score = (item_score / sum) });
      --final_scores[item_id] = nil;
    end

    --logger.debug("-- FINAL SCORES (NORMALIZED AND UNSORTED)");
    --redis.debug(result);

    --logger.debug("-- FINAL SCORES (NORMALIZED AND SORTED)");
    table.sort(result, function (a, b)
      return a.score > b.score;
    end);
    --redis.debug(result);

    return result;
  end -- TCREngine::_getRecommendations()

  -----------------------------------------------------------------------------

  --[[
  -- Composes two ids into a pair.
  --]]
  self._getRecommendationsFast = function (
    user_id,
    limit
  )
    local logger = self._logger;
    local store = self._store;

    limit = limit or 10;
    local userItems = getUserItems(user_id);

    if (nil == userItems) then
      return nil;
    end

    --[[
     * For each item the user has interacted with, fetch the top N similar
     * items.
     *
     * NOTE: This should be done in parallel.
     *  1. Fetch all items the user has interacted with.
     *  2. Batch all (item_id, weight) tuples such that they can be sent as a
     *     single request to each item server.
     *  3. Return the results.
    ]]--
    --local itemSimilarities = {};
    local keys = {};
    local weights = {};
    local counter = 0;
    for item_id, item_value in pairs(userItems)
    do
      keys[#keys + 1] = composeItemSimilarityZSetKey(item_id);
      weights[#weights + 1] = item_value;
    end

    local args = {}
    for ii = 1, #keys
    do
      args[#args + 1] = keys[ii];
    end
    local keyOnlyArgs = { table.unpack(args) };
    args[#args + 1] = 'weights';
    for ii = 1, #weights
    do
      args[#args + 1] = weights[ii];
    end

    --[[
    store.call('zunionstore', 'out', '4',
      'z:item:similarities:item-4', 'z:item:similarities:item-2',
      'z:item:similarities:item-1', 'z:item:similarities:item-3',
      'weights', '3', '5', '2', '2');
    ]]--
    redis.debug(keyOnlyArgs);
    store.call('zunionstore', 'out-summed', #keys, unpack(keyOnlyArgs));
    store.call('zunionstore', 'out-weighted', #keys, unpack(args));

    --local similarItems = store.call('zdiffstore', 'out', '+inf', '-inf',
    --  'withscores', 'limit', 0, 100);
    local similarItemsSummed = store.call('zrevrangebyscore', 'out-summed',
      '+inf', '-inf', 'withscores', 'limit', 0, 100);
    logger.debug("summed");
    redis.debug(similarItemsSummed);
    local similarItems = store.call('zrevrangebyscore', 'out-weighted',
      '+inf', '-inf', 'withscores', 'limit', 0, 100);
    --logger.debug("weighted");
    --redis.debug(similarItems);
    local sims = {};
    for ii = 1, #similarItems
    do
      local similarItemSum = tonumber(store.call('zscore', 'out-summed',
        similarItems[ii][1]));
      logger.debug('> sims[' .. similarItems[ii][1] .. '] = '
        .. tonumber(similarItems[ii][2]) .. ' / ' .. similarItemSum);
      sims[similarItems[ii][1]] = (tonumber(similarItems[ii][2])
        / similarItemSum);
    end
    redis.debug(sims);

    local final_scores = {};
    local sum = 0;
    for similar_item_id, similar_item_value in pairs(sims)
    do
      -- Prune recommended items by those already purchased.
      if (nil == userItems[similar_item_id]
        or 5 ~= userItems[similar_item_id])
      then
        table.insert(final_scores, {
          id = similar_item_id,
          score = similar_item_value
        });
        sum = (sum + similar_item_value);

        counter = (counter + 1);
        if (limit == counter) then
          break;
        end

      end
    end

    for ii = 1, #final_scores
    do
      local item  = final_scores[ii];
      final_scores[ii].score = (item.score / sum);
    end

    redis.debug(final_scores);

    table.sort(final_scores, function (a, b) return a.score > b.score end)
    return final_scores;
  end -- TCREngine::_track_event()

  -----------------------------------------------------------------------------
  --[[ ABSTRACT IMPLEMENTATIONS ]]---------------------------------------------
  -----------------------------------------------------------------------------

  self.addUser = function ()
    local logger = self._logger;
    logger.debug("Inside Overriding Function ("
      .. self._short_name .. ")")
  end -- TCREngine::addUser()

  -----------------------------------------------------------------------------

  self.addItem = function ()
    local logger = self._logger;
    logger.debug("Inside Overriding Function ("
      .. self._short_name .. ")")
  end -- TCREngine::addItem()

  -----------------------------------------------------------------------------

  self.recordInteraction = function (interaction)
    self._track_event(interaction.userId, interaction.itemId,
      interaction.event_type, interaction.weight);
  end -- TCREngine::recordInteraction()

  -----------------------------------------------------------------------------

  return (self);
end -- TCREngine

--local tcre = TCREngine.new('tcre');
--[[
tcre.incrementItemCount('item-001', 1.0);
tcre._saveNewUser('user-001', 'item-001', 1.0);
redis.debug(tcre._composeItemPairHashFieldKey('10301212', '166'))
redis.debug(tcre._composeItemPairHashFieldKey(166, 10301212))
tcre._saveSimilarity('item-001', 'item-002', 0.69);
tcre._updateItemSimilarity('item-002', 30, 'item-001', 2);
]]--

--[[
tcre._track_event("10301212", "item-1", "impression", 0);
--db:dump();
tcre._track_event("10301212", "item-1", "click", 2);
--db:dump();
tcre._track_event("10301212", "item-2", "click", 2);
--db:dump();
tcre._track_event("10301212", "item-3", "click", 2);
--db:dump();
tcre._track_event("10301212", "item-4", "add-to-cart", 3);
--db:dump();
tcre._track_event("10301212", "item-2", "buy", 5);
--db:dump();
logger.debug('--- recs ---');
redis.debug(tcre._getRecommendations("10301212"));
redis.debug(tcre._getRecommendationsFast("10301212"));
db:dump();
--]]

--[[

function getRankings (
  user_id,
  candidateArray
) {
  let user = store.users[user_id];
  let userItems = user.items;

  /* Get the user's explicit scores for candidates (if any) */
  //let scores = {};
  candidateMap = {};
  for (let ii in candidateArray) {
    let candidate = candidateArray[ii];
    candidateMap[candidate] = true;
/*
    if (candidate in userItems) {
      scores[candidate] = userItems[candidate];
      delete candidates[ii];
    }
*/
  }

  //candidates = candidates.filter(function (el) { return (el !== null); });

  let itemSimilarities = [];
  for (let item_id in userItems) {
    let counter = 0;
    let similarities = [];
    for (let similar_item_id in store.similarities[item_id]) {

      /*
       * Prune recommended items by those already purchased.
       */
      if (!(similar_item_id in candidateMap)) {
        continue;
      }

      similarities.push([
        item_id,
        similar_item_id,
        store.similarities[item_id][similar_item_id]
      ]);

    }

    if (0 < similarities.length) {
      itemSimilarities.push([
        [
          item_id,
          userItems[item_id]
        ],
        similarities
      ]);
    }
  }
  console.log(JSON.stringify(itemSimilarities, null, 2));

  /* Predict the user's weight for each recommended item */
  let scores = [];
  for (let ii in itemSimilarities) {
    let item = itemSimilarities[ii][0];
    let sims = itemSimilarities[ii][1];
    for (let jj in sims) {
      let sim = sims[jj];
      scores.push([ sim[1], sim[2] * item[1], sim[2] ]);
    }
  }

  console.log(JSON.stringify(scores, null, 2));

  let final_scores = {};
  for (let ii in scores) {
    let score = scores[ii];
    if (!(score[0] in final_scores)) {
      final_scores[score[0] ] = [ 0, 0 ];
    }
    final_scores[score[0] ][0] += score[1];
    final_scores[score[0] ][1] += score[2];
  }

  console.log(JSON.stringify(final_scores, null, 2));
  for (let item in final_scores) {
    let item_score = final_scores[item];
    final_scores[item] = (item_score[0] / item_score[1]);
  }
  console.log(JSON.stringify(final_scores, null, 2));

  /* normalize */
  let sum = 0;
  for (let item in final_scores) {
    let item_score = final_scores[item];
    sum += item_score;
  }
  for (let item in final_scores) {
    let item_score = final_scores[item];
    final_scores[item] = (item_score / sum);
  }
  console.log(JSON.stringify(final_scores, null, 2));

  table.sort(obj, function(a,b) return a.score > b.score end)

  final_scores = sortProperties(final_scores);
  console.log(JSON.stringify(final_scores, null, 2));

}


track_event("10301212", "item-1", "impression", 0);
console.log(JSON.stringify(store, null, 2));
track_event("10301212", "item-1", "click", 2);
console.log(JSON.stringify(store, null, 2));
track_event("10301212", "item-2", "click", 2);
console.log(JSON.stringify(store, null, 2));
track_event("10301212", "item-3", "click", 2);
console.log(JSON.stringify(store, null, 2));
track_event("10301212", "item-1", "buy", 5);
console.log(JSON.stringify(store, null, 2));

track_event("179", "item-1", "click", 2);
console.log(JSON.stringify(store, null, 2));
track_event("179", "item-4", "click", 2);
console.log(JSON.stringify(store, null, 2));
track_event("179", "item-5", "click", 2);
console.log(JSON.stringify(store, null, 2));

track_event("166", "item-1", "click", 2);
console.log(JSON.stringify(store, null, 2));
track_event("166", "item-4", "buy", 5);
console.log(JSON.stringify(store, null, 2));
track_event("166", "item-7", "click", 2);
console.log(JSON.stringify(store, null, 2));
track_event("166", "item-8", "click", 2);
console.log(JSON.stringify(store, null, 2));

//getRecommendations("10301212");
//getRecommendations("179");
console.log('recommendations...');
console.log(getRecommendations("166"));
console.log('----');
/*
getRankings("166", [
  'item-1',
  'item-2',
  'item-3',
  'item-4',
  'item-5',
  'item-6',
  'item-7',
  'item-8'
  ]);
*/
]]--

--fpp:endif
