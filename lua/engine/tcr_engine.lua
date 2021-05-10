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

local pretty = require('pl.pretty');
local fakeredis = require('fakeredis');
local unpack = table.unpack;
local db = fakeredis.new();

local redis = {
  call = function (cmd, ...)
    return db:call(cmd, ...)
  end
};

--[[
let store = {
  itemCounts: {
  },
  pairCounts: {
  },
  similarities: {
  },
  similaritiesIndex: {
  },
  users: {
  }
};
]]--

local TCREngine = {}
TCREngine.new = function(dbname)
  -------------------------------------------------------------------------------
  --[[ PROPERTIES ]]-------------------------------------------------------------
  -------------------------------------------------------------------------------

  local self = AbstractEngine.new()
  self.name = 'TencentRec Item-based Collaborative Filtering Engine';

  self.dbname = dbname;

  -------------------------------------------------------------------------------
  --[[ PRIVATE METHODS ]]--------------------------------------------------------
  -------------------------------------------------------------------------------

  -------------------------------------------------------------------------------
  --[[ PRIVATE METHODS ]]--------------------------------------------------------
  -------------------------------------------------------------------------------

  --[[
  -- Updates the item count.
  --]]
  function self._updateItemCount (
    item_id,
    delta_weight
  )
    redis.call('zincrby', 'z:item:counts', delta_weight, item_id);
  end -- TCREngine::_updateItemCount()

  -------------------------------------------------------------------------------

  --[[
  -- Saves a new user and updates the item count.
  --]]
  function self._saveNewUser (
    user_id,
    item_id,
    weight
  )
    print("SAVING NEW USER");
    local user_key = ('h:user:i:' .. user_id);
    redis.call('hset', user_key, item_id, weight);
    self._updateItemCount(item_id, weight);
  end -- TCREngine::_saveNewUser()

  -------------------------------------------------------------------------------

  --[[
  -- Composes two ids into a pair.
  --]]
  function self._composeItemPairKey (
    firstItemId,
    secondItemId
  )
    local ids = { tostring(firstItemId), tostring(secondItemId) };
    table.sort(ids);
    return (ids[1] .. ':' .. ids[2]);
  end -- TCREngine::_composeItemPairKey()

  -------------------------------------------------------------------------------

  --[[
  -- Composes two ids into a pair.
  --]]
  function self._saveSimilarity (
    firstItem,
    secondItem,
    similarity
  )
    print("SAVING SIMILARITY")
    redis.call('zadd', 'z:item:similarities:' .. firstItem, similarity, secondItem);
    redis.call('zadd', 'z:item:similarities:' .. secondItem, similarity, firstItem);

    local itemPairKey = self._composeItemPairKey(firstItem, secondItem);
    redis.call('hset', 'h:item:similarities:', itemPairKey, similarity);
  end -- TCREngine::_saveSimilarity()

  -------------------------------------------------------------------------------

  --[[
  -- Composes two ids into a pair.
  --]]
  function self._updateSimilarity (
    firstItem,
    newItemCount,
    secondItem,
    pairCount
  )
    local secondItemCount = redis.call('zscore', 'z:item:counts', secondItem);
    print("PAIRCOUNT: " .. pairCount .. ", NEWITEMCOUNT: " .. newItemCount)
    local similarity =
      (pairCount / (math.sqrt(newItemCount) * math.sqrt(secondItemCount)));
    print(similarity);
    self._saveSimilarity(firstItem, secondItem, similarity);
  end -- TCREngine::_updateSimilarity()

  -------------------------------------------------------------------------------

  --[[
  -- Composes two ids into a pair.
  --]]
  function self._updatePairCount (
    eventItemId,
    currentItemWeight,
    newItemWeight,
    newItemCount,
    anotherItemId,
    anotherItemWeight
  )
    local deltaCoRating = 0;
    if (0 == currentItemWeight) then
      print ('newItemWeight = ' .. newItemWeight);
      print ('anotherItemWeight = ' .. anotherItemWeight);
      deltaCoRating = math.min(newItemWeight, anotherItemWeight);
    elseif (currentItemWeight < anotherItemWeight) then
      if (newItemWeight < anotherItemWeight) then
        deltaCoRating = (newItemWeight - currentItemWeight);
      else
        deltaCoRating = (anotherItemWeight - currentItemWeight);
      end
    end

    local itemPairKey = self._composeItemPairKey(eventItemId, anotherItemId);
    local currentPairCount = tonumber(redis.call('zscore', 'z:item:paircounts', itemPairKey));
    if (nil == currentPairCount) then
      currentPairCount = 0;
    end

    if (0 ~= deltaCoRating) then
      redis.call('zincrby', 'z:item:paircounts', deltaCoRating, itemPairKey);
    end

    self._updateSimilarity(eventItemId, newItemCount, anotherItemId,
      (currentPairCount + deltaCoRating));
  end -- TCREngine::_updatePairCount()

  -------------------------------------------------------------------------------

  --[[
  -- Composes two ids into a pair.
  --]]
  function self._updatePair (
    eventItemId,
    currentItemWeight,
    newItemWeight,
    newItemCount,
    anotherItem
  )
    print('update pair ' .. eventItemId .. ' / ' .. anotherItem.item_id);
    local anotherItemId = anotherItem.item_id;
    local anotherItemWeight = anotherItem.weight;
    self._updatePairCount(eventItemId, currentItemWeight, newItemWeight,
      newItemCount, anotherItemId, anotherItemWeight);
  end -- TCREngine::_updatePair()

  -------------------------------------------------------------------------------

  --[[
  -- Composes two ids into a pair.
  --]]
  function self._recalculateSimilarity (
    user,
    item_id,
    current_weight,
    new_weight
  )
    print("RECALCULATING SIMILARITY");
    local currentItemCount = redis.call('zscore', 'z:item:counts', item_id);
    if (nil == currentItemCount) then
      currentItemCount = 0;
    end

    local itemCountDelta = (new_weight - current_weight);
    self._updateItemCount(item_id, itemCountDelta);
    local newItemCount = (currentItemCount + itemCountDelta);
    for another_item_id, another_item_value in pairs(user)
    do
      if (another_item_id ~= item_id) then
        self._updatePair(item_id, current_weight, new_weight, newItemCount,
          { item_id = another_item_id, weight = another_item_value });
      end
    end
  end -- TCREngine::_recalculateSimilarity()

  -------------------------------------------------------------------------------

  --[[
  -- Retrieves the user's items.
  --]]
  function self._getUserItems (
    user_id
  )
    local user_key = ('h:user:i:' .. user_id);
    local user_data = redis.call('hgetall', user_key);
    if (0 == #user_data) then
      return nil;
    end

    -- Convert Redis hash result to table
    local user = {};
    for ii = 1, #user_data, 2
    do
      user[user_data[ii]] = tonumber(user_data[(ii + 1)]);
    end

    return user;
  end -- TCREngine::_getUserItems()

  -------------------------------------------------------------------------------

  --[[
  -- Composes two ids into a pair.
  --]]
  function self._track_event (
    user_id,
    item_id,
    event_type,
    weight
  )
    print("track_event");
    --[[
    -- If this event is an impression, we only need to record it for
    -- statistics, not for recommendation.
    --]]
    if ('impression' == event_type) then
      return false;
    end

    -- Fetch user
    local user = self._getUserItems(user_id);
    if (nil == user) then
      self._saveNewUser(user_id, item_id, weight);
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

    local user_key = ('h:user:i:' .. user_id);
    redis.call('hset', user_key, item_id, newWeight);
    self._recalculateSimilarity(user, item_id, currentWeight, newWeight);
  end -- TCREngine::_track_event()

  -------------------------------------------------------------------------------

  --[[
  -- Composes two ids into a pair.
  --]]
  function self._getRecommendations (
    user_id,
    limit
  )
    limit = limit or 10;
    local userItems = self._getUserItems(user_id);

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
    local itemSimilarities = {};
    for item_id, item_value in pairs(userItems)
    do
      local counter = 0;
      local similarities = {};
      local similarItems = redis.call('zrevrangebyscore', 'z:item:similarities:' .. item_id, '+inf', '-inf', 'withscores', 'limit', 0, 100);
      --print("similarItems for " .. item_id);
      --pretty.dump(similarItems);
      local sims = {};
      for ii = 1, #similarItems
      do
        sims[similarItems[ii][1]] = tonumber(similarItems[ii][2]);
      end
      --pretty.dump(sims);

      for similar_item_id, similar_item_value in pairs(sims)
      do
        -- Prune recommended items by those already purchased.
        if (nil == userItems[similar_item_id] or 5 ~= userItems[similar_item_id]) then
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
      --print("-- SIMILARITIES");
      --pretty.dump(similarities);

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
    print("-- ITEM SIMILARITIES");
    pretty.dump(itemSimilarities);

    -- Predict the user's weight for each recommended item
    local scores = {};
    for ii = 1, #itemSimilarities
    do
      local item = itemSimilarities[ii][1];
      local sims = itemSimilarities[ii][2];
      print("-- item " .. ii);
      pretty.dump(item);
      print("-- sims " .. ii);
      pretty.dump(sims);
      for jj = 1, #sims
      do
        local sim = sims[jj];
        table.insert(scores, { sim[2], sim[3] * item[2], sim[3] });
      end
    end

    print("-- SCORES");
    pretty.dump(scores);

    local final_scores = {};
    for ii = 1, #scores
    do
      local score = scores[ii];
      if (nil == final_scores[score[1]]) then
        final_scores[score[1]] = { 0, 0 };
      end

      print('final[' .. score[1] .. '][1] = ' .. final_scores[score[1]][1] .. ' + ' .. score[2]);
      print('final[' .. score[1] .. '][2] = ' .. final_scores[score[1]][2] .. ' + ' .. score[3]);
      final_scores[score[1]][1] = (final_scores[score[1]][1] + score[2]);
      final_scores[score[1]][2] = (final_scores[score[1]][2] + score[3]);
    end

    --print("-- FINAL SCORES");
    --pretty.dump(final_scores);

    local sum = 0;
    for item_id, item_score in pairs(final_scores)
    do
      print('> final[' .. item_id .. '] = ' .. item_score[1] .. ' / ' .. item_score[2]);
      final_scores[item_id] = (item_score[1] / item_score[2]);
      sum = (sum + final_scores[item_id]);
    end

    --print("-- FINAL SCORES 2");
    --pretty.dump(final_scores);

    local result = {};
    for item_id, item_score in pairs(final_scores)
    do
      --print("> " .. item_id)
      table.insert(result, { id = item_id, score = (item_score / sum) });
      --final_scores[item_id] = nil;
    end

    --print("-- FINAL SCORES (NORMALIZED AND UNSORTED)");
    --pretty.dump(result);

    --print("-- FINAL SCORES (NORMALIZED AND SORTED)");
    table.sort(result, function (a, b) return a.score > b.score end)
    --pretty.dump(result);

    return result;
  end -- TCREngine::_track_event()

  -------------------------------------------------------------------------------

  --[[
  -- Composes two ids into a pair.
  --]]
  function self._getRecommendationsFast (
    user_id,
    limit
  )
    limit = limit or 10;
    local userItems = self._getUserItems(user_id);

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
    local itemSimilarities = {};
    local keys = {};
    local weights = {};
    local counter = 0;
    for item_id, item_value in pairs(userItems)
    do
      keys[#keys + 1] = ('z:item:similarities:' .. item_id);
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

    --redis.call('zunionstore', 'out', '4', 'z:item:similarities:item-4', 'z:item:similarities:item-2', 'z:item:similarities:item-1', 'z:item:similarities:item-3', 'weights', '3', '5', '2', '2');
    pretty.dump(keyOnlyArgs);
    redis.call('zunionstore', 'out-summed', #keys, unpack(keyOnlyArgs));
    redis.call('zunionstore', 'out-weighted', #keys, unpack(args));

    --local similarItems = redis.call('zdiffstore', 'out', '+inf', '-inf', 'withscores', 'limit', 0, 100);
    local similarItemsSummed = redis.call('zrevrangebyscore', 'out-summed', '+inf', '-inf', 'withscores', 'limit', 0, 100);
    print("summed");
    pretty.dump(similarItemsSummed);
    local similarItems = redis.call('zrevrangebyscore', 'out-weighted', '+inf', '-inf', 'withscores', 'limit', 0, 100);
    --print("weighted");
    --pretty.dump(similarItems);
    local sims = {};
    for ii = 1, #similarItems
    do
      similarItemSum = tonumber(redis.call('zscore', 'out-summed', similarItems[ii][1]));
      print('> sims[' .. similarItems[ii][1] .. '] = ' .. tonumber(similarItems[ii][2]) .. ' / ' .. similarItemSum);
      sims[similarItems[ii][1]] = tonumber(similarItems[ii][2]) / similarItemSum;
    end
    pretty.dump(sims);

    local final_scores = {};
    counter = 0;
    local sum = 0;
    for similar_item_id, similar_item_value in pairs(sims)
    do
      -- Prune recommended items by those already purchased.
      if (nil == userItems[similar_item_id] or 5 ~= userItems[similar_item_id]) then
        table.insert(final_scores, { id = similar_item_id, score = similar_item_value });
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

    pretty.dump(final_scores);

    table.sort(final_scores, function (a, b) return a.score > b.score end)
    return final_scores;
  end -- TCREngine::_track_event()

  -------------------------------------------------------------------------------
  --[[ ABSTRACT IMPLEMENTATIONS ]]-----------------------------------------------
  -------------------------------------------------------------------------------

  function self.addUser()
    print("Inside Overriding Function (" .. self.dbname .. ")")
  end -- TCREngine::addUser()

  -------------------------------------------------------------------------------

  function self.addItem()
    print("Inside Overriding Function (" .. self.dbname .. ")")
  end -- TCREngine::addItem()

  -------------------------------------------------------------------------------

  function self.recordInteraction(interaction)
    --print("Inside Overriding Function (" .. self.dbname .. ")")
    self._track_event(interaction.userId, interaction.itemId,
      interaction.event_type, interaction.weight);
  end -- TCREngine::recordInteraction()

  -------------------------------------------------------------------------------

  -------------------------------------------------------------------------------

  return self
end -- TCREngine


--local tcre = TCREngine.new('tcre');
--[[
tcre._updateItemCount('item-001', 1.0);
tcre._saveNewUser('user-001', 'item-001', 1.0);
pretty.dump(tcre._composeItemPairKey('10301212', '166'))
pretty.dump(tcre._composeItemPairKey(166, 10301212))
tcre._saveSimilarity('item-001', 'item-002', 0.69);
tcre._updateSimilarity('item-002', 30, 'item-001', 2);
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
print('--- recs ---');
pretty.dump(tcre._getRecommendations("10301212"));
pretty.dump(tcre._getRecommendationsFast("10301212"));
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
