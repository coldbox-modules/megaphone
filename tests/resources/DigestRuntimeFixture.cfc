component accessors="true" {

    property name="recipient";
    property name="queueAdapter";
    function getSettings() {
        return { "digests": { "testing": {} }, "queue": { "leaseSeconds": 60, "maxAttempts": 5, "retrySeconds": 1 } };
    }
    function resolve( key, fallback ) {
        if ( arguments.key == "queueAdapter" && !isNull( variables.queueAdapter ) ) {
            return variables.queueAdapter;
        }
        if ( !isNull( arguments.fallback ) ) {
            return arguments.fallback;
        }
        return;
    }
    function getNotifiable( type, id ) {
        return new tests.resources.InboxRecipient( arguments.id, arguments.type );
    }
    function digest( value, context ) {
        return new megaphone.models.Delivery.NotificationSnapshotHasher().digest( value, context );
    }

}
