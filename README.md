# pony.flow

**WARNING: [THIS ONLY WORKS WITH MY FORK OF PONY](https://github.com/KittyMac/ponyc/tree/roc)**

### Purpose

The pony runtime is fantastic, but it is not perfect. The full discussion of which I am not going to enter here, but suffice it to say to achieve optimal perfomance in complex actor architectures it is best to preemptively avoid message pressure scenarios which will result in cascadig muting of actors.  This library is meant to provide the tools required to make flow control of your messaging easier, so your complex system of communicating actors can work like the well-oiled machine you meant it to be.

To help understand these concepts, this document will take one example architecture and show how the components in pony.flow can help combat problems the bare architecture will experience.

[TODO] Insert graph of actor architecture

Data streams into our architecture in discrete chunks of data.  Imagine an infinite amount of data is to be processed by the system, and we want to process it a bit at a time.  Our input actor (in this case, the FileExtStreamReader actor) aggressively reads chunks of data and passes them to the BZ2StreamDecompress actor for decompression.

We now have two actors into our architecture and are already in trouble!  The FileExtStreamReader can read raw, compressed data and pass it to the BZ2StreamDecompress actor faster than the BZ2StreamDecompress actor could possibly hope to decompress it.  All of those chunks of data will fill up that actor's mailbox, causing the pony messaging system to "mute" the file actor.  While this is acceptable as a worst case scenario, this also means all of the chunks of data (which could be quite large!) are just taking up RAM which could be utilized by other parts of the actor network.  The ideal scenario is that the file actor provides just enough data to the decompression actor to keep the decompression actor busy 100% of the time.

### Actor Flow Interfaces

pony.flow provides a very basic Flowable interface so you can have multiple different actors plug-n-play with each other into a processing network.  There are only two method, flowReceived() to pass data from one actor to another and flowFinished() to specify that the work is done.

```
interface Flowable
	be flowFinished()
	be flowReceived(dataIso:Any iso)
```

### Custom Actor Batch Sizes

By default in the pony runtime each actor has the same sized mailbox (default at the time of this writing is 100 messages).  In our scenario above, the BZ2StreamDecompress is much slower than the FileExtStreamReader.  The FileExtStreamReader will quickly load the entire file into memory where it will sit in the BZ2StreamDecompress's mailbox.  When decompressing large files, this is a very wasteful memory usage pattern.  Ideally, only enough of the file is loaded to fully provide concurrency between the two actors (the file reader is reading while the bzip decompressor is decompressing.  Since the bzip decompressor is slow, it should be kept fed 100% of the time, and the file streaming actor should be paused when instead of just overloading the actor's mailbox).

To handle this gracefully I needed to make two changes to Pony. The first change allows you, the programmer, to set a custom batch size for any actor you create.  Doing so it trivial, just provide a _batch() method on your actor and return the size of the mailbox you want.

In our BZ2StreamDecompress example, we can simply set that value to a low number, like 4.  This allows for the file streamer to keep the BZ2StreamDecompress 100% busy without wasting memory.

```
actor BZ2StreamDecompress is Flowable

	fun _batch():USize => 4
	
	be flowFinished() =>
		@fprintf[I64](@pony_os_stdout[Pointer[U8]](), "flow finished\n".cstring())
	
	be flowReceived(dataIso: Any iso) =>
		@fprintf[I64](@pony_os_stdout[Pointer[U8]](), "flow received\n".cstring())

```

### Self-muting Actors

Unfortunately, the custom batch size per actor chane was not enough to get the desired functionality out of stock Pony. The current Pony actor muting/overloading system requires that the consumer actor fully process messages until it has exceeded its set batch size and more messages remain.  Then the actor will mute the sender and set itself to be flagged as overloaded.  It will then not unmute the sender until it has done "one processing batch" worth of messages and not exceeded the batch size.

The has the downside that a fast producer can generate as many messages as it can before the actor sets itself to be overloaded, and the send can be muted (so, think thousands of messages in the slow consumers mailbox instead of the "default" 100 batch size).  What we really want is for the producer actor to mute itself when it sends a message to a "full" mailbox, and set the target actore to be overloaded at the same time. This way the fast producing file loader will mute immediately once it overflows the target mailbox, and the consuming actor can unmute it once there is any space free in its mailbox. The file loader will process concurrently, but only when it needs to. The consumer actor will be always fed (other scheduling issues not withstanding) and spend 100% of its time processing the data.

You don't need to do anything more special than the _batch() method above.  Self-muting actors will now ensure your consumer actors will not be overloaded more than the batch size you set.


## License

pony.flow is free software distributed under the terms of the MIT license, reproduced below. pony.flow may be used for any purpose, including commercial purposes, at absolutely no cost. No paperwork, no royalties, no GNU-like "copyleft" restrictions. Just download and enjoy.

Copyright (c) 2019 Rocco Bowling

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.