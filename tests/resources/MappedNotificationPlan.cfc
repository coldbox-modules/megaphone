component extends="megaphone.models.NotificationPlan" {

    /** Captures an application constructor dependency before data is configured. */
    public MappedNotificationPlan function init( required string marker ) {
        variables.marker = arguments.marker;
        return this;
    }

    /** Identifies the model supplied by the application mapping. */
    public boolean function suppliedByTestMapping() {
        return variables.marker == "from-wirebox";
    }

}
