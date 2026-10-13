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

    /**
     * Initializes an empty WireBox cursor or a page with its continuation loader.
     * @returns DatabaseNotificationKeysetCursor
     */
    public DatabaseNotificationKeysetCursor function init(
        array results = [],
        string nextCursor = "",
        boolean hasMore = false,
        function loader
    ) {
        return configure( argumentCollection = arguments );
    }

    /**
     * Sets the page and continuation loader after WireBox constructs the cursor.
     * This preserves constructor injection supplied by an application override.
     *
     * @results The current page's DatabaseNotification objects.
     * @nextCursor The token identifying the next page boundary.
     * @hasMore Whether another page is available.
     * @loader The callback that loads a page from its boundary token.
     * @returns DatabaseNotificationKeysetCursor
     */
    public DatabaseNotificationKeysetCursor function configure(
        required array results,
        required string nextCursor,
        required boolean hasMore,
        function loader
    ) {
        variables.results = arguments.results;
        variables.nextCursor = arguments.nextCursor;
        variables.hasMore = arguments.hasMore;
        if ( !isNull( arguments.loader ) ) {
            variables.loader = arguments.loader;
        } else {
            structDelete( variables, "loader" );
        }
        return this;
    }

    /**
     * Checks whether another page is available.
     * @returns boolean
     */
    public boolean function hasNext() {
        return variables.hasMore;
    }

    /**
     * Loads the next page and returns this cursor.
     * @returns DatabaseNotificationKeysetCursor
     */
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

    /**
     * Returns this object's public data as a serializable memento.
     * @returns struct
     */
    public struct function getMemento() {
        return {
            "results": variables.results.map( ( entry ) => entry.getMemento() ),
            "nextCursor": variables.nextCursor,
            "hasMore": variables.hasMore
        };
    }

}
