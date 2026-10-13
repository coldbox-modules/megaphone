/** A registered non-database queue that serializes jobs for explicit test consumption. */
component extends="cbq.models.Providers.AbstractQueueProvider" accessors="true" {

    property name="entries";

    public any function init() {
        variables.entries = [];
        return this;
    }

    public any function push(
        required string queueName,
        required any job,
        numeric delay = 0,
        numeric attempts = 0
    ) {
        variables.entries.append( {
            "queueName": arguments.queueName,
            "payload": serializeJSON( arguments.job.getMemento() ),
            "delay": arguments.delay
        } );
        return this;
    }

}
