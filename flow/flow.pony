
interface FlowConsumer
	// data is being flowed to me from another actor
	be flow(dataIso:Any iso)

interface FlowConsumerAck	
	// data is being flowed to me from another actor. The producer
	// is requested that we acknowledge when we have completed
	// processing the data
	be flowAck(sender:FlowProducer tag, dataIso:Any iso)

interface FlowConsumerAll is (FlowConsumer & FlowConsumerAck)



interface FlowProducer
// Called by a consumer when they have finished processing a flow
	be ackFlow()
	
	

	
	