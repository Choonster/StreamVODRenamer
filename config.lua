local lpeg = require("lpeg")
local re = require("re")
local locale = lpeg.locale()

-- Match a pattern exactly count times
-- http://hisham.hm/2010/10/21/lpeg-cheat-sheet/
local function X(patt, count)
	return count == 1 and patt or patt * X(patt, count - 1)
end

-- Get a pattern that matches the specified number of digits and captures them as a number
local function number(numDigits)
	return X(locale.digit, numDigits) / tonumber
end

local CONFIG = {}

---------------------
-- START OF CONFIG --
---------------------

-- The base directory to search. This should contain multiple subdirectories, each of which should contain the VODs to rename. Further levels of subdirectories won't be searched.
CONFIG.BASE_DIR = [[C:\Users\USER\Downloads\LivestreamDownloads]]

-- The date pattern to look for in the file names
CONFIG.DATE_PATTERN = number(4) * number(2) * number(2) * " - " -- "<year><month><day> - "

-- The date format to output (passed to os.date)
CONFIG.DATE_FORMAT = "%Y-%m-%d - " -- "<year>-<month>-<day> - "

-- The index pattern to look for in the file names
CONFIG.INDEX_PATTERN = "X of " * (locale.digit^1 / tonumber) * " - " -- "X of <number> - "

-- The index format to output (passed to string.format)
CONFIG.INDEX_FORMAT = "%d of %d - " -- "<current> of <max> - "

-- The game pattern to look for in the file names
CONFIG.GAME_PATTERN = lpeg.P("GAME -") -- "GAME -"

-- The game format to output (passed to string.format)
CONFIG.GAME_FORMAT = "%s -" -- "<game> -"

-- The file pattern to rename
CONFIG.FILE_PATTERN = (
	CONFIG.DATE_PATTERN * -- Date
	CONFIG.INDEX_PATTERN^-1 * -- Index (0 or 1 times)
	CONFIG.GAME_PATTERN -- Game
)

-- Whether to output command text
CONFIG.SHOW_COMMANDS = false

-------------------
-- END OF CONFIG --
-------------------

return CONFIG
