component {

    public struct function getSettings() {
        return { "durable": { "leaseSeconds": 60, "maxAttempts": 5, "retrySeconds": 30 } };
    }
    public any function resolve( required string key, any fallback ) {
        if ( !isNull( arguments.fallback ) ) {
            return arguments.fallback;
        }
        return;
    }

}
