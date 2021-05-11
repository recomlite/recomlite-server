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

-- luacheck: push ignore ImpressionDiscountingReranker
local ImpressionDiscountingReranker = {};
-- luacheck: pop
ImpressionDiscountingReranker.new = function(options)
  -----------------------------------------------------------------------------
  --[[ PROPERTIES ]]-----------------------------------------------------------
  -----------------------------------------------------------------------------

  -- luacheck: globals AbstractReranker
  local self = AbstractReranker.new()
  self.options = options or {};
  self.w1 = options.w1 or 1.0;
  self.w2 = options.w2 or 1.0;

  -----------------------------------------------------------------------------
  --[[ PRIVATE METHODS ]]------------------------------------------------------
  -----------------------------------------------------------------------------

  -----------------------------------------------------------------------------
  --[[ ABSTRACT IMPLEMENTATIONS ]]---------------------------------------------
  -----------------------------------------------------------------------------

  -- luacheck: push no unused args
  function self.rerank (user_id, recommendations)
    return recommendations;
  end -- ImpressionDiscountingReranker::rerank()
  -- luacheck: pop

  return self;
end -- ImpressionDiscountingReranker
--fpp:endif
