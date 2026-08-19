--!nostrict
local process = require("@lune/process")
Vector2 = require("@lune/roblox").Vector2

local harness = require("./harness")
require("./syntax.spec")(harness)
require("./config.spec")(harness)
require("./geom.spec")(harness)
require("./recipe.spec")(harness)

print(`\n{harness.passed} прошло, {harness.failed} упало`)
process.exit(if harness.failed > 0 then 1 else 0)
