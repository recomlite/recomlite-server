--fpp:ifndef INTERNER_LUA                /* Guard against multiple inclusion */
--fpp:define INTERNER_LUA
--[[                                                   :vi set ts=2 et sw=2: **
** ========================================================================= **
**                ____                            __    _ __                 **
**               / __ \___  _________  ____ ___  / /   (_) /____             **
**              / /_/ / _ \/ ___/ __ \/ __ `__ \/ /   / / __/ _ \            **
**             / _, _/  __/ /__/ /_/ / / / / / / /___/ / /_/  __/            **
**            /_/ |_|\___/\___/\____/_/ /_/ /_/_____/_/\__/\___/             **
**                                                                           **
** ========================================================================= **
**                          STRING INTERNING ENGINE                          **
** ========================================================================= **
** RecomLite Recommender System                                              **
** Copyright (C) Jonah H. Harris <jonah.harris@gmail.com>                    **
** All Rights Reserved.                                                      **
**                                                                           **
** Permission to use, copy, modify, and/or distribute this software for any  **
** purpose is subject to the terms specified in the License Agreement.       **
** ========================================================================= **
**                                                                           **
** Interning Engine                                                          **
** ----------------                                                          **
**                                                                           **
** DESCRIPTION                                                               **
**  This script performs recommendation dithering via an impression-based    **
**  post-processing step using discounting on unengaged items.               **
**                                                                           **
** USAGE                                                                     **
**  Interner.new({ config });                                                **
**  Interner.clear();                                                        **
**  Interner.count();                                                        **
**  Interner.idOf(token [, token_type, should_intern]);                      **
**  Interner.typeOf(token_id);                                               **
**  Interner.valueOf(token_id);                                              **
**                                                                           **
** EXAMPLE                                                                   **
**  local string_pool = Interner.new({                                       **
**    prefix = 'sp:',                                                        **
**    logger = redis,                                                        **
**    store = redis                                                          **
**  });                                                                      **
** ======================================================================= --]]

-- luacheck: push ignore Interner
local Interner = {};
-- luacheck: pop
Interner.new = function (config)
  -----------------------------------------------------------------------------
  --[[ PROPERTIES ]]-----------------------------------------------------------
  -----------------------------------------------------------------------------

  -- Validate passed-in configuration.
  if (type(config) ~= 'table'
    or type(config.prefix) ~= 'string'
    or type(config.logger) ~= 'table'
    or not config.logger.LOG_DEBUG
    or type(config.logger.log) ~= 'function'
    or type(config.store) ~= 'table'
    or type(config.store.call) ~= 'function')
  then
    error('invalid configuration.');
  end

  --[[
  -- This is our local instance.
  --]]
  local self = {};

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
    type_hash = (self._prefix .. ':th')
  };

  --[[
  -- Mappings for Lua <-> token types.
  --]]
  self._type_mapping = {
    ['nil'] = 1,
    ['boolean'] = 2,
    ['number'] = 3,
    ['string'] = 4,
    ['userdata'] = 5,
    ['function'] = 6,
    ['thread'] = 7,
    ['table'] = 8
  };

  -----------------------------------------------------------------------------
  --[[ LOCAL FUNCTIONS ]]------------------------------------------------------
  -----------------------------------------------------------------------------

  local function is_nonexistent_redis_value (value)
    return (nil == value or (type(value) == 'boolean' and not value));
  end -- is_nonexistent_redis_value()

  -----------------------------------------------------------------------------
  --[[ PRIVATE METHODS ]]------------------------------------------------------
  -----------------------------------------------------------------------------

  --[[
  -- Returns the number of tokens interned.
  --]]
  self._clear = function ()
    local logger = self._logger;
    local store = self._store;
    for internal_key, redis_key in pairs(self._keys)
    do
      logger.log(logger.LOG_DEBUG, (
        'Deleting key ' .. '(' .. redis_key .. ')'
          .. ' for internal clear of ' .. internal_key
      ));
      store.call('DEL', redis_key);
    end
    return true;
  end -- Interner::_count()

  -----------------------------------------------------------------------------

  --[[
  -- Returns the number of tokens interned.
  --]]
  self._count = function ()
    return self._store.call('HLEN', self._keys.forward_hash);
  end -- Interner::_count()

  -----------------------------------------------------------------------------

  --[[
  -- Delete an interned token by id.
  --]]
  self._delete_token = function (
    token
  )
    local store = self._store;
    local token_id = store.call('HGET', self._keys.forward_hash, token);
    if (is_nonexistent_redis_value(token_id)) then
      return false;
    else
      store.call('HDEL', self._keys.forward_hash, token);
      store.call('HDEL', self._keys.reverse_hash, token_id);
      store.call('HDEL', self._keys.type_hash, token_id);
      return true;
    end
  end -- Interner::_delete_token()

  -----------------------------------------------------------------------------

  --[[
  -- Generic string interning function.
  --]]
  self._get_token_for_token_id = function (
    token_id
  )
    local store = self._store;
    local token = store.call('HGET', self._keys.reverse_hash, token_id);
    if (is_nonexistent_redis_value(token)) then
      return nil;
    else
      return token;
    end
  end -- Interner::_get_token_for_token_id()

  -----------------------------------------------------------------------------

  --[[
  -- Generic string interning function.
  --]]
  self._get_type_for_token_id = function (
    token_id
  )
    local store = self._store;
    local token_type = store.call('HGET', self._keys.type_hash, token_id);
    if (is_nonexistent_redis_value(token_type)) then
      return nil;
    else
      token_type = tonumber(token_type);
      for k, v in pairs(self._type_mapping)
      do
        if (v == token_type) then
          return (k);
        end
      end
    end
  end -- Interner::_get_type_for_token_id()

  -----------------------------------------------------------------------------

  --[[
  -- Generic string interning function.
  --]]
  self._intern_token = function (
    token,
    token_type,
    should_intern
  )
    local store = self._store;
    local token_id = store.call('HGET', self._keys.forward_hash, token);
    if (is_nonexistent_redis_value(token_id)) then
      if (should_intern) then
        token_id = store.call('INCRBY', self._keys.sequence, 1);
        store.call('HSET', self._keys.forward_hash, token, token_id);
        store.call('HSET', self._keys.reverse_hash, token_id, token);
        store.call('HSET', self._keys.type_hash, token_id,
          self._type_mapping[token_type]);
        return tonumber(token_id);
      else
        -- This external id has NOT been interned and this was only a lookup.
        return (nil);
      end
    else
      -- This external id has been interned.
      return tonumber(token_id);
    end
  end -- Interner::_intern_token()

  -----------------------------------------------------------------------------
  --[[ PUBLIC METHODS ]]-------------------------------------------------------
  -----------------------------------------------------------------------------

  --[[
  -- Clear (destroy) all internments.
  --]]
  self.clear = function ()
    return self._clear();
  end -- Interner::clear()

  -----------------------------------------------------------------------------

  --[[
  -- Return the count of tokens interned.
  --]]
  self.count = function ()
    return self._count();
  end -- Interner::count()

  -----------------------------------------------------------------------------

  --[[
  -- Unintern the given token.
  --]]
  self.delete = function (
    token
  )
    assert(token);
    return self._delete(token);
  end -- Interner::delete()

  -----------------------------------------------------------------------------

  --[[
  -- Return the numeric id representing the interned token.
  --
  -- TODO: Optional check to ensure passed-in token type matches interned.
  --]]
  self.idOf = function (
    token,
    token_type,
    should_intern
  )
    assert(token);
    token_type = token_type or type(token);
    should_intern = should_intern or true;

    return self._intern_token(token, token_type, should_intern);
  end -- Interner::idOf()

  -----------------------------------------------------------------------------

  --[[
  -- Return the interned token type for the given id.
  --]]
  self.typeOf = function (
    token_id
  )
    assert(token_id);
    return self._get_type_for_token_id(token_id);
  end -- Interner::typeOf()

  -----------------------------------------------------------------------------

  --[[
  -- Return the interned token for the given id.
  --]]
   self.valueOf = function (
    token_id
  )
    assert(token_id);
    return self._get_token_for_token_id(token_id);
  end -- Interner::valueOf()

  -----------------------------------------------------------------------------

  return (self);
end -- Interner
--fpp:endif
