local uv = require "lluv"

uv.timer():start(100, function()
	error('SOME_ERROR_MESSAGE')
end)

local pass = false
uv.run(function(msg)
	print('ERROR MESSAGE:')
	print(msg)
	print("-------------------")
	pass = not not string.find(msg, 'SOME_ERROR_MESSAGE', nil, true)
end)

if not pass then
	print('Fail!')
	os.exit(-1)
end

print('Done!')
