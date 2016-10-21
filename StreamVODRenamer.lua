local winapi = require("winapi")
local file = require("pl.file")
local path = require("pl.path")
local utils = require("pl.utils")
local re = require("re")

require("pl.app").require_here()
local REPLACEMENTS = require("games")
local CONFIG = require("config")

do
	-- Make os.tmpname return a file name instead of a full path like it does in MSVC 13 and earlier
	-- Fixes winapi.temp_name returning an invalid path (https://github.com/stevedonovan/winapi/issues/25)
	local tmpname = os.tmpname
	os.tmpname = function()
		return "\\" .. path.basename(tmpname())
	end
end

--- Wrapper around winapi.files that always returns a function
local function files(mask, subdirs, attrib)
	return winapi.files(mask, subdirs, attrib) or function() end
end

--- Print the specified string after calling string.format on it.
--
-- @param format The format string
-- @param ... The format arguments
local function printf(format, ...)
	print(format:format(...))
end

--- Execute the specified command after calling string.format on it and return a file handle to read its output.
--
-- @param command The format string
-- @param ... The format arguments
local function popen(command, mode, ...)
	command = command:format(...)

	if CONFIG.SHOW_COMMANDS then
		printf("> %s", command)
	end

	return assert(winapi.spawn_process(command))
end

--- Helper function that produces a readable error message from os.execute or file:close (when called on a file from io.popen).
-- Calls string.format on `message` with `command, status, signal` as arguments.
--
-- @param success Did the command succeed?
-- @param message The format string for the error message
-- @param command The command that was executed
-- @param status "exit" if the command terminated normally, or "signal" if the command was terminated by a signal
-- @param signal The exit status of the command if the command terminated normally, or the signal that terminated the command if the command was terminated by a signal
local function assertExecute(message, command, success, status, signal)
	if not success then
		error(message:format(command, status, signal))
	end
end

--- Execute the specified command after calling string.format on it.
-- Throws an error if the command fails.
--
-- @param command The format string
-- @param ... The format arguments
local function execute(command, ...)
	command = command:format(...)

	if CONFIG.SHOW_COMMANDS then
		printf("> %s", command)
	end

	assertExecute([[Failed to execute command "%s": status = %s, signal = %d]], command, winapi.execute(command, "unicode"))
end

winapi.set_encoding(winapi.CP_UTF8) -- Set WinAPI's encoding to UTF-8
execute("chcp 65001") -- Set the output encoding to UTF-8

--- Fix the AAC stream of the specified file, allowing its length and thumbnail to be displayed by Windows
--
-- @param fullPath The file name
local function fixAACStream(fullPath)
	local dirname, filename = path.splitpath(fullPath)
	printf("Testing AAC stream of %s...", filename)

	local tempPath = winapi.temp_name() .. ".mp4"

	-- Try to copy the video to a new file to detect a malformed AAC stream
	-- The line directly after "Press [q] to stop, [?] for help" will either be an error or a progress message.
	-- If it's an error, the AAC stream is malformed and needs to be fixed. If it's a progress message, nothing needs to be done.

	-- `-y` = Overwrite files without asking
	-- `-v error` = Only log errors
	-- `-i "%s"` = Input file
	-- `-codec copy` = Copy the streams without decoding/reencoding them
	-- `"%s"` = Output file
	-- `2>&1` = Redirect stderr to stdout
	local process, outputStream, command = popen([[ffmpeg -y -v error -i "%s" -codec copy "%s"]], "r", fullPath, tempPath)

	local outputText = ""
	local chunk = outputStream:read()

	-- Keep reading from the output until it starts the copying process
	while chunk do
		outputText = outputText .. chunk

		if outputText:find("Press [q] to stop, [?] for help", 1, true) then
			break
		end

		chunk = outputStream:read()
	end

	-- Strip everything except the last two lines

	outputText = outputText:gsub(".+\n([^\n]+\n[^\n]+)", "%1")

	-- Keep reading from the output until we have at least 150 characters
	chunk = outputStream:read()
	while chunk do
		outputText = outputText .. chunk

		if #outputText >= 150 then
			break
		end

		chunk = outputStream:read()
	end

	-- Kill the process
	process:kill()

	-- If the AAC stream is malformed,
	if outputText:find("Malformed AAC bitstream detected.+'aac_adtstoasc'") then
		printf("Fixing AAC stream of %s...", filename)

		-- Fix the AAC stream
		-- `-y` = Overwrite files without asking
		-- `-v error` = Only log errors
		-- `-i "%s"` = Input file
		-- `-bsf:a aac_adtstoasc` = Fix Malformed AAC bitstream
		-- `-codec copy` = Copy the streams without decoding/reencoding them
		-- `"%s"` = Output file
		-- `-ss 2` = Start at 2 seconds
		execute([[ffmpeg -y -v error -i "%s" -bsf:a aac_adtstoasc -codec copy "%s"]], fullPath, tempPath)

		execute([[copy %s %s]], utils.quote_arg(tempPath), utils.quote_arg(fullPath)) -- Overwrite the old file with the new one
	end

	-- Try to delete the temp file, but don't throw an error if it fails
	winapi.delete_file_or_dir(tempPath)
end

--- Rename the specified file, replacing "GAME" with the game name and adding separators to the date.
--
-- @param fullPath The full file path
local function renameFile(fullPath, index)
	local dirname, filename = path.splitpath(fullPath)

	local newFileName = filename

	newFileName = re.gsub(newFileName, CONFIG.DATE_PATTERN, function(year, month, day) -- Add separators to the date (only once)
		local time = os.time({ year = year, month = month, day = day })
		return os.date(CONFIG.DATE_FORMAT, time)
	end)

	newFileName = re.gsub(newFileName, CONFIG.INDEX_PATTERN, function(maxIndex)
		return CONFIG.INDEX_FORMAT:format(index, maxIndex)
	end)

	newFileName = re.gsub(newFileName, CONFIG.GAME_PATTERN, function() -- Replace GAME with the game name (only once)
		local upperFileName = newFileName:upper()

		for fileNameText, fullGameName in pairs(REPLACEMENTS) do
			if upperFileName:find(fileNameText, 1, true) then
				return CONFIG.GAME_FORMAT:format(fullGameName)
			end
		end

		printf([[ERROR: Couldn't find game name for file "%s"!]], filename)
	end)

	local newPath = path.join(dirname, newFileName)
	printf([[Renaming "%s" to "%s"...]], filename, newFileName)
	execute([[ren %s %s]], utils.quote_arg(fullPath), utils.quote_arg(newFileName))

	fixAACStream(newPath)
end

--- Rename files in the specified directory, optionally visiting subdirectories.
--
-- @param dirname The directory name
-- @param checkSubdirs Whether to check subdirectories
local function renameFiles(dirname, checkSubdirs)
	print()
	printf("Entering directory %s...", dirname)

	local mask = dirname .. "\\*"
	local index = 1

	-- Iterate through the files in this directory and rename any that match the pattern
	-- Uses winapi.files instead of lfs.dir because it supports Unicode on Windows
	for file in files(mask, false, "-D") do
		local fullPath = path.join(dirname, file)

		-- If the file matches the pattern, rename it
		if CONFIG.FILE_PATTERN:match(file) then
			renameFile(fullPath, index)

			index = index + 1
		end
	end

	-- If this is the top-level directory and we're checking subdirectories, rename the files in each subdirectory
	if checkSubdirs then
		for dir in files(mask, true, "D") do
			renameFiles(dir, false)
		end
	end
end

print("Stream VOD Renamer running")

renameFiles(CONFIG.BASE_DIR, true)
