--fpp:ifndef ABSTRACT_ENGINE_LUA
--fpp:define ABSTRACT_ENGINE_LUA
--[[                                                   :vi set ts=2 et sw=2: **
** ========================================================================= **
**                ____                            __    _ __                 **
**               / __ \___  _________  ____ ___  / /   (_) /____             **
**              / /_/ / _ \/ ___/ __ \/ __ `__ \/ /   / / __/ _ \            **
**             / _, _/  __/ /__/ /_/ / / / / / / /___/ / /_/  __/            **
**            /_/ |_|\___/\___/\____/_/ /_/ /_/_____/_/\__/\___/             **
**                                                                           **
** ========================================================================= **
**                         ABSTRACT ENGINE INTERFACE                         **
** ========================================================================= **
** RecomLite Recommender System                                              **
** Copyright (C) Jonah H. Harris <jonah.harris@gmail.com>                    **
** All Rights Reserved.                                                      **
**                                                                           **
** Permission to use, copy, modify, and/or distribute this software for any  **
** purpose is subject to the terms specified in the License Agreement.       **
** ========================================================================= **
**                                                                           **
** Abstract Recommendation Engine Class                                      **
** ------------------------------------                                      **
**                                                                           **
** DESCRIPTION                                                               **
**  This script represents an abstract recommendation class designed to be   **
**  subclassed by actual implementations.                                    **
** ======================================================================= --]]

-- luacheck: push ignore AbstractEngine
local AbstractEngine = {};
-- luacheck: pop
AbstractEngine.new = function()
  local self = {};

  function self.addUser()
      error("I am abstract!");
  end

  function self.addItem()
      error("I am abstract!");
  end

  function self.recordInteraction()
      error("I am abstract!");
  end

  function self.getRecommendations()
      error("I am abstract!");
  end

  return self;
end
--fpp:endif
