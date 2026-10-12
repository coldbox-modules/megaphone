/** Forward-only pagination over a recipient's current, authorized inbox. */
component accessors="true" {

    property name="results" type="array";
    property name="nextCursor" type="string";
    property
        name="hasMore"
        type="boolean"
        getter="false"
        setter="false";
    property name="loader" getter="false" setter="false";

    public DatabaseNotificationKeysetCursor function init(
        required array results,
        required string nextCursor,
        required boolean hasMore,
        required function loader
    ) {
        variables.results = arguments.results;
        variables.nextCursor = arguments.nextCursor;
        variables.hasMore = arguments.hasMore;
        variables.loader = arguments.loader;
        return this;
    }

    public boolean function hasNext() {
        return variables.hasMore;
    }

    public DatabaseNotificationKeysetCursor function next() {
        if ( !hasNext() ) {
            throw(
                type = "Megaphone.DatabaseNotificationCursor.MaximumPageReached",
                message = "Check hasNext() before advancing the notification cursor."
            );
        }
        var nextPage = variables.loader( variables.nextCursor );
        variables.results = nextPage.getResults();
        variables.nextCursor = nextPage.getNextCursor();
        variables.hasMore = nextPage.hasNext();
        return this;
    }

    public struct function getMemento() {
        return {
            "results": variables.results.map( ( entry ) => entry.getMemento() ),
            "nextCursor": variables.nextCursor,
            "hasMore": variables.hasMore
        };
    }

}
