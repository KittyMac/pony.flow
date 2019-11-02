# pony.flow

**WARNING: Some of the features in this library rely on [my custom fork of pony](https://github.com/KittyMac/ponyc/tree/roc)**. Specific features which rely on this are noted in the descriptions below by the tag [custom fork].

### Purpose

The pony runtime is fantastic, but it is not perfect. The full discussion of which I am not going to enter here, but suffice it to say to achieve optimal perfomance in complex actor architectures it is best to preemptively avoid message pressure scenarios which will result in cascadig muting of actors.  This library is meant to provide the tools required to make flow control of your messaging easier, so your complex system of communicating actors can work like the well-oiled machine you meant it to be.

To help understand these concepts, this document will take one example architecture and show how the components in pony.flow can help combat problems the bare architecture will experience.

[TODO] Insert graph of actor architecture

Data streams into our architecture in discrete chunks of data.  Imagine an infinite amount of data is to be processed by the system, and we want to process it a bit at a time.  Our input actor (in this case, the FileExtStreamReader actor) aggressively reads chunks of data and passes them to the BZ2StreamDecompress actor for decompression.

We now have two actors into our architecture and are already in trouble!  The FileExtStreamReader can read raw, compressed data and pass it to the BZ2StreamDecompress actor faster than the BZ2StreamDecompress actor could possibly hope to decompress it.  All of those chunks of data will fill up that actor's mailbox, causing the pony messaging system to "mute" the file actor.  While this is acceptable as a worst case scenario, this also means all of the chunks of data (which could be quite large!) are just taking up RAM which could be utilized by other parts of the actor network.  The ideal scenario is that the file actor provides just enough data to the decompression actor to keep the decompression actor busy 100% of the time.

### Actor Flow Interfaces

pony.flow provides several interfaces to allow creating actors which can flow data between each other in a more generic manner.  They are:

```
interface FlowConsumer
	be flow(dataIso:Any iso)
```
Allows unrestricted flowing of data to another actor.

```
interface FlowConsumerAck
	be flowAck(sender:FlowProducer tag, dataIso:Any iso)
```
Allows flowing of data to another actor. That actor should call back to the FlowProducer's ackFlow() method when the processing of that data has been completed.

```
interface FlowProducer
	be ackFlow()
```
Called by consumer actors when a previously sent message has completed processing. This is generally used to tell producers to producer more data.

### 1-to-1 producer and consumer messaging

Given the interfaces above, you probably guess the most obvious flow mechanism available. A producer create a chunk of data and sends it to the consumer. The producer then waits until the consumer acknowledges the message before it will produce the next message. This provides a tight coupling between the producer and consumer, completely eliminating wasted memory by not allowing any concurrency between the producer and the consumer to occur.

This basic produce -> consume -> ack paradigm is useful, but not really advised as it removes concurrency (one of the main reasons to use Pony in the first place!).  However, it provides the building blocks necessary to more complex mechanisms, like rate limiting.

### Rate Limiting

Rate limiting builds off of the 1-to-1 produce -> consume -> ack paradigm but extends it to allow the produce to have up to a certain number of concurrent messages at one time. This allows concurrency to happen, but limits the amount of unrestrained growth that can happen.

pony.flow provides a the FlowRateLimiter class to ease rewriting producer code to follow this paradigm. The following example is a producer limited to 4 concurrent messages to the consumer at a time

```
actor RateLimitedProducer is FlowProducer
	let rateLimiter:FlowRateLimiter
	
	let target:FlowConsumerAck tag
	
	new create(target':FlowConsumerAck tag) =>
		target = target'
		
		let sender = this
		rateLimiter = FlowRateLimiter(4, {ref () =>
				@fprintf[I64](@pony_os_stdout[Pointer[U8]](), "produced %d bytes of data\n".cstring(), Data.size())
				let msg = "x".mul(Data.size())
				target.flowAck(sender, consume msg)
			})
		
	be ackFlow() =>
		rateLimiter.ack()
```



### Dynamic Actor Batch Sizes [custom fork]

This is an example of shallow mailbox overloading; the distance and complexity between the producer and the consumer is not deep, so we can solve this using a new feature of my customized ponyc, the _batch() method.

By default in the pony runtime each actor has the same sized mailbox (default at the time of this writing is 100 messages).  In our scenario above, if the BZ2StreamDecompress actor's mail box overloads, all it will do is mute the FileExtStreamReader actor.  This is the desired behaviour, but letting it queue up 100 messages is undesirabe.  If we had a convenient mechanism to allow us to set the mailbox size of just the BZ2StreamDecompress actor to "2", then we can take advantage of the built in muting feature and limit the amount of wasted RAM in one blow.

This solution is not perfect, because actor overloading and muting is controlled by the receiving actor only after they have processed a "batch" amount of messages at one time. In our example, the FileExtStreamReader is so fast compared to the BZ2StreamDecompress decompressor that it could potentially queue up hundreds of messages before the BZ2StreamDecompress actor has a chance to process the first two of them.


## License

pony.flow is free software distributed under the terms of the MIT license, reproduced below. pony.flow may be used for any purpose, including commercial purposes, at absolutely no cost. No paperwork, no royalties, no GNU-like "copyleft" restrictions. Just download and enjoy.

Copyright (c) 2019 Rocco Bowling

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.