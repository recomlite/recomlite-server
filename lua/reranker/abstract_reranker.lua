--fpp:ifndef ABSTRACT_RERANKER_LUA
--fpp:define ABSTRACT_RERANKER_LUA
--[[                                                   :vi set ts=2 et sw=2: **
** ========================================================================= **
**                ____                            __    _ __                 **
**               / __ \___  _________  ____ ___  / /   (_) /____             **
**              / /_/ / _ \/ ___/ __ \/ __ `__ \/ /   / / __/ _ \            **
**             / _, _/  __/ /__/ /_/ / / / / / / /___/ / /_/  __/            **
**            /_/ |_|\___/\___/\____/_/ /_/ /_/_____/_/\__/\___/             **
**                                                                           **
** ========================================================================= **
**                         ABSTRACT RERANKER INTERFACE                         **
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

local AbstractReranker = {}
AbstractReranker.new = function()
  local self = {};

  function self.rerank(user_id, recommendations)
    error("I am abstract!");
  end

  return self;
end
--fpp:endif
