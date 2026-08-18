--!nostrict
local harness = { passed = 0, failed = 0 }

function harness.test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		harness.passed += 1
		print("  ok   " .. name)
	else
		harness.failed += 1
		print("  FAIL " .. name)
		print("       " .. tostring(err))
	end
end

function harness.equals(actual, expected, name)
	if actual ~= expected then
		error((name or "значение") .. ": получили " .. tostring(actual) .. ", ждали " .. tostring(expected), 2)
	end
end

function harness.near(actual, expected, name)
	if math.abs(actual - expected) > 1e-6 then
		error((name or "значение") .. ": получили " .. tostring(actual) .. ", ждали " .. tostring(expected), 2)
	end
end

return harness
