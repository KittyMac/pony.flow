use "ponytest"

actor Main is TestList
	new create(env: Env) => PonyTest(env, this)
	new make() => None

	fun tag tests(test: PonyTest) =>
	
	
		"""
		All test examples produce 4 MB strings to a consumer which processes them for 1 second each.
		
		_TestBasicFlow: unrestricted producer, fills the consumers queue with strings. My tests show
						max concurrent memory usage of the consumer's message box reaches 360MB (!) 
						of waiting messages
		
		_TestAckFlow: 	uses the ack flow of pony.flow. There is a 1-to-1 ratio of producer to consumer
						as the producer will not produce again until the consumer ack's that it has
						finished processing the data. No wasted memory because the consumer's mailbox
						never has more than one message in it.  But this is not efficient, as we have
						lost all concurrency between the produce and the consumber. Total concurrent
						memory usage is 5 MB.
		
		_TestRateLimiter: 	uses the ack flow and the FlowRateLimiter class to allow 4 concurrent
							messages between the producer and the consumer. This allows us to cap the amount
							of wasted memory while keeping maximum concurrency. Total concurrent
							memory usage is 29.7 MB.
		"""
		//test(_TestBasicFlow)
		//test(_TestAckFlow)
		test(_TestRateLimiter)
		//test(_TestBatchOverride)
	
	// Required to keep pony memory usage down when dealing with large chunks of memory,
	// especially when dealing with "processor" actors who don't allocate memory themselves
	// they just pass messages
 	fun @runtime_override_defaults(rto: RuntimeOptions) =>
		rto.ponynoblock = true
		rto.ponygcinitial = 0
		rto.ponygcfactor = 1.0


// ********************** BASIC FLOW **********************

primitive Data
	fun size():USize => 1024*1024*4

actor Producer is FlowProducer
	
	let target:FlowConsumerAll tag
	var count:USize
	
	new create(target':FlowConsumerAll tag) =>
		target = target'
		count = 0
	
	// In a non-ack flow, the producer sends data as fast as it possibly can, regardless
	// of how overloaded the consumer may get because of that.  This can be easily seen
	// in the printout, where all of the "produced" logs happen before the "consumed" logs
	be start() =>
		produce()
	
	be produce() =>
		count = count + 1
		if count < 100 then
			let msg = "x".mul(Data.size())
			@fprintf[I64](@pony_os_stdout[Pointer[U8]](), "produced %d bytes of data, count = %d\n".cstring(), Data.size(), count)
			target.flow(consume msg)
			
			// Note: never just call produce() again, because the GC will hold an extra reference to msg and
			// never release it.  Simply calling produceAgain() which then calls produce() will avoid this
			produceAgain()
		end
	
	be produceAgain() =>
		produce()
	
	// In an ack flow, the producer relies on the consumer to acknowledge when it is done
	// processing the data it was sent.  The producer can use this ack to limit the rate
	// at which the data is sent.
	be startAck() =>
		produceAck()
	
	be produceAck() =>
		count = count + 1
		if count < 100 then
			let msg = "x".mul(Data.size())
			@fprintf[I64](@pony_os_stdout[Pointer[U8]](), "produced %d bytes of data, count = %d\n".cstring(), Data.size(), count)
			target.flowAck(this, consume msg)
		end
	be ackFlow() =>
		produceAck()
	

actor Consumer is (FlowConsumer & FlowConsumerAck)

	fun sharedFlow(data: String ref) =>
		// simulate processing time
		@sleep[U32](U32(1))
		@fprintf[I64](@pony_os_stdout[Pointer[U8]](), "consumed %d bytes of data\n".cstring(), data.size())

	be flow(dataIso: Any iso) =>
		let data:Any ref = consume dataIso
		try
			sharedFlow(data as String ref)
		end
	
	be flowAck(sender:FlowProducer tag, dataIso:Any iso) =>
		let data:Any ref = consume dataIso
		try
			sharedFlow(data as String ref)
		end
		sender.ackFlow()
		

class iso _TestBasicFlow is UnitTest
	fun name(): String => "unrestricted producer and consumer"

	fun apply(h: TestHelper) =>
		let flow = Producer(Consumer)
		flow.start()

class iso _TestAckFlow is UnitTest
	fun name(): String => "simple 1-to-1 producer and consumer"

	fun apply(h: TestHelper) =>
		let flow = Producer(Consumer)
		flow.startAck()
		

// ************************************************************


// ********************** FLOW RATE LIMITER **********************

actor RateLimitedProducer is FlowProducer
	let rateLimiter:FlowRateLimiter
	
	let target:FlowConsumerAck tag
	var count:USize
	
	new create(target':FlowConsumerAck tag) =>
		target = target'
		count = 0
		
		let sender = this
		rateLimiter = FlowRateLimiter(4, {ref () =>
				@fprintf[I64](@pony_os_stdout[Pointer[U8]](), "produced %d bytes of data\n".cstring(), Data.size())
				let msg = "x".mul(Data.size())
				target.flowAck(sender, consume msg)
				count = count + 1
				count < 100
			})
		
	be ackFlow() =>
		rateLimiter.ack()
		

class iso _TestRateLimiter is UnitTest
	fun name(): String => "rate limited producer and consumer"

	fun apply(h: TestHelper) =>
		let flow = RateLimitedProducer(Consumer)


// ************************************************************


// ********************** BATCH OVERRIDE **********************

actor BatchOverride

	let x:I64 = 0

	fun _batch():USize =>
		20
	
	be foo() =>
		@fprintf[I64](@pony_os_stdout[Pointer[U8]](), "BatchOverride.foo was called\n".cstring())

class iso _TestBatchOverride is UnitTest
	fun name(): String => "custom batch size"

	fun apply(h: TestHelper) =>
		BatchOverride.foo()
		
// ************************************************************