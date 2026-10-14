component {

    function resolve( required string type, required string id ) {
        return new tests.resources.InboxRecipient( arguments.id, arguments.type );
    }

}
