--fpp:ifndef EPSILON_DITHERING_RERANKER_LUA
--fpp:define EPSILON_DITHERING_RERANKER_LUA
--[[                                                   :vi set ts=2 et sw=2: **
** ========================================================================= **
**                ____                            __    _ __                 **
**               / __ \___  _________  ____ ___  / /   (_) /____             **
**              / /_/ / _ \/ ___/ __ \/ __ `__ \/ /   / / __/ _ \            **
**             / _, _/  __/ /__/ /_/ / / / / / / /___/ / /_/  __/            **
**            /_/ |_|\___/\___/\____/_/ /_/ /_/_____/_/\__/\___/             **
**                                                                           **
** ========================================================================= **
**              EPSILON-BASED RECOMMENDATION DITHERING RERANKER              **
** ========================================================================= **
** RecomLite Recommender System                                              **
** Copyright (C) Jonah H. Harris <jonah.harris@gmail.com>                    **
** All Rights Reserved.                                                      **
**                                                                           **
** Permission to use, copy, modify, and/or distribute this software for any  **
** purpose is subject to the terms specified in the License Agreement.       **
** ========================================================================= **
**                                                                           **
** Perform a Slightly-shuffled Reordering of Recommendations                 **
** ---------------------------------------------------------                 **
**                                                                           **
** DESCRIPTION                                                               **
**  This script performs recommendation dithering via an epsilon-based       **
**  post-processing step using normally distributed random noise.            **
**                                                                           **
**  SEE ALSO:                                                                **
**    - Ted Dunning and Ellen Friedman. 2014. Practical Machine Learning:    **
**        Innovations in Recommendation (1st. ed.). O'Reilly Media, Inc.     **
**                                                                           **
** USAGE                                                                     **
**  EpsilonDitheringReranker.new({ epsilon = [1.0, 3.0] });                  **
**  EpsilonDitheringReranker.rerank(user_id, { recommendations };            **
**                                                                           **
**  This expects recommendations of the standard form as input:              **
**    [                                                                      **
**      { id: <ITEM/USER ID>, score: <NORMALIZED SCORE> },                   **
**      ...                                                                  **
**    ]                                                                      **
**                                                                           **
** EXAMPLE                                                                   **
**  local edr = EpsilonDitheringReranker.new({ epsilon = 1.25 });            **
**  local rrecs = edr.rerank('user-001', recs);                              **
** ======================================================================= --]]

-- ========================================================================= --
-- -- INCLUSIONS ----------------------------------------------------------- --
-- ========================================================================= --

--fpp:include "abstract_reranker.lua"

-- luacheck: push ignore EpsilonDitheringReranker
local EpsilonDitheringReranker = {};
-- luacheck: pop
EpsilonDitheringReranker.new = function(options)
  -----------------------------------------------------------------------------
  --[[ PROPERTIES ]]-----------------------------------------------------------
  -----------------------------------------------------------------------------

  -- luacheck: globals AbstractReranker
  local self = AbstractReranker.new()
  self.options = options or {};
  self.epsilon = options.epsilon or 1.0;
  self.sd = 1e-10;

  if (self.options.epsilon > 1.0) then
    self.sd = math.sqrt(math.log(self.options.epsilon));
  end

  -----------------------------------------------------------------------------
  --[[ PRIVATE METHODS ]]------------------------------------------------------
  -----------------------------------------------------------------------------

  -----------------------------------------------------------------------------
  --[[ ABSTRACT IMPLEMENTATIONS ]]---------------------------------------------
  -----------------------------------------------------------------------------

  -- luacheck: push no unused args
  function self.rerank (user_id, recommendations)
    local function gaussian (mean, sd)
      local u1, u2
      repeat u1 = math.random() u2 = math.random() until u1 > 0.0001

      local logPiece = math.sqrt(-2 * math.log(u1))
      local cosPiece = math.cos(2 * math.pi * u2)

      return ((logPiece * cosPiece) * sd + mean);
    end

    -- Sort recommendations by score descending
    table.sort(recommendations, function (a, b) return a.score > b.score end)

    -- Calculate dither score by rank
    local ds = {};
    for ii = 1, #recommendations
    do
      ds[recommendations[ii].id] = (math.log(ii) + gaussian(0, self.sd));
    end

    -- Sort recommendations by ditherScore ascending */
    table.sort(recommendations, function (a, b) return ds[a.id] < ds[b.id] end)

    return recommendations;
  end -- EpsilonDitheringReranker::rerank()
  -- luacheck: pop

  return self
end -- EpsilonDitheringReranker
--fpp:endif
