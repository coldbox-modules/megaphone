/** ColdBox discovers and owns this module scheduler as cbScheduler@megaphone. */
component {

    function configure() {
        // Module schedulers are configured before ModuleConfig.onLoad maps configured stores.
        task( "emailDigest-deliveries" )
            .call( () => {
                if ( structIsEmpty( getModuleSettings( "megaphone" ).digests ?: {} ) ) {
                    return;
                }
                var digests = getInstance( "EmailDigestService@megaphone" );
                digests.refreshSchedules();
                digests.dispatchDue();
            } )
            .everyMinute()
            .delay( 1, "minutes" )
            .withNoOverlaps();
    }

    function onStartup() {
        var digests = getInstance( "EmailDigestService@megaphone" );
        digests.useScheduler( this );
        if ( !structIsEmpty( getModuleSettings( "megaphone" ).digests ?: {} ) ) {
            digests.refreshSchedules();
        }
    }

    function onAnyTaskError( required task, required exception ) {
        variables.log.error( "Email digest task [#arguments.task.getName()#] failed", arguments.exception );
    }

}
