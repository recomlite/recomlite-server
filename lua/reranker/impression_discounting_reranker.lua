--fpp:ifndef IMPRESSION_DISCOUNTING_RERANKER_LUA
--fpp:define IMPRESSION_DISCOUNTING_RERANKER_LUA
--[[                                                   :vi set ts=2 et sw=2: **
** ========================================================================= **
**                ____                            __    _ __                 **
**               / __ \___  _________  ____ ___  / /   (_) /____             **
**              / /_/ / _ \/ ___/ __ \/ __ `__ \/ /   / / __/ _ \            **
**             / _, _/  __/ /__/ /_/ / / / / / / /___/ / /_/  __/            **
**            /_/ |_|\___/\___/\____/_/ /_/ /_/_____/_/\__/\___/             **
**                                                                           **
** ========================================================================= **
**           IMPRESSION-BASED RECOMMENDATION DISCOUNTING RERANKER            **
** ========================================================================= **
** RecomLite Recommender System                                              **
** Copyright (C) Jonah H. Harris <jonah.harris@gmail.com>                    **
** All Rights Reserved.                                                      **
**                                                                           **
** Permission to use, copy, modify, and/or distribute this software for any  **
** purpose is subject to the terms specified in the License Agreement.       **
** ========================================================================= **
**                                                                           **
** Penalize Unengaging Recommendations                                       **
** -----------------------------------                                       **
**                                                                           **
** DESCRIPTION                                                               **
**  This script performs recommendation dithering via an impression-based    **
**  post-processing step using discounting on unengaged items.               **
**                                                                           **
**  SEE ALSO:                                                                **
**    - Pei Lee, Laks V.S. Lakshmanan, Mitul Tiwari, and Sam Shah. 2014.     **
**        Modeling impression discounting in large-scale recommender systems.**
**        In Proceedings of the 20th ACM SIGKDD international conference on  **
**        Knowledge discovery and data mining (KDD '14). Association for     **
**        Computing Machinery, New York, NY, USA, 1837–1846.                 **
**                                                                           **
** USAGE                                                                     **
**  ImpressionDiscountingReranker.new({ w1 = (0.0, 1.0], w2 = (0.0, 1.0] }); **
**  ImpressionDiscountingReranker.rerank(user_id, { recommendations };       **
**                                                                           **
** EXAMPLE                                                                   **
**  local idr = ImpressionDiscountingReranker.new({ w1 = 0.5, w2 = 0.5 });   **
**  local rrecs = idr.rerank('user-001', recs);                              **
** ======================================================================= --]]

local ImpressionDiscountingReranker = {}
ImpressionDiscountingReranker.new = function(dbname)
  -------------------------------------------------------------------------------
  --[[ PROPERTIES ]]-------------------------------------------------------------
  -------------------------------------------------------------------------------

  local self = AbstractReranker.new()
  self.options = options or {};
  self.epsilon = options.epsilon or 1.0;
  self.sd = 1e-10;

  if (self.options.epsilon > 1.0) then
    self.sd = math.sqrt(math.log(self.options.epsilon));
  end

  -------------------------------------------------------------------------------
  --[[ PRIVATE METHODS ]]--------------------------------------------------------
  -------------------------------------------------------------------------------

  -------------------------------------------------------------------------------
  --[[ ABSTRACT IMPLEMENTATIONS ]]-----------------------------------------------
  -------------------------------------------------------------------------------

  function self.rerank (user_id, recommendations, epsilon)
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
  end

  return self
end -- ImpressionDiscountingReranker
--fpp:endif
