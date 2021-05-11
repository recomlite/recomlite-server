--fpp:ifndef COMMON_TYPES_LUA            /* Guard against multiple inclusion */
--fpp:define COMMON_TYPES_LUA

local function is_string (value)
  if (type(value) ~= 'string') then
    return false;
  end
  return true;
end

local function is_integer (value)
  if ((type(value) ~= 'number') or ((value % 1) ~= 0)) then
    return false;
  end
  return true;
end

local function is_number (value)
  if (type(value) ~= 'number') then
    return false;
  end
  return true;
end

local function is_boolean (value)
  if (type(value) ~= 'boolean') then
    return false;
  end
  return true;
end

--fpp:endif
