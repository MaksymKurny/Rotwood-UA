local REPO = "MaksymKurny/Rotwood-UA/"
local BRANCH = "main"
local LINK = "data_scripts_zip/localizations/uk.po"
local LocUpdate = {
	URL = "https://raw.githubusercontent.com/"..REPO..BRANCH.."/"..LINK,
	V_URL = "https://api.github.com/repos/"..REPO.."commits?path="..LINK.."&page=1&per_page=1&sha="..BRANCH,
	PATH = "",
	lastModified = "",
}

function LocUpdate:StartUpdate()
	print("[Loc Update] Start update")
	TheSim:QueryServer(self.URL, function (result, isSuccessful, resultCode)
		if resultCode ~= 200 or not isSuccessful or #result < 1 then
			print("[Loc Update] Update: fail")
			return
		end
		
		local f = io.open(self.PATH.."uk.po", "w")
		if f then
			f:write(result)
			f:close()
		else
			print("[Loc Update] Update: fail")
		end
		
		local ver_f = io.open(self.PATH.."version.txt", "w")
		if ver_f then
			ver_f:write(self.lastModified)
			ver_f:close()
		else
			print("[Loc Update] Save version: fail")
		end
	end, "GET")
end

function LocUpdate:GetLastCommitDate(fn)
	TheSim:QueryServer(self.V_URL, function (result, isSuccessful, resultCode)
		if resultCode ~= 200 or not isSuccessful or #result < 1 then
			print("[Loc Update] Get version: fail")
			return
		end
		
		local commit_data = json.decode(result)
		if commit_data and commit_data[1] and commit_data[1].commit and commit_data[1].commit.author and commit_data[1].commit.author.date then
			local lastModified = commit_data[1].commit.author.date
			fn(lastModified)
		end
	end, "HEAD")
end

function LocUpdate:CheckUpdate()
	self:GetLastCommitDate(function(date)
		local file = io.open(self.PATH.."version.txt", "r")
		if file then
			local curr_date = file:read("*all")
			file:close()
			if date and curr_date and date ~= curr_date then
				self.lastModified = date
				self:StartUpdate()
			end
		else
			print("[Loc Update] Read version: fail")
		end
	end)
end

return LocUpdate