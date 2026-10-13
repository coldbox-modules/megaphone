component extends="megaphone.models.DatabaseNotificationKeysetCursor" {

    /**
     * Captures constructor data that must be supplied by the WireBox mapping.
     * @returns MappedDatabaseNotificationKeysetCursor
     */
    public MappedDatabaseNotificationKeysetCursor function init( required string marker ) {
        variables.marker = arguments.marker;
        return this;
    }

    /**
     * Identifies the cursor supplied by the test's WireBox override.
     * @returns boolean
     */
    public boolean function suppliedByTestMapping() {
        return variables.marker == "from-wirebox";
    }

}
