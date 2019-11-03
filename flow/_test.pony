use "ponytest"

actor Main is TestList
	new create(env: Env) => PonyTest(env, this)
	new make() => None

	fun tag tests(test: PonyTest) =>
		
		"""
		All test examples produce 4 MB strings to a consumer which processes them for 1 second each.
	
		_TestBadFlow: unrestricted producer, quickly fills the consumers queue with strings 4 MB strings. 
						My tests show max concurrent memory usage of the consumer's message box reaches over
						215MB (!) of waiting messages
	
		_TestGoodFlow: 	sets a custom batch size of 4 for the consumer actor. With my changes to how pony actor
						muting works, the producer actor will immediately mute itself when the consumer's
						mailbox exceeds its batch size of 4. This brings concurrent memory usage down to a
						constant 22 MB (4 messages waiting in the queue, one actively being processed).
		"""
		
		
		//test(_TestBadFlow)
		test(_TestGoodFlow)
	
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

actor Producer
	
	let target:Flowable tag
	var count:USize
	
	new create(target':Flowable tag) =>
		target = target'
		count = 0
		produce()
	
	be produce() =>
		count = count + 1
		if count < 60 then
			let msg = "x".mul(Data.size())
			@fprintf[I64](@pony_os_stdout[Pointer[U8]](), "produced %d bytes of data, count = %d\n".cstring(), Data.size(), count)
			target.flowReceived(consume msg)
			
			// Note: never just call produce() again, because the GC will hold an extra reference to msg and
			// never release it.  Simply calling produceAgain() which then calls produce() will avoid this
			produceAgain()
		else
			target.flowFinished()
		end
	
	be produceAgain() =>
		produce()	

actor GoodConsumer is Flowable

	fun _batch():USize => 4
	
	be flowFinished() =>
		@fprintf[I64](@pony_os_stdout[Pointer[U8]](), "flow finished\n".cstring())
	
	be flowReceived(dataIso: Any iso) =>
		try
			@fprintf[I64](@pony_os_stdout[Pointer[U8]](), "begin consuming %d bytes of data\n".cstring(), (dataIso as String iso).size())
			@sleep[U32](U32(1))
			@fprintf[I64](@pony_os_stdout[Pointer[U8]](), "end consuming %d bytes of data\n".cstring(), (dataIso as String iso).size())
		end

actor BadConsumer is Flowable
	be flowFinished() =>
		@fprintf[I64](@pony_os_stdout[Pointer[U8]](), "flow finished\n".cstring())

	be flowReceived(dataIso: Any iso) =>
		try
			@fprintf[I64](@pony_os_stdout[Pointer[U8]](), "begin consuming %d bytes of data\n".cstring(), (dataIso as String iso).size())
			@sleep[U32](U32(1))
			@fprintf[I64](@pony_os_stdout[Pointer[U8]](), "end consuming %d bytes of data\n".cstring(), (dataIso as String iso).size())
		end
			

class iso _TestBadFlow is UnitTest
	fun name(): String => "bad flow"

	fun apply(h: TestHelper) =>
		Producer(BadConsumer)


class iso _TestGoodFlow is UnitTest
	fun name(): String => "good flow"

	fun apply(h: TestHelper) =>
		Producer(GoodConsumer)

// ************************************************************
