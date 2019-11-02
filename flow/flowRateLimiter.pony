class FlowRateLimiter
	"""
	provides a simple rate limiting interface for sending messages to consumers
	"""	
	let produce:{ref ():Bool} ref
	
	var rate:USize
	var count:USize
	
	new create(rate':USize, produce': {ref ():Bool} ref) =>
		rate = rate'
		produce = produce'
		count = 1
		ack()
	
	fun ref ack() =>
		count = count - 1
		while count < rate do
			count = count + 1
			if produce() == false then
				rate = 0
			end
		end